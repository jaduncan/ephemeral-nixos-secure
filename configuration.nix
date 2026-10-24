{
  config,
  lib,
  pkgs,
  settings,
  ...
}:

let
  home = "/home/${settings.username}";
  chezmoiSource = "${home}/.local/share/chezmoi";
in
{
  networking.hostName = settings.hostname;

  hardware.enableRedistributableFirmware = true;

  boot = {
    loader.systemd-boot.enable = true;
    loader.systemd-boot.editor = false;
    loader.systemd-boot.configurationLimit = 5;
    loader.efi.canTouchEfiVariables = true;
    loader.timeout = 3;

    initrd.systemd.enable = true;

    plymouth.enable = true;

    consoleLogLevel = 3;
    initrd.verbose = false;
    kernelParams = [
      "quiet"
      "splash"
      "rd.udev.log_level=3"
      "rd.systemd.show_status=auto"
      # "plymouth.use-simpledrm"
    ];

    tmp.useTmpfs = true;
    tmp.cleanOnBoot = true;

    initrd.systemd.services.rollback = {
      description = "Rollback Btrfs root to blank snapshot";
      wantedBy = [ "initrd.target" ];
      after = [ "systemd-cryptsetup@cryptroot.service" ];
      before = [ "sysroot.mount" ];
      unitConfig.DefaultDependencies = "no";
      serviceConfig.Type = "oneshot";
      script = ''
        set -euo pipefail
        mkdir -p /btrfs_tmp
        mount -o subvolid=5 /dev/mapper/cryptroot /btrfs_tmp
        trap 'umount /btrfs_tmp' EXIT

        if [[ ! -e /btrfs_tmp/root-blank ]]; then
          echo "ERROR: root-blank subvolume missing" >&2
          exit 1
        fi

        if [[ -e /btrfs_tmp/root ]]; then
          # higher id is a newer child, so delete from the bottom
          list=$(btrfs subvolume list -o /btrfs_tmp/root)
          if [[ -n $list ]]; then
            mapfile -t subvols < <(printf '%s\n' "$list" | cut -d' ' -f9-)
            for ((i = ''${#subvols[@]} - 1; i >= 0; i--)); do
              subvolume=''${subvols[i]}
              [[ -n $subvolume ]] || continue
              btrfs subvolume delete "/btrfs_tmp/$subvolume"
            done
          fi
          btrfs subvolume delete /btrfs_tmp/root
        fi

        btrfs subvolume snapshot /btrfs_tmp/root-blank /btrfs_tmp/root
      '';
    };
  };

  fileSystems."/persist".neededForBoot = true;
  fileSystems."/var/log".neededForBoot = true;

  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/home"
      "/var/lib/nixos"
      "/var/lib/AccountsService"
      "/var/lib/systemd/backlight"
      "/var/lib/systemd/rfkill"
      "/var/lib/systemd/timers"
      "/var/lib/systemd/linger"
      {
        directory = "/var/lib/systemd/timesync";
        user = "systemd-timesync";
        group = "systemd-timesync";
      }
      "/var/lib/bluetooth"
      "/var/lib/NetworkManager"
      "/var/lib/cups"
      "/var/lib/flatpak"
      "/var/lib/fwupd"
      "/var/lib/containers"
      "/etc/NetworkManager/system-connections"
    ];
    files = [
      "/etc/machine-id"
      "/var/lib/systemd/random-seed"
    ];
  };

  # blank root drops /home/$USER. create it here.
  system.activationScripts.ensureUserHome = {
    deps = [ "users" "groups" ];
    text = ''
      home=${lib.escapeShellArg "/persist/home/${settings.username}"}
      if [ ! -d "$home" ]; then
        mkdir -p "$home"
        chmod 0700 "$home"
      fi
      chown ${
        lib.escapeShellArg "${settings.username}:${config.users.users.${settings.username}.group}"
      } "$home"
    '';
  };

  system.activationScripts.persistSecrets = {
    deps = [ "users" ];
    text = ''
      mkdir -p /persist/passwords
      chmod 700 /persist/passwords
      for f in /persist/passwords/*; do
        if [ -e "$f" ]; then
          chmod 600 "$f"
        fi
      done

      mkdir -p /persist/etc/ssh
      chmod 755 /persist/etc/ssh
      for f in /persist/etc/ssh/ssh_host_*_key; do
        if [ -f "$f" ]; then
          chmod 600 "$f"
        fi
      done
      for f in /persist/etc/ssh/ssh_host_*_key.pub; do
        if [ -f "$f" ]; then
          chmod 644 "$f"
        fi
      done

      if [ -f /persist/etc/chezmoi-repo ]; then
        chown ${
          lib.escapeShellArg "${settings.username}:${config.users.users.${settings.username}.group}"
        } /persist/etc/chezmoi-repo
        chmod 600 /persist/etc/chezmoi-repo
      fi
    '';
  };

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  hardware.graphics.enable = true;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  services.power-profiles-daemon.enable = true;

  services.printing.enable = true;
  # Off by default — mDNS/printer discovery; enable if you need .local / network CUPS
  services.avahi.enable = false;

  services.fwupd.enable = true;
  services.flatpak.enable = true;

  systemd.services.flatpak-flathub = {
    description = "Add Flathub Flatpak remote";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [ pkgs.flatpak ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      flatpak remote-add --system --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo
    '';
  };

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  systemd.oomd = {
    enable = true;
    enableRootSlice = true;
    enableSystemSlice = true;
    enableUserSlices = true;
  };

  # rootless. group podman is the root socket, so the user is not in it.
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
      flags = [ "--all" ];
    };
  };

  boot.supportedFilesystems = [
    "btrfs"
    "ntfs"
    "exfat"
    "vfat"
  ];

  fonts.packages = with pkgs; [
    noto-fonts-color-emoji
    noto-fonts-cjk-sans
    liberation_ttf
  ];

  programs.dconf.enable = true;

  # Desktop / Downloads / .local / etc. on first graphical/user session
  systemd.user.services.xdg-user-dirs = {
    description = "Create default XDG user directories";
    wantedBy = [ "default.target" ];
    unitConfig.ConditionUser = "!@system";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.xdg-user-dirs}/bin/xdg-user-dirs-update";
    };
  };

  networking.networkmanager = {
    enable = true;
    plugins = with pkgs; [
      networkmanager-openvpn
    ];
  };
  networking.firewall.enable = true;

  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      X11Forwarding = false;
      AllowAgentForwarding = false;
    };
    hostKeys = [
      {
        path = "/persist/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
      {
        path = "/persist/etc/ssh/ssh_host_rsa_key";
        type = "rsa";
        bits = 4096;
      }
    ];
  };

  services.fstrim.enable = true;

  systemd.sleep.settings.Sleep = {
    AllowHibernation = "no";
    AllowHybridSleep = "no";
    AllowSuspendThenHibernate = "no";
  };

  time.timeZone = settings.timeZone;
  i18n.defaultLocale = "en_US.UTF-8";

  programs.zsh = {
    enable = true;
    enableCompletion = true;
  };
  users.defaultUserShell = pkgs.zsh;

  users.mutableUsers = false;
  users.users.${settings.username} = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "audio"
      "lp"
      "dialout"
    ];
    hashedPasswordFile = "/persist/passwords/${settings.username}";
  };
  users.users.root.hashedPassword = "!";

  security.sudo = {
    execWheelOnly = true;
    extraConfig = ''
      Defaults lecture = never
    '';
  };

  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
    firefox
    mkpasswd
    ghostty
    chezmoi
    distrobox
    vlc
    wl-clipboard
    htop
    file
    unzip
    zip
    p7zip
    usbutils
    pciutils
    dig
    ripgrep
    wireguard-tools
    xdg-user-dirs
  ];

  environment.sessionVariables.TERMINAL = "ghostty";

  # /persist/etc/chezmoi-repo is "<git-url> <commit>", mode 600, owned by the user.
  systemd.services.chezmoi-init = {
    description = "Initialize chezmoi from /persist/etc/chezmoi-repo";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [
      pkgs.git
      pkgs.chezmoi
      pkgs.coreutils
    ];
    unitConfig.ConditionPathExists = [
      "/persist/etc/chezmoi-repo"
      "!${chezmoiSource}"
    ];
    serviceConfig = {
      Type = "oneshot";
      User = settings.username;
      Group = "users";
      WorkingDirectory = home;
      Environment = "HOME=${home}";
    };
    script = ''
      set -euo pipefail
      line=$(head -n 1 /persist/etc/chezmoi-repo | tr -d '\r')
      read -r url rev extra <<<"$line"
      if [[ -z ''${url:-} || -z ''${rev:-} || -n ''${extra:-} ]]; then
        echo "/persist/etc/chezmoi-repo must be one line: <git-url> <commit>" >&2
        exit 1
      fi
      if [[ ! $rev =~ ^[0-9a-fA-F]{7,64}$ ]]; then
        echo "chezmoi commit must be 7-64 hex chars" >&2
        exit 1
      fi
      case $url in
        https://* | ssh://* | git@*) ;;
        *)
          echo "chezmoi url must start with https://, ssh://, or git@" >&2
          exit 1
          ;;
      esac

      dest=${lib.escapeShellArg chezmoiSource}
      mkdir -p "$(dirname "$dest")"
      cleanup() { rm -rf "$dest"; }
      trap cleanup ERR
      git clone -- "$url" "$dest"
      git -C "$dest" checkout --detach "$rev"
      chezmoi init --apply
      trap - ERR
    '';
  };

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [ "root" ];
      auto-optimise-store = true;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  nixpkgs.config.allowUnfree = settings.allowUnfree;

  system.stateVersion = "25.05";
}

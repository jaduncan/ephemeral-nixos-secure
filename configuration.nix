{
  lib,
  pkgs,
  settings,
  ...
}:

let
  chezmoiRepo = settings.chezmoiRepo or "";
  chezmoiEnabled = chezmoiRepo != "";
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
        mkdir -p /btrfs_tmp
        mount -o subvolid=5 /dev/mapper/cryptroot /btrfs_tmp

        if [[ ! -e /btrfs_tmp/root-blank ]]; then
          echo "ERROR: root-blank subvolume missing" >&2
          exit 1
        fi

        if [[ -e /btrfs_tmp/root ]]; then
          btrfs subvolume list -o /btrfs_tmp/root |
            cut -f9 -d' ' |
            while read -r subvolume; do
              btrfs subvolume delete "/btrfs_tmp/$subvolume"
            done
          btrfs subvolume delete /btrfs_tmp/root
        fi

        btrfs subvolume snapshot /btrfs_tmp/root-blank /btrfs_tmp/root
        umount /btrfs_tmp
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
      "/var/lib/systemd"
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
    ];
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
      "podman"
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

  systemd.user.services.chezmoi-init = lib.mkIf chezmoiEnabled {
    description = "Initialize chezmoi from settings.chezmoiRepo";
    wantedBy = [ "default.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecCondition = "${pkgs.bash}/bin/bash -c '! test -d %h/.local/share/chezmoi'";
      ExecStart = "${pkgs.chezmoi}/bin/chezmoi init --apply ${lib.escapeShellArg chezmoiRepo}";
      RemainAfterExit = true;
    };
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

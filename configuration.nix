{
  lib,
  pkgs,
  settings,
  ...
}:

{
  imports = [
    ./boot.nix
    ./persist.nix
    ./users.nix
    ./unfree.nix
  ];

  networking.hostName = settings.hostname;

  hardware.enableRedistributableFirmware = true;

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
  environment.persistence."/persist".directories = [
    "/var/lib/flatpak"
    "/var/lib/containers"
  ];

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

  # off unless a host turns it on. keys stay on /persist either way.
  services.openssh = {
    enable = lib.mkDefault false;
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
    ];
  };

  time.timeZone = settings.timeZone;
  i18n.defaultLocale = "en_US.UTF-8";

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

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [ "root" ];
      # only admins talk to the nix daemon
      allowed-users = [ "@wheel" ];
      auto-optimise-store = true;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  system.stateVersion = "25.05";
}

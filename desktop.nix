{
  lib,
  pkgs,
  settings,
  ...
}:

let
  desktop = settings.desktop;
  isPlasma = desktop == "plasma";
  isGnome = desktop == "gnome";
  isNiri = desktop == "niri";
in
{
  assertions = [
    {
      assertion = lib.elem desktop [
        "plasma"
        "gnome"
        "niri"
      ];
      message = "settings.desktop must be one of: plasma, gnome, niri (got: ${desktop})";
    }
  ];

  environment.persistence."/persist".directories =
    lib.optionals isPlasma [ "/var/lib/sddm" ]
    ++ lib.optionals isGnome [ "/var/lib/gdm" ];

  # --- Plasma ---
  services.xserver.enable = lib.mkIf (isPlasma || isGnome) true;
  services.displayManager.sddm = lib.mkIf isPlasma {
    enable = true;
    wayland.enable = true;
  };
  services.desktopManager.plasma6.enable = lib.mkIf isPlasma true;

  boot.plymouth = lib.mkIf isPlasma {
    theme = "breeze";
    themePackages = [ pkgs.kdePackages.breeze-plymouth ];
  };

  # --- GNOME ---
  services.displayManager.gdm = lib.mkIf isGnome {
    enable = true;
    wayland = true;
  };
  services.desktopManager.gnome.enable = lib.mkIf isGnome true;

  # --- niri + Noctalia ---
  programs.niri.enable = lib.mkIf isNiri true;
  programs.noctalia = lib.mkIf isNiri {
    enable = true;
    systemd.enable = true;
    recommendedServices.enable = true;
  };

  services.greetd = lib.mkIf isNiri {
    enable = true;
    settings = {
      default_session = {
        command = "${lib.getExe pkgs.tuigreet} --time --cmd ${lib.getExe' pkgs.niri "niri-session"}";
        user = "greeter";
      };
    };
  };

  environment.systemPackages =
    with pkgs;
    lib.optionals isPlasma [
      kdePackages.kate
      kdePackages.ark
      kdePackages.okular
      kdePackages.gwenview
      kdePackages.spectacle
      kdePackages.discover
      kdePackages.partitionmanager
    ]
    ++ lib.optionals isGnome [
      gnome-tweaks
      nautilus
      gnome-text-editor
      loupe
      file-roller
    ]
    ++ lib.optionals isNiri [
      xwayland-satellite
      fuzzel
      brightnessctl
      playerctl
    ];
}

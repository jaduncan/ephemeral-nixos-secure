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
    lib.optionals isPlasma [ "/var/lib/plasmalogin" ]
    ++ lib.optionals isGnome [ "/var/lib/gdm" ];

  # X11 helpers still useful for XWayland / some greeters
  services.xserver.enable = lib.mkIf (isPlasma || isGnome) true;

  # --- Plasma (Login Manager replaces SDDM on unstable) ---
  services.desktopManager.plasma6.enable = lib.mkIf isPlasma true;
  services.displayManager.plasma-login-manager.enable = lib.mkIf isPlasma true;

  boot.plymouth = lib.mkIf isPlasma {
    theme = "breeze";
    themePackages = [ pkgs.kdePackages.breeze-plymouth ];
  };

  # --- GNOME (GDM is Wayland-only as of GNOME 50; do not set gdm.wayland) ---
  services.displayManager.gdm.enable = lib.mkIf isGnome true;
  services.desktopManager.gnome.enable = lib.mkIf isGnome true;

  # --- niri + Noctalia (greeter + shell from nixpkgs) ---
  programs.niri.enable = lib.mkIf isNiri true;
  programs.noctalia = lib.mkIf isNiri {
    enable = true;
    systemd.enable = true;
    recommendedServices.enable = true;
  };
  # Wires greetd for us; session list includes niri when programs.niri.enable
  services.displayManager.noctalia-greeter.enable = lib.mkIf isNiri true;

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

{ pkgs, ... }:

let
  # pinned because the file carries Flathub's signing key. a hash mismatch
  # means Flathub changed it; check flathub.org before taking the new hash.
  flathubRepo = pkgs.fetchurl {
    url = "https://dl.flathub.org/repo/flathub.flatpakrepo";
    hash = "sha256-M3HdJQ5h2eFjNjAHP+/aFTzUQm9y9K+gwzc64uj+oDo=";
  };
in
{
  services.flatpak.enable = true;
  environment.persistence."/persist".directories = [ "/var/lib/flatpak" ];

  # the repo file comes from the store, so this needs no network and works
  # on an offline first boot
  systemd.services.flatpak-flathub = {
    description = "Add Flathub Flatpak remote";
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.flatpak ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      StateDirectory = "flatpak";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      PrivateNetwork = true;
      NoNewPrivileges = true;
      CapabilityBoundingSet = [ "" ];
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      ProtectClock = true;
      ProtectHostname = true;
      RestrictAddressFamilies = [ "AF_UNIX" ];
      RestrictNamespaces = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      SystemCallArchitectures = "native";
    };
    script = ''
      flatpak remote-add --system --if-not-exists flathub ${flathubRepo}
    '';
  };
}

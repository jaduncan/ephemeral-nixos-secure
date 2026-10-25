{
  config,
  lib,
  pkgs,
  settings,
  ...
}:

let
  home = "/home/${settings.username}";
  group = config.users.users.${settings.username}.group;
  chezmoiSource = "${home}/.local/share/chezmoi";
in
{
  assertions = [
    {
      assertion = builtins.match "[a-z_][a-z0-9_-]{0,31}" settings.username != null;
      message = "settings.username must be a plain account name ([a-z_][a-z0-9_-]*, max 32)";
    }
  ];

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

  system.activationScripts.chezmoiRepo = {
    deps = [ "users" ];
    text = ''
      if [ -f /persist/etc/chezmoi-repo ]; then
        chown ${lib.escapeShellArg "${settings.username}:${group}"} /persist/etc/chezmoi-repo
        chmod 600 /persist/etc/chezmoi-repo
      fi
    '';
  };

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
      Group = group;
      WorkingDirectory = home;
      Environment = "HOME=${home}";
      # clones over the network and writes dotfiles into home, nothing else.
      # chezmoi scripts that need sudo won't work here; run them by hand.
      ProtectSystem = "strict";
      ReadWritePaths = [ home ];
      PrivateTmp = true;
      PrivateDevices = true;
      NoNewPrivileges = true;
      CapabilityBoundingSet = [ "" ];
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      ProtectClock = true;
      ProtectHostname = true;
      RestrictAddressFamilies = [
        "AF_UNIX"
        "AF_INET"
        "AF_INET6"
      ];
      RestrictNamespaces = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      SystemCallArchitectures = "native";
    };
    script = ''
      set -euo pipefail
      line=$(head -n 1 /persist/etc/chezmoi-repo | tr -d '\r')
      read -r url rev extra <<<"$line"
      if [[ -z ''${url:-} || -z ''${rev:-} || -n ''${extra:-} ]]; then
        echo "/persist/etc/chezmoi-repo must be one line: <git-url> <commit>" >&2
        exit 1
      fi
      if [[ ! $rev =~ ^[0-9a-fA-F]{40}$ ]]; then
        echo "chezmoi commit must be the full 40-character hash" >&2
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
}

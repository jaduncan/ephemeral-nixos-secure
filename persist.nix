{
  config,
  lib,
  settings,
  ...
}:

let
  owner = lib.escapeShellArg "${settings.username}:${config.users.users.${settings.username}.group}";
in
{
  fileSystems."/persist".neededForBoot = true;
  fileSystems."/var/log".neededForBoot = true;

  # base system state. modules that add a service persist its state next to it.
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/home"
      "/var/lib/nixos"
      "/var/lib/AccountsService"
      {
        directory = "/var/lib/bluetooth";
        mode = "0700";
      }
      "/var/lib/NetworkManager"
      {
        directory = "/etc/NetworkManager/system-connections";
        mode = "0700";
      }
      "/var/lib/cups"
      {
        directory = "/var/lib/fwupd";
        user = "fwupd-refresh";
        group = "fwupd-refresh";
      }
      "/var/lib/systemd/backlight"
      "/var/lib/systemd/rfkill"
      "/var/lib/systemd/timers"
      "/var/lib/systemd/linger"
      {
        directory = "/var/lib/systemd/timesync";
        user = "systemd-timesync";
        group = "systemd-timesync";
      }
    ];
    files = [
      "/etc/machine-id"
      "/var/lib/systemd/random-seed"
      # host key for encrypted service credentials (libvirt uses one)
      "/var/lib/systemd/credential.secret"
    ];
  };

  # impermanence only bind-mounts a file that already exists on /persist;
  # otherwise it leaves a symlink and systemd writes the key onto the wiped
  # root. so make the key in /persist first.
  system.activationScripts.credentialSecret.text = ''
    if [ ! -s /persist/var/lib/systemd/credential.secret ]; then
      mkdir -p /persist/var/lib/systemd
      SYSTEMD_CREDENTIAL_SECRET=/persist/var/lib/systemd/credential.secret \
        ${config.systemd.package}/bin/systemd-creds setup
    fi
  '';
  system.activationScripts.persist-files.deps = [ "credentialSecret" ];

  # blank root drops /home/$USER. create it here.
  system.activationScripts.ensureUserHome = {
    deps = [
      "users"
      "groups"
    ];
    text = ''
      home=${lib.escapeShellArg "/persist/home/${settings.username}"}
      if [ ! -d "$home" ]; then
        mkdir -p "$home"
        chmod 0700 "$home"
      fi
      chown ${owner} "$home"
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
    '';
  };
}

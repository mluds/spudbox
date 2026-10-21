{
  config,
  lib,
  pkgs,
  ...
}:

with config.my;

let
  configScript = pkgs.writers.writePython3Bin "tautulli-config" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./tautulli-config.py);
in
{
  services.tautulli = {
    enable = true;
  };

  systemd.services.tautulli.serviceConfig = import ./hardening.nix // {
    # New files owner-only; see lock_down_data_dir above
    UMask = "0077";
  };

  systemd.services.tautulli-config = {
    description = "Update Tautulli configuration";
    after = [
      "tautulli.service"
      "plex-config.service"
    ];
    wants = [ "tautulli.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = lib.getExe configScript;
    };

    environment = {
      SECRETS_DIR = secretsDir;
      TAUTULLI_CONFIG = "${config.services.tautulli.dataDir}/config.ini";
      PLEX_PORT = toString plexPort;
      TAUTULLI_PORT = toString tautulliPort;
      TAUTULLI_ADMIN_USERNAME_FILE = "${secretsDir}/admin/username";
      TAUTULLI_ADMIN_PASSWORD_FILE = "${secretsDir}/tautulli/password";
    };
  };
}

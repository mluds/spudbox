{
  config,
  lib,
  pkgs,
  helpers,
  ...
}:

let
  inherit (config.my)
    secretsDir
    storageDir
    plexPort
    domain
    ;

  configScript = pkgs.writers.writePython3Bin "plex-config" {
    libraries = with pkgs.python3Packages; [
      plexapi
      requests
    ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./plex-config.py);
in
{
  users.groups.plex = { };

  services.plex = {
    enable = true;
    user = "plex";
    group = "media";
    openFirewall = true;
    # The iGPU for hardware transcoding, instead of every device ("*")
    accelerationDevices = [ "char-drm" ];
  };

  systemd = {
    tmpfiles.rules = [
      # Plex state (databases, Preferences.xml with its token) is private
      "d ${config.services.plex.dataDir} 0700 plex media -"
      "d ${secretsDir} 0700 root root -"
      "d ${secretsDir}/plex 0700 root root -"
      "f ${secretsDir}/plex/token 0600 root root -"
      "f ${secretsDir}/plex/username 0600 root root -"
      "f ${secretsDir}/plex/password 0600 root root -"
    ];

    services = {
      # On top of the module's own hardening (MemoryDenyWriteExecute,
      # ProtectSystem, ...). RestrictNamespaces stays off, as upstream notes.
      plex.serviceConfig = {
        CapabilityBoundingSet = "";
        # Plex sends its debug output to stdout too (~1,900 lines an hour) and
        # keeps full logs in its own Logs dir; the journal gets info and up.
        LogLevelMax = "info";
        ProtectProc = "invisible";
        ProtectKernelLogs = true;
        ProtectClock = true;
        ProtectHostname = true;
        SystemCallArchitectures = "native";
      };

      plex-config = {
        description = "Configure Plex libraries and settings after startup";
        after = [ "plex.service" ];
        requires = [ "plex.service" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "oneshot";
          User = "root";
          Environment = [
            "SECRETS_DIR=${secretsDir}"
            "MEDIA_DIR=${storageDir}/data/media"
            "PLEX_URL=http://localhost:${toString plexPort}"
            "PLEX_ACCESS_URL=https://plex.${domain}"
            "PLEX_USERNAME_FILE=${secretsDir}/plex/username"
            "PLEX_PASSWORD_FILE=${secretsDir}/plex/password"
          ];

          ExecStartPre = "${helpers}/bin/wait-for-http http://localhost:${toString plexPort}/identity 1";
          ExecStart = lib.getExe configScript;
        };
      };
    };
  };
}

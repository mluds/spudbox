{
  config,
  lib,
  pkgs,
  helpers,
  ...
}:

let
  inherit (config.spudbox)
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
  services.plex = {
    enable = true;
    user = "plex";
    group = "media";
    openFirewall = true;
    # The iGPU for hardware transcoding, instead of every device ("*")
    accelerationDevices = [ "char-drm" ];
  };

  systemd = {
    # Plex state (databases, Preferences.xml with its token) is private
    tmpfiles.rules = [ "d ${config.services.plex.dataDir} 0700 plex media -" ];

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
        # The main process is the FHS env's bwrap, not Plex. The module's
        # KillSignal (SIGQUIT, to the whole cgroup) made bwrap dump core (the
        # unit ended "failed") and, through --die-with-parent, SIGKILL Plex
        # mid-shutdown, so its transcoder and EasyAudioEncode were left until
        # the 90 s stop timeout. Signal only Plex (bwrap's one child) and wait:
        # it stops its own helpers, and bwrap exits with it. Anything left
        # still gets KillSignal afterwards.
        ExecStop = lib.getExe (
          pkgs.writeShellApplication {
            name = "plex-stop";
            runtimeInputs = with pkgs; [
              coreutils
              procps
            ];
            text = ''
              pkill -QUIT -P "''${MAINPID:-0}" || exit 0
              while kill -0 "$MAINPID" 2>/dev/null; do sleep 0.2; done
            '';
          }
        );
      };

      plex-config = {
        description = "Configure Plex libraries and settings after startup";
        # Wants, not Requires: the nightly backup stops Plex, and Requires=
        # would deactivate this unit until the next switch.
        after = [ "plex.service" ];
        wants = [ "plex.service" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
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

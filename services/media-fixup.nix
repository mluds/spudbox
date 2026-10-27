{
  config,
  lib,
  pkgs,
  helpers,
  ...
}:

# Every 15 minutes, checks video files added to the library since the last run
# and rewrites the ones some Plex clients can't play (see media-fixup.sh).
# Dolby Vision profile 5 is re-encoded on the Intel iGPU, so this needs one
# (spudbox.mediaFixup.enable; x86_64 only).
#
# ffmpeg parses downloaded (untrusted) files, so the timer runs it sandboxed
# as its own user: only the media pool's data dir is writable, API keys
# arrive via LoadCredential, and CAP_CHOWN alone lets it give a rewritten
# file its original owner. `sudo media-fixup FILE` still runs as root.
let
  cfg = config.spudbox;
  inherit (cfg)
    plexPort
    radarrPort
    secretsDir
    sonarrPort
    storageDir
    ;

  # Vulkan (libplacebo) and VA-API (hevc_vaapi) drivers for the Intel iGPU,
  # pointed at directly so the rest of the system is unaffected.
  gpuEnv = {
    VK_ICD_FILENAMES = "${pkgs.mesa}/share/vulkan/icd.d/intel_icd.x86_64.json";
    LIBVA_DRIVERS_PATH = "${pkgs.intel-media-driver}/lib/dri";
    LIBVA_DRIVER_NAME = "iHD";
  };

  stateDir = "/var/lib/media-fixup";
  workDir = "${storageDir}/data/.media-fixup";
  mediaDirs = [
    "${storageDir}/data/media/tv"
    "${storageDir}/data/media/movies"
  ];

  # credential name -> secret, read by the script's `secret` function
  credentials = {
    sonarr-api-key = "sonarr/api-key";
    radarr-api-key = "radarr/api-key";
    plex-token = "plex/token";
  };

  # Baked into the command so `sudo media-fixup FILE` works outside the unit.
  settings = gpuEnv // {
    MEDIA_DIRS = toString mediaDirs;
    TV_DIR = "${storageDir}/data/media/tv";
    WORK_DIR = workDir;
    STATE_DIR = stateDir;
    XDG_CACHE_HOME = "${stateDir}/cache"; # Mesa shader cache
    SONARR_PORT = toString sonarrPort;
    RADARR_PORT = toString radarrPort;
    PLEX_PORT = toString plexPort;
  };

  mediaFixup = pkgs.writeShellApplication {
    name = "media-fixup";
    runtimeInputs = with pkgs; [
      ffmpeg-full
      curl
      jq
      xmlstarlet
      coreutils
      findutils
      gnugrep
      gnused
      helpers
    ];
    text =
      lib.concatLines (lib.mapAttrsToList (n: v: "export ${n}=${lib.escapeShellArg v}") settings)
      + builtins.readFile ./media-fixup.sh;
  };
in
lib.mkIf cfg.mediaFixup.enable {
  assertions = [
    {
      assertion = pkgs.stdenv.hostPlatform.isx86_64;
      message = "spudbox.mediaFixup needs an Intel iGPU (x86_64).";
    }
  ];

  environment.systemPackages = [ mediaFixup ];

  users.users.media-fixup = {
    isSystemUser = true;
    group = "media";
  };

  systemd = {
    tmpfiles.rules = [
      # Scratch space on the same pool as the media, so finished files are
      # moved into place rather than copied.
      "d ${workDir} 0700 media-fixup media -"
    ];

    services.media-fixup = {
      description = "Make new video files playable on every Plex client";
      after = [
        "plex.service"
        "sonarr.service"
        "radarr.service"
      ];
      unitConfig.RequiresMountsFor = [ storageDir ];
      inherit (cfg) onFailure;
      serviceConfig = import ./hardening.nix // {
        Type = "oneshot";
        User = "media-fixup";
        Group = "media";
        StateDirectory = "media-fixup";
        StateDirectoryMode = "0700";
        LoadCredential = lib.mapAttrsToList (name: path: "${name}:${secretsDir}/${path}") credentials;
        # Only the media pool's data dir is writable, which also confines
        # CAP_CHOWN (read-only mounts refuse chown). One path, not one per
        # library: separate bind mounts would turn the scratch -> library
        # rename into a full copy (EXDEV).
        ProtectSystem = "strict";
        ReadWritePaths = [ "${storageDir}/data" ];
        CapabilityBoundingSet = [ "CAP_CHOWN" ];
        AmbientCapabilities = [ "CAP_CHOWN" ];
        # The iGPU (VA-API/Vulkan) instead of PrivateDevices' empty /dev
        PrivateDevices = false;
        DevicePolicy = "closed";
        DeviceAllow = [ "char-drm rw" ];
        SupplementaryGroups = [
          "render"
          "video"
        ];
        ExecStart = lib.getExe mediaFixup;
        Nice = 10;
        IOSchedulingClass = "idle";
      };
    };

    timers.media-fixup = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "10min";
        OnUnitInactiveSec = "15min";
      };
    };
  };
}

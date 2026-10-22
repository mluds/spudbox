{
  config,
  lib,
  pkgs,
  helpers,
  ...
}:

with config.my;

# Every 15 minutes, checks video files added to the library since the last run
# and rewrites the ones some Plex clients can't play (see media-fixup.sh).
# Dolby Vision profile 5 is re-encoded on the Intel iGPU, so this is
# x86_64 (prod) only.
let
  # Vulkan (libplacebo) and VA-API (hevc_vaapi) drivers for the Intel iGPU,
  # pointed at directly so the rest of the system is unaffected.
  gpuEnv = {
    VK_ICD_FILENAMES = "${pkgs.mesa}/share/vulkan/icd.d/intel_icd.x86_64.json";
    LIBVA_DRIVERS_PATH = "${pkgs.intel-media-driver}/lib/dri";
    LIBVA_DRIVER_NAME = "iHD";
  };

  stateDir = "/var/lib/media-fixup";

  # Baked into the command so `sudo media-fixup FILE` works outside the unit.
  settings = gpuEnv // {
    MEDIA_DIRS = "${storageDir}/data/media/tv ${storageDir}/data/media/movies";
    TV_DIR = "${storageDir}/data/media/tv";
    WORK_DIR = "${storageDir}/data/.media-fixup";
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
lib.mkIf pkgs.stdenv.hostPlatform.isx86_64 {
  environment.systemPackages = [ mediaFixup ];

  systemd = {
    tmpfiles.rules = [
      "d ${stateDir} 0700 root root -"
      # Scratch space on the same pool as the media, so finished files are
      # moved into place rather than copied.
      "d ${storageDir}/data/.media-fixup 0700 root root -"
    ];

    services.media-fixup = {
      description = "Make new video files playable on every Plex client";
      after = [
        "plex.service"
        "sonarr.service"
        "radarr.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        User = "root"; # reads API keys from the root-only secrets dir
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

{
  config,
  pkgs,
  lib,
  ...
}:

with config.my;

let
  configScript = pkgs.writers.writePython3Bin "bazarr-config" {
    libraries = with pkgs.python3Packages; [
      deepmerge
      pyyaml
    ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./bazarr-config.py);
  configTemplate = pkgs.writeText "bazarr-config-template.yaml" (
    lib.generators.toYAML { } {
      general = {
        ip = "127.0.0.1"; # loopback only; reached through Caddy
        enabled_providers = [
          "opensubtitlescom"
          "assrt"
        ];
        serie_default_enabled = true;
        serie_default_profile = 1;
        movie_default_enabled = true;
        movie_default_profile = 1;
        parse_embedded_audio_track = false;
        use_embedded_subs = true;
        chmod = "0660";
        chmod_enabled = true;
        use_radarr = true;
        use_sonarr = true;
        subzero_mods = "remove_tags,remove_HI,common";
      };
      subsync = {
        use_subsync = true;
        use_subsync_movie_threshold = false;
        use_subsync_threshold = false;
        force_audio = true;
        no_fix_framerate = false;
      };
      auth = {
        type = "form";
      };
      radarr = {
        ip = "localhost";
        port = radarrPort;
      };
      sonarr = {
        ip = "localhost";
        port = sonarrPort;
      };
      opensubtitlescom = {
        include_ai_translated = false;
        use_hash = false;
      };
      assrt = { };
    }
  );

  newConfigContent = builtins.readFile configTemplate;
in
{
  users.groups.bazarr = { };

  services.bazarr = {
    enable = true;
    user = "bazarr";
    group = "media";
    openFirewall = false;
  };

  systemd.services.bazarr.serviceConfig = import ../hardening.nix;

  systemd.services.bazarr-config = {
    description = "Bazarr Configuration Updater";
    after = [
      "bazarr.service"
      "radarr-config.service"
      "sonarr-config.service"
    ];
    wants = [ "bazarr.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Environment = [
        "SECRETS_DIR=${secretsDir}"
        "CONFIG_PATH=/var/lib/bazarr/config/config.yaml"
        "DB_PATH=/var/lib/bazarr/db/bazarr.db"
        "NEW_CONFIG=${lib.escapeShellArg newConfigContent}"
      ];
      ExecStart = lib.getExe configScript;
    };
  };
}

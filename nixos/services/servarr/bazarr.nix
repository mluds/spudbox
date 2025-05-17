{ config, pkgs, lib, secrets, ... }:

with config.my;

let 
  adminPasswordMD5 = builtins.hashString "md5" secrets.adminPassword;

  pythonEnv = pkgs.python3.withPackages (ps: [ ps.deepmerge ps.pyyaml ]);
  mergeScript = pkgs.writeScript "bazarr-config-merge.py" ''
    #!${pkgs.python3}/bin/python
    import yaml
    import sys
    import os
    from deepmerge import always_merger

    config_path = os.environ['CONFIG_PATH']
    new_config = yaml.safe_load(os.environ['NEW_CONFIG'])
    
    try:
        with open(config_path, 'r') as f:
            existing_config = yaml.safe_load(f) or {}
    except FileNotFoundError:
        existing_config = {}

    merged_config = always_merger.merge(existing_config, new_config)
    
    with open(config_path, 'w') as f:
        yaml.dump(merged_config, f, sort_keys=False)
    
    # Restart service if config changed
    if existing_config != merged_config:
        os.system("systemctl restart bazarr")
  '';

  configTemplate = pkgs.writeText "bazarr-config-template.yaml" (lib.generators.toYAML {} {
    general = {
      enabled_providers = [ "opensubtitlescom" "assrt" ];
      serie_default_enabled = true;
      serie_default_profile = 1;
      movie_default_enabled = true;
      movie_default_profile = 1;
      parse_embedded_audio_track = false;
      use_embedded_subs = false;
      chmod = "0660";
      chmod_enabled = true;
      use_radarr = true;
      use_sonarr = true;
      subzero_mods = "remove_tags,remove_HI";
    };
    auth = {
      type = "form";
      username = secrets.adminUsername;
      password = adminPasswordMD5;
      apikey = secrets.bazarrApiKey;
    };
    radarr = {
      ip = "localhost";
      port = toString radarrPort;
      apikey = secrets.radarrApiKey;
    };
    sonarr = {
      ip = "localhost";
      port = toString sonarrPort;
      apikey = secrets.sonarrApiKey;
    };
    opensubtitlescom = {
      username = secrets.opensubtitlesUsername;
      password = secrets.opensubtitlesPassword;
      include_ai_translated = false;
      use_hash = true;
    };
    assrt = {
      token = secrets.assrtApiToken;
    };
  });

  newConfigContent = builtins.readFile configTemplate;
in {
  users.groups.bazarr = {};

  users.users.bazarr = {
    isSystemUser = true;
    group = "bazarr";
    extraGroups = [ "media" ];
    createHome = false;
    useDefaultShell = false;
  };

  services.bazarr = {
    enable = true;
    user = "bazarr";
    openFirewall = false;
  };

  systemd.services.bazarr-config-updater = {
    description = "Bazarr Configuration Updater";
    after = [ "bazarr.service" ];
    wants = [ "bazarr.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Group = "root";
      Environment = [
        "CONFIG_PATH=/var/lib/bazarr/config/config.yaml"
        "NEW_CONFIG=${lib.escapeShellArg newConfigContent}"
      ];
      ExecStart = "${pythonEnv}/bin/python ${mergeScript}";
    };
  };
}

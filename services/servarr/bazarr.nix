{ config, pkgs, lib, secrets, ... }:

with config.my;

let
  adminPasswordMD5 = builtins.hashString "md5" secrets.adminPassword;

  pythonEnv = pkgs.python3.withPackages (ps: [ ps.deepmerge ps.pyyaml ]);
  configScript = pkgs.writeScript "bazarr-config.py" ''
    #!${pkgs.python3}/bin/python
    import sqlite3
    import yaml
    import os
    import time
    import sys
    from deepmerge import always_merger

    def wait_for_file(file_path, timeout=300, check_interval=3):
      elapsed = 0
      while elapsed < timeout:
        if os.path.exists(file_path):
          return True
        time.sleep(check_interval)
        elapsed += check_interval
      return False

    def make_lists_unique(obj):
      if isinstance(obj, list):
        seen = set()
        unique_list = []
        unhashable_items = []

        for item in obj:
          processed_item = make_lists_unique(item)

          try:
            if processed_item not in seen:
              seen.add(processed_item)
              unique_list.append(processed_item)
          except TypeError:
            if not any(processed_item == x for x in unhashable_items):
              unhashable_items.append(processed_item)
              unique_list.append(processed_item)
        return unique_list

      elif isinstance(obj, dict):
        return {k: make_lists_unique(v) for k, v in obj.items()}

      else:
        return obj

    config_path = os.environ['CONFIG_PATH']
    new_config = yaml.safe_load(os.environ['NEW_CONFIG'])

    # Wait for Radarr API key file
    radarr_key_path = "${secretsDir}/radarr/api-key"
    wait_for_file(radarr_key_path):

    # Read Radarr API key and update configuration
    with open(radarr_key_path, 'r') as f:
      radarr_api_key = f.read().strip()
    if 'radarr' in new_config:
      new_config['radarr']['apikey'] = radarr_api_key
    else:
      new_config['radarr'] = {'apikey': radarr_api_key}

    wait_for_file(config_path)

    os.system("systemctl stop bazarr")

    try:
      with open(config_path, 'r') as f:
        existing_config = yaml.safe_load(f) or {}
    except FileNotFoundError:
      existing_config = {}

    merged_config = always_merger.merge(existing_config, new_config)
    merged_config = make_lists_unique(merged_config)

    with open(config_path, 'w') as f:
      yaml.dump(merged_config, f, sort_keys=False)

    db_path = os.environ['DB_PATH']
    wait_for_file(db_path)
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("UPDATE table_settings_languages SET enabled = 1 WHERE code2 IN ('en', 'zh');")
    cursor.execute("DELETE FROM table_languages_profiles;")
    cursor.execute("""
      INSERT INTO table_languages_profiles (
        "profileId", cutoff, "originalFormat", items, name,
        "mustContain", "mustNotContain", tag
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """, (
      1, None, 0,
      '[{"id": 1, "language": "en", "audio_exclude": "False", "hi": "False", "forced": "False"}]',
      'Default', '[]', '[]', None
    ))
    cursor.execute("""
      INSERT INTO table_languages_profiles (
        "profileId", cutoff, "originalFormat", items, name,
        "mustContain", "mustNotContain", tag
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """, (
      2, None, 0,
      '[{"id": 1, "language": "en", "audio_exclude": "False", "hi": "False", "forced": "False"}, {"id": 2, "language": "zh", "audio_exclude": "False", "hi": "False", "forced": "False"}]',
      'English and Chinese', '[]', '[]', None
    ))
    conn.commit()

    os.system("systemctl start bazarr")
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
      username = secrets.adminUsername;
      password = adminPasswordMD5;
      apikey = secrets.bazarrApiKey;
    };
    radarr = {
      ip = "localhost";
      port = toString radarrPort;
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
      use_hash = false;
    };
    assrt = {
      token = secrets.assrtApiToken;
    };
  });

  newConfigContent = builtins.readFile configTemplate;
in {
  users.groups.bazarr = {};

  services.bazarr = {
    enable = true;
    user = "bazarr";
    group = "media";
    openFirewall = false;
  };

  systemd.services.bazarr-config = {
    description = "Bazarr Configuration Updater";
    serviceConfig = {
      Type = "exec";
      User = "root";
      Environment = [
        "CONFIG_PATH=/var/lib/bazarr/config/config.yaml"
        "DB_PATH=/var/lib/bazarr/db/bazarr.db"
        "NEW_CONFIG=${lib.escapeShellArg newConfigContent}"
      ];
      ExecStart = "${pythonEnv}/bin/python ${configScript}";
    };
  };
}

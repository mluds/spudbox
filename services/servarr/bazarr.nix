{ config, pkgs, lib, ... }:

with config.my;

let
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

    # Read API keys and update configuration
    services = [
      ('auth', 'bazarr'),
      ('radarr', 'radarr'),
      ('sonarr', 'sonarr')
    ]
    for key, service in services:
        key_path = f"${secretsDir}/{service}/api-key"
        wait_for_file(key_path)

        with open(key_path, 'r') as f:
            api_key = f.read().strip()
        if service in new_config:
            new_config[key]['apikey'] = api_key
        else:
            new_config[key] = {'apikey': api_key}

    # Read OpenSubtitles credentials from files
    opensubtitles_username_path = '${secretsDir}/opensubtitles/username'
    opensubtitles_password_path = '${secretsDir}/opensubtitles/password'
    
    wait_for_file(opensubtitles_username_path)
    wait_for_file(opensubtitles_password_path)

    with open(opensubtitles_username_path, 'r') as f:
        opensubtitles_username = f.read().strip()
    with open(opensubtitles_password_path, 'r') as f:
        opensubtitles_password = f.read().strip()

    # Update OpenSubtitles configuration
    if 'opensubtitlescom' in new_config:
        new_config['opensubtitlescom']['username'] = opensubtitles_username
        new_config['opensubtitlescom']['password'] = opensubtitles_password
    else:
        new_config['opensubtitlescom'] = {
            'username': opensubtitles_username,
            'password': opensubtitles_password,
            'include_ai_translated': False,
            'use_hash': False
        }

    # Read admin credentials from files
    import hashlib
    with open('${secretsDir}/admin/username', 'r') as f:
        admin_username = f.read().strip()
    with open('${secretsDir}/admin/password', 'r') as f:
        admin_password_md5 = hashlib.md5(f.read().strip().encode()).hexdigest()
    new_config.setdefault('auth', {})
    new_config['auth']['type'] = 'form'
    new_config['auth']['username'] = admin_username
    new_config['auth']['password'] = admin_password_md5

    # Read ASSRT token from secrets
    assrt_token_path = '${secretsDir}/assrt/api-token'
    if os.path.exists(assrt_token_path):
        with open(assrt_token_path, 'r') as f:
            new_config.setdefault('assrt', {})
            new_config['assrt']['token'] = f.read().strip()

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

    # Export the actual API key to secrets for homepage
    api_key_dir = "${secretsDir}/bazarr"
    os.makedirs(api_key_dir, exist_ok=True)
    with open(config_path, 'r') as f:
      final_config = yaml.safe_load(f) or {}
    api_key = final_config.get('auth', {}).get('apikey', "")
    with open(os.path.join(api_key_dir, 'api-key'), 'w') as f:
      f.write(api_key)
    print(f"Exported Bazarr API key to {api_key_dir}/api-key")
  '';
  configTemplate = pkgs.writeText "bazarr-config-template.yaml" (lib.generators.toYAML {} {
    general = {
      enabled_providers = [ "opensubtitlescom" "assrt" ];
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
      port = toString radarrPort;
    };
    sonarr = {
      ip = "localhost";
      port = toString sonarrPort;
    };
    opensubtitlescom = {
      include_ai_translated = false;
      use_hash = false;
    };
    assrt = {};
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
    after = [ "bazarr.service" "radarr-config.service" "sonarr-config.service" ];
    wants = [ "bazarr.service" ];
    wantedBy = [ "multi-user.target" ];
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

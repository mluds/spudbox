import hashlib
import os
import sqlite3
import subprocess
import time

import yaml
from deepmerge import always_merger

SECRETS_DIR = os.environ["SECRETS_DIR"]


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


config_path = os.environ["CONFIG_PATH"]
new_config = yaml.safe_load(os.environ["NEW_CONFIG"])

# Read API keys and update configuration
services = [("auth", "bazarr"), ("radarr", "radarr"), ("sonarr", "sonarr")]
for key, service in services:
    key_path = f"{SECRETS_DIR}/{service}/api-key"
    wait_for_file(key_path)

    with open(key_path) as f:
        api_key = f.read().strip()
    if key in new_config:
        new_config[key]["apikey"] = api_key
    else:
        new_config[key] = {"apikey": api_key}

# Read OpenSubtitles credentials from files
opensubtitles_username_path = f"{SECRETS_DIR}/opensubtitles/username"
opensubtitles_password_path = f"{SECRETS_DIR}/opensubtitles/password"

wait_for_file(opensubtitles_username_path)
wait_for_file(opensubtitles_password_path)

with open(opensubtitles_username_path) as f:
    opensubtitles_username = f.read().strip()
with open(opensubtitles_password_path) as f:
    opensubtitles_password = f.read().strip()

# Update OpenSubtitles configuration
if "opensubtitlescom" in new_config:
    new_config["opensubtitlescom"]["username"] = opensubtitles_username
    new_config["opensubtitlescom"]["password"] = opensubtitles_password
else:
    new_config["opensubtitlescom"] = {
        "username": opensubtitles_username,
        "password": opensubtitles_password,
        "include_ai_translated": False,
        "use_hash": False,
    }

# Read admin credentials from files

with open(f"{SECRETS_DIR}/admin/username") as f:
    admin_username = f.read().strip()
with open(f"{SECRETS_DIR}/bazarr/password") as f:
    # Bazarr stores and checks an unsalted MD5; its format, not our choice
    admin_password_md5 = hashlib.md5(f.read().strip().encode()).hexdigest()  # noqa: S324
new_config.setdefault("auth", {})
new_config["auth"]["type"] = "form"
new_config["auth"]["username"] = admin_username
new_config["auth"]["password"] = admin_password_md5

# Read ASSRT token from secrets
assrt_token_path = f"{SECRETS_DIR}/assrt/api-token"
if os.path.exists(assrt_token_path):
    with open(assrt_token_path) as f:
        new_config.setdefault("assrt", {})
        new_config["assrt"]["token"] = f.read().strip()

wait_for_file(config_path)

subprocess.run(["systemctl", "stop", "bazarr"], check=True)

try:
    with open(config_path) as f:
        existing_config = yaml.safe_load(f) or {}
except FileNotFoundError:
    existing_config = {}

merged_config = always_merger.merge(existing_config, new_config)
merged_config = make_lists_unique(merged_config)

with open(config_path, "w") as f:
    yaml.dump(merged_config, f, sort_keys=False)

db_path = os.environ["DB_PATH"]
wait_for_file(db_path)
conn = sqlite3.connect(db_path)
cursor = conn.cursor()
cursor.execute("UPDATE table_settings_languages SET enabled = 1 WHERE code2 IN ('en', 'zh');")
cursor.execute("DELETE FROM table_languages_profiles;")
cursor.execute(
    """
  INSERT INTO table_languages_profiles (
    "profileId", cutoff, "originalFormat", items, name,
    "mustContain", "mustNotContain", tag
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
""",
    (
        1,
        None,
        0,
        '[{"id": 1, "language": "en", "audio_exclude": "False", "hi": "False", "forced": "False"}]',
        "Default",
        "[]",
        "[]",
        None,
    ),
)
cursor.execute(
    """
  INSERT INTO table_languages_profiles (
    "profileId", cutoff, "originalFormat", items, name,
    "mustContain", "mustNotContain", tag
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
""",
    (
        2,
        None,
        0,
        '[{"id": 1, "language": "en", "audio_exclude": "False", "hi": "False", "forced": "False"}, {"id": 2, "language": "zh", "audio_exclude": "False", "hi": "False", "forced": "False"}]',
        "English and Chinese",
        "[]",
        "[]",
        None,
    ),
)
conn.commit()

subprocess.run(["systemctl", "start", "bazarr"], check=True)

# Export the actual API key to secrets for homepage
os.umask(0o077)  # a new secret file is 0600 from the start
api_key_dir = f"{SECRETS_DIR}/bazarr"
os.makedirs(api_key_dir, exist_ok=True)
with open(config_path) as f:
    final_config = yaml.safe_load(f) or {}
api_key = final_config.get("auth", {}).get("apikey", "")
with open(os.path.join(api_key_dir, "api-key"), "w") as f:
    f.write(api_key)
print(f"Exported Bazarr API key to {api_key_dir}/api-key")

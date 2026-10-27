import hashlib
import json
import os
import sqlite3
import subprocess
import time

import yaml
from deepmerge import Merger

SECRETS_DIR = os.environ["SECRETS_DIR"]
CONFIG_PATH = os.environ["CONFIG_PATH"]
DB_PATH = os.environ["DB_PATH"]

# Lists (enabled_providers) gain the template's entries without repeating them
# on every run; everything else is overwritten by the template.
merger = Merger(
    [(list, ["append_unique"]), (dict, ["merge"]), (set, ["union"])], ["override"], ["override"]
)


def read_secret(name):
    with open(f"{SECRETS_DIR}/{name}") as f:
        return f.read().strip()


def wait_for_file(path, timeout=300):
    """Bazarr writes its config and DB on first start."""
    deadline = time.time() + timeout
    while not os.path.exists(path):
        if time.time() > deadline:
            raise SystemExit(f"Bazarr never wrote {path}")
        time.sleep(3)


def language(id_, code):
    return {"id": id_, "language": code, "audio_exclude": "False", "hi": "False", "forced": "False"}


# spudbox.bazarr.languageProfiles, as JSON: [{name, languages}, ...]
with open(os.environ["LANGUAGE_PROFILES"]) as f:
    profiles = json.load(f)
# profileId -> (name, languages)
LANGUAGE_PROFILES = {
    id_: (profile["name"], [language(i, code) for i, code in enumerate(profile["languages"], 1)])
    for id_, profile in enumerate(profiles, 1)
}
LANGUAGES = sorted({code for profile in profiles for code in profile["languages"]})

with open(os.environ["CONFIG_TEMPLATE"]) as f:
    new_config = yaml.safe_load(f)
new_config["radarr"]["apikey"] = read_secret("radarr/api-key")
new_config["sonarr"]["apikey"] = read_secret("sonarr/api-key")
if "opensubtitlescom" in new_config:
    new_config["opensubtitlescom"]["username"] = read_secret("opensubtitles/username")
    new_config["opensubtitlescom"]["password"] = read_secret("opensubtitles/password")
new_config["auth"]["username"] = read_secret("admin/username")
# Bazarr stores and checks an unsalted MD5; its format, not our choice
new_config["auth"]["password"] = hashlib.md5(  # noqa: S324
    read_secret("bazarr/password").encode()
).hexdigest()
if "assrt" in new_config:
    new_config["assrt"]["token"] = read_secret("assrt/api-token")

wait_for_file(CONFIG_PATH)
wait_for_file(DB_PATH)
subprocess.run(["systemctl", "stop", "bazarr"], check=True)

with open(CONFIG_PATH) as f:
    config = merger.merge(yaml.safe_load(f) or {}, new_config)
with open(CONFIG_PATH, "w") as f:
    yaml.dump(config, f, sort_keys=False)

with sqlite3.connect(DB_PATH) as conn:
    conn.executemany(
        "UPDATE table_settings_languages SET enabled = 1 WHERE code2 = ?;",
        [(code,) for code in LANGUAGES],
    )
    conn.execute("DELETE FROM table_languages_profiles;")
    conn.executemany(
        """
      INSERT INTO table_languages_profiles (
        "profileId", cutoff, "originalFormat", items, name,
        "mustContain", "mustNotContain", tag
      ) VALUES (?, NULL, 0, ?, ?, '[]', '[]', NULL)
    """,
        [(id_, json.dumps(items), name) for id_, (name, items) in LANGUAGE_PROFILES.items()],
    )
conn.close()

subprocess.run(["systemctl", "start", "bazarr"], check=True)

# Export Bazarr's own API key for homepage
os.umask(0o077)  # a new secret file is 0600 from the start
os.makedirs(f"{SECRETS_DIR}/bazarr", exist_ok=True)
with open(f"{SECRETS_DIR}/bazarr/api-key", "w") as f:
    f.write(config.get("auth", {}).get("apikey", ""))
print(f"Exported Bazarr API key to {SECRETS_DIR}/bazarr/api-key")

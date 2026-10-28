# First-time setup of a fresh Audiobookshelf install: replaces the users
# table with a root account whose password is audiobookshelf/password, then
# creates the Audiobooks library. Other people are added in its web UI. It refuses to run on a
# database that already has users, because the DELETE would wipe them and
# their listening progress; set ABS_FORCE=1 to override (systemctl
# set-environment, or edit the unit). With ABS_IF_EMPTY=1 (how
# audiobookshelf-access runs it on every boot) it waits for Audiobookshelf
# and quietly does nothing once there are users.
import json
import os
import socket
import sqlite3
import subprocess
import sys
import time

import bcrypt
import jwt
import requests

SECRETS_DIR = os.environ["SECRETS_DIR"]
DB_PATH = os.environ["ABS_DB"]
HOST = "localhost"
PORT = os.environ["ABS_PORT"]
BASE_URL = f"http://{HOST}:{PORT}"
USER_ID = os.environ["ADMIN_USER_ID"]


def read_secret(name):
    with open(f"{SECRETS_DIR}/{name}") as f:
        return f.read().strip()


def user_count():
    conn = sqlite3.connect(DB_PATH)
    try:
        return conn.execute("SELECT count(*) FROM users").fetchone()[0]
    except sqlite3.OperationalError:  # no users table yet
        return 0
    finally:
        conn.close()


def get_token_secret():
    conn = sqlite3.connect(DB_PATH)
    row = conn.execute("SELECT value FROM settings WHERE key = 'server-settings'").fetchone()
    conn.close()
    if row:
        secret = json.loads(row[0]).get("tokenSecret", "")
        if secret:
            return secret
    # The DB doesn't have it yet
    return read_secret("audiobookshelf/token-secret")


def wait_for_port(host, port, timeout=30, retry_interval=1):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection((host, port), timeout=1):
                return
        except OSError:
            time.sleep(retry_interval)
    sys.exit(f"Audiobookshelf didn't open port {port}")


def reset_root_user(username, token):
    pash = bcrypt.hashpw(
        read_secret("audiobookshelf/password").encode("utf-8"),
        bcrypt.gensalt(rounds=8, prefix=b"2a"),
    ).decode()
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("DELETE FROM users;")
    cursor.execute(
        """
    INSERT INTO users (
      id, username, email, pash, type, token, isActive, isLocked, lastSeen,
      permissions, bookmarks, extraData, createdAt, updatedAt
    ) VALUES (
      ?, ?, '', ?, 'root', ?, 1, 0, NULL, ?, '[]', ?,
      datetime('now') || ' +00:00', datetime('now') || ' +00:00'
    )
    """,
        (
            USER_ID,
            username,
            pash,
            token,
            json.dumps(
                {
                    "download": True,
                    "update": True,
                    "delete": True,
                    "upload": True,
                    "createEreader": True,
                    "accessAllLibraries": True,
                    "accessAllTags": True,
                    "accessExplicitContent": True,
                    "selectedTagsNotAccessible": False,
                    "librariesAccessible": [],
                    "itemTagsSelected": [],
                }
            ),
            json.dumps({"seriesHideFromContinueListening": []}),
        ),
    )
    conn.commit()
    conn.close()
    print("Root user reset.")


def create_library(headers):
    lib_name = "Audiobooks"
    libraries = requests.get(f"{BASE_URL}/api/libraries", headers=headers, timeout=30).json()[
        "libraries"
    ]
    if any(lib["name"] == lib_name for lib in libraries):
        print("Audiobooks library already exists")
        return
    print("Audiobooks library not found, creating...")
    new_library = {
        "name": lib_name,
        "folders": [{"fullPath": os.environ["LIBRARY_DIR"]}],
        "icon": "audiobookshelf",
        "mediaType": "book",
        "provider": "google",
    }
    response = requests.post(
        f"{BASE_URL}/api/libraries", headers=headers, json=new_library, timeout=30
    )
    response.raise_for_status()
    library_id = response.json()["id"]
    response = requests.post(
        f"{BASE_URL}/api/libraries/{library_id}/scan", headers=headers, timeout=30
    )
    response.raise_for_status()
    print("Library created successfully!")


def main():
    if os.getenv("ABS_IF_EMPTY") == "1":
        # Audiobookshelf creates its database on first start.
        wait_for_port(HOST, PORT, timeout=300)
        if user_count():
            print("Audiobookshelf is set up already; nothing to do.")
            return
    existing = user_count()
    if existing and os.getenv("ABS_FORCE") != "1":
        sys.exit(
            f"Refusing: the database has {existing} user(s), which this would delete. Set ABS_FORCE=1 to override."
        )

    username = read_secret("admin/username")
    # A forged root token, used only for this setup's own API calls.
    # Homepage's key is a scoped API key managed by audiobookshelf-access.
    token = jwt.encode(payload={"userId": USER_ID, "username": username}, key=get_token_secret())
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

    subprocess.run(["systemctl", "stop", "audiobookshelf"], check=True)
    reset_root_user(username, token)
    subprocess.run(["systemctl", "start", "audiobookshelf"], check=True)
    wait_for_port(HOST, PORT)
    create_library(headers)


if __name__ == "__main__":
    main()

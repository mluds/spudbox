import os
import secrets
import subprocess
import sys
import time

import requests

SECRETS_DIR = os.environ["SECRETS_DIR"]
BASE = f"http://localhost:{os.environ['ABS_PORT']}"
KEY_FILE = f"{SECRETS_DIR}/audiobookshelf/apikey"
HOMEPAGE_USER = "homepage"


def read_secret(name):
    with open(f"{SECRETS_DIR}/{name}") as f:
        return f.read().strip()


def bearer(token):
    return {"Authorization": f"Bearer {token}"}


def login(username, password):
    r = requests.post(
        f"{BASE}/login", json={"username": username, "password": password}, timeout=10
    )
    return r.json()["user"]["accessToken"] if r.ok else None


def wait_for_abs(timeout=180):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            if requests.get(f"{BASE}/healthcheck", timeout=3).ok:
                return
        except requests.RequestException:
            pass
        time.sleep(2)
    sys.exit("Audiobookshelf didn't come up")


def root_token():
    username = read_secret("admin/username")
    new = read_secret("audiobookshelf/password")
    token = login(username, new)
    if token:
        return token
    old = read_secret("admin/password")
    old_token = login(username, old)
    if not old_token:
        sys.exit("ERROR: neither audiobookshelf/password nor admin/password logs in as root")
    print("Changing the root password to audiobookshelf/password...")
    r = requests.patch(
        f"{BASE}/api/me/password",
        headers=bearer(old_token),
        json={"password": old, "newPassword": new},
        timeout=10,
    )
    r.raise_for_status()
    token = login(username, new)
    if not token:
        sys.exit("ERROR: new root password rejected after the change")
    return token


def homepage_user(token):
    users = requests.get(f"{BASE}/api/users", headers=bearer(token), timeout=10).json()["users"]
    for user in users:
        if user["username"] == HOMEPAGE_USER:
            return user
    print(f"Creating read-only user {HOMEPAGE_USER}...")
    r = requests.post(
        f"{BASE}/api/users",
        headers=bearer(token),
        timeout=10,
        json={
            "username": HOMEPAGE_USER,
            # Never used to log in; only its API key is
            "password": secrets.token_urlsafe(32),
            "type": "user",
            "isActive": True,
            "permissions": {
                "download": False,
                "update": False,
                "delete": False,
                "upload": False,
                "createEreader": False,
                "accessAllLibraries": True,
                "accessAllTags": True,
                "accessExplicitContent": True,
            },
        },
    )
    r.raise_for_status()
    return r.json()["user"]


def key_is_valid():
    try:
        key = open(KEY_FILE).read().strip()
    except FileNotFoundError:
        return False
    r = requests.get(f"{BASE}/api/me", headers=bearer(key), timeout=10)
    return r.ok and r.json().get("username") == HOMEPAGE_USER


def main():
    wait_for_abs()
    token = root_token()
    user = homepage_user(token)
    if key_is_valid():
        print("Homepage API key is valid")
        return
    # Replace any earlier homepage keys, then issue a new one
    keys = requests.get(f"{BASE}/api/api-keys", headers=bearer(token), timeout=10).json()["apiKeys"]
    for key in keys:
        if key["name"] == HOMEPAGE_USER:
            requests.delete(f"{BASE}/api/api-keys/{key['id']}", headers=bearer(token), timeout=10)
    r = requests.post(
        f"{BASE}/api/api-keys",
        headers=bearer(token),
        timeout=10,
        json={"name": HOMEPAGE_USER, "userId": user["id"], "isActive": True},
    )
    r.raise_for_status()
    os.umask(0o077)
    with open(KEY_FILE + ".tmp", "w") as f:
        f.write(r.json()["apiKey"]["apiKey"])
    os.replace(KEY_FILE + ".tmp", KEY_FILE)
    print("Issued a new homepage API key; restarting homepage to load it")
    # homepage reads its keys via LoadCredential at start
    subprocess.run(["systemctl", "try-restart", "homepage-dashboard.service"], check=False)


main()

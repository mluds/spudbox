{ config, pkgs, ... }:

with config.my;

let
  dbFile = "/var/lib/audiobookshelf/config/absdatabase.sqlite";
  tokenSecretFile = "${secretsDir}/audiobookshelf/token-secret";

  # Runs on every boot/switch (unlike the one-off audiobookshelf-config):
  #  1. The root account uses its own password (audiobookshelf/password). An
  #     install still on the shared admin/password is rotated through
  #     PATCH /api/me/password (finding #5).
  #  2. Homepage gets a revocable API key for a read-only "homepage" user,
  #     rather than a forged, never-expiring root token.
  accessScript =
    let
      pythonEnv = pkgs.python3.withPackages (ps: [ ps.requests ]);
    in
    pkgs.writeScript "audiobookshelf-access" ''
      #!${pythonEnv}/bin/python
      import os
      import secrets
      import subprocess
      import sys
      import time

      import requests

      BASE = "http://localhost:${toString audiobookshelfPort}"
      KEY_FILE = "${secretsDir}/audiobookshelf/apikey"
      HOMEPAGE_USER = "homepage"


      def read_secret(name):
          with open(f"${secretsDir}/{name}") as f:
              return f.read().strip()


      def bearer(token):
          return {"Authorization": f"Bearer {token}"}


      def login(username, password):
          r = requests.post(f"{BASE}/login", json={"username": username, "password": password}, timeout=10)
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
          r = requests.patch(f"{BASE}/api/me/password", headers=bearer(old_token),
                             json={"password": old, "newPassword": new}, timeout=10)
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
          r = requests.post(f"{BASE}/api/users", headers=bearer(token), timeout=10, json={
              "username": HOMEPAGE_USER,
              # Never used to log in; only its API key is
              "password": secrets.token_urlsafe(32),
              "type": "user",
              "isActive": True,
              "permissions": {
                  "download": False, "update": False, "delete": False, "upload": False,
                  "createEreader": False, "accessAllLibraries": True, "accessAllTags": True,
                  "accessExplicitContent": True,
              },
          })
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
          r = requests.post(f"{BASE}/api/api-keys", headers=bearer(token), timeout=10,
                            json={"name": HOMEPAGE_USER, "userId": user["id"], "isActive": True})
          r.raise_for_status()
          os.umask(0o077)
          with open(KEY_FILE + ".tmp", "w") as f:
              f.write(r.json()["apiKey"]["apiKey"])
          os.replace(KEY_FILE + ".tmp", KEY_FILE)
          print("Issued a new homepage API key; restarting homepage to load it")
          # homepage reads its keys via LoadCredential at start
          subprocess.run(["systemctl", "try-restart", "homepage-dashboard.service"], check=False)


      main()
    '';

  configScript =
    let
      pythonEnv = pkgs.python3.withPackages (ps: [
        ps.requests
        ps.bcrypt
        ps.pyjwt
      ]);
    in
    pkgs.writeScriptBin "audiobookshelf-config" ''
      #!${pythonEnv}/bin/python

      import os
      import sqlite3
      import requests
      import json
      from urllib.parse import urljoin
      import bcrypt
      import time
      import socket
      import jwt

      with open("${secretsDir}/audiobookshelf/password", "r") as f:
          admin_password = f.read().strip()
      salt = bcrypt.gensalt(rounds=8, prefix=b"2a")
      hashed = bcrypt.hashpw(admin_password.encode('utf-8'), salt)
      pash = hashed.decode()

      db_path = "${dbFile}"
      host = 'localhost'
      port = '${toString audiobookshelfPort}'
      base_url = f"http://{host}:{port}"
      login_url = urljoin(base_url, "/login")
      user_id = "d3b07384-1138-4e19-8878-669fc7a4c34a"
      with open("${secretsDir}/admin/username", "r") as f:
          username = f.read().strip()

      def get_token_secret():
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        cursor.execute("SELECT value FROM settings WHERE key = 'server-settings'")
        row = cursor.fetchone()
        conn.close()
        if row:
          settings = json.loads(row[0])
          return settings.get('tokenSecret', "")
        return ""

      token_secret = get_token_secret()
      if not token_secret:
        # Fallback to file if DB doesn't have it yet
        with open("${tokenSecretFile}", "r") as f:
          token_secret = f.read().strip()

      token = jwt.encode(
        payload={ "userId": user_id, "username": username },
        key=token_secret
      )

      headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
      }

      # The forged token is only used for this one-off setup's own API calls.
      # Homepage's key is a scoped API key managed by audiobookshelf-access.

      def main():
        os.system("systemctl stop audiobookshelf")
        run_sql_script()
        os.system("systemctl start audiobookshelf")
        wait_for_port(host, port)
        create_library()
        create_users()

      def wait_for_port(host, port, timeout=30, retry_interval=1):
        start_time = time.time()
        while time.time() - start_time < timeout:
          try:
            with socket.create_connection((host, port), timeout=1):
              return True
          except (ConnectionRefusedError, socket.timeout, OSError):
            time.sleep(retry_interval)
          except Exception as e:
            print(f"Unexpected error: {e}")
            break
        return False

      def run_sql_script():
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()

        cursor.execute("DELETE FROM users;")
        cursor.execute(
          """
          INSERT INTO users (
            id, username, email, pash, type, token, isActive, isLocked, lastSeen,
            permissions, bookmarks, extraData, createdAt, updatedAt
          ) VALUES (
            ?, ?, ''', ?, 'root', ?, 1, 0, NULL, ?, '[]', ?,
            datetime('now') || ' +00:00', datetime('now') || ' +00:00'
          )
          """,
          (
            user_id,
            username,
            pash,
            token,
            json.dumps({"download": True, "update": True, "delete": True, "upload": True, "createEreader": True, "accessAllLibraries": True, "accessAllTags": True, "accessExplicitContent": True, "selectedTagsNotAccessible": False, "librariesAccessible": [], "itemTagsSelected": []}),
            json.dumps({"seriesHideFromContinueListening": []}),
          ),
        )
        conn.commit()
        print("Database initialization completed successfully.")
        return True

      def create_library():
        lib_name = "Audiobooks"
        libraries = requests.get(f"{base_url}/api/libraries", headers=headers).json()["libraries"]
        audiobooks_exists = any(lib["name"] == lib_name for lib in libraries)
        if audiobooks_exists:
          print("Audiobooks library already exists")
        else:
          print("Audiobooks library not found, creating...")
          new_library = {
            "name": lib_name,
            "folders": [{"fullPath": "${storageDir}/data/media/audiobooks"}],
            "icon": "audiobookshelf",
            "mediaType": "book",
            "provider": "google"
          }
          response = requests.post(f"{base_url}/api/libraries", headers=headers, json=new_library)
          response.raise_for_status()
          id = response.json()['id']
          response = requests.post(f"{base_url}/api/libraries/{id}/scan", headers=headers)
          response.raise_for_status()
          print("Library created successfully!")

      def create_users():
        users_json = os.getenv("AUDIOBOOKSHELF_USERS", "[]")
        users = json.loads(users_json)
        existing_users = requests.get(f"{base_url}/api/users", headers=headers).json()["users"]
        existing_usernames = [user['username'] for user in existing_users]
        for user in users:
          username = user['username']
          if username in existing_usernames:
            print(f"User {username} already exists")
            continue
          # Plaintext login passwords aren't deployed to the server (see
          # deploy.sh); copy one to this path by hand to create the user.
          password_file = os.path.join("${secretsDir}", "users", username, "plaintext")
          if not os.path.exists(password_file):
            print(f"Skipping user {username}: no {password_file}")
            continue
          with open(password_file, 'r') as f:
            password = f.read().strip()
          new_user = {
            "username": username,
            "password": password,
            "type": "admin" if user['superuser'] else "user",
            "isActive": True
          }
          response = requests.post(f"{base_url}/api/users", headers=headers, json=new_user)
          response.raise_for_status()
          print(f"Created user {username}")

      if __name__ == "__main__":
        main()
    '';

in
{
  services.audiobookshelf = {
    enable = true;
    openFirewall = false;
    port = audiobookshelfPort;
    group = "media";
  };

  # The DB holds user password hashes and the root API token
  systemd.services = {
    audiobookshelf.serviceConfig = import ./hardening.nix // {
      StateDirectoryMode = "0700";
    };

    audiobookshelf-access = {
      description = "Audiobookshelf root password and homepage API key";
      after = [ "audiobookshelf.service" ];
      wants = [ "audiobookshelf.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = accessScript;
      };
    };

    audiobookshelf-config = {
      description = "Configure Audiobookshelf";
      serviceConfig = {
        User = "root";
        Type = "oneshot";
        ExecStart = "${configScript}/bin/audiobookshelf-config";
        Environment = [
          "AUDIOBOOKSHELF_USERS='${
            builtins.toJSON (
              map (user: {
                inherit (user) username superuser;
              }) users
            )
          }'"
        ];
      };
    };
  };
}

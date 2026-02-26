{ config, pkgs, secrets, ... }:

with config.my;

let
  dbFile = "/var/lib/audiobookshelf/config/absdatabase.sqlite";
  tokenSecretFile = "${secretsDir}/audiobookshelf/token-secret";

  configScript = let
    pythonEnv = pkgs.python3.withPackages (ps: [ ps.requests ps.bcrypt ps.pyjwt ]);
  in pkgs.writeScriptBin "audiobookshelf-config" ''
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

    admin_password = os.getenv("ADMIN_PASSWORD")
    salt = bcrypt.gensalt(rounds=8, prefix=b"2a")
    hashed = bcrypt.hashpw(admin_password.encode('utf-8'), salt)
    pash = hashed.decode()

    db_path = "${dbFile}"
    host = 'localhost'
    port = '${toString audiobookshelfPort}'
    base_url = f"http://{host}:{port}"
    login_url = urljoin(base_url, "/login")
    user_id = "d3b07384-1138-4e19-8878-669fc7a4c34a"
    username = "${secrets.adminUsername}"

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

    apikey_path = "${secretsDir}/audiobookshelf/apikey"
    parent_dir = os.path.dirname(apikey_path)
    os.makedirs(parent_dir, exist_ok=True)
    with open(apikey_path, "w") as f:
      f.write(token)

    def main():
      os.system("systemctl stop audiobookshelf")
      run_sql_script()
      os.system("systemctl start audiobookshelf")
      wait_for_port(host, port)
      create_library()
      create_users()

    def wait_for_file(file_path, timeout=300, check_interval=3):
      elapsed = 0
      while elapsed < timeout:
        if os.path.exists(file_path):
          return True
        time.sleep(check_interval)
        elapsed += check_interval
      return False

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
      cursor.execute(f"""
        INSERT INTO users (
          id, username, email, pash, type, token, isActive, isLocked, lastSeen,
          permissions, bookmarks, extraData, createdAt, updatedAt
        ) VALUES (
          '{user_id}',
          '{username}',
          ''',
          '{pash}',
          'root',
          '{token}',
          1,
          0,
          NULL,
          '{{"download":true,"update":true,"delete":true,"upload":true,"createEreader":true,"accessAllLibraries":true,"accessAllTags":true,"accessExplicitContent":true,"selectedTagsNotAccessible":false,"librariesAccessible":[],"itemTagsSelected":[]}}',
          '[]',
          '{{"seriesHideFromContinueListening":[]}}',
          datetime('now') || ' +00:00',
          datetime('now') || ' +00:00'
        );
      """)
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
          "folders": [{"fullPath": "/mnt/storage/data/media/audiobooks"}],
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
        password_file = os.path.join("${secretsDir}", "users", username, "plaintext")
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

in {
  services.audiobookshelf = {
    enable = true;
    openFirewall = false;
    port = audiobookshelfPort;
    group = "media";
  };

  systemd.services.audiobookshelf-config = {
    description = "Configure Audiobookshelf";
    serviceConfig = {
      User = "root";
      Type = "exec";
      ExecStart = "${configScript}/bin/audiobookshelf-config";
      Environment = [
        "ADMIN_PASSWORD=${secrets.adminPassword}"
        "AUDIOBOOKSHELF_USERS='${
          builtins.toJSON (map (user: {
            inherit (user) username superuser;
          }) users)
        }'"
      ];
    };
  };
}

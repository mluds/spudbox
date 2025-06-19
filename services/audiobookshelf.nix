{ config, pkgs, secrets, ... }:

with config.my;

let
  dbFile = "/var/lib/audiobookshelf/config/absdatabase.sqlite";

  configScript = let
    pythonEnv = pkgs.python3.withPackages (ps: [ ps.requests ps.bcrypt ]);
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

    def main():
      os.system("systemctl stop audiobookshelf")
      run_sql_script()
      os.system("systemctl start audiobookshelf")
      wait_for_port(host, port)
      api_token = get_api_token()
      print(api_token)

    def wait_for_file(file_path, timeout=30, check_interval=1):
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
          'admin',
          ''',
          '{pash}',
          'root',
          NULL,
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

    def get_api_token():
      credentials = {"username": "admin", "password": admin_password}
      headers = {"Content-Type": "application/json"}
      response = requests.post(
        login_url,
        data=json.dumps(credentials),
        headers=headers,
        timeout=10
      )
      user_data = response.json().get("user", {})
      return user_data.get("token")

    if __name__ == "__main__":
      main()
  '';

in {
  services.audiobookshelf = {
    enable = true;
    openFirewall = false;
    port = audiobookshelfPort;
  };

  systemd.services.audiobookshelf-config = {
    description = "Configure Audiobookshelf";
    serviceConfig = {
      User = "root";
      Type = "exec";
      ExecStart = "${configScript}/bin/audiobookshelf-config";
      Environment = [
        "ADMIN_PASSWORD=${secrets.adminPassword}"
      ];
    };
  };
}
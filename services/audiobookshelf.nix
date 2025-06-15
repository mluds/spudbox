{ config, pkgs, ... }:

with config.my;

let
  dbFile = "/var/lib/audiobookshelf/config/absdatabase.sqlite";
  sqlFile = pkgs.writeText "audiobookshelf-init.sql" ''
    DELETE FROM users;
    INSERT INTO users (
      id, username, email, pash, type, token, isActive, isLocked, lastSeen,
      permissions, bookmarks, extraData, createdAt, updatedAt
    ) VALUES (
      'd3b07384-1138-4e19-8878-669fc7a4c34a',
      'admin',
      ''',
      '$2a$08$N9SPPCdrbt8IzWvF6Nqr/OEB9vzgBidy7VxSF6upQgbD.wB2N2GVa',
      'root',
      NULL,
      1,
      0,
      NULL,
      '{"download":true,"update":true,"delete":true,"upload":true,"createEreader":true,"accessAllLibraries":true,"accessAllTags":true,"accessExplicitContent":true,"selectedTagsNotAccessible":false,"librariesAccessible":[],"itemTagsSelected":[]}',
      '[]',
      '{"seriesHideFromContinueListening":[]}',
      datetime('now') || ' +00:00',
      datetime('now') || ' +00:00'
    );
  '';

  configScript = let
    pythonEnv = pkgs.python3.withPackages (ps: [ ps.requests ]);
  in pkgs.writeScriptBin "audiobookshelf-config" ''
    #!${pythonEnv}/bin/python

    import os
    import sqlite3
    import requests
    import time
    import json
    from urllib.parse import urljoin

    db_path = "${dbFile}"
    sql_path = "${sqlFile}"
    base_url = "http://localhost:${toString audiobookshelfPort}"
    login_url = urljoin(base_url, "/login")
    user_id = "d3b07384-1138-4e19-8878-669fc7a4c34a"

    def run_sql_script():
      if not os.path.exists(db_path):
        print(f"Database file not found: {db_path}")
        return False

      try:
        with open(sql_path, 'r') as sql_file:
          sql_script = sql_file.read()
        
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        cursor.executescript(sql_script)
        conn.commit()
        print("Database initialization completed successfully.")
        return True
      except sqlite3.Error as e:
        print(f"SQLite error: {e}")
        return False
      finally:
        conn.close()

    def get_api_token():
      credentials = {"username": "admin", "password": "admin"}
      headers = {"Content-Type": "application/json"}
      response = requests.post(
        login_url,
        data=json.dumps(credentials),
        headers=headers,
        timeout=10
      )
      print(response.json())
      user_data = response.json().get("user", {})
      return user_data.get("token")

    if __name__ == "__main__":
      run_sql_script()
      api_token = get_api_token()
      print(api_token)
  '';

in {
  services.audiobookshelf = {
    enable = true;
    openFirewall = false;
    port = audiobookshelfPort;
  };

  systemd.services.audiobookshelf-config = {
    description = "Configure Audiobookshelf";
    after = [ "audiobookshelf.service" ];
    requires = [ "audiobookshelf.service" ];
    serviceConfig = {
      User = "root";
      Type = "exec";
      ExecStart = "${configScript}/bin/audiobookshelf-config";
    };
  };
}

{config, pkgs, secrets, ...}:

with config.my;

let
  configScript = pkgs.writeScriptBin "tautulli-config-updater" ''
    #!${pkgs.python3}/bin/python3
    from os import getenv, path, urandom
    import base64
    import configparser
    from hashlib import pbkdf2_hmac
    import subprocess
    import time

    def generate_pbkdf2_hash():
      password = getenv('TAUTULLI_ADMIN_PASSWORD')
      # salt = base64.b64decode(getenv('TAUTULLI_SALT'))
      salt = urandom(16)
      iterations = int(getenv('TAUTULLI_ITERATIONS', '600000'))
      print(password)

      hashed = pbkdf2_hmac('sha256', password.encode('utf-8'), salt, iterations)
      salt_b64 = base64.b64encode(salt).decode()
      hashed_b64 = base64.b64encode(hashed).decode()
      formatted = "PBKDF2$sha256$" + str(iterations) + "$" + salt_b64 + "$" + hashed_b64
      return formatted

    def update_config():
      cfg_path = getenv('TAUTULLI_CONFIG')

      parser = configparser.ConfigParser()
      if path.exists(cfg_path):
        parser.read(cfg_path)

      if not parser.has_section('General'):
        parser.add_section('General')

      parser['General']['api_key'] = getenv('TAUTULLI_API_KEY')
      parser['General']['http_username'] = getenv('TAUTULLI_ADMIN_USERNAME')
      parser['General']['http_password'] = generate_pbkdf2_hash()
      parser['General']['http_port'] = getenv('TAUTULLI_PORT')
      parser['General']['pms_port'] = getenv('PLEX_PORT')
      parser['General']['pms_url'] = f"http://localhost:{getenv('PLEX_PORT')}"
      parser['General']['first_run_complete'] = '1';

      with open(cfg_path, 'w') as configfile:
        parser.write(configfile)

    def main():
      while not path.exists(getenv('TAUTULLI_CONFIG')):
        time.sleep(1)

      print("Stopping Tautulli service...")
      subprocess.run(["systemctl", "stop", "tautulli"], check=False)

      print("Waiting for service to stop...")
      time.sleep(2)

      print("Updating configuration...")
      update_config()

      print("Starting Tautulli service...")
      subprocess.run(["systemctl", "start", "tautulli"], check=True)

    if __name__ == "__main__":
      main()
  '';
in {
  services.tautulli = {
    enable = true;
  };

  systemd.services.tautulli-config-update = {
    description = "Update Tautulli configuration";
    after = [ "tautulli.service" ];
    requires = [ "tautulli.service" ];

    serviceConfig = {
      Type = "exec";
      User = "root";
      ExecStart = "${configScript}/bin/tautulli-config-updater";
    };

    environment = {
      TAUTULLI_CONFIG = "${config.services.tautulli.dataDir}/config.ini";
      PLEX_PORT = toString plexPort;
      TAUTULLI_PORT = toString tautulliPort;
      TAUTULLI_ADMIN_USERNAME = secrets.adminUsername;
      TAUTULLI_API_KEY = secrets.tautulliApiKey;
      TAUTULLI_ADMIN_PASSWORD = secrets.adminPassword;
      TAUTULLI_SALT = "1cduJ6RzGVo5CY2nxK5rZQ==";  # openssl rand -base64 16
    };
  };
}

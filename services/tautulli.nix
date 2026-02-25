{config, pkgs, secrets, ...}:

with config.my;

let
  configScript = pkgs.writeText "tautulli-config.py" ''
    from os import getenv, path, urandom, makedirs
    import configparser
    from base64 import b64encode
    from hashlib import pbkdf2_hmac
    import subprocess
    import time

    def main():
      while not path.exists(getenv('TAUTULLI_CONFIG')):
        print("Waiting for initial Tautulli config:", getenv('TAUTULLI_CONFIG'))
        time.sleep(5)

      print("Stopping Tautulli service...")
      subprocess.run(["systemctl", "stop", "tautulli"], check=False)

      print("Waiting for service to stop...")
      time.sleep(5)

      print("Updating configuration...")
      update_config()

      print("Starting Tautulli service...")
      subprocess.run(["systemctl", "start", "tautulli"], check=True)

      print("Exporting API key...")
      export_api_key()

    SALT_LENGTH = 16
    KEY_LENGTH = 24
    HASH_FUNCTION = 'sha256'
    COST_FACTOR = 600000

    def make_hash(password):
      if isinstance(password, str):
        password = password.encode('utf-8')
      salt = b64encode(urandom(SALT_LENGTH))
      return 'PBKDF2''${}''${}''${}''${}'.format(
        HASH_FUNCTION,
        COST_FACTOR,
        salt.decode('utf-8'),
        b64encode(pbkdf2_hmac(HASH_FUNCTION, password, salt, COST_FACTOR, KEY_LENGTH)).decode('utf-8'))

    def update_config():
      cfg_path = getenv('TAUTULLI_CONFIG')

      parser = configparser.ConfigParser()
      if path.exists(cfg_path):
        parser.read(cfg_path)

      if not parser.has_section('General'):
        parser.add_section('General')

      parser['General']['http_username'] = getenv('TAUTULLI_ADMIN_USERNAME')
      parser['General']['http_password'] = make_hash(getenv('TAUTULLI_ADMIN_PASSWORD'))
      parser['General']['http_port'] = getenv('TAUTULLI_PORT')
      parser['General']['first_run_complete'] = '1';
      parser['PMS']['pms_ip'] = '127.0.0.1';
      parser['PMS']['pms_port'] = getenv('PLEX_PORT')
      parser['PMS']['pms_url'] = f"http://127.0.0.1:{getenv('PLEX_PORT')}"

      with open(cfg_path, 'w') as configfile:
        parser.write(configfile)

    def export_api_key():
      cfg_path = getenv('TAUTULLI_CONFIG')
      parser = configparser.ConfigParser()
      parser.read(cfg_path)
      api_key = parser['General']['api_key']

      secret_dir = "${secretsDir}/tautulli"
      makedirs(secret_dir, exist_ok=True)
      secret_path = path.join(secret_dir, "api-key")
      with open(secret_path, 'w') as f:
        f.write(api_key)
      print(f"API key written to {secret_path}")

    if __name__ == "__main__":
      main()
  '';
in {
  services.tautulli = {
    enable = true;
  };

  systemd.services.tautulli-config = {
    description = "Update Tautulli configuration";

    serviceConfig = {
      Type = "exec";
      User = "root";
      ExecStart = "${pkgs.python3}/bin/python ${configScript}";
    };

    environment = {
      TAUTULLI_CONFIG = "${config.services.tautulli.dataDir}/config.ini";
      PLEX_PORT = toString plexPort;
      TAUTULLI_PORT = toString tautulliPort;
      TAUTULLI_ADMIN_USERNAME = secrets.adminUsername;
      TAUTULLI_ADMIN_PASSWORD = secrets.adminPassword;
    };
  };
}

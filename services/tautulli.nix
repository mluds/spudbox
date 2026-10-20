{ config, pkgs, ... }:

with config.my;

let
  configScript = pkgs.writeText "tautulli-config.py" ''
    from os import getenv, path, urandom, makedirs, walk, lstat, chmod
    from stat import S_IMODE, S_ISLNK
    import configparser
    from base64 import b64encode
    from hashlib import pbkdf2_hmac
    from urllib.request import urlopen
    from xml.etree import ElementTree
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

      print("Reading Plex token...")
      plex_token = read_plex_token()

      print("Fetching Plex server identity...")
      plex_identity = get_plex_identity()

      print("Updating configuration...")
      update_config(plex_token, plex_identity)

      print("Locking down data dir contents...")
      lock_down_data_dir()

      print("Starting Tautulli service...")
      subprocess.run(["systemctl", "start", "tautulli"], check=True)

      print("Exporting API key...")
      export_api_key()

    def lock_down_data_dir():
      # The module's tmpfiles rule resets the dir itself to 0755, so make
      # everything inside it owner-only instead (config.ini has the Plex token).
      # New files are covered by UMask=0077 on tautulli.service.
      data_dir = path.dirname(getenv('TAUTULLI_CONFIG'))
      for root, dirs, files in walk(data_dir):
        for name in dirs + files:
          p = path.join(root, name)
          st = lstat(p)
          if not S_ISLNK(st.st_mode) and S_IMODE(st.st_mode) & 0o077:
            chmod(p, S_IMODE(st.st_mode) & ~0o077)

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

    def read_plex_token():
      token_path = "${secretsDir}/plex/token"
      with open(token_path, 'r') as f:
        return f.read().strip()

    def get_plex_identity():
      plex_port = getenv('PLEX_PORT')
      url = f"http://127.0.0.1:{plex_port}/identity"
      response = urlopen(url)
      tree = ElementTree.parse(response)
      root = tree.getroot()
      return {
        'machineIdentifier': root.get('machineIdentifier', '''),
        'friendlyName': root.get('friendlyName', '''),
      }

    def update_config(plex_token, plex_identity):
      cfg_path = getenv('TAUTULLI_CONFIG')

      parser = configparser.ConfigParser()
      if path.exists(cfg_path):
        parser.read(cfg_path)

      if not parser.has_section('General'):
        parser.add_section('General')
      if not parser.has_section('PMS'):
        parser.add_section('PMS')

      with open(getenv('TAUTULLI_ADMIN_USERNAME_FILE'), 'r') as f:
        parser['General']['http_username'] = f.read().strip()
      with open(getenv('TAUTULLI_ADMIN_PASSWORD_FILE'), 'r') as f:
        parser['General']['http_password'] = make_hash(f.read().strip())
      parser['General']['http_host'] = '127.0.0.1'  # loopback only; reached through Caddy
      parser['General']['http_port'] = getenv('TAUTULLI_PORT')
      parser['General']['first_run_complete'] = '1'
      parser['General']['system_analytics'] = '0'

      plex_port = getenv('PLEX_PORT')
      parser['PMS']['pms_ip'] = '127.0.0.1'
      parser['PMS']['pms_port'] = plex_port
      parser['PMS']['pms_url'] = f"http://127.0.0.1:{plex_port}"
      parser['PMS']['pms_token'] = plex_token
      parser['PMS']['pms_identifier'] = plex_identity['machineIdentifier']
      parser['PMS']['pms_name'] = plex_identity['friendlyName']
      parser['PMS']['pms_ssl'] = '0'
      parser['PMS']['pms_is_cloud'] = '0'
      parser['PMS']['pms_is_remote'] = '0'

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
in
{
  services.tautulli = {
    enable = true;
  };

  # New files owner-only; see lock_down_data_dir above
  systemd.services.tautulli.serviceConfig.UMask = "0077";

  systemd.services.tautulli-config = {
    description = "Update Tautulli configuration";
    after = [
      "tautulli.service"
      "plex-config.service"
    ];
    wants = [ "tautulli.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = "${pkgs.python3}/bin/python ${configScript}";
    };

    environment = {
      TAUTULLI_CONFIG = "${config.services.tautulli.dataDir}/config.ini";
      PLEX_PORT = toString plexPort;
      TAUTULLI_PORT = toString tautulliPort;
      TAUTULLI_ADMIN_USERNAME_FILE = "${secretsDir}/admin/username";
      TAUTULLI_ADMIN_PASSWORD_FILE = "${secretsDir}/admin/password";
    };
  };
}

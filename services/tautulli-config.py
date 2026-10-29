import configparser
import subprocess
import time
from base64 import b64encode
from hashlib import pbkdf2_hmac
from os import chmod, environ, lstat, makedirs, path, umask, urandom, walk
from stat import S_IMODE, S_ISLNK
from urllib.request import urlopen
from xml.etree import ElementTree

SECRETS_DIR = environ["SECRETS_DIR"]
CONFIG = environ["TAUTULLI_CONFIG"]
PLEX_PORT = environ["PLEX_PORT"]


def main():
    deadline = time.time() + 300
    while not path.exists(CONFIG):
        if time.time() > deadline:
            raise SystemExit(f"Tautulli never wrote {CONFIG}")
        print("Waiting for initial Tautulli config:", CONFIG)
        time.sleep(5)

    # Without a Plex token yet (a fresh install before Plex is claimed), the
    # login and loopback binding are still applied; the Plex link waits for
    # the next run, and the unit fails until then.
    token_path = f"{SECRETS_DIR}/plex/token"
    plex_token = read_file(token_path) if path.exists(token_path) else ""
    plex_identity = None
    if plex_token:
        print("Fetching Plex server identity...")
        plex_identity = get_plex_identity()

    print("Stopping Tautulli service...")
    subprocess.run(["systemctl", "stop", "tautulli"], check=False)

    print("Updating configuration...")
    update_config(plex_token, plex_identity)

    print("Locking down data dir contents...")
    lock_down_data_dir()

    print("Starting Tautulli service...")
    subprocess.run(["systemctl", "start", "tautulli"], check=True)

    print("Exporting API key...")
    export_api_key()

    if not plex_token:
        raise SystemExit(
            "No Plex token yet: login and binding set, Plex not linked. Once Plex is set up, "
            "restart plex-config and tautulli-config."
        )


def lock_down_data_dir():
    # The module's tmpfiles rule resets the dir itself to 0755, so make
    # everything inside it owner-only instead (config.ini has the Plex token).
    # New files are covered by UMask=0077 on tautulli.service.
    data_dir = path.dirname(CONFIG)
    for root, dirs, files in walk(data_dir):
        for name in dirs + files:
            p = path.join(root, name)
            st = lstat(p)
            if not S_ISLNK(st.st_mode) and S_IMODE(st.st_mode) & 0o077:
                chmod(p, S_IMODE(st.st_mode) & ~0o077)


SALT_LENGTH = 16
KEY_LENGTH = 24
HASH_FUNCTION = "sha256"
COST_FACTOR = 600000


def make_hash(password):
    salt = b64encode(urandom(SALT_LENGTH))
    key = b64encode(pbkdf2_hmac(HASH_FUNCTION, password.encode(), salt, COST_FACTOR, KEY_LENGTH))
    # PBKDF2$<hash>$<rounds>$<salt>$<key>, the format Tautulli checks against
    return f"PBKDF2${HASH_FUNCTION}${COST_FACTOR}${salt.decode()}${key.decode()}"


def read_file(path):
    with open(path) as f:
        return f.read().strip()


def get_plex_identity():
    url = f"http://127.0.0.1:{PLEX_PORT}/identity"
    # A fixed http://127.0.0.1 URL to the local Plex, not user input
    response = urlopen(url, timeout=30)  # noqa: S310
    tree = ElementTree.parse(response)  # noqa: S314
    root = tree.getroot()
    return {
        "machineIdentifier": root.get("machineIdentifier", ""),
        "friendlyName": root.get("friendlyName", ""),
    }


def update_config(plex_token, plex_identity):
    parser = configparser.ConfigParser()
    parser.read(CONFIG)  # skips a missing file

    settings = {
        "General": {
            "http_username": read_file(f"{SECRETS_DIR}/admin/username"),
            "http_password": make_hash(read_file(f"{SECRETS_DIR}/tautulli/password")),
            "http_host": "127.0.0.1",  # loopback only; reached through Caddy
            "http_port": environ["TAUTULLI_PORT"],
            "first_run_complete": "1",
            "system_analytics": "0",
        },
    }
    if plex_token:
        settings["PMS"] = {
            "pms_ip": "127.0.0.1",
            "pms_port": PLEX_PORT,
            "pms_url": f"http://127.0.0.1:{PLEX_PORT}",
            "pms_token": plex_token,
            "pms_identifier": plex_identity["machineIdentifier"],
            "pms_name": plex_identity["friendlyName"],
            "pms_ssl": "0",
            "pms_is_cloud": "0",
            "pms_is_remote": "0",
        }
    parser.read_dict(settings)

    with open(CONFIG, "w") as configfile:
        parser.write(configfile)


def export_api_key():
    parser = configparser.ConfigParser()
    parser.read(CONFIG)
    api_key = parser["General"]["api_key"]

    secret_dir = f"{SECRETS_DIR}/tautulli"
    makedirs(secret_dir, exist_ok=True)
    secret_path = path.join(secret_dir, "api-key")
    umask(0o077)  # a new secret file is 0600 from the start
    with open(secret_path, "w") as f:
        f.write(api_key)
    print(f"API key written to {secret_path}")


if __name__ == "__main__":
    main()

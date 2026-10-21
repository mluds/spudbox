import os
import sqlite3
import requests
import json
import bcrypt
import time
import socket
import jwt

SECRETS_DIR = os.environ["SECRETS_DIR"]

with open(f"{SECRETS_DIR}/audiobookshelf/password", "r") as f:
    admin_password = f.read().strip()
salt = bcrypt.gensalt(rounds=8, prefix=b"2a")
hashed = bcrypt.hashpw(admin_password.encode("utf-8"), salt)
pash = hashed.decode()

db_path = os.environ["ABS_DB"]
host = "localhost"
port = os.environ["ABS_PORT"]
base_url = f"http://{host}:{port}"
user_id = os.environ["ADMIN_USER_ID"]
with open(f"{SECRETS_DIR}/admin/username", "r") as f:
    username = f.read().strip()


def get_token_secret():
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT value FROM settings WHERE key = 'server-settings'")
    row = cursor.fetchone()
    conn.close()
    if row:
        settings = json.loads(row[0])
        return settings.get("tokenSecret", "")
    return ""


token_secret = get_token_secret()
if not token_secret:
    # Fallback to file if DB doesn't have it yet
    with open(f"{SECRETS_DIR}/audiobookshelf/token-secret", "r") as f:
        token_secret = f.read().strip()

token = jwt.encode(payload={"userId": user_id, "username": username}, key=token_secret)

headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

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
      ?, ?, '', ?, 'root', ?, 1, 0, NULL, ?, '[]', ?,
      datetime('now') || ' +00:00', datetime('now') || ' +00:00'
    )
    """,
        (
            user_id,
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
            "folders": [{"fullPath": os.environ["LIBRARY_DIR"]}],
            "icon": "audiobookshelf",
            "mediaType": "book",
            "provider": "google",
        }
        response = requests.post(f"{base_url}/api/libraries", headers=headers, json=new_library)
        response.raise_for_status()
        id = response.json()["id"]
        response = requests.post(f"{base_url}/api/libraries/{id}/scan", headers=headers)
        response.raise_for_status()
        print("Library created successfully!")


def create_users():
    users_json = os.getenv("AUDIOBOOKSHELF_USERS", "[]")
    users = json.loads(users_json)
    existing_users = requests.get(f"{base_url}/api/users", headers=headers).json()["users"]
    existing_usernames = [user["username"] for user in existing_users]
    for user in users:
        username = user["username"]
        if username in existing_usernames:
            print(f"User {username} already exists")
            continue
        # Plaintext login passwords aren't deployed to the server (see
        # deploy.sh); copy one to this path by hand to create the user.
        password_file = os.path.join(f"{SECRETS_DIR}", "users", username, "plaintext")
        if not os.path.exists(password_file):
            print(f"Skipping user {username}: no {password_file}")
            continue
        with open(password_file, "r") as f:
            password = f.read().strip()
        new_user = {
            "username": username,
            "password": password,
            "type": "admin" if user["superuser"] else "user",
            "isActive": True,
        }
        response = requests.post(f"{base_url}/api/users", headers=headers, json=new_user)
        response.raise_for_status()
        print(f"Created user {username}")


if __name__ == "__main__":
    main()

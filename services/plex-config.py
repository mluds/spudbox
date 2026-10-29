import os
import time
from urllib.parse import urlencode
from xml.etree import ElementTree

import requests
from plexapi.exceptions import NotFound
from plexapi.myplex import MyPlexAccount
from plexapi.server import PlexServer


def read_file(path):
    with open(path) as f:
        return f.read().strip()


def get_token(plex_url, secrets_dir):
    token_path = f"{secrets_dir}/plex/token"
    # Reuse existing token if valid
    try:
        token = read_file(token_path)
        if token:
            PlexServer(plex_url, token)
            print("Existing token is valid, skipping sign-in")
            return token
    except Exception as e:
        print(f"Saved token unusable ({type(e).__name__}); signing in again")

    # Token missing or invalid, sign in
    print("Signing in to Plex...")
    username = read_file(f"{secrets_dir}/plex/username")
    password = read_file(f"{secrets_dir}/plex/password")
    account = MyPlexAccount(username, password)
    token = account.authToken
    os.umask(0o077)  # a new secret file is 0600 from the start
    with open(token_path, "w") as f:
        f.write(token)
    return token


def identity(plex_url):
    r = requests.get(f"{plex_url}/identity", timeout=30)
    r.raise_for_status()
    return ElementTree.fromstring(r.text)  # noqa: S314 (the local Plex's own XML)


def claim_server(plex_url, token):
    """Claim a fresh server for the plex.tv account, as Plex's setup page does.

    Until it's claimed, Plex can only be managed from localhost, and its own
    sign-in, remote access, Tautulli and Jellyseerr don't work. Claiming uses
    a short-lived, single-use claim token from plex.tv.
    """
    server = identity(plex_url)
    if server.get("claimed") == "1":
        return
    print("Claiming the Plex server for the plex.tv account...")
    r = requests.get(
        "https://plex.tv/api/claim/token.json",
        headers={"X-Plex-Token": token, "Accept": "application/json"},
        timeout=30,
    )
    r.raise_for_status()
    r = requests.post(
        f"{plex_url}/myplex/claim",
        params={"token": r.json()["token"]},
        headers={"X-Plex-Client-Identifier": server.get("machineIdentifier", "")},
        timeout=60,
    )
    r.raise_for_status()
    deadline = time.time() + 60
    while identity(plex_url).get("claimed") != "1":
        if time.time() > deadline:
            raise SystemExit("Plex didn't report itself claimed within a minute")
        time.sleep(2)
    print("Plex server claimed.")


def main():
    plex_url = os.environ["PLEX_URL"]
    access_url = os.environ["PLEX_ACCESS_URL"]
    media_dir = os.environ["MEDIA_DIR"]
    library_sections = [
        {
            "name": "Movies",
            "type": "movie",
            "agent": "tv.plex.agents.movie",
            "scanner": "Plex Movie",
            "location": f"{media_dir}/movies",
            "language": "en-US",
        },
        {
            "name": "TV Shows",
            "type": "show",
            "agent": "tv.plex.agents.series",
            "scanner": "Plex TV Series",
            "location": f"{media_dir}/tv",
            "language": "en-US",
        },
        {
            "name": "Videos",
            "type": "movie",
            "agent": "com.plexapp.agents.none",
            "scanner": "Plex Video Files Scanner",
            "location": f"{media_dir}/videos",
            "language": "xn",
        },
    ]

    token = get_token(plex_url, os.environ["SECRETS_DIR"])
    claim_server(plex_url, token)
    plex = PlexServer(plex_url, token)

    def add_library(section):
        """Add a library section via the raw Plex API.

        PlexAPI's library.add() forces language=en-US which is invalid for
        the com.plexapp.agents.none agent (Other Videos), so we use the
        raw API for all libraries to keep things consistent.
        """
        url = f"{plex_url}/library/sections?{urlencode(section)}"
        resp = requests.post(url, headers={"X-Plex-Token": token}, timeout=60)
        resp.raise_for_status()

    for section in library_sections:
        try:
            existing = plex.library.section(section["name"])
            if existing.agent != section["agent"]:
                print(
                    f"Recreating '{section['name']}' library (agent {existing.agent} -> {section['agent']})"
                )
                existing.delete()
                add_library(section)
        except NotFound:
            add_library(section)
    plex.settings.fSEventLibraryUpdatesEnabled = True
    plex.settings.fSEventLibraryPartialScanEnabled = True
    plex.settings.customConnections = access_url
    # Remote access through a router port forward of TCP 32400 -> this host.
    # Plex Pass covers remote streaming; Plex tracks the public IP itself.
    plex.settings.publishServerOnPlexOnlineKey = True
    plex.settings.manualPortMappingMode = True
    plex.settings.manualPortMappingPort = 32400
    plex.settings.save()


if __name__ == "__main__":
    main()

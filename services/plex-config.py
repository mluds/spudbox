import os
from os import getenv
from urllib.parse import urlencode

import requests
from plexapi.exceptions import NotFound
from plexapi.myplex import MyPlexAccount
from plexapi.server import PlexServer


def read_file(path):
    with open(path) as f:
        return f.read().strip()


def get_token(plex_url, token_path, username_file, password_file):
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
    username = read_file(username_file)
    password = read_file(password_file)
    account = MyPlexAccount(username, password)
    token = account.authToken
    os.umask(0o077)  # a new secret file is 0600 from the start
    with open(token_path, "w") as f:
        f.write(token)
    return token


def main():
    plex_url = getenv("PLEX_URL")
    access_url = getenv("PLEX_ACCESS_URL")
    media_dir = getenv("MEDIA_DIR")
    token_path = f"{getenv('SECRETS_DIR')}/plex/token"
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

    token = get_token(
        plex_url, token_path, getenv("PLEX_USERNAME_FILE"), getenv("PLEX_PASSWORD_FILE")
    )
    plex = PlexServer(plex_url, token)

    def add_library(section):
        """Add a library section via the raw Plex API.

        PlexAPI's library.add() forces language=en-US which is invalid for
        the com.plexapp.agents.none agent (Other Videos), so we use the
        raw API for all libraries to keep things consistent.
        """
        params = urlencode(
            {
                "name": section["name"],
                "type": section["type"],
                "agent": section["agent"],
                "scanner": section["scanner"],
                "language": section["language"],
                "location": section["location"],
            }
        )
        url = f"{plex_url}/library/sections?{params}"
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

{ config, pkgs, ... }:

with config.my;

let
  pythonEnv = pkgs.python3.withPackages (ps: [ ps.plexapi ]);
  configurePlexScript = pkgs.writeText "configure-plex.py" ''
    from os import getenv
    from urllib.parse import urlencode
    import requests
    from plexapi.server import PlexServer
    from plexapi.myplex import MyPlexAccount
    from plexapi.exceptions import NotFound

    def read_file(path):
        with open(path, 'r') as f:
            return f.read().strip()

    def get_token(plex_url, token_path, username_file, password_file):
      # Reuse existing token if valid
      try:
        token = read_file(token_path)
        if token:
          PlexServer(plex_url, token)
          print("Existing token is valid, skipping sign-in")
          return token
      except Exception:
        pass

      # Token missing or invalid, sign in
      print("Signing in to Plex...")
      username = read_file(username_file)
      password = read_file(password_file)
      account = MyPlexAccount(username, password)
      token = account.authToken
      with open(token_path, 'w') as f:
        f.write(token)
      return token

    def main():
      plex_url = getenv('PLEX_URL')
      access_url = getenv('PLEX_ACCESS_URL')
      token_path = '${secretsDir}/plex/token'
      library_sections = [
        {
          "name": "Movies",
          "type": "movie",
          "agent": "tv.plex.agents.movie",
          "scanner": "Plex Movie",
          "location": "${storageDir}/data/media/movies",
          "language": "en-US"
        },
        {
          "name": "TV Shows",
          "type": "show",
          "agent": "tv.plex.agents.series",
          "scanner": "Plex TV Series",
          "location": "${storageDir}/data/media/tv",
          "language": "en-US"
        },
        {
          "name": "Videos",
          "type": "movie",
          "agent": "com.plexapp.agents.none",
          "scanner": "Plex Video Files Scanner",
          "location": "${storageDir}/data/media/videos",
          "language": "xn"
        }
      ]

      token = get_token(plex_url, token_path, getenv('PLEX_USERNAME_FILE'), getenv('PLEX_PASSWORD_FILE'))
      plex = PlexServer(plex_url, token)

      def add_library(section):
        """Add a library section via the raw Plex API.

        PlexAPI's library.add() forces language=en-US which is invalid for
        the com.plexapp.agents.none agent (Other Videos), so we use the
        raw API for all libraries to keep things consistent.
        """
        params = urlencode({
          'name': section['name'],
          'type': section['type'],
          'agent': section['agent'],
          'scanner': section['scanner'],
          'language': section['language'],
          'location': section['location'],
        })
        url = f"{plex_url}/library/sections?{params}"
        resp = requests.post(url, headers={'X-Plex-Token': token})
        resp.raise_for_status()

      for section in library_sections:
        try:
          existing = plex.library.section(section['name'])
          if existing.agent != section['agent']:
            print(f"Recreating '{section['name']}' library (agent {existing.agent} -> {section['agent']})")
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

    if __name__ == '__main__':
        main()
  '';
in
{
  users.groups.plex = { };

  services.plex = {
    enable = true;
    user = "plex";
    group = "media";
    openFirewall = true;
  };

  systemd.tmpfiles.rules = [
    # Plex state (databases, Preferences.xml with its token) is private
    "d ${config.services.plex.dataDir} 0700 plex media -"
    "d ${secretsDir} 0700 root root -"
    "d ${secretsDir}/plex 0700 root root -"
    "f ${secretsDir}/plex/token 0600 root root -"
    "f ${secretsDir}/plex/username 0600 root root -"
    "f ${secretsDir}/plex/password 0600 root root -"
  ];

  systemd.services.plex-config = {
    description = "Configure Plex libraries and settings after startup";
    after = [ "plex.service" ];
    requires = [ "plex.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Environment = [
        "PLEX_URL=http://localhost:${toString plexPort}"
        "PLEX_ACCESS_URL=https://plex.${domain}"
        "PLEX_USERNAME_FILE=${secretsDir}/plex/username"
        "PLEX_PASSWORD_FILE=${secretsDir}/plex/password"
      ];

      ExecStartPre = "${pkgs.bash}/bin/bash -c 'until ${pkgs.curl}/bin/curl -sSf http://localhost:${toString plexPort}/identity; do sleep 1; done'";
      ExecStart = "${pythonEnv}/bin/python ${configurePlexScript}";
    };
  };
}

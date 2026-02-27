{ config, pkgs, ... }:

with config.my;

let
  pythonEnv = pkgs.python3.withPackages (ps: [ ps.plexapi ]);
  configurePlexScript = pkgs.writeText "configure-plex.py" ''
    from os import getenv
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
        }
      ]

      token = get_token(plex_url, token_path, getenv('PLEX_USERNAME_FILE'), getenv('PLEX_PASSWORD_FILE'))
      plex = PlexServer(plex_url, token)

      for section in library_sections:
        try:
          plex.library.section(section['name'])
        except NotFound:
          plex.library.add(
            name=section['name'],
            type=section['type'],
            agent=section['agent'],
            scanner=section['scanner'],
            location=section['location'],
            language=section['language']
          )
      plex.settings.fSEventLibraryUpdatesEnabled = True
      plex.settings.fSEventLibraryPartialScanEnabled = True
      plex.settings.customConnections = access_url
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
    "d ${secretsDir} 0750 root media -"
    "d ${secretsDir}/plex 0750 root media -"
    "f ${secretsDir}/plex/token 0660 root media -"
    "f ${secretsDir}/plex/username 0660 root media -"
    "f ${secretsDir}/plex/password 0660 root media -"
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

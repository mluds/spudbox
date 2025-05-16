{config, pkgs, secrets, ...}:

with config.my;

let
  pythonEnv = pkgs.python3.withPackages (ps: [ ps.plexapi ]);
  configurePlexScript = pkgs.writeText "configure-plex.py" ''
    import os
    import traceback
    from plexapi.server import PlexServer
    from plexapi.myplex import MyPlexAccount
    from plexapi.exceptions import NotFound

    def main():
        plex_url = os.environ.get('PLEX_URL')
        access_url = os.environ.get('PLEX_ACCESS_URL')
        username = os.environ.get('PLEX_USERNAME')
        password = os.environ.get('PLEX_PASSWORD')
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
        account = MyPlexAccount(username, password)
        token = account.authToken
        plex = PlexServer(plex_url, token)

        # 1. Write plex token to homepage services config (implement this part)

        # 2. Configure plex libraries and settings
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
in {
  users.groups.plex = {};
  users.users.plex = {
    isSystemUser = true;
    group = "plex";
    extraGroups = [ "media" ];
    createHome = false;
    useDefaultShell = false;
  };

  services.plex = {
    enable = true;
    user = "plex";
    group = "plex";
    openFirewall = true;
  };

  systemd.services.plex.serviceConfig = {
    Environment = [
      # Get a fresh claim token from: https://plex.tv/claim
      "PLEX_CLAIM=${secrets.plexClaim}"
    ];
  };

  systemd.services.plex-config = {
    description = "Configure Plex libraries and settings after startup";
    after = [ "plex.service" ];
    requires = [ "plex.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      User = "plex";
      Environment = [
        "PLEX_URL=http://localhost:${toString plexPort}"
        "PLEX_ACCESS_URL=https://plex.${domain}"
        "PLEX_USERNAME=${secrets.plexUsername}"
        "PLEX_PASSWORD=${secrets.plexPassword}"
      ];

      ExecStartPre = "${pkgs.bash}/bin/bash -c 'until ${pkgs.curl}/bin/curl -sSf http://localhost:${toString plexPort}/identity; do sleep 1; done'";
      ExecStart = "${pythonEnv}/bin/python ${configurePlexScript}";
    };
  };
}

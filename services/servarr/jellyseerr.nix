{ config, pkgs, lib, secrets, ... }:

with config.my;

let
  partialSettingsFile = pkgs.writeText "jellyseerr-settings.json" (builtins.toJSON {
    main = {
      apiKey = secrets.jellyseerr.apiKey;
    };
    plex = {
      name = "SpudBox";
      ip = "localhost";
      port = plexPort;
      useSsl = false;
      libraries = [
        {
          id = 11;
          name = "Movies";
          enabled = true;
          type = "movie";
        }
        {
          id = 12;
          name = "TV Shows";
          enabled = true;
          type = "show";
        }
      ];
    };
    tautulli = {};
    radarr = [
      {
        name = "Radarr";
        hostname = "localhost";
        port = 7878;
        apiKey = "__RADARR_API_KEY__";  # Placeholder value
        useSsl = false;
        activeProfileId = 1;
        activeProfileName = "Any";
        activeDirectory = "${storageDir}/data/media/movies";
        is4k = false;
        minimumAvailability = "released";
        tags = [];
        isDefault = true;
        syncEnabled = true;
        preventSearch = false;
        tagRequests = false;
        id = 0;
      }
    ];
    sonarr = [
      {
        name = "Sonarr";
        hostname = "localhost";
        port = sonarrPort;
        apiKey = secrets.sonarrApiKey;
        useSsl = false;
        baseUrl = "";
        activeProfileId = 1;
        activeProfileName = "Any";
        activeDirectory = "${storageDir}/data/media/tv";
        tags = [];
        animeTags = [];
        is4k = false;
        isDefault = true;
        enableSeasonFolders = false;
        syncEnabled = true;
        preventSearch = false;
        tagRequests = false;
        id = 0;
      }
    ];
  });
  configMerger = pkgs.writeScriptBin "jellyseerr-config-merger" ''
    #!/bin/sh
    set -e
    
    echo "Waiting for Jellyseerr to start..."
    until curl -sSf http://localhost:${toString jellyseerrPort}/settings/main >/dev/null; do
      sleep 2
    done

    echo "Merging configuration..."
    jq -s '.[0] * .[1]' \
      /var/lib/jellyseerr/config/settings.json \
      ${partialSettingsFile} \
      > /var/lib/jellyseerr/config/settings.json.tmp

    echo "Reading Radarr API key from secrets file..."
    RADARR_API_KEY=$(tr -d '\n' < ${secretsDir}/radarr/api-key)

    echo "Injecting Radarr API key into configuration..."
    jq --arg key "$RADARR_API_KEY" \
       '.radarr[0].apiKey = $key' \
       /var/lib/jellyseerr/config/settings.json.tmp \
       > /var/lib/jellyseerr/config/settings.json

    chown jellyseerr:jellyseerr /var/lib/jellyseerr/config/settings.json
    rm -f /var/lib/jellyseerr/config/settings.json.tmp
    systemctl try-reload-or-restart jellyseerr
  '';
in
{
  users.groups.jellyseerr = {};
  users.users.jellyseerr = {
    isSystemUser = true;
    group = "jellyseerr";
    extraGroups = [ "media" ];
    createHome = false;
    useDefaultShell = false;
  };

  services.jellyseerr = {
    enable = true;
    openFirewall = false;
  };

  systemd.services.jellyseerr = {
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "jellyseerr";
      Group = "jellyseerr";
      StateDirectory = "jellyseerr";
    };
  };

  systemd.services.jellyseerr-config = {
    description = "Jellyseerr Configuration Merger";
    after = [ "jellyseerr.service" ];
    path = with pkgs; [ curl jq coreutils ];
    serviceConfig = {
      Type = "exec";
      User = "root";
      ExecStart = "${configMerger}/bin/jellyseerr-config-merger";
    };
  };
}

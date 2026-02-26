{ config, pkgs, lib, secrets, ... }:

with config.my;

let
  settingsFile = "/var/lib/jellyseerr/config/settings.json";

  configScript = pkgs.writeScriptBin "jellyseerr-config" ''
    #!/bin/sh
    set -e

    CURL="${pkgs.curl}/bin/curl"
    JQ="${pkgs.jq}/bin/jq"
    BASE="http://localhost:''${JELLYSEERR_PORT}"

    echo "Waiting for Jellyseerr to start..."
    until $CURL -sSf "$BASE/api/v1/settings/public" >/dev/null 2>&1; do
      sleep 2
    done

    INITIALIZED=$($CURL -s "$BASE/api/v1/settings/public" | $JQ -r '.initialized')
    if [ "$INITIALIZED" = "true" ]; then
      echo "Jellyseerr already initialized, skipping setup."
      exit 0
    fi

    PLEX_TOKEN=$(cat ${secretsDir}/plex/token)
    RADARR_KEY=$(tr -d '\n' < ${secretsDir}/radarr/api-key)
    SONARR_KEY=$(tr -d '\n' < ${secretsDir}/sonarr/api-key)

    COOKIE_FILE=$(mktemp)
    trap "rm -f $COOKIE_FILE" EXIT

    echo "Authenticating with Plex..."
    $CURL -s -c "$COOKIE_FILE" -X POST -H 'Content-Type: application/json' \
      -d "{\"authToken\": \"$PLEX_TOKEN\"}" \
      "$BASE/api/v1/auth/plex" >/dev/null

    echo "Marking setup as complete..."
    $CURL -s -b "$COOKIE_FILE" -X POST -H 'Content-Type: application/json' \
      "$BASE/api/v1/settings/initialize" >/dev/null

    echo "Configuring Plex server..."
    $CURL -s -b "$COOKIE_FILE" -X POST -H 'Content-Type: application/json' \
      -d "{\"ip\": \"127.0.0.1\", \"port\": ''${PLEX_PORT}, \"useSsl\": false}" \
      "$BASE/api/v1/settings/plex" >/dev/null

    echo "Syncing Plex libraries..."
    $CURL -s -b "$COOKIE_FILE" "$BASE/api/v1/settings/plex/library?sync=true" >/dev/null

    echo "Enabling libraries..."
    $JQ '.plex.libraries = [.plex.libraries[] | .enabled = true]' \
      ${settingsFile} > ${settingsFile}.tmp
    mv ${settingsFile}.tmp ${settingsFile}
    chown jellyseerr:jellyseerr ${settingsFile}

    echo "Adding Radarr..."
    $CURL -s -b "$COOKIE_FILE" -X POST -H 'Content-Type: application/json' \
      -d "{\"name\": \"Radarr\", \"hostname\": \"localhost\", \"port\": ''${RADARR_PORT}, \"apiKey\": \"$RADARR_KEY\", \"useSsl\": false, \"activeProfileId\": 1, \"activeProfileName\": \"Any\", \"activeDirectory\": \"''${MOVIES_DIR}\", \"is4k\": false, \"minimumAvailability\": \"released\", \"tags\": [], \"isDefault\": true, \"syncEnabled\": true, \"preventSearch\": false, \"tagRequests\": false}" \
      "$BASE/api/v1/settings/radarr" >/dev/null

    echo "Adding Sonarr..."
    $CURL -s -b "$COOKIE_FILE" -X POST -H 'Content-Type: application/json' \
      -d "{\"name\": \"Sonarr\", \"hostname\": \"localhost\", \"port\": ''${SONARR_PORT}, \"apiKey\": \"$SONARR_KEY\", \"useSsl\": false, \"baseUrl\": \"\", \"activeProfileId\": 1, \"activeProfileName\": \"Any\", \"activeDirectory\": \"''${TV_DIR}\", \"tags\": [], \"animeTags\": [], \"is4k\": false, \"isDefault\": true, \"enableSeasonFolders\": false, \"syncEnabled\": true, \"preventSearch\": false, \"tagRequests\": false}" \
      "$BASE/api/v1/settings/sonarr" >/dev/null

    echo "Restarting Jellyseerr..."
    systemctl restart jellyseerr

    echo "Jellyseerr setup complete."
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
    description = "Configure Jellyseerr";
    after = [ "jellyseerr.service" "plex-config.service" "radarr-config.service" "sonarr-config.service" ];
    wants = [ "jellyseerr.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = "${configScript}/bin/jellyseerr-config";
    };

    environment = {
      JELLYSEERR_PORT = toString jellyseerrPort;
      PLEX_PORT = toString plexPort;
      RADARR_PORT = toString radarrPort;
      SONARR_PORT = toString sonarrPort;
      MOVIES_DIR = "${storageDir}/data/media/movies";
      TV_DIR = "${storageDir}/data/media/tv";
    };
  };
}

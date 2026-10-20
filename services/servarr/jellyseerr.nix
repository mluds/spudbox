{
  config,
  pkgs,
  lib,
  ...
}:

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

    export_api_key() {
      echo "Exporting API key..."
      mkdir -p ${secretsDir}/jellyseerr
      $JQ -r '.main.apiKey' ${settingsFile} > ${secretsDir}/jellyseerr/api-key
    }

    configure_email() {
      echo "Configuring email notifications..."
      GMAIL_ADDRESS=$(cat ${secretsDir}/gmail/address)
      GMAIL_APP_PASSWORD=$(cat ${secretsDir}/gmail/app-password)

      $JQ --arg emailFrom "$GMAIL_ADDRESS" \
          --arg authUser "$GMAIL_ADDRESS" \
          --arg authPass "$GMAIL_APP_PASSWORD" \
          '.notifications.agents.email = {
            "enabled": false,
            "types": 4,
            "options": {
              "emailFrom": $emailFrom,
              "smtpHost": "smtp.gmail.com",
              "smtpPort": 587,
              "secure": false,
              "ignoreTls": false,
              "requireTls": true,
              "authUser": $authUser,
              "authPass": $authPass,
              "allowSelfSigned": false,
              "senderName": "Jellyseerr"
            }
          }' ${settingsFile} > ${settingsFile}.tmp
      mv ${settingsFile}.tmp ${settingsFile}
      chown jellyseerr:jellyseerr ${settingsFile}
    }

    configure_pushover() {
      echo "Configuring Pushover notifications..."
      PUSHOVER_TOKEN=$(cat ${secretsDir}/pushover/app-token)
      PUSHOVER_USER=$(cat ${secretsDir}/pushover/user-key)
      API_KEY=$($JQ -r '.main.apiKey' ${settingsFile})

      $CURL -s -X POST -H 'Content-Type: application/json' \
        -H "X-Api-Key: $API_KEY" \
        -d "{\"enabled\": true, \"types\": 24, \"options\": {\"accessToken\": \"$PUSHOVER_TOKEN\", \"userToken\": \"$PUSHOVER_USER\", \"sound\": \"pushover\"}}" \
        "$BASE/api/v1/settings/notifications/pushover" >/dev/null
    }

    configure_plex() {
      echo "Configuring Plex settings..."
      API_KEY=$($JQ -r '.main.apiKey' ${settingsFile})

      # Enable periodic full scan to catch movies that were initially
      # unmatched when added to Plex (race between add and metadata match)
      $CURL -s -X POST -H 'Content-Type: application/json' \
        -H "X-Api-Key: $API_KEY" \
        -d "{\"ip\": \"127.0.0.1\", \"port\": ''${PLEX_PORT}, \"useSsl\": false, \"periodicScanning\": 21600}" \
        "$BASE/api/v1/settings/plex" >/dev/null

      # Enable all libraries for scanning
      LIB_IDS=$($CURL -s "$BASE/api/v1/settings/plex/library" \
        -H "X-Api-Key: $API_KEY" | $JQ -r '[.[].id] | join(",")')
      $CURL -s "$BASE/api/v1/settings/plex/library?sync=true&enable=$LIB_IDS" \
        -H "X-Api-Key: $API_KEY" >/dev/null

      # Run recently added scan once daily instead of every 5 minutes
      # to avoid waking the HDD with constant Plex API queries
      $CURL -s -X POST -H 'Content-Type: application/json' \
        -H "X-Api-Key: $API_KEY" \
        -d '{"schedule": "0 0 6 * * *"}' \
        "$BASE/api/v1/settings/jobs/plex-recently-added-scan/schedule" >/dev/null
    }

    set_external_urls() {
      echo "Setting external URLs for Radarr/Sonarr..."
      $JQ --arg radarrUrl "$RADARR_EXTERNAL_URL" \
          --arg sonarrUrl "$SONARR_EXTERNAL_URL" \
        '.radarr = [.radarr[] | .externalUrl = $radarrUrl] | .sonarr = [.sonarr[] | .externalUrl = $sonarrUrl]' \
        ${settingsFile} > ${settingsFile}.tmp
      mv ${settingsFile}.tmp ${settingsFile}
      chown jellyseerr:jellyseerr ${settingsFile}
    }

    INITIALIZED=$($CURL -s "$BASE/api/v1/settings/public" | $JQ -r '.initialized')
    if [ "$INITIALIZED" = "true" ]; then
      echo "Jellyseerr already initialized, skipping setup."
      export_api_key
      configure_plex
      configure_email
      configure_pushover
      set_external_urls
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
      -d "{\"ip\": \"127.0.0.1\", \"port\": ''${PLEX_PORT}, \"useSsl\": false, \"periodicScanning\": 21600}" \
      "$BASE/api/v1/settings/plex" >/dev/null

    echo "Syncing Plex libraries..."
    $CURL -s -b "$COOKIE_FILE" "$BASE/api/v1/settings/plex/library?sync=true" >/dev/null

    echo "Adding Radarr..."
    $CURL -s -b "$COOKIE_FILE" -X POST -H 'Content-Type: application/json' \
      -d "{\"name\": \"Radarr\", \"hostname\": \"localhost\", \"port\": ''${RADARR_PORT}, \"apiKey\": \"$RADARR_KEY\", \"useSsl\": false, \"externalUrl\": \"''${RADARR_EXTERNAL_URL}\", \"activeProfileId\": 1, \"activeProfileName\": \"Any\", \"activeDirectory\": \"''${MOVIES_DIR}\", \"is4k\": false, \"minimumAvailability\": \"released\", \"tags\": [], \"isDefault\": true, \"syncEnabled\": true, \"preventSearch\": false, \"tagRequests\": false}" \
      "$BASE/api/v1/settings/radarr" >/dev/null

    echo "Adding Sonarr..."
    $CURL -s -b "$COOKIE_FILE" -X POST -H 'Content-Type: application/json' \
      -d "{\"name\": \"Sonarr\", \"hostname\": \"localhost\", \"port\": ''${SONARR_PORT}, \"apiKey\": \"$SONARR_KEY\", \"useSsl\": false, \"externalUrl\": \"''${SONARR_EXTERNAL_URL}\", \"baseUrl\": \"\", \"activeProfileId\": 1, \"activeProfileName\": \"Any\", \"activeDirectory\": \"''${TV_DIR}\", \"tags\": [], \"animeTags\": [], \"is4k\": false, \"isDefault\": true, \"enableSeasonFolders\": false, \"syncEnabled\": true, \"preventSearch\": false, \"tagRequests\": false}" \
      "$BASE/api/v1/settings/sonarr" >/dev/null

    export_api_key
    configure_plex
    configure_email
    configure_pushover

    echo "Restarting Jellyseerr..."
    systemctl restart seerr

    echo "Jellyseerr setup complete."
  '';
in
{
  users.groups.jellyseerr = { };
  users.users.jellyseerr = {
    isSystemUser = true;
    group = "jellyseerr";
    extraGroups = [ "media" ];
    createHome = false;
    useDefaultShell = false;
  };

  services.seerr = {
    enable = true;
    openFirewall = false;
  };

  systemd.services.seerr = {
    # Loopback only; reached through Caddy.
    environment.HOST = "127.0.0.1";
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "jellyseerr";
      Group = "jellyseerr";
      StateDirectory = "jellyseerr";
      # settings.json holds the Gmail app password and Plex token
      StateDirectoryMode = "0700";
    };
  };

  systemd.services.jellyseerr-config = {
    description = "Configure Jellyseerr";
    after = [
      "seerr.service"
      "plex-config.service"
      "radarr-config.service"
      "sonarr-config.service"
    ];
    wants = [ "seerr.service" ];
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
      RADARR_EXTERNAL_URL = "https://radarr.${domain}";
      SONARR_EXTERNAL_URL = "https://sonarr.${domain}";
    };
  };
}

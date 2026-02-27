{ config, pkgs, ... }:

with config.my;

let
  quality = import ./qualityDefinitions.nix;
  cfgFile = "${config.services.sonarr.dataDir}/config.xml";
  dbFile = "${config.services.sonarr.dataDir}/sonarr.db";
  configScript = pkgs.writeScriptBin "sonarr-config" ''
    #!/bin/sh
    set -e
    SONARR_API_KEY=$(cat ${secretsDir}/sonarr/api-key)
    NZBGEEK_API_KEY=$(cat ${secretsDir}/nzbgeek/api-key)
    SABNZBD_API_KEY=$(cat ${secretsDir}/sabnzbd/api-key)
    ADMIN_USERNAME=$(cat ${secretsDir}/admin/username)
    ADMIN_PASSWORD=$(cat ${secretsDir}/admin/password)

    if [ -f "${dbFile}" ]; then
      sqlite3 "${dbFile}" "DELETE FROM \"Users\";"
    fi
    xmlstarlet ed -L \
      --subnode '/Config[not(Authentication)]' -t elem -n Authentication \
      --subnode '/Config/Authentication[not(Username)]' -t elem -n Username \
      --subnode '/Config/Authentication[not(Password)]' -t elem -n Password \
      -u "/Config/AuthenticationMethod" -v "Forms" \
      -u "/Config/Authentication/Username" -v "$ADMIN_USERNAME" \
      -u "/Config/Authentication/Password" -v "$ADMIN_PASSWORD" \
      -u "/Config/ApiKey" -v "$SONARR_API_KEY" \
      "${cfgFile}"
    if systemctl -q is-active sonarr.service; then
      systemctl restart sonarr.service
    fi

    echo "Waiting for Sonarr to start..."
    while ! curl -sSf "http://localhost:${toString sonarrPort}/login" >/dev/null; do
      sleep 2
    done

    echo "Adding root folder..."
    curl -X POST "http://localhost:${toString sonarrPort}/api/v3/rootfolder" \
      -H "X-Api-Key: $SONARR_API_KEY" \
      -H "Content-Type: application/json" \
      -d '{"name": "TV", "path": "${storageDir}/data/media/tv"}' \
      --fail --silent --show-error || echo "Root folder may already exist"

    echo "Configuring media management settings..."
    curl -X PUT "http://localhost:${toString sonarrPort}/api/v3/config/mediamanagement/1" \
      -H "X-Api-Key: $SONARR_API_KEY" \
      -H "Content-Type: application/json" \
      -d '{
        "id": 1,
        "autoUnmonitorPreviouslyDownloadedMovies": false,
        "recycleBin": "",
        "recycleBinCleanupDays": 7,
        "downloadPropersAndRepacks": "preferAndUpgrade",
        "createEmptyMovieFolders": false,
        "deleteEmptyFolders": false,
        "fileDate": "none",
        "rescanAfterRefresh": "always",
        "autoRenameFolders": false,
        "pathsDefaultStatic": false,
        "setPermissionsLinux": true,
        "chmodFolder": "775",
        "chownGroup": "",
        "skipFreeSpaceCheckWhenImporting": false,
        "minimumFreeSpaceWhenImporting": 100,
        "copyUsingHardlinks": true,
        "useScriptImport": false,
        "scriptImportPath": "",
        "importExtraFiles": false,
        "extraFileExtensions": "srt",
        "enableMediaInfo": true
      }' \
      --fail --silent --show-error || echo "Media management may already be configured"

    echo "Configuring NZBGeek..."
    curl -X POST "http://localhost:${toString sonarrPort}/api/v3/indexer" \
      -H "X-Api-Key: $SONARR_API_KEY" \
      -H "Content-Type: application/json" \
      -d '{
        "name": "NZBGeek",
        "implementationName": "Newznab",
        "implementation": "Newznab",
        "configContract": "NewznabSettings",
        "enable": true,
        "protocol": "usenet",
        "enableRss": true,
        "enableAutomaticSearch": true,
        "enableInteractiveSearch": true,
        "supportsRss": true,
        "supportsSearch": true,
        "fields": [
          {"name": "baseUrl", "value": "https://api.nzbgeek.info/"},
          {"name": "apiPath", "value": "/api"},
          {"name": "apiKey", "value": "'"$NZBGEEK_API_KEY"'"},
          {"name": "categories", "value": [5020, 5030, 5040, 5045]},
          {"name": "animeCategories", "value": [5070]},
          {"name": "animeStandardFormatSearch", "value": true}
        ]
      }' \
      --fail --silent --show-error || echo "NZBGeek may already be configured"

    echo "Configuring SABnzbd..."
    curl -X POST "http://localhost:${toString sonarrPort}/api/v3/downloadclient" \
      -H "X-Api-Key: $SONARR_API_KEY" \
      -H "Content-Type: application/json" \
      -d '{
        "name": "SABnzbd",
        "enable": true,
        "protocol": "usenet",
        "implementation": "Sabnzbd",
        "configContract": "SabnzbdSettings",
        "removeCompletedDownloads": true,
        "removeFailedDownloads": true,
        "fields": [
          {"name": "host", "value": "localhost"},
          {"name": "port", "value": ${toString sabnzbdPort}},
          {"name": "apiKey", "value": "$SABNZBD_API_KEY"},
          {"name": "category", "value": "tv"}
        ]
      }' \
      --fail --silent --show-error || echo "SABnzbd may already be configured"

    echo "Ensuring download cleanup is enabled..."
    SAB_CLIENT=$(curl -sS "http://localhost:${toString sonarrPort}/api/v3/downloadclient" \
      -H "X-Api-Key: $SONARR_API_KEY" | jq '.[0]')
    if [ "$(echo "$SAB_CLIENT" | jq '.removeCompletedDownloads')" != "true" ] || \
       [ "$(echo "$SAB_CLIENT" | jq '.removeFailedDownloads')" != "true" ]; then
      SAB_ID=$(echo "$SAB_CLIENT" | jq '.id')
      echo "$SAB_CLIENT" | jq '.removeCompletedDownloads = true | .removeFailedDownloads = true' | \
        curl -X PUT "http://localhost:${toString sonarrPort}/api/v3/downloadclient/$SAB_ID" \
          -H "X-Api-Key: $SONARR_API_KEY" \
          -H "Content-Type: application/json" \
          -d @- --fail --silent --show-error
    fi

    echo "Updating quality profiles..."
    qualityDefs=$(curl -sS "http://localhost:${toString sonarrPort}/api/v3/qualitydefinition" \
      -H "X-Api-Key: $SONARR_API_KEY")

    echo '${builtins.toJSON quality.qualitySettings}' > /tmp/quality_settings_sonarr.json

    echo "$qualityDefs" | jq --argjson settings "$(cat /tmp/quality_settings_sonarr.json)" '
      map(
        . as $def |
        ($def.quality.name) as $name |
        if $settings | has($name) then
          $def * {
            minSize: $settings[$name].minSize,
            maxSize: $settings[$name].maxSize,
            preferredSize: $settings[$name].preferredSize
          }
        else
          $def
        end
      )
    ' | jq -c '.[]' | while read def; do
      id=$(jq -r '.id' <<< "$def")
      echo "Updating $id..."
      curl -X PUT "http://localhost:${toString sonarrPort}/api/v3/qualitydefinition/$id" \
        -H "X-Api-Key: $SONARR_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$def" \
        --fail --silent --show-error || echo "Failed to update $id"
    done
    rm -f /tmp/quality_settings_sonarr.json

    echo "Importing existing shows from disk..."
    UNMAPPED=$(curl -sS "http://localhost:${toString sonarrPort}/api/v3/rootfolder" \
      -H "X-Api-Key: $SONARR_API_KEY" \
      | jq -r '.[0].unmappedFolders[].name')
    if [ -n "$UNMAPPED" ]; then
      echo "$UNMAPPED" | while IFS= read -r folder; do
        SEARCH_TERM=$(echo "$folder" | sed 's/([^)]*)$//' | sed 's/ *$//')
        SHOW=$(curl -sS "http://localhost:${toString sonarrPort}/api/v3/series/lookup?term=$(echo "$SEARCH_TERM" | jq -sRr @uri)" \
          -H "X-Api-Key: $SONARR_API_KEY" \
          | jq '.[0]')
        if [ "$SHOW" != "null" ] && [ -n "$SHOW" ]; then
          echo "$SHOW" | jq --arg path "${storageDir}/data/media/tv/$folder" \
            '. + {path: $path, rootFolderPath: "${storageDir}/data/media/tv", qualityProfileId: 1, monitored: true, addOptions: {monitor: "existing", searchForMissingEpisodes: false, searchForCutoffUnmetEpisodes: false}}' \
            | curl -sS -X POST "http://localhost:${toString sonarrPort}/api/v3/series" \
              -H "X-Api-Key: $SONARR_API_KEY" \
              -H "Content-Type: application/json" \
              -d @- >/dev/null 2>&1 && echo "  Added: $folder" || echo "  Skipped: $folder (already exists or error)"
        else
          echo "  Not found: $folder"
        fi
      done
      echo "Triggering disk scan..."
      curl -sS -X POST "http://localhost:${toString sonarrPort}/api/v3/command" \
        -H "X-Api-Key: $SONARR_API_KEY" \
        -H "Content-Type: application/json" \
        -d '{"name": "RescanSeries"}' >/dev/null
    else
      echo "  No unmapped folders found"
    fi

    echo "Applying quality profile..."
    curl -X PUT "http://localhost:${toString sonarrPort}/api/v3/qualityprofile/1" \
      -H "X-Api-Key: $SONARR_API_KEY" \
      -H "Content-Type: application/json" \
      -d '${builtins.toJSON quality.qualityProfile}' \
      --fail --silent --show-error
  '';
in {
  services.sonarr = {
    enable = true;
    user = "sonarr";
    group = "media";
    openFirewall = false;
  };

  systemd.services.sonarr-config = {
    wantedBy = [ "multi-user.target" ];
    after = [ "sonarr.service" ];
    path = with pkgs; [ curl jq xmlstarlet sqlite ];
    serviceConfig = {
      User = "root";
      Type = "oneshot";
      ExecStart = "${configScript}/bin/sonarr-config";
    };
  };
}

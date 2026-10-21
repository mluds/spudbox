{ config, pkgs, ... }:

with config.my;

let
  quality = import ./qualityDefinitions.nix;
  cfgFile = "${config.services.radarr.dataDir}/config.xml";
  dbFile = "${config.services.radarr.dataDir}/radarr.db";
  setConfigXml = import ./set-config-xml.nix { inherit pkgs; };
  configScript = pkgs.writeScriptBin "radarr-config" ''
    #!/bin/sh
    set -e
    umask 077
    # Secrets go to curl via files (-H @file, -d @file), never as arguments,
    # which any local user could read from /proc/<pid>/cmdline.
    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT
    printf 'X-Api-Key: %s\n' "$(cat ${secretsDir}/radarr/api-key)" > "$TMP/key"
    NZBGEEK_API_KEY=$(cat ${secretsDir}/nzbgeek/api-key)
    SABNZBD_API_KEY=$(cat ${secretsDir}/sabnzbd/api-key)

    if [ -f "${dbFile}" ]; then
      sqlite3 "${dbFile}" "DELETE FROM \"Users\";"
    fi
    xmlstarlet ed -L \
      -u "/Config/AuthenticationMethod" -v "Forms" \
      "${cfgFile}"
    ${setConfigXml}/bin/set-config-xml "${cfgFile}" \
      Authentication/Username=${secretsDir}/admin/username \
      Authentication/Password=${secretsDir}/radarr/password \
      ApiKey=${secretsDir}/radarr/api-key
    if systemctl -q is-active radarr.service; then
      systemctl restart radarr.service
    fi

    echo "Waiting for Radarr to start..."
    while ! curl -sSf "http://localhost:${toString radarrPort}/login" >/dev/null; do
      sleep 2
    done

    echo "Adding root folder..."
    curl -X POST "http://localhost:${toString radarrPort}/api/v3/rootfolder" \
      -H @"$TMP/key" \
      -H "Content-Type: application/json" \
      -d '{"name": "Movies", "path": "${storageDir}/data/media/movies"}' \
      --fail --silent --show-error || echo "Root folder may already exist"

    echo "Configuring media management settings..."
    curl -X PUT "http://localhost:${toString radarrPort}/api/v3/config/mediamanagement/1" \
      -H @"$TMP/key" \
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
    curl -X POST "http://localhost:${toString radarrPort}/api/v3/indexer" \
      -H @"$TMP/key" \
      -H "Content-Type: application/json" \
      -d @- \
      --fail --silent --show-error <<EOF || echo "NZBGeek may already be configured"
      {
        "name": "NZBGeek",
        "priority": 1,
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
          {"name": "apiKey", "value": "$NZBGEEK_API_KEY"},
          {"name": "categories", "value": [2000, 2010, 2020, 2030, 2040, 2045, 2050, 2060]}
        ]
      }
    EOF

    echo "Configuring SABnzbd..."
    curl -X POST "http://localhost:${toString radarrPort}/api/v3/downloadclient" \
      -H @"$TMP/key" \
      -H "Content-Type: application/json" \
      -d @- \
      --fail --silent --show-error <<EOF || echo "SABnzbd may already be configured"
      {
        "name": "SABnzbd",
        "priority": 1,
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
          {"name": "category", "value": "movies"}
        ]
      }
    EOF

    echo "Ensuring download cleanup is enabled..."
    SAB_CLIENT=$(curl -sS "http://localhost:${toString radarrPort}/api/v3/downloadclient" \
      -H @"$TMP/key" | jq '.[0]')
    if [ "$(echo "$SAB_CLIENT" | jq '.removeCompletedDownloads')" != "true" ] || \
       [ "$(echo "$SAB_CLIENT" | jq '.removeFailedDownloads')" != "true" ]; then
      SAB_ID=$(echo "$SAB_CLIENT" | jq '.id')
      echo "$SAB_CLIENT" | jq '.removeCompletedDownloads = true | .removeFailedDownloads = true' | \
        curl -X PUT "http://localhost:${toString radarrPort}/api/v3/downloadclient/$SAB_ID" \
          -H @"$TMP/key" \
          -H "Content-Type: application/json" \
          -d @- --fail --silent --show-error
    fi

    echo "Updating quality profiles..."
    qualityDefs=$(curl -sS "http://localhost:${toString radarrPort}/api/v3/qualitydefinition" \
      -H @"$TMP/key")

    echo '${builtins.toJSON quality.qualitySettings}' > "$TMP/quality_settings.json"

    echo "$qualityDefs" | jq --argjson settings "$(cat "$TMP/quality_settings.json")" '
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
      curl -X PUT "http://localhost:${toString radarrPort}/api/v3/qualitydefinition/$id" \
        -H @"$TMP/key" \
        -H "Content-Type: application/json" \
        -d "$def" \
        --fail --silent --show-error || echo "Failed to update $id"
    done
    rm -f "$TMP/quality_settings.json"

    echo "Importing existing movies from disk..."
    UNMAPPED=$(curl -sS "http://localhost:${toString radarrPort}/api/v3/rootfolder" \
      -H @"$TMP/key" \
      | jq -r '.[0].unmappedFolders[].name')
    if [ -n "$UNMAPPED" ]; then
      echo "$UNMAPPED" | while IFS= read -r folder; do
        SEARCH_TERM=$(echo "$folder" | sed 's/(//' | sed 's/)//')
        MOVIE=$(curl -sS "http://localhost:${toString radarrPort}/api/v3/movie/lookup?term=$(echo "$SEARCH_TERM" | jq -sRr @uri)" \
          -H @"$TMP/key" \
          | jq '.[0]')
        if [ "$MOVIE" != "null" ] && [ -n "$MOVIE" ]; then
          echo "$MOVIE" | jq --arg path "${storageDir}/data/media/movies/$folder" \
            '. + {path: $path, rootFolderPath: "${storageDir}/data/media/movies", qualityProfileId: 1, monitored: true, addOptions: {searchForMovie: false}}' \
            | curl -sS -X POST "http://localhost:${toString radarrPort}/api/v3/movie" \
              -H @"$TMP/key" \
              -H "Content-Type: application/json" \
              -d @- >/dev/null 2>&1 && echo "  Added: $folder" || echo "  Skipped: $folder (already exists or error)"
        else
          echo "  Not found: $folder"
        fi
      done
      echo "Triggering disk scan..."
      curl -sS -X POST "http://localhost:${toString radarrPort}/api/v3/command" \
        -H @"$TMP/key" \
        -H "Content-Type: application/json" \
        -d '{"name": "RescanMovie"}' >/dev/null
    else
      echo "  No unmapped folders found"
    fi

    echo "Applying Any quality profile..."
    curl -X PUT "http://localhost:${toString radarrPort}/api/v3/qualityprofile/1" \
      -H @"$TMP/key" \
      -H "Content-Type: application/json" \
      -d '${builtins.toJSON quality.radarrQualityProfile}' \
      --fail --silent --show-error
  '';
  # Runs as a DynamicUser; the API key arrives via LoadCredential and goes to
  # curl as a header file so it never appears on a command line.
  autoImportScript = pkgs.writeShellScript "radarr-auto-import" ''
    umask 077
    printf 'X-Api-Key: %s\n' "$(cat "$CREDENTIALS_DIRECTORY/radarr-api-key")" > "$RUNTIME_DIRECTORY/key"
    API="http://localhost:${toString radarrPort}/api/v3"
    HDR="-H @$RUNTIME_DIRECTORY/key -H Content-Type:application/json"

    # Find import-blocked or import-pending (with warnings) queue items
    BLOCKED=$(${pkgs.curl}/bin/curl -sS "$API/queue?includeUnknownMovieItems=true&pageSize=100" $HDR \
      | ${pkgs.jq}/bin/jq -c '[.records[] | select((.trackedDownloadState == "importBlocked" or (.trackedDownloadState == "importPending" and .trackedDownloadStatus == "warning")) and .movieId != null)]')

    COUNT=$(echo "$BLOCKED" | ${pkgs.jq}/bin/jq 'length')
    if [ "$COUNT" -eq 0 ]; then
      exit 0
    fi

    echo "Found $COUNT items to import, processing..."
    echo "$BLOCKED" | ${pkgs.jq}/bin/jq -c '.[]' | while read -r item; do
      DOWNLOAD_ID=$(echo "$item" | ${pkgs.jq}/bin/jq -r '.downloadId')
      MOVIE_ID=$(echo "$item" | ${pkgs.jq}/bin/jq '.movieId')
      TITLE=$(echo "$item" | ${pkgs.jq}/bin/jq -r '.title')

      # Get manual import candidates for this download
      CANDIDATES=$(${pkgs.curl}/bin/curl -sS "$API/manualimport?downloadId=$DOWNLOAD_ID&movieId=$MOVIE_ID" $HDR)

      # Set the movieId on each candidate and POST the import
      IMPORT_BODY=$(echo "$CANDIDATES" | ${pkgs.jq}/bin/jq --argjson mid "$MOVIE_ID" \
        '[.[] | . + {movieId: $mid}]')

      ${pkgs.curl}/bin/curl -sS -X POST "$API/command" $HDR \
        -d "$(echo "$IMPORT_BODY" | ${pkgs.jq}/bin/jq -c '{name: "ManualImport", importMode: "move", files: .}')" \
        >/dev/null 2>&1 \
        && echo "  Imported: $TITLE" \
        || echo "  Failed: $TITLE"
    done
  '';
in
{
  users.groups.radarr = { };
  users.users.radarr = {
    isSystemUser = true;
    group = "media";
    extraGroups = [ "radarr" ];
    createHome = false;
    useDefaultShell = false;
  };
  services.radarr = {
    enable = true;
    user = "radarr";
    group = "media";
    openFirewall = false;
    # Loopback only; reached through Caddy (env var overrides config.xml).
    settings.server.bindaddress = "127.0.0.1";
  };

  systemd = {
    services = {
      radarr-config = {
        wantedBy = [ "multi-user.target" ];
        after = [ "radarr.service" ];
        path = with pkgs; [
          curl
          jq
          xmlstarlet
          sqlite
        ];
        serviceConfig = {
          User = "root";
          Type = "oneshot";
          ExecStart = "${configScript}/bin/radarr-config";
        };
      };

      radarr-auto-import = {
        description = "Auto-import blocked Radarr downloads";
        after = [ "radarr.service" ];
        requires = [ "radarr.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = autoImportScript;
          DynamicUser = true;
          RuntimeDirectory = "radarr-auto-import";
          LoadCredential = "radarr-api-key:${secretsDir}/radarr/api-key";
        };
      };
    };

    timers.radarr-auto-import = {
      description = "Periodically auto-import blocked Radarr downloads";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*:0/15";
        Persistent = true;
      };
    };
  };
}

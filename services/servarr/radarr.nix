{ config, pkgs, ... }:

with config.my;

let
  quality = import ./qualityDefinitions.nix;
  cfgFile = "${config.services.radarr.dataDir}/config.xml";
  dbFile = "${config.services.radarr.dataDir}/radarr.db";
  configScript = pkgs.writeScriptBin "radarr-config" ''
    #!/bin/sh
    RADARR_API_KEY=$(cat ${secretsDir}/radarr/api-key)
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
      -u "/Config/ApiKey" -v "$RADARR_API_KEY" \
      "${cfgFile}"
    if systemctl -q is-active radarr.service; then
      systemctl restart radarr.service
    fi

    echo "Waiting for Radarr to start..."
    while ! curl -sSf "http://localhost:${toString radarrPort}/login" >/dev/null; do
      sleep 2
    done

    echo "Adding root folder..."
    curl -X POST "http://localhost:${toString radarrPort}/api/v3/rootfolder" \
      -H "X-Api-Key: $RADARR_API_KEY" \
      -H "Content-Type: application/json" \
      -d '{"name": "Movies", "path": "${storageDir}/data/media/movies"}' \
      --fail --silent --show-error || echo "Root folder may already exist"

    echo "Configuring media management settings..."
    curl -X PUT "http://localhost:${toString radarrPort}/api/v3/config/mediamanagement/1" \
      -H "X-Api-Key: $RADARR_API_KEY" \
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
      -H "X-Api-Key: $RADARR_API_KEY" \
      -H "Content-Type: application/json" \
      -d '{
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
          {"name": "apiKey", "value": "'"$NZBGEEK_API_KEY"'"},
          {"name": "categories", "value": [2000, 2010, 2020, 2030, 2040, 2045, 2050, 2060]}
        ]
      }' \
      --fail --silent --show-error || echo "NZBGeek may already be configured"

    echo "Configuring SABnzbd..."
    curl -X POST "http://localhost:${toString radarrPort}/api/v3/downloadclient" \
      -H "X-Api-Key: $RADARR_API_KEY" \
      -H "Content-Type: application/json" \
      -d '{
        "name": "SABnzbd",
        "priority": 1,
        "enable": true,
        "protocol": "usenet",
        "implementation": "Sabnzbd",
        "configContract": "SabnzbdSettings",
        "fields": [
          {"name": "host", "value": "localhost"},
          {"name": "port", "value": ${toString sabnzbdPort}},
          {"name": "apiKey", "value": "$SABNZBD_API_KEY"},
          {"name": "category", "value": "movies"}
        ]
      }' \
      --fail --silent --show-error || echo "SABnzbd may already be configured"

    echo "Updating quality profiles..."
    qualityDefs=$(curl -sS "http://localhost:${toString radarrPort}/api/v3/qualitydefinition" \
      -H "X-Api-Key: $RADARR_API_KEY")

    echo '${builtins.toJSON quality.qualitySettings}' > /tmp/quality_settings_radarr.json

    echo "$qualityDefs" | jq --argjson settings "$(cat /tmp/quality_settings_radarr.json)" '
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
        -H "X-Api-Key: $RADARR_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$def" \
        --fail --silent --show-error || echo "Failed to update $id"
    done
    rm -f /tmp/quality_settings_radarr.json

    echo "Applying Any quality profile..."
    curl -X PUT "http://localhost:${toString radarrPort}/api/v3/qualityprofile/1" \
      -H "X-Api-Key: $RADARR_API_KEY" \
      -H "Content-Type: application/json" \
      -d '${builtins.toJSON quality.radarrQualityProfile}' \
      --fail --silent --show-error
  '';
in {
  users.groups.radarr = {};
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
  };

  systemd.services.radarr-config = {
    wantedBy = [ "multi-user.target" ];
    after = [ "radarr.service" ];
    path = with pkgs; [ curl jq xmlstarlet sqlite ];
    serviceConfig = {
      User = "root";
      Type = "exec";
      ExecStart = "${configScript}/bin/radarr-config";
    };
  };
}

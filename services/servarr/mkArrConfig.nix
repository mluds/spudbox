{
  config,
  lib,
  pkgs,
  helpers,
}:

# Builds the *-config script shared by Sonarr and Radarr: set the admin login
# and API key, then configure the app through its v3 API. It runs on every
# boot, so POSTs for things that already exist fail and are skipped.
{
  name, # "sonarr" / "radarr": service, secret and data dir name
  port,
  rootFolder, # { name, path }
  sabCategory, # SABnzbd category for its downloads
  indexerFields, # extra NZBGeek fields (categories, ...)
  priority ? null, # indexer and download client priority, if not the app's default
  qualityProfile, # PUT to /qualityprofile/1
  # Adding existing folders found on disk:
  lookupPath, # e.g. "movie/lookup"
  addPath, # e.g. "movie"
  addOptions, # merged into each added item
  rescanCommand, # e.g. "RescanMovie"
  searchTermSed, # sed script turning a folder name into a search term
}:

let
  inherit (config.services.${name}) dataDir;
  inherit (config.my) secretsDir sabnzbdPort;
  inherit (import ./qualityDefinitions.nix) qualitySettings;
  setConfigXml = import ./set-config-xml.nix { inherit pkgs; };
  json = value: lib.escapeShellArg (builtins.toJSON value);
  withPriority = attrs: attrs // lib.optionalAttrs (priority != null) { inherit priority; };
  field = name: value: { inherit name value; };

  # Radarr's field names, sent to both apps.
  mediaManagement = {
    id = 1;
    autoUnmonitorPreviouslyDownloadedMovies = false;
    recycleBin = "";
    recycleBinCleanupDays = 7;
    downloadPropersAndRepacks = "preferAndUpgrade";
    createEmptyMovieFolders = false;
    deleteEmptyFolders = false;
    fileDate = "none";
    rescanAfterRefresh = "always";
    autoRenameFolders = false;
    pathsDefaultStatic = false;
    setPermissionsLinux = true;
    chmodFolder = "775";
    chownGroup = "";
    skipFreeSpaceCheckWhenImporting = false;
    minimumFreeSpaceWhenImporting = 100;
    copyUsingHardlinks = true;
    useScriptImport = false;
    scriptImportPath = "";
    importExtraFiles = false;
    extraFileExtensions = "srt";
    enableMediaInfo = true;
  };

  # The apiKey fields are filled in from secret files at runtime (with_key).
  indexer = withPriority {
    name = "NZBGeek";
    implementationName = "Newznab";
    implementation = "Newznab";
    configContract = "NewznabSettings";
    enable = true;
    protocol = "usenet";
    enableRss = true;
    enableAutomaticSearch = true;
    enableInteractiveSearch = true;
    supportsRss = true;
    supportsSearch = true;
    fields = [
      (field "baseUrl" "https://api.nzbgeek.info/")
      (field "apiPath" "/api")
      (field "apiKey" "")
    ]
    ++ indexerFields;
  };

  downloadClient = withPriority {
    name = "SABnzbd";
    enable = true;
    protocol = "usenet";
    implementation = "Sabnzbd";
    configContract = "SabnzbdSettings";
    removeCompletedDownloads = true;
    removeFailedDownloads = true;
    fields = [
      (field "host" "localhost")
      (field "port" sabnzbdPort)
      (field "apiKey" "")
      (field "category" sabCategory)
    ];
  };
in
pkgs.writeShellApplication {
  name = "${name}-config";
  runtimeInputs = with pkgs; [
    curl
    jq
    xmlstarlet
    sqlite
    helpers
    setConfigXml
  ];
  text = ''
    umask 077
    # Secrets reach curl, jq and the XML editor through files, never as
    # arguments, which any local user could read from /proc/<pid>/cmdline.
    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT
    printf 'X-Api-Key: %s\n' "$(read-secret ${name}/api-key)" > "$TMP/key"

    # api METHOD PATH [curl args...]
    api() {
      local method=$1 path=$2
      shift 2
      curl -sS --fail -X "$method" "http://localhost:${toString port}/api/v3/$path" \
        -H @"$TMP/key" -H "Content-Type: application/json" "$@"
    }

    # with_key BODY SECRET: BODY with its apiKey field set to the secret.
    with_key() {
      jq -n --argjson body "$1" --rawfile key "${secretsDir}/$2" \
        '$body | (.fields[] | select(.name == "apiKey")).value = ($key | rtrimstr("\n"))'
    }

    if [ -f "${dataDir}/${name}.db" ]; then
      sqlite3 "${dataDir}/${name}.db" 'DELETE FROM "Users";'
    fi
    xmlstarlet ed -L -u "/Config/AuthenticationMethod" -v "Forms" "${dataDir}/config.xml"
    set-config-xml "${dataDir}/config.xml" \
      Authentication/Username=${secretsDir}/admin/username \
      Authentication/Password=${secretsDir}/${name}/password \
      ApiKey=${secretsDir}/${name}/api-key
    if systemctl -q is-active ${name}.service; then
      systemctl restart ${name}.service
    fi

    echo "Waiting for ${name} to start..."
    wait-for-http "http://localhost:${toString port}/login"

    echo "Adding root folder..."
    api POST rootfolder -d ${json rootFolder} >/dev/null \
      || echo "Root folder may already exist"

    echo "Configuring media management settings..."
    api PUT config/mediamanagement/1 -d ${json mediaManagement} >/dev/null \
      || echo "Media management may already be configured"

    echo "Configuring NZBGeek..."
    with_key ${json indexer} nzbgeek/api-key | api POST indexer -d @- >/dev/null \
      || echo "NZBGeek may already be configured"

    echo "Configuring SABnzbd..."
    with_key ${json downloadClient} sabnzbd/api-key | api POST downloadclient -d @- >/dev/null \
      || echo "SABnzbd may already be configured"

    echo "Ensuring download cleanup is enabled..."
    SAB_CLIENT=$(api GET downloadclient | jq '.[0]')
    if [ "$(jq '.removeCompletedDownloads and .removeFailedDownloads' <<< "$SAB_CLIENT")" != true ]; then
      jq '.removeCompletedDownloads = true | .removeFailedDownloads = true' <<< "$SAB_CLIENT" \
        | api PUT "downloadclient/$(jq '.id' <<< "$SAB_CLIENT")" -d @- >/dev/null
    fi

    echo "Updating quality definitions..."
    api GET qualitydefinition \
      | jq -c --argjson settings ${json qualitySettings} \
        '.[] | select($settings[.quality.name]) | . * $settings[.quality.name]' \
      | while read -r def; do
          id=$(jq -r '.id' <<< "$def")
          echo "Updating $id..."
          api PUT "qualitydefinition/$id" -d "$def" >/dev/null || echo "Failed to update $id"
        done

    echo "Importing existing folders from disk..."
    UNMAPPED=$(api GET rootfolder | jq -r '.[0].unmappedFolders[].name')
    if [ -n "$UNMAPPED" ]; then
      while IFS= read -r folder; do
        term=$(sed ${lib.escapeShellArg searchTermSed} <<< "$folder")
        item=$(api GET "${lookupPath}?term=$(jq -rn --arg t "$term" '$t | @uri')" | jq '.[0]') || item=null
        if [ "$item" = null ] || [ -z "$item" ]; then
          echo "  Not found: $folder"
        elif jq --arg path "${rootFolder.path}/$folder" --argjson extra ${
          json {
            rootFolderPath = rootFolder.path;
            qualityProfileId = 1;
            monitored = true;
            inherit addOptions;
          }
        } \
          '. + {path: $path} + $extra' <<< "$item" \
          | api POST ${addPath} -d @- >/dev/null 2>&1; then
          echo "  Added: $folder"
        else
          echo "  Skipped: $folder (already exists or error)"
        fi
      done <<< "$UNMAPPED"
      echo "Triggering disk scan..."
      api POST command -d '{"name": "${rescanCommand}"}' >/dev/null
    else
      echo "  No unmapped folders found"
    fi

    echo "Applying quality profile..."
    api PUT qualityprofile/1 -d ${json qualityProfile} >/dev/null
  '';
}

{
  config,
  lib,
  pkgs,
  helpers,
  ...
}:

with config.my;

let
  mkArrConfig = import ./mkArrConfig.nix {
    inherit
      config
      lib
      pkgs
      helpers
      ;
  };
  configScript = mkArrConfig {
    name = "radarr";
    port = radarrPort;
    rootFolder = {
      name = "Movies";
      path = "${storageDir}/data/media/movies";
    };
    sabCategory = "movies";
    priority = 1;
    indexerFields = [
      {
        name = "categories";
        value = [
          2000
          2010
          2020
          2030
          2040
          2045
          2050
          2060
        ];
      }
    ];
    qualityProfile = (import ./qualityDefinitions.nix).radarrQualityProfile;
    lookupPath = "movie/lookup";
    addPath = "movie";
    addOptions.searchForMovie = false;
    rescanCommand = "RescanMovie";
    # "Title (2020)" -> "Title 2020"
    searchTermSed = "s/(//; s/)//";
  };
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
        serviceConfig = {
          User = "root";
          Type = "oneshot";
          ExecStart = lib.getExe configScript;
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

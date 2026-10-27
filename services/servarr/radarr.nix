{
  config,
  lib,
  pkgs,
  helpers,
  ...
}:

let
  inherit (config.spudbox)
    radarrPort
    secretsDir
    storageDir
    ;

  mkArrConfig = import ./mkArrConfig.nix {
    inherit
      config
      lib
      pkgs
      helpers
      ;
  };
  arr = mkArrConfig {
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
  # Imports downloads Radarr left in its queue as import-blocked/pending.
  # Runs as a DynamicUser; the API key arrives via LoadCredential and goes to
  # curl as a header file so it never appears on a command line. Candidates
  # Radarr rejects permanently (samples, wrong movie, ...) are skipped, and
  # each download is tried once: one stuck item was "imported" every 15
  # minutes for 53 days because the command was queued but never succeeded.
  autoImportScript = pkgs.writeShellApplication {
    name = "radarr-auto-import";
    runtimeInputs = with pkgs; [
      curl
      jq
      gnugrep
    ];
    text = ''
      umask 077
      printf 'X-Api-Key: %s\n' "$(tr -d '\n' < "$CREDENTIALS_DIRECTORY/radarr-api-key")" > "$RUNTIME_DIRECTORY/key"
      API="http://localhost:${toString radarrPort}/api/v3"
      TRIED="$STATE_DIRECTORY/tried" # downloadIds already attempted
      touch "$TRIED"
      api() { curl -sS --fail -H @"$RUNTIME_DIRECTORY/key" -H "Content-Type: application/json" "$@"; }

      # Radarr restarts on every switch; try again next time rather than alert.
      if ! QUEUE=$(api "$API/queue?includeUnknownMovieItems=true&pageSize=100"); then
        echo "Radarr not reachable; will retry"
        exit 0
      fi
      jq -c '.records[]
        | select((.trackedDownloadState == "importBlocked"
            or (.trackedDownloadState == "importPending" and .trackedDownloadStatus == "warning"))
          and .movieId != null and .downloadId != null)' <<< "$QUEUE" |
        while read -r item; do
          DOWNLOAD_ID=$(jq -r '.downloadId' <<< "$item")
          grep -qxF "$DOWNLOAD_ID" "$TRIED" && continue
          MOVIE_ID=$(jq '.movieId' <<< "$item")
          TITLE=$(jq -r '.title' <<< "$item")

          # Marked only once Radarr answers, so a stop mid-run (the backup) doesn't use up the try.
          CANDIDATES=$(api "$API/manualimport?downloadId=$DOWNLOAD_ID&movieId=$MOVIE_ID") || continue
          echo "$DOWNLOAD_ID" >> "$TRIED"
          FILES=$(jq -c --argjson mid "$MOVIE_ID" \
            '[.[] | select(all(.rejections[]?; .type != "permanent")) | . + {movieId: $mid}]' <<< "$CANDIDATES")
          if [ "$(jq length <<< "$FILES")" -eq 0 ]; then
            echo "  Skipped: $TITLE ($(jq -r '[.[].rejections[]?.reason] | unique | join("; ")' <<< "$CANDIDATES"))"
            continue
          fi
          if jq -c '{name: "ManualImport", importMode: "move", files: .}' <<< "$FILES" |
            api -o /dev/null -X POST "$API/command" -d @-; then
            echo "  Import queued: $TITLE"
          else
            echo "  Failed to queue: $TITLE"
          fi
        done
    '';
  };
in
lib.mkMerge [
  arr
  {
    systemd = {
      services = {
        radarr-auto-import = {
          description = "Auto-import blocked Radarr downloads";
          # No Requires=: the nightly backup stops Radarr, and that would kill a
          # run in progress (an alert) or let a run start Radarr mid-backup. The
          # script exits 0 when Radarr is down.
          after = [ "radarr.service" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe autoImportScript;
            DynamicUser = true;
            RuntimeDirectory = "radarr-auto-import";
            StateDirectory = "radarr-auto-import";
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
]

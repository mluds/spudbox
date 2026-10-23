{
  config,
  lib,
  pkgs,
  ...
}:

# Weekly disk rescan of the Sonarr and Radarr libraries, which notices files
# added, renamed or deleted outside the apps. Their own 12-24 h metadata
# refresh no longer rescans (rescanAfterRefresh = "afterManual" in
# mkArrConfig.nix), so the HDD isn't read for it once or twice a day.
# Sunday 02:45 is right after the nightly backup (02:30), which has already
# spun the drive up and restarted the apps.
let
  inherit (config.my) secretsDir sonarrPort radarrPort;

  rescanScript = pkgs.writeShellApplication {
    name = "arr-rescan";
    runtimeInputs = [ pkgs.curl ];
    text = ''
      umask 077
      # rescan NAME PORT COMMAND: queue a whole-library rescan; the API key
      # goes to curl as a header file, never on its command line.
      rescan() {
        printf 'X-Api-Key: %s\n' "$(tr -d '\n' < "$CREDENTIALS_DIRECTORY/$1-api-key")" > "$RUNTIME_DIRECTORY/key"
        curl -sS --fail --retry 5 --retry-delay 30 --retry-all-errors -o /dev/null \
          -H @"$RUNTIME_DIRECTORY/key" -H "Content-Type: application/json" \
          -d "{\"name\": \"$3\"}" "http://localhost:$2/api/v3/command"
        echo "$1: $3 queued"
      }
      rescan sonarr ${toString sonarrPort} RescanSeries
      rescan radarr ${toString radarrPort} RescanMovie
    '';
  };
in
{
  systemd.services.arr-rescan = {
    description = "Weekly Sonarr/Radarr library rescan";
    after = [
      "sonarr.service"
      "radarr.service"
    ];
    onFailure = [ "notify-failure@%n.service" ];
    serviceConfig = import ../hardening.nix // {
      Type = "oneshot";
      DynamicUser = true;
      RuntimeDirectory = "arr-rescan";
      LoadCredential = [
        "sonarr-api-key:${secretsDir}/sonarr/api-key"
        "radarr-api-key:${secretsDir}/radarr/api-key"
      ];
      ExecStart = lib.getExe rescanScript;
    };
  };

  systemd.timers.arr-rescan = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun 02:45";
      Persistent = true;
    };
  };
}

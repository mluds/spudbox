{
  config,
  lib,
  pkgs,
  ...
}:

with config.my;

# Pushover alert when a unit fails, so a broken nightly backup or *-config
# run doesn't go unnoticed until someone runs test.sh. Units opt in with
#   onFailure = [ "notify-failure@%n.service" ];
# (media-fixup.nix does); the ones below are attached here. The message is
# the unit name plus the tail of its journal.
let
  notifyScript = pkgs.writeShellApplication {
    name = "notify-failure";
    runtimeInputs = with pkgs; [
      curl
      systemd
      coreutils
    ];
    text = ''
      UNIT=$1
      umask 077
      # Keys go to curl in a file, never on its command line.
      printf 'token=%s&user=%s' \
        "$(tr -d '\n' < "$CREDENTIALS_DIRECTORY/pushover-app-token")" \
        "$(tr -d '\n' < "$CREDENTIALS_DIRECTORY/pushover-user-key")" \
        > "$RUNTIME_DIRECTORY/auth"
      # Pushover caps messages at 1024 characters; the newest lines matter most.
      journalctl -u "$UNIT" -n 15 -o cat --no-pager 2>&1 | tail -c 900 > "$RUNTIME_DIRECTORY/log" || true
      # Pushover rejects an empty message (HTTP 400)
      [ -s "$RUNTIME_DIRECTORY/log" ] || echo "No log lines; see journalctl -u $UNIT" > "$RUNTIME_DIRECTORY/log"
      curl -sS --fail-with-body --max-time 30 -o /dev/stderr https://api.pushover.net/1/messages.json \
        -d @"$RUNTIME_DIRECTORY/auth" \
        --data-urlencode "title=spudbox: $UNIT failed" \
        --data-urlencode "message@$RUNTIME_DIRECTORY/log"
    '';
  };

  # Oneshots and timers whose failure nobody would otherwise see.
  watched = [
    "create-dirs"
    "restic-backups-local"
    "restic-backups-r2"
    "check-drive-status"
    "sabnzbd-resume"
    "radarr-auto-import"
    "caddy-config"
    "plex-config"
    "tautulli-config"
    "sonarr-config"
    "radarr-config"
    "prowlarr-config"
    "bazarr-config"
    "jellyseerr-config"
    "audiobookshelf-access"
    "homebridge-config"
  ];
in
{
  systemd.services = {
    "notify-failure@" = {
      description = "Pushover alert: %i failed";
      serviceConfig = import ./hardening.nix // {
        Type = "oneshot";
        ExecStart = "${lib.getExe notifyScript} %i";
        DynamicUser = true;
        SupplementaryGroups = [ "systemd-journal" ]; # read the failed unit's log
        RuntimeDirectory = "notify-failure/%i";
        LoadCredential = [
          "pushover-app-token:${secretsDir}/pushover/app-token"
          "pushover-user-key:${secretsDir}/pushover/user-key"
        ];
      };
    };
  }
  // lib.genAttrs watched (_: {
    onFailure = [ "notify-failure@%n.service" ];
  });
}

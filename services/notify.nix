{
  config,
  lib,
  pkgs,
  ...
}:

# The oneshots and timer jobs nobody watches:
#  - a Pushover alert when one fails, so a broken nightly backup or *-config
#    run doesn't go unnoticed until someone runs test.sh. Units opt in with
#      onFailure = [ "notify-failure@%n.service" ];
#    (media-fixup.nix does); the ones below are attached here. The message is
#    the unit name plus the tail of its journal.
#  - the setup oneshots stay active after they succeed (RemainAfterExit), so a
#    switch only re-runs those whose unit changed, instead of every one of
#    them restarting Sonarr, Radarr, Bazarr and Tautulli and rescanning the
#    libraries on each deploy. They still run on every boot; deploy.sh
#    restarts them all when a secret changed.
let
  inherit (config.my) secretsDir;

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
      curl -sS --fail-with-body --max-time 30 https://api.pushover.net/1/messages.json \
        -d @"$RUNTIME_DIRECTORY/auth" \
        --data-urlencode "title=spudbox: $UNIT failed" \
        --data-urlencode "message@$RUNTIME_DIRECTORY/log"
    '';
  };

  # Configure an app from Nix and secrets, once per boot or change. Their
  # Type=oneshot is set here, with RemainAfterExit.
  setupUnits = [
    "create-dirs"
    "caddy-config"
    "plex-config"
    "tautulli-config"
    "sonarr-config"
    "radarr-config"
    "bazarr-config"
    "jellyseerr-config"
    "audiobookshelf-access"
    "homebridge-config"
  ];

  # Run by timers.
  jobUnits = [
    "restic-backups-local"
    "restic-backups-r2"
    "check-drive-status"
    "sabnzbd-resume"
    "radarr-auto-import"
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
  // lib.genAttrs jobUnits (_: {
    onFailure = [ "notify-failure@%n.service" ];
  })
  // lib.genAttrs setupUnits (_: {
    onFailure = [ "notify-failure@%n.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  });

  # For test.sh (none may be failed) and deploy.sh (restarts SETUP_UNITS
  # after a secret changed).
  environment.etc."spudbox/env".text = lib.concatLines [
    (lib.toShellVar "ALERT_UNITS" (setupUnits ++ jobUnits))
    (lib.toShellVar "SETUP_UNITS" setupUnits)
  ];
}

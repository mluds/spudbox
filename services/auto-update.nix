{
  config,
  lib,
  pkgs,
  ...
}:

# autoUpdate: every night, deploy the instance repository's newest commit on
# its branch, as `./deploy.sh` would (no secrets: those stay as deployed),
# then run spudbox-test and roll back if it fails. With daily GitHub Actions
# bumping Plex in the module (update-plex.yml) and the module in the
# instance's flake.lock (template/.github/workflows/update-lock.yml), the
# server keeps itself current.
#
# It only moves forward along the branch: if the running system was
# deployed by hand from uncommitted changes, or from a commit that isn't on
# the branch, it leaves it alone (and fails, so an alert goes out, once
# that has lasted three days). A commit that failed its tests isn't retried.
let
  cfg = config.spudbox.autoUpdate;
  inherit (config.spudbox) secretsDir plexPort;

  script = pkgs.writeShellApplication {
    name = "spudbox-auto-update";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      jq
      gitMinimal
      gnutar
      openssh
      config.nix.package
      config.system.build.nixos-rebuild
    ];
    text = ''
      state=$STATE_DIRECTORY
      repo=$state/repo
      tree=$state/tree
      export GIT_SSH_COMMAND="ssh -i ${secretsDir}/auto-update/deploy-key -o IdentitiesOnly=yes -o BatchMode=yes"

      # skip REASON: leave the running system alone; after three days of
      # that, fail (an alert) so auto-updates don't stop unnoticed.
      skip() {
        echo "$1"
        [ -s "$state/skipped-since" ] || date +%s > "$state/skipped-since"
        if [ $(($(date +%s) - $(cat "$state/skipped-since"))) -gt $((3 * 86400)) ]; then
          echo "Auto-updates have been paused like this since $(date -d "@$(cat "$state/skipped-since")")."
          exit 1
        fi
        exit 0
      }

      [ -d "$repo" ] || git init -q "$repo"
      git -C "$repo" fetch -q --no-tags ${lib.escapeShellArg cfg.repository} ${lib.escapeShellArg cfg.branch}
      new=$(git -C "$repo" rev-parse FETCH_HEAD)
      # shellcheck disable=SC1091
      running=$(source /run/current-system/etc/spudbox/env && echo "$REVISION")

      case $running in
        *-dirty) skip "Running $running, deployed by hand with uncommitted changes; not replacing it." ;;
      esac
      if ! running_full=$(git -C "$repo" rev-parse -q --verify "$running^{commit}") ||
        ! git -C "$repo" merge-base --is-ancestor "$running_full" "$new"; then
        skip "Running $running, which isn't on ${cfg.branch}; not replacing it."
      fi
      rm -f "$state/skipped-since"
      if [ "$running_full" = "$new" ]; then
        echo "Up to date: $running."
        exit 0
      fi
      if [ "$(cat "$state/failed" 2>/dev/null)" = "$new" ]; then
        echo "''${new:0:7} already failed its tests; waiting for a newer commit."
        exit 0
      fi
      echo "Updating $running -> ''${new:0:7}:"
      git -C "$repo" log --format='  %h %s' "$running_full..$new"

      # Don't restart Plex under someone watching: wait up to 3 hours.
      umask 077
      printf 'X-Plex-Token: %s\n' "$(cat ${secretsDir}/plex/token 2>/dev/null)" > "$RUNTIME_DIRECTORY/plex-header"
      for _ in $(seq 18); do
        streams=$(curl -fs --max-time 10 -H @"$RUNTIME_DIRECTORY/plex-header" -H 'Accept: application/json' \
          http://localhost:${toString plexPort}/status/sessions | jq '.MediaContainer.size // 0') || streams=0
        [ "$streams" -eq 0 ] && break
        echo "Plex is streaming to $streams; checking again in 10 minutes."
        sleep 600
      done

      # The tree as ./deploy.sh copies it: no .git, no secrets (the flake
      # isn't a git checkout, so all of it goes into the world-readable store).
      rm -rf "$tree"
      mkdir -p "$tree"
      git -C "$repo" archive "$new" -- . ':(exclude)secrets' | tar -x -C "$tree"
      git -C "$repo" rev-parse --short "$new" > "$tree/.revision"

      prev=$(readlink -f /nix/var/nix/profiles/system)
      rollback() {
        echo "Rolling back to $prev."
        nix-env -p /nix/var/nix/profiles/system --set "$prev"
        "$prev/bin/switch-to-configuration" switch || true
        echo "$new" > "$state/failed"
      }

      # Exit 4: switched, but some units failed to start; the tests decide.
      rc=0
      nixos-rebuild switch --flake "path:$tree#default" || rc=$?
      if [ "$rc" -ne 0 ] && [ "$rc" -ne 4 ]; then
        if [ "$(readlink -f /nix/var/nix/profiles/system)" != "$prev" ]; then rollback; fi
        echo "nixos-rebuild failed (exit $rc)."
        exit 1
      fi

      # As ./deploy.sh: wait for the apps (a switch can restart them), then
      # test, once more after a pause if the apps were still settling.
      # shellcheck disable=SC1091
      source /etc/spudbox/env
      for path in "$TAUTULLI_PORT" "$BAZARR_PORT" "$SONARR_PORT" "$RADARR_PORT" "$JELLYSEERR_PORT" "$SABNZBD_PORT" "$PLEX_PORT/identity"; do
        for _ in $(seq 60); do
          code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://localhost:$path") || true
          [ "$code" != "000" ] && break
          sleep 5
        done
      done
      if /run/current-system/sw/bin/spudbox-test > "$RUNTIME_DIRECTORY/test.log" 2>&1 ||
        { sleep 120 && /run/current-system/sw/bin/spudbox-test > "$RUNTIME_DIRECTORY/test.log" 2>&1; }; then
        echo "Updated to ''${new:0:7}; $(tail -n 1 "$RUNTIME_DIRECTORY/test.log" | sed 's/\x1b\[[0-9;]*m//g' | xargs)."
        exit 0
      fi
      grep -a FAIL "$RUNTIME_DIRECTORY/test.log" | sed 's/\x1b\[[0-9;]*m//g' || true
      rollback
      echo "spudbox-test failed on ''${new:0:7}."
      exit 1
    '';
  };
in
lib.mkIf cfg.enable {
  # The deploy key reaches the repository over SSH; GitHub's host key
  # (https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints).
  programs.ssh.knownHosts."github.com".publicKey =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";

  # For test.sh.
  environment.etc."spudbox/env".text = lib.concatLines [
    (lib.toShellVar "AUTO_UPDATE_REPOSITORY" cfg.repository)
    (lib.toShellVar "AUTO_UPDATE_BRANCH" cfg.branch)
  ];

  systemd = {
    services.spudbox-auto-update = {
      description = "Deploy the newest spudbox instance commit";
      # A switch must not restart the unit that's running the switch.
      restartIfChanged = false;
      # The nightly backup stops the apps at 02:30.
      after = [
        "network-online.target"
        "restic-backups-local.service"
        "restic-backups-r2.service"
      ];
      wants = [ "network-online.target" ];
      environment.HOME = "/root";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe script;
        StateDirectory = "spudbox-auto-update";
        StateDirectoryMode = "0700";
        RuntimeDirectory = "spudbox-auto-update";
      };
    };

    timers.spudbox-auto-update = {
      wantedBy = [ "timers.target" ];
      timerConfig.OnCalendar = cfg.time;
    };
  };
}

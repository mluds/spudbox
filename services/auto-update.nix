{
  config,
  lib,
  pkgs,
  ...
}:

# autoUpdate: every night, deploy the instance repository's newest commit on
# its branch, as `./deploy.sh` would (no secrets: those stay as deployed),
# then run spudbox-test and roll back if it fails. With daily GitHub Actions
# updating the module's pins (update.yml) and the module in the
# instance's flake.lock (template/.github/workflows/update-lock.yml), the
# server keeps itself current.
#
# It only moves forward along the branch: if the running system was
# deployed by hand from uncommitted changes, or from a commit that isn't on
# the branch, it leaves it alone (and fails, so an alert goes out, once
# that has lasted three days). A commit that failed its tests isn't retried.
#
# autoUpdate.reboot: when the running kernel (or its modules or initrd) is
# older than the installed one, it then reboots, once Plex is idle. With
# systemd-boot the new system is booted once, with the system that was
# running left as the default entry, so a kernel that panics (panic=10) or
# hangs (the hardware watchdog) comes back up on the old one. After the
# boot, spudbox-reboot-check runs spudbox-test, makes the newest entry the
# default again, and alerts if the tests fail or the server came back on the
# old system. A kernel that didn't boot isn't tried again by itself.
let
  cfg = config.spudbox.autoUpdate;
  inherit (config.spudbox) secretsDir plexPort;
  systemdBoot = config.boot.loader.systemd-boot.enable;

  # Only the nightly run reboots, and only with autoUpdate.reboot.
  rebootIfDue = lib.optionalString cfg.reboot "reboot_if_due";

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
      config.systemd.package
      config.system.build.nixos-rebuild
    ];
    text = ''
      state=$STATE_DIRECTORY
      repo=$state/repo
      tree=$state/tree
      export GIT_SSH_COMMAND="ssh -i ${secretsDir}/auto-update/deploy-key -o IdentitiesOnly=yes -o BatchMode=yes"
      umask 077
      printf 'X-Plex-Token: %s\n' "$(cat ${secretsDir}/plex/token 2>/dev/null)" > "$RUNTIME_DIRECTORY/plex-header"

      # wait_for_streams: until nobody is watching Plex, for up to 3 hours
      # (fails if someone still is).
      wait_for_streams() {
        local streams
        for _ in $(seq 18); do
          streams=$(curl -fs --max-time 10 -H @"$RUNTIME_DIRECTORY/plex-header" -H 'Accept: application/json' \
            http://localhost:${toString plexPort}/status/sessions | jq '.MediaContainer.size // 0') || streams=0
          [ "$streams" -eq 0 ] && return 0
          echo "Plex is streaming to $streams; checking again in 10 minutes."
          sleep 600
        done
        return 1
      }

      # As ./deploy.sh: wait for the apps (a switch or boot starts them).
      wait_for_apps() {
        local path code
        # shellcheck disable=SC1091
        source /etc/spudbox/env
        for path in "$TAUTULLI_PORT" "$BAZARR_PORT" "$SONARR_PORT" "$RADARR_PORT" "$JELLYSEERR_PORT" "$SABNZBD_PORT" "$PLEX_PORT/identity"; do
          for _ in $(seq 60); do
            code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://localhost:$path") || true
            [ "$code" != "000" ] && break
            sleep 5
          done
        done
      }
      # spudbox-test needs a login PATH: sudo (a setuid wrapper), curl, jq, ...
      run_tests() {
        PATH=/run/wrappers/bin:/run/current-system/sw/bin:$PATH \
          spudbox-test > "$RUNTIME_DIRECTORY/test.log" 2>&1
      }
      test_summary() { tail -n 1 "$RUNTIME_DIRECTORY/test.log" | sed 's/\x1b\[[0-9;]*m//g' | xargs; }
      test_failures() { grep -a FAIL "$RUNTIME_DIRECTORY/test.log" | sed 's/\x1b\[[0-9;]*m//g' || true; }

      # What only a reboot brings in.
      boot_parts() { readlink -f "$1/kernel" "$1/kernel-modules" "$1/initrd"; }
      linux_version() { ls "$1/kernel-modules/lib/modules"; }
      # The newest generation of the system profile that is system $1, if any.
      generation_of() {
        local link n found=""
        for link in /nix/var/nix/profiles/system-*-link; do
          [ "$(readlink -f "$link")" = "$1" ] || continue
          n=''${link##*/system-}
          n=''${n%-link}
          if [ -z "$found" ] || [ "$n" -gt "$found" ]; then found=$n; fi
        done
        echo "$found"
      }
      has_boot_entry() {
        [ -n "$1" ] && bootctl list --json=short | jq -e --arg id "nixos-generation-$1.conf" 'any(.[]; .id == $id)' > /dev/null
      }

      # Reboot onto the current system if its kernel isn't the running one.
      reboot_if_due() {
        local target booted kernel version new_gen old_gen
        target=$(readlink -f /run/current-system)
        booted=$(readlink -f /run/booted-system)
        [ "$(boot_parts "$booted")" != "$(boot_parts "$target")" ] || return 0
        kernel=$(readlink -f "$target/kernel")
        version=$(linux_version "$target")
        if [ "$(cat "$state/reboot-failed" 2>/dev/null)" = "$kernel" ]; then
          echo "Not rebooting onto Linux $version: the last reboot onto it came back on the old system. Reboot by hand to try it again."
          return 0
        fi
        if ! wait_for_streams; then
          echo "Plex is still streaming; rebooting onto Linux $version tomorrow night instead."
          return 0
        fi
        printf '%s\n' "$target" "$booted" > "$state/reboot"
      ${lib.optionalString systemdBoot ''
        # Boot the new system once; until it passes, the old one stays the default.
        new_gen=$(generation_of "$target")
        old_gen=$(generation_of "$booted")
        if has_boot_entry "$new_gen" && has_boot_entry "$old_gen"; then
          bootctl set-default "nixos-generation-$old_gen.conf"
          bootctl set-oneshot "nixos-generation-$new_gen.conf"
        else
          echo "No boot entry for generation ''${old_gen:-?} (running) or ''${new_gen:-?} (new): if Linux $version doesn't boot, the server won't come back by itself."
        fi
      ''}
        echo "Rebooting onto Linux $version (running $(uname -r)); spudbox-reboot-check tests it after the boot."
        systemctl --no-block reboot
        exit 0
      }

      # After a reboot by reboot_if_due (spudbox-reboot-check).
      after_reboot() {
        local target from booted version
        [ -s "$state/reboot" ] || exit 0
        { read -r target; read -r from; } < "$state/reboot"
        rm "$state/reboot"
      ${lib.optionalString systemdBoot ''
        # The newest generation is the default entry again.
        bootctl set-default "" || echo "Couldn't reset the default boot entry (bootctl set-default \"\")."
      ''}
        booted=$(readlink -f /run/booted-system)
        version=$(linux_version "$target")
        if [ "$booted" != "$target" ]; then
          if [ "$booted" != "$from" ]; then
            echo "Booted $booted, not the system the reboot was for ($target); not checking it."
            exit 0
          fi
          readlink -f "$target/kernel" > "$state/reboot-failed"
          echo "Rebooted onto Linux $version, but the server came back on the old system ($(uname -r)): the new kernel didn't boot."
          echo "It won't reboot onto it again by itself; a reboot by hand tries it again (it's the default entry)."
          exit 1
        fi
        wait_for_apps
        if run_tests || { sleep 120 && run_tests; } || { sleep 120 && run_tests; }; then
          echo "Rebooted onto Linux $version; $(test_summary)."
          exit 0
        fi
        test_failures
        echo "spudbox-test failed after rebooting onto Linux $version. The previous system is in the boot menu."
        exit 1
      }

      if [ "''${1:-}" = --after-reboot ]; then after_reboot; fi

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
        ${rebootIfDue}
        exit 0
      fi
      if [ "$(cat "$state/failed" 2>/dev/null)" = "$new" ]; then
        echo "''${new:0:7} already failed its tests; waiting for a newer commit."
        ${rebootIfDue}
        exit 0
      fi
      echo "Updating $running -> ''${new:0:7}:"
      git -C "$repo" log --format='  %h %s' "$running_full..$new"

      # Don't restart Plex under someone watching (after 3 hours, go ahead).
      wait_for_streams || true

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

      # Test, once more after a pause if the apps were still settling.
      wait_for_apps
      if run_tests || { sleep 120 && run_tests; }; then
        echo "Updated to ''${new:0:7}; $(test_summary)."
        ${rebootIfDue}
        exit 0
      fi
      test_failures
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

  # With reboot: a kernel that panics or hangs reboots (onto the old system,
  # see above) instead of waiting for someone to power-cycle it. The
  # watchdog only works where the board has one (/dev/watchdog).
  boot.kernelParams = lib.mkIf cfg.reboot [ "panic=10" ];

  systemd = {
    settings.Manager.RuntimeWatchdogSec = lib.mkIf cfg.reboot (lib.mkDefault "30s");

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

    # Not in notify.nix's ALERT_UNITS: spudbox-test fails on those when
    # they've failed, and that would roll back every update after one bad boot.
    services.spudbox-reboot-check = lib.mkIf cfg.reboot {
      description = "Test the server after spudbox-auto-update rebooted it";
      wantedBy = [ "multi-user.target" ];
      after = [ "multi-user.target" ];
      unitConfig.ConditionPathExists = "/var/lib/spudbox-auto-update/reboot";
      restartIfChanged = false;
      inherit (config.spudbox) onFailure;
      environment.HOME = "/root";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe script} --after-reboot";
        StateDirectory = "spudbox-auto-update";
        StateDirectoryMode = "0700";
        RuntimeDirectory = "spudbox-reboot-check";
      };
    };

    timers.spudbox-auto-update = {
      wantedBy = [ "timers.target" ];
      timerConfig.OnCalendar = cfg.time;
    };
  };
}

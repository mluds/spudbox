{
  config,
  lib,
  pkgs,
  ...
}:

# Nightly restic backup of /var/lib (app configs + databases; media is not
# backed up, it's re-downloadable and the *arr DBs record what we had).
#
#   restic-backups-local  02:30, services stopped, -> ${backupDir}/restic (HDD)
#   restic-backups-r2     on local success, `restic copy` -> an S3 bucket such
#                         as Cloudflare R2 (spudbox.offsiteBackup)
#
# Both repos share secrets/restic/password (generated on first boot unless
# supplied) — keep a copy in a password manager; without it the backups can't
# be decrypted. `sudo spudbox-restore` puts a snapshot's app state back.
let
  cfg = config.spudbox;
  inherit (cfg) backupDir secretsDir;
  localRepo = "${backupDir}/restic";
  passwordFile = "${secretsDir}/restic/password";
  restic = "${pkgs.restic}/bin/restic";

  # Stopped for a consistent copy of their SQLite DBs.
  stoppedServices = [
    "homepage-dashboard"
    "sonarr"
    "radarr"
    "bazarr"
    "seerr"
    "plex"
    "transmission"
    "sabnzbd"
    "tautulli"
    "audiobookshelf"
  ];

  pruneOpts = [
    "--keep-daily 7"
    "--keep-weekly 4"
    "--keep-monthly 12"
  ];
  # What spudbox-restore puts back: each app's state dir under /var/lib, and
  # the secrets (the restored apps match the secrets they were backed up
  # with, e.g. Audiobookshelf's root password).
  # dir under /var/lib -> the service that runs as its owner.
  appStateDirs = {
    plex = "plex";
    plexpy = "tautulli";
    sonarr = "sonarr";
    radarr = "radarr";
    bazarr = "bazarr";
    jellyseerr = "seerr";
    sabnzbd = "sabnzbd";
    transmission = "transmission";
    audiobookshelf = "audiobookshelf";
  }
  // lib.optionalAttrs cfg.homebridge.enable { homebridge = "homebridge"; }
  // lib.optionalAttrs cfg.mediaFixup.enable { media-fixup = "media-fixup"; };
  stateDirNames = lib.attrNames appStateDirs;

  restoreScript = pkgs.writeShellApplication {
    name = "spudbox-restore";
    runtimeInputs = with pkgs; [
      coreutils
      rsync
      systemd
    ];
    text = ''
      usage() {
        echo "usage: spudbox-restore [--from local|r2] [--yes] [SNAPSHOT (default: latest)]" >&2
        exit 1
      }
      if [ "$(id -u)" -ne 0 ]; then
        exec sudo "$0" "$@"
      fi
      repo=local yes=false snapshot=latest
      while [ $# -gt 0 ]; do
        case $1 in
          --from) repo=''${2:-}; shift 2 ;;
          --yes) yes=true; shift ;;
          -*) usage ;;
          *) snapshot=$1; shift ;;
        esac
      done
      case $repo in local ${lib.optionalString cfg.offsiteBackup.enable "| r2"}) ;; *) usage ;; esac
      restic=/run/current-system/sw/bin/restic-$repo

      echo "Snapshot to restore (from the $repo repository):"
      if [ "$snapshot" = latest ]; then
        "$restic" snapshots --latest 1 --compact
      else
        "$restic" snapshots --compact "$snapshot"
      fi
      echo
      echo "This REPLACES the state of: ${toString stateDirNames}"
      echo "and puts back the snapshot's secrets. The apps are stopped meanwhile."
      if [ "$yes" != true ]; then
        read -rp "Type 'restore' to go ahead: " answer < /dev/tty
        [ "$answer" = restore ] || { echo "Nothing changed."; exit 1; }
      fi

      staging=/var/lib/spudbox-restore
      rm -rf "$staging"
      install -d -m 700 "$staging"
      trap 'rm -rf "$staging"' EXIT

      echo "Stopping the apps..."
      systemctl stop ${toString stoppedServices}
      # Start them again even if the restore fails part-way.
      trap 'rm -rf "$staging"; systemctl start ${toString stoppedServices}' EXIT

      includes=(--include ${secretsDir})
      for dir in ${toString stateDirNames}; do includes+=(--include "/var/lib/$dir"); done
      "$restic" restore "$snapshot" --target "$staging" "''${includes[@]}"

      # Each dir goes back owned by the user and group its service runs as
      # now (user IDs can differ after a reinstall, and the top of a state
      # dir can belong to root while the app's files don't). --delete drops
      # files the snapshot doesn't have, such as a fresh install's database
      # write-ahead logs.
      while read -r dir unit; do
        [ -d "$staging/var/lib/$dir" ] || { echo "Not in the snapshot: /var/lib/$dir"; continue; }
        user=$(systemctl show -p User --value "$unit.service")
        user=''${user:-root}
        group=$(systemctl show -p Group --value "$unit.service")
        group=''${group:-$(id -gn "$user")}
        owner=$user:$group
        echo "Restoring /var/lib/$dir ($owner)..."
        mkdir -p "/var/lib/$dir"
        rsync -a --delete --chown="$owner" "$staging/var/lib/$dir/" "/var/lib/$dir/"
      done <<'EOF'
      ${lib.concatLines (lib.mapAttrsToList (dir: unit: "${dir} ${unit}") appStateDirs)}EOF
      # Secrets: added and overwritten, never deleted (newer ones stay).
      if [ -d "$staging${secretsDir}" ]; then
        echo "Restoring ${secretsDir}..."
        rsync -a --numeric-ids --chown=root:root --chmod=D700,F600 "$staging${secretsDir}/" "${secretsDir}/"
      fi

      echo "Starting the apps and re-running the setup units..."
      trap 'rm -rf "$staging"' EXIT
      # One app that doesn't start (say homepage, before Plex has a token)
      # mustn't stop the rest of the restore.
      if ! systemctl start ${toString stoppedServices}; then
        echo "Some apps didn't start (systemctl --failed)."
      fi
      # shellcheck source=/dev/null
      source /etc/spudbox/env
      if ! systemctl restart "''${SETUP_UNITS[@]/%/.service}"; then
        echo "Some setup units failed (systemctl --failed); the restore itself is done."
      fi
      echo "Restored. Check with spudbox-test."
    '';
  };
in
{
  environment.systemPackages = [
    pkgs.restic
    restoreScript
  ];

  services.restic.backups = {
    local = {
      repository = localRepo;
      inherit passwordFile pruneOpts;
      initialize = true;
      createWrapper = true;
      paths = [ "/var/lib" ];
      # Things each app rebuilds or re-downloads by itself: caches, poster
      # art, logs, and the apps' own backup copies (~1 GB, mostly Radarr's
      # MediaCover). Plex's Metadata and Media stay: slow to regenerate.
      exclude = [
        "/var/lib/docker"
        "/var/lib/systemd/coredump"
        "/var/lib/plex/Plex Media Server/Cache"
        "/var/lib/plex/Plex Media Server/Logs"
        "/var/lib/plex/Plex Media Server/Crash Reports"
        "/var/lib/plex/Plex Media Server/Plug-in Support/Caches"
        "/var/lib/radarr/.config/Radarr/MediaCover"
        "/var/lib/radarr/.config/Radarr/logs"
        "/var/lib/radarr/.config/Radarr/Backups"
        "/var/lib/sonarr/.config/NzbDrone/MediaCover"
        "/var/lib/sonarr/.config/NzbDrone/logs"
        "/var/lib/sonarr/.config/NzbDrone/Backups"
        "/var/lib/plexpy/logs"
        "/var/lib/plexpy/backups"
        "/var/lib/bazarr/log"
        "/var/lib/bazarr/backup"
      ];
      backupPrepareCommand = ''
        ${pkgs.coreutils}/bin/mkdir -p ${backupDir}
        ${pkgs.coreutils}/bin/chmod 700 ${backupDir}
        ${pkgs.systemd}/bin/systemctl stop ${toString stoppedServices}
      '';
      # Runs as ExecStopPost, so services come back even if the backup fails.
      backupCleanupCommand = ''
        ${pkgs.systemd}/bin/systemctl start ${toString stoppedServices}
      '';
      timerConfig = {
        OnCalendar = "*-*-* 02:30:00";
        Persistent = true;
      };
    };
  }
  // lib.optionalAttrs cfg.offsiteBackup.enable {
    # No paths: the module's "prepare" hook copies the local snapshots up,
    # then the unit prunes and checks the R2 repo. Services stay up.
    r2 = {
      inherit (cfg.offsiteBackup) repository;
      inherit passwordFile pruneOpts;
      environmentFile = "${secretsDir}/r2/s3-credentials.env";
      createWrapper = true;
      runCheck = true;
      timerConfig = null;
      backupPrepareCommand = ''
        if ! ${restic} cat config >/dev/null 2>&1; then
          ${restic} init --copy-chunker-params \
            --from-repo ${localRepo} --from-password-file ${passwordFile}
        fi
        ${restic} copy --from-repo ${localRepo} --from-password-file ${passwordFile}
      '';
    };
  };

  systemd.services = {
    restic-backups-local = {
      # /mnt/storage is mounted nofail; never back up onto the NVMe by accident.
      unitConfig.RequiresMountsFor = [ backupDir ];
      onSuccess = lib.optional cfg.offsiteBackup.enable "restic-backups-r2.service";
    };
    restic-backups-r2 = lib.mkIf cfg.offsiteBackup.enable {
      unitConfig.RequiresMountsFor = [ backupDir ];
    };
  };
}

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
#   restic-backups-r2     on local success, `restic copy` -> Cloudflare R2
#
# Both repos share secrets/restic/password — keep it in the password manager
# too; without it the backups can't be decrypted. Restores: see CLAUDE.md.
let
  inherit (config.my) backupDir secretsDir;
  localRepo = "${backupDir}/restic";
  passwordFile = "${secretsDir}/restic/password";
  r2Repo = "s3:https://8b37a4bbd0f5e7e52c56476fd07bc4f8.r2.cloudflarestorage.com/spudbox-backups";
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
  ]
  # A unit that doesn't exist would make `systemctl stop` fail the backup.
  ++ lib.optional config.my.prowlarr.enable "prowlarr";

  pruneOpts = [
    "--keep-daily 7"
    "--keep-weekly 4"
    "--keep-monthly 12"
  ];
in
{
  environment.systemPackages = [ pkgs.restic ];

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

    # No paths: the module's "prepare" hook copies the local snapshots up,
    # then the unit prunes and checks the R2 repo. Services stay up.
    r2 = {
      repository = r2Repo;
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
      onSuccess = [ "restic-backups-r2.service" ];
    };
    restic-backups-r2.unitConfig.RequiresMountsFor = [ backupDir ];
  };
}

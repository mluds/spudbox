{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [ autorestic restic ];
  system.activationScripts.autorestic-config = ''
    mkdir -p /var/lib/autorestic
    cat > /var/lib/autorestic/config.yml <<'EOF'
    version: 2

    locations:
      varlib:
        from: /var/lib
        to: local-backup
        options:
          forget:
            keep-daily: 7
            keep-weekly: 4
            keep-monthly: 12
            forgetoption: prune
        hooks:
          before:
            - systemctl stop homepage-dashboard
            - systemctl stop sonarr
            - systemctl stop radarr
            - systemctl stop bazarr
            - systemctl stop prowlarr
            - systemctl stop jellyseerr
            - systemctl stop plex
            - systemctl stop transmission
            - systemctl stop sabnzbd
            - systemctl stop caddy
            - systemctl stop tautulli
            - systemctl stop audiobookshelf
            - systemctl stop ttyd
          after:
            - systemctl start homepage-dashboard
            - systemctl start sonarr
            - systemctl start radarr
            - systemctl start bazarr
            - systemctl start prowlarr
            - systemctl start jellyseerr
            - systemctl start plex
            - systemctl start transmission
            - systemctl start sabnzbd
            - systemctl start caddy
            - systemctl start tautulli
            - systemctl start audiobookshelf
            - systemctl start ttyd

    backends:
      local-backup:
        type: local
        path: /mnt/backup
    EOF
    chmod 600 /var/lib/autorestic/config.yml
  '';

  systemd.services.autorestic-backup = {
    description = "Autorestic backup job";
    path = with pkgs; [ bash restic ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStartPre = "${pkgs.autorestic}/bin/autorestic -c /var/lib/autorestic/config.yml --ci check";
      ExecStart = "${pkgs.autorestic}/bin/autorestic -c /var/lib/autorestic/config.yml --ci backup -a";
      TimeoutStopSec = "infinity";
    };
    after = [ "network.target" ];
    requires = [ "network.target" ];
    preStart = ''
      mkdir -p /mnt/backup
      chmod 700 /mnt/backup
    '';
  };

  systemd.timers.autorestic-backup = {
    description = "Timer for autorestic backups";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 02:30:00";
      Persistent = true;
      Unit = "autorestic-backup.service";
    };
  };
}

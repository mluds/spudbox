{ config, pkgs, ... }:

with config.my;

let
  autoresticCustom = pkgs.stdenv.mkDerivation rec {
    name = "autoresticCustom";
    version = "1.8.4";
    src = pkgs.fetchurl {
      url = "https://github.com/mluds/autorestic/releases/download/v${version}/autorestic_${version}_linux_amd64.bz2";
      sha256 = "1m4g1y8vr8mczjfwlnxp1a8k7m8jzz58dn3a3yyv53ggj4ayfx3c";
    };
    nativeBuildInputs = [ pkgs.bzip2 ];
    dontUnpack = true;
    installPhase = ''
      mkdir -p $out/bin
      bzip2 -dc $src > $out/bin/autorestic
      chmod +x $out/bin/autorestic
    '';
  };
in
{
  environment.systemPackages = with pkgs; [
    autoresticCustom
    restic
  ];
  system.activationScripts.autorestic-config = ''
    mkdir -p /var/lib/autorestic
    cat > /var/lib/autorestic/config.yml <<'EOF'
    version: 2

    locations:
      varlib:
        from: /var/lib
        to: local-backup
        forget: prune
        options:
          forget:
            keep-daily: 7
            keep-weekly: 4
            keep-monthly: 12
        hooks:
          before:
            - systemctl stop homepage-dashboard
            - systemctl stop sonarr
            - systemctl stop radarr
            - systemctl stop bazarr
            - systemctl stop prowlarr
            - systemctl stop seerr
            - systemctl stop plex
            - systemctl stop transmission
            - systemctl stop sabnzbd
            - systemctl stop caddy
            - systemctl stop tautulli
            - systemctl stop audiobookshelf
          after:
            - systemctl start homepage-dashboard
            - systemctl start sonarr
            - systemctl start radarr
            - systemctl start bazarr
            - systemctl start prowlarr
            - systemctl start seerr
            - systemctl start plex
            - systemctl start transmission
            - systemctl start sabnzbd
            - systemctl start caddy
            - systemctl start tautulli
            - systemctl start audiobookshelf

    backends:
      local-backup:
        type: local
        path: ${backupDir}
    EOF
    chmod 600 /var/lib/autorestic/config.yml
  '';

  systemd.services.autorestic-backup = {
    description = "Autorestic backup job";
    path = with pkgs; [
      bash
      restic
    ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = "${autoresticCustom}/bin/autorestic -c /var/lib/autorestic/config.yml --ci backup -a";
      TimeoutStopSec = "infinity";
    };
    preStart = ''
      mkdir -p ${backupDir}
      chmod 700 ${backupDir}
      ${autoresticCustom}/bin/autorestic -c /var/lib/autorestic/config.yml --ci check
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

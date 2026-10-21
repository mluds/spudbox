{ config, pkgs, ... }:

with config.my;

let
  dbFile = "/var/lib/prowlarr/prowlarr.db";
  cfgFile = "/var/lib/prowlarr/config.xml";
  setConfigXml = import ./set-config-xml.nix { inherit pkgs; };
  # Like Sonarr/Radarr: clear the user, put the credentials in config.xml,
  # and Prowlarr imports them on start as a salted PBKDF2 hash and removes
  # them from config.xml. (Inserting the row directly meant an unsalted
  # SHA-256 hash, and a password on sqlite3's command line.)
  configScript = pkgs.writeScriptBin "prowlarr-config" ''
    #!/bin/sh
    set -e
    umask 077

    if [ -f "${dbFile}" ]; then
      sqlite3 "${dbFile}" "DELETE FROM Users;"
    fi

    xmlstarlet ed -L \
      -u "/Config/AuthenticationMethod" -v "Forms" \
      "${cfgFile}"
    ${setConfigXml}/bin/set-config-xml "${cfgFile}" \
      Authentication/Username=${secretsDir}/admin/username \
      Authentication/Password=${secretsDir}/prowlarr/password

    if systemctl -q is-active prowlarr.service; then
      systemctl restart prowlarr.service
    fi

    echo "Exporting Prowlarr API key..."
    mkdir -p ${secretsDir}/prowlarr
    xmlstarlet sel -t -v '/Config/ApiKey' /var/lib/prowlarr/config.xml > ${secretsDir}/prowlarr/api-key
  '';
in
{
  services.prowlarr = {
    enable = true;
    openFirewall = false;
    # Loopback only; reached through Caddy (env var overrides config.xml).
    settings.server.bindaddress = "127.0.0.1";
  };

  systemd.services.prowlarr-config = {
    description = "Configure Prowlarr";
    after = [ "prowlarr.service" ];
    wants = [ "prowlarr.service" ];
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [
      xmlstarlet
      sqlite
    ];
    serviceConfig = {
      User = "root";
      Type = "oneshot";
      ExecStart = "${configScript}/bin/prowlarr-config";
    };
  };
}

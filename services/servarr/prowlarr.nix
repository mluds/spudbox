{config, pkgs, secrets, ...}:

with config.my;

let
  dbFile = "/var/lib/prowlarr/prowlarr.db";
  adminPasswordHash = builtins.hashString "sha256" secrets.adminPassword;
  configScript = pkgs.writeScriptBin "prowlarr-config" ''
    #!/bin/sh
    set -e

    if [ -f "${dbFile}" ]; then
      sqlite3 "${dbFile}" "DELETE FROM Users; \
        INSERT INTO Users (Identifier, Username, Password, Salt, Iterations) \
        VALUES ('d3b07384-1138-4e19-8878-669fc7a4c34a', '${secrets.adminUsername}', '${adminPasswordHash}', null, 0);"
    fi

    xmlstarlet ed -L \
      -u "/Config/AuthenticationMethod" -v "Forms" \
      "/var/lib/prowlarr/config.xml"

    if systemctl -q is-active prowlarr.service; then
      systemctl restart prowlarr.service
    fi

    echo "Exporting Prowlarr API key..."
    mkdir -p ${secretsDir}/prowlarr
    xmlstarlet sel -t -v '/Config/ApiKey' /var/lib/prowlarr/config.xml > ${secretsDir}/prowlarr/api-key
  '';
in {
  services.prowlarr = {
    enable = true;
    openFirewall = false;
  };

  systemd.services.prowlarr-config = {
    description = "Configure Prowlarr";
    after = [ "prowlarr.service" ];
    wants = [ "prowlarr.service" ];
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [ xmlstarlet sqlite ];
    serviceConfig = {
      User = "root";
      Type = "oneshot";
      ExecStart = "${configScript}/bin/prowlarr-config";
    };
  };
}

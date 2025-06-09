{config, pkgs, secrets, ...}:

let
  dbFile = "/var/lib/prowlarr/prowlarr.db";
  adminPasswordHash = builtins.hashString "sha256" secrets.adminPassword;
  configScript = pkgs.writeScriptBin "prowlarr-config" ''
    #!/bin/sh

    if [ -f "${dbFile}" ]; then
      sqlite3 "${dbFile}" "DELETE FROM Users; \
        INSERT INTO Users (Identifier, Username, Password, Salt, Iterations) \
        VALUES ('d3b07384-1138-4e19-8878-669fc7a4c34a', '${secrets.adminUsername}', '${adminPasswordHash}', null, 0);"
    fi

    xmlstarlet ed -L \
      -u "/Config/AuthenticationMethod" -v "Forms" \
      -u "/Config/ApiKey" -v "${secrets.prowlarrApiKey}" \
      "/var/lib/prowlarr/config.xml"

    if systemctl -q is-active prowlarr.service; then
      systemctl restart prowlarr.service
    fi
  '';
in {
  services.prowlarr = {
    enable = true;
    openFirewall = false;
  };

  systemd.services.prowlarr-config = {
    description = "Configure Prowlarr";
    after = [ "prowlarr.service" ];
    path = with pkgs; [ xmlstarlet sqlite ];
    serviceConfig = {
      User = "root";
      Type = "exec";
      ExecStart = "${configScript}/bin/prowlarr-config";
    };
  };
}

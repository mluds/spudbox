{config, pkgs, secrets, ...}:

let
  configScript = pkgs.writeScriptBin "prowlarr-config" ''
    #!/bin/sh
    xmlstarlet ed -L \
      -u "/Config/AuthenticationMethod" -v "External" \
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
    path = with pkgs; [ xmlstarlet ];
    serviceConfig = {
      User = "root";
      Type = "exec";
      ExecStart = "${configScript}/bin/prowlarr-config";
    };
  };
}

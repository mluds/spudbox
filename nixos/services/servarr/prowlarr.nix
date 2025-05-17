{config, pkgs, secrets, ...}:

{
  services.prowlarr = {
    enable = true;
    openFirewall = true;
  };

  system.activationScripts.prowlarrConfig = let
    xmlstarlet = "${pkgs.xmlstarlet}/bin/xmlstarlet";
    cfgFile = "/var/lib/prowlarr/config.xml";
  in ''
    ${xmlstarlet} ed -L \
      -u "/Config/AuthenticationMethod" -v "External" \
      -u "/Config/ApiKey" -v "${secrets.prowlarrApiKey}" \
      "${cfgFile}"
    if ${config.systemd.package}/bin/systemctl -q is-active prowlarr.service; then
      ${config.systemd.package}/bin/systemctl restart prowlarr.service
    fi
  '';
}

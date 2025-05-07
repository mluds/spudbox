{ config, pkgs, ... }:

with config.my;

{
  users.groups.sonarr = {};

  users.users.sonarr = {
    isSystemUser = true;
    group = "sonarr";
    extraGroups = [ "media" ];
    createHome = false;
    useDefaultShell = false;
  };

  services.sonarr = {
    enable = true;
    user = "sonarr";
    openFirewall = true;
  };

  system.activationScripts.sonarrConfig = let
    xmlstarlet = "${pkgs.xmlstarlet}/bin/xmlstarlet";
    sqlite = "${pkgs.sqlite}/bin/sqlite3";
    cfgFile = "${config.services.sonarr.dataDir}/config.xml";
    dbFile = "${config.services.sonarr.dataDir}/sonarr.db";
  in ''
    if [ -f "${dbFile}" ]; then
      ${sqlite} "${dbFile}" "DELETE FROM \"Users\";"
    fi
    ${xmlstarlet} ed -L \
      --subnode '/Config[not(Authentication)]' -t elem -n Authentication \
      --subnode '/Config/Authentication[not(Username)]' -t elem -n Username \
      --subnode '/Config/Authentication[not(Password)]' -t elem -n Password \
      -u "/Config/AuthenticationMethod" -v "Forms" \
      -u "/Config/Authentication/Username" -v "$(cat ${adminUsernamePath})" \
      -u "/Config/Authentication/Password" -v "$(cat ${adminPasswordPath})" \
      -u "/Config/ApiKey" -v "${sonarrApiKey}" \
      "${cfgFile}"
    if ${config.systemd.package}/bin/systemctl -q is-active sonarr.service; then
      ${config.systemd.package}/bin/systemctl restart sonarr.service
    fi
  '';
}

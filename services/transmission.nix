  
{pkgs, config, secrets, ...}:

with config.my;

{
  services.transmission = {
    enable = true;
    openRPCPort = false;
    webHome = "${pkgs.flood-for-transmission}";
    user = "transmission";
    group = "media";
    settings = {
      rpc-bind-address = "127.0.0.1";
      rpc-whitelist-enabled = true;
      rpc-authentication-required = true;
      rpc-username = secrets.adminUsername;
      rpc-password = secrets.adminPassword;
      incomplete-dir-enabled = true;
      incomplete-dir = "${cacheDir}/data/torrents/incomplete";
      download-dir = "${cacheDir}/data/torrents/complete";
    };
  };
}

  
{pkgs, config, ...}:

with config.my;

let
  credentialsFile = pkgs.writeText "transmission-credentials.json" (builtins.toJSON {
    rpc-username = builtins.readFile /var/lib/secrets/admin/username;
    rpc-password = builtins.readFile /var/lib/secrets/admin/password;
  });
in {
  services.transmission = {
    enable = true;
    package = pkgs.transmission_4;
    openRPCPort = false;
    webHome = "${pkgs.flood-for-transmission}";
    user = "transmission";
    group = "media";
    credentialsFile = credentialsFile;
    settings = {
      rpc-bind-address = "127.0.0.1";
      rpc-whitelist-enabled = true;
      rpc-authentication-required = true;
      incomplete-dir-enabled = true;
      incomplete-dir = "${cacheDir}/data/torrents/incomplete";
      download-dir = "${cacheDir}/data/torrents/complete";
    };
  };
}

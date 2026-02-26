
{pkgs, config, ...}:

with config.my;

let
  credentialsDir = "/run/transmission";
  credentialsPath = "${credentialsDir}/credentials.json";
in {
  services.transmission = {
    enable = true;
    package = pkgs.transmission_4;
    openRPCPort = false;
    webHome = "${pkgs.flood-for-transmission}";
    user = "transmission";
    group = "media";
    credentialsFile = credentialsPath;
    settings = {
      rpc-bind-address = "127.0.0.1";
      rpc-whitelist-enabled = true;
      rpc-authentication-required = true;
      incomplete-dir-enabled = true;
      incomplete-dir = "${cacheDir}/data/torrents/incomplete";
      download-dir = "${cacheDir}/data/torrents/complete";
    };
  };

  systemd.services.transmission.serviceConfig.ExecStartPre = let
    script = pkgs.writeShellScript "transmission-credentials" ''
      mkdir -p ${credentialsDir}
      ADMIN_USERNAME=$(cat ${secretsDir}/admin/username)
      ADMIN_PASSWORD=$(cat ${secretsDir}/admin/password)
      ${pkgs.jq}/bin/jq -n \
        --arg user "$ADMIN_USERNAME" \
        --arg pass "$ADMIN_PASSWORD" \
        '{"rpc-username": $user, "rpc-password": $pass}' \
        > ${credentialsPath}
      chmod 600 ${credentialsPath}
    '';
  in [
    "+${script}"
  ];
}

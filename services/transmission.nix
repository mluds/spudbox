{
  config,
  pkgs,
  lib,
  ...
}:

with config.my;

let
  credentialsDir = "/run/transmission";
  credentialsPath = "${credentialsDir}/credentials.json";
  floodConfig = pkgs.runCommand "flood-for-transmission-configured" { } ''
    cp -r ${pkgs.flood-for-transmission} $out
    chmod +w $out
    cat > $out/config.json <<'EOF'
    ${builtins.toJSON {
      COMMON_PATH = [
        "${storageDir}/data/media/movies"
        "${storageDir}/data/media/tv"
        "${storageDir}/data/media/videos"
      ];
    }}
    EOF
  '';
in
{
  services.transmission = {
    enable = true;
    package = pkgs.transmission_4;
    openRPCPort = false;
    webHome = floodConfig;
    user = "transmission";
    group = "media";
    credentialsFile = credentialsPath;
    settings = {
      rpc-bind-address = "127.0.0.1";
      rpc-whitelist-enabled = true;
      rpc-authentication-required = true;
      incomplete-dir-enabled = true;
      incomplete-dir = "${cacheDir}/data/torrents/incomplete";
      download-dir = "${storageDir}/data/media/videos";
    };
  };

  systemd.services.transmission.serviceConfig = {
    # settings.json holds the RPC password hash; downloads live under
    # storageDir/cacheDir, so the media group doesn't need this dir (module: 0750)
    StateDirectoryMode = lib.mkForce "0700";

    ExecStartPre = lib.mkBefore (
      let
        script = pkgs.writeShellScript "transmission-credentials" ''
          umask 077
          mkdir -p ${credentialsDir}
          # --rawfile reads the secrets itself, keeping them off jq's argv
          ${pkgs.jq}/bin/jq -n \
            --rawfile user ${secretsDir}/admin/username \
            --rawfile pass ${secretsDir}/transmission/password \
            '{"rpc-username": ($user | rtrimstr("\n")), "rpc-password": ($pass | rtrimstr("\n"))}' \
            > ${credentialsPath}
          chmod 600 ${credentialsPath}
        '';
      in
      [
        "+${script}"
      ]
    );
  };
}

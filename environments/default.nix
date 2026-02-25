{ pkgs, ... }:

let
  cacheDir = "/mnt/cache";
  appdataDir = "${cacheDir}/appdata";
in {
  my = {
    inherit cacheDir appdataDir;
    storageDir = "/mnt/storage";
    backupDir = "/mnt/backup";
    backupDrives = [];
    secretsDir = "/var/lib/secrets";

    plexPort = 32400;
    tautulliPort = 8181;
    sonarrPort = 8989;
    radarrPort = 7878;
    bazarrPort = 6767;
    whisparrPort = 6969;
    sabnzbdPort = 8081;
    qbittorrentPort = 8082;
    caddyAdminPort = 2019;
    jellyseerrPort = 5055;
    homeassistantPort = 8123;
    zwavejsPort = 8091;
    homepagePort = 3000;
    ariangPort = 6880;
    transmissionPort = 9091;
    prowlarrPort = 9696;
    audiobookshelfPort = 8000;
    ttydPort = 7681;
    homebridgePort = 8581;

    usenetServerHosts = [
      "news.frugalusenet.com"
      "eunews.frugalusenet.com"
      "asnews.frugalusenet.com"
      "bonus.frugalusenet.com"
      "usnews.blocknews.net"
    ];
    usenetServerPort = 563;

    users = [
      {
        username = "luds";
        sshPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEEhpJNrO3TZHAOEk4InRTfy2rtlzY6vrD7grcfb4zte";
        superuser = true;
      }
    ];

    encodeBase64 = str: builtins.readFile (pkgs.runCommand "encoded" {} ''
      echo -n "${str}" | ${pkgs.coreutils}/bin/base64 -w0 > $out
    '');

    bcryptHash = password: pkgs.runCommand "bcrypt-hash" {
      buildInputs = [ pkgs.mkpasswd ];
      inherit password;
      preferLocalBuild = true;
      allowSubstitutes = false;
    } ''
      echo -n "$password" | mkpasswd -m bcrypt -s > $out
    '';
  };
}

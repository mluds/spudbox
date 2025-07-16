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
    aria2Port = 6800;
    stashPort = 9999;
    stashvrPort = 9666;
    transmissionPort = 9091;
    prowlarrPort = 9696;
    audiobookshelfPort = 8000;
    ttydPort = 7681;

    usenetServerHosts = [
      "news.frugalusenet.com"
      "eunews.frugalusenet.com"
      "asnews.frugalusenet.com"
      "bonus.frugalusenet.com"
      "usnews.blocknews.net"
    ];
    usenetServerPort = 563;

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

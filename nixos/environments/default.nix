{ pkgs, ... }:

{
  my = {
    plexPort = 32400;
    tautulliPort = 8181;
    sonarrPort = 8989;
    radarrPort = 7878;
    bazarrPort = 6767;
    whisparrPort = 6969;
    sabnzbdPort = 8081;
    qbittorrentPort = 8082;
    caddyAdminPort = 2019;
    overseerrPort = 5055;
    homeassistantPort = 8123;
    zwavejsPort = 8091;
    homepagePort = 3000;
    cockpitPort = 9090;
    ariangPort = 6880;
    aria2Port = 6800;
    stashPort = 9999;
    stashvrPort = 9666;

    adminPasswordHash = "fix_me";

    encodeBase64 = str: builtins.readFile (pkgs.runCommand "encoded" {} ''
      echo -n "${str}" | ${pkgs.coreutils}/bin/base64 -w0 > $out
    '');
  };
}

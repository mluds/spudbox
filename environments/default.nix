_:

let
  cacheDir = "/mnt/cache";
  appdataDir = "${cacheDir}/appdata";
  storageDir = "/mnt/storage";
in
{
  my = {
    inherit cacheDir appdataDir storageDir;
    # Local restic repo lives on the HDD, not the NVMe holding /var/lib.
    backupDir = "${storageDir}/backups";
    backupDrives = [ ];
    secretsDir = "/var/lib/secrets";

    plexPort = 32400;
    tautulliPort = 8181;
    sonarrPort = 8989;
    radarrPort = 7878;
    bazarrPort = 6767;
    sabnzbdPort = 8081;
    caddyAdminPort = 2019;
    jellyseerrPort = 5055;
    homepagePort = 3000;
    transmissionPort = 9091;
    prowlarrPort = 9696;
    audiobookshelfPort = 8000;
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
  };
}

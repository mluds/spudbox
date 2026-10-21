{ lib, ... }:

# Typed `my.*` options; values are set in environments/. A typo such as
# `my.sonarPort` is an eval error instead of a silently ignored attribute.
let
  inherit (lib) mkOption types;

  str =
    description:
    mkOption {
      type = types.str;
      inherit description;
    };

  port =
    description:
    mkOption {
      type = types.port;
      inherit description;
    };

  drives =
    description:
    mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            device = str "Whole-disk block device, e.g. /dev/sda.";
            partition = str "Its single XFS partition, e.g. /dev/sda1.";
            mount = str "Where the partition is mounted before being pooled by mergerfs.";
          };
        }
      );
      default = [ ];
      inherit description;
    };
in
{
  options.my = {
    domain = str "Base domain; each web UI is served at <service>.<domain>.";

    secretsDir = str "Root-only directory holding the deployed secrets.";
    cacheDir = str "mergerfs pool of cacheDrives (downloads in progress).";
    storageDir = str "mergerfs pool of storageDrives (media library).";
    backupDir = str "Where the local restic repo lives.";

    cacheDrives = drives "Drives pooled at cacheDir.";
    storageDrives = drives "Drives pooled at storageDir.";
    backupDrives = drives "Drives pooled at backupDir.";

    adminUserId = str "Fixed user ID of the Audiobookshelf root account (audiobookshelf-config inserts it).";

    plexPort = port "Plex";
    tautulliPort = port "Tautulli";
    sonarrPort = port "Sonarr";
    radarrPort = port "Radarr";
    bazarrPort = port "Bazarr";
    sabnzbdPort = port "SABnzbd";
    caddyAdminPort = port "Caddy admin API";
    jellyseerrPort = port "Jellyseerr (seerr)";
    homepagePort = port "Homepage dashboard";
    transmissionPort = port "Transmission RPC/web UI";
    prowlarrPort = port "Prowlarr";
    audiobookshelfPort = port "Audiobookshelf";
    homebridgePort = port "Homebridge UI";
    driveStatusPort = port "drive-status JSON server";

    usenetServerHosts = mkOption {
      type = types.listOf types.str;
      description = "Usenet servers, in priority order.";
    };
    usenetServerPort = port "Usenet server port (TLS).";

    users = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            username = str "Login name.";
            sshPublicKey = str "Authorized SSH key.";
            superuser = mkOption {
              type = types.bool;
              default = false;
              description = "Member of wheel; admin in apps that have users.";
            };
          };
        }
      );
      description = "Login users. Password hashes come from secrets/users/<name>/hashed.";
    };
  };
}

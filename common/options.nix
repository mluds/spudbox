{ config, lib, ... }:

# Typed `spudbox.*` options, set in an instance's spudbox.nix (see
# template/spudbox.nix). A typo such as `spudbox.sonarPort` is an eval error
# instead of a silently ignored attribute.
let
  inherit (lib) mkOption mkEnableOption types;
  cfg = config.spudbox;

  str =
    description:
    mkOption {
      type = types.str;
      inherit description;
    };

  port =
    default: description:
    mkOption {
      type = types.port;
      inherit default description;
    };

  drives =
    description:
    mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            device = str "Whole-disk block device, e.g. /dev/disk/by-id/ata-WDC_...";
            partition = str "Its single XFS partition, e.g. /dev/disk/by-id/ata-WDC_...-part1.";
            mount = str "Where the partition is mounted before being pooled by mergerfs, e.g. /mnt/storage1.";
          };
        }
      );
      default = [ ];
      inherit description;
    };
in
{
  options.spudbox = {
    domain = str ''
      Base domain; each web UI is served at https://<service>.<domain>
      (LAN only). Point a wildcard DNS record *.<domain> at the server.
    '';

    secretsDir = mkOption {
      type = types.str;
      default = "/var/lib/secrets";
      description = "Root-only directory holding the secrets (deployed and generated).";
    };
    storageDir = mkOption {
      type = types.str;
      default = "/mnt/storage";
      description = "mergerfs pool of storageDrives: the media library.";
    };
    cacheDir = mkOption {
      type = types.str;
      default = "/mnt/cache";
      description = "mergerfs pool of cacheDrives: downloads in progress. Without cacheDrives it's a plain directory on the root disk.";
    };
    backupDir = mkOption {
      type = types.str;
      default = "${cfg.storageDir}/backups";
      defaultText = lib.literalExpression ''"''${config.spudbox.storageDir}/backups"'';
      description = "Where the local restic repository lives (on the media disks, not the boot disk).";
    };

    cacheDrives = drives "Drives pooled at cacheDir.";
    storageDrives = drives "Drives pooled at storageDir.";
    backupDrives = drives "Drives pooled at backupDir.";

    adminUserId = mkOption {
      type = types.str;
      default = "d3b07384-1138-4e19-8878-669fc7a4c34a";
      description = "Fixed user ID of the Audiobookshelf root account (audiobookshelf-config inserts it).";
    };

    plexPort = port 32400 "Plex";
    tautulliPort = port 8181 "Tautulli";
    sonarrPort = port 8989 "Sonarr";
    radarrPort = port 7878 "Radarr";
    bazarrPort = port 6767 "Bazarr";
    sabnzbdPort = port 8081 "SABnzbd";
    caddyAdminPort = port 2019 "Caddy admin API";
    jellyseerrPort = port 5055 "Jellyseerr (seerr)";
    homepagePort = port 3000 "Homepage dashboard";
    transmissionPort = port 9091 "Transmission RPC/web UI";
    audiobookshelfPort = port 8000 "Audiobookshelf";
    homebridgePort = port 8581 "Homebridge UI";
    driveStatusPort = port 9100 "drive-status JSON server";

    users = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            username = str "Login name.";
            sshPublicKey = str "Authorized SSH key.";
            superuser = mkOption {
              type = types.bool;
              default = false;
              description = "Member of wheel (passwordless sudo); admin in apps that have users.";
            };
          };
        }
      );
      description = ''
        Login users. SSH keys only; an optional password hash can be put in
        secrets/users/<name>/hashed (mkpasswd -m yescrypt).
      '';
    };

    usenet = {
      servers = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "news.example-provider.com" ];
        description = "Usenet server hostnames, in priority order. All share the login in secrets/usenet/{username,password}.";
      };
      port = port 563 "Usenet server port (TLS).";
      connections = mkOption {
        type = types.ints.positive;
        default = 20;
        description = "Connections per usenet server.";
      };
    };

    indexers = mkOption {
      type = types.listOf (
        types.submodule (
          { config, ... }:
          {
            options = {
              name = str "Indexer name, as shown in Sonarr and Radarr.";
              url = str "Newznab API base URL, e.g. https://api.nzbgeek.info/.";
              apiPath = mkOption {
                type = types.str;
                default = "/api";
                description = "Newznab API path.";
              };
              apiKeySecret = mkOption {
                type = types.str;
                default = "${lib.toLower config.name}/api-key";
                defaultText = lib.literalExpression ''"''${lib.toLower name}/api-key"'';
                description = "Secret file (under secretsDir) holding the indexer's API key.";
              };
            };
          }
        )
      );
      default = [ ];
      description = "Newznab (usenet) indexers added to Sonarr and Radarr.";
    };

    subtitleProviders = mkOption {
      type = types.listOf (
        types.enum [
          "opensubtitlescom"
          "assrt"
        ]
      );
      default = [ ];
      description = ''
        Bazarr subtitle providers. opensubtitlescom needs
        secrets/opensubtitles/{username,password}; assrt needs secrets/assrt/api-token.
      '';
    };

    tls = mkOption {
      type = types.enum [
        "cloudflare"
        "internal"
      ];
      default = "internal";
      description = ''
        Where the HTTPS certificate comes from. "cloudflare": a real wildcard
        certificate for *.<domain> from Let's Encrypt via a Cloudflare DNS
        challenge (needs secrets/cloudflare/api-token, a token with
        Zone:DNS:Edit). "internal": Caddy's own CA; browsers warn until you
        trust its root (/var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt).
      '';
    };

    disableIPv6 = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Turn IPv6 off, so the torrent client doesn't announce a global IPv6
        address. NetworkManager re-enables it per profile; see the README
        ("IPv6") for the one-time nmcli step.
      '';
    };

    homepage = {
      title = mkOption {
        type = types.str;
        default = "SpudBox";
        description = "Dashboard title.";
      };
      description = mkOption {
        type = types.str;
        default = "Home Server";
        description = "Dashboard description.";
      };
      bookmarks = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              title = str "Shown name.";
              href = str "Link.";
              description = str "Subtitle.";
              icon = str "homepage icon name, e.g. cloudflare or mdi-multimedia.";
            };
          }
        );
        default = [ ];
        description = "Bookmarks row under the services (provider dashboards, ...).";
      };
    };

    pushover.enable = mkEnableOption ''
      Pushover alerts when a setup unit, backup or timer job fails, and
      Jellyseerr request notifications. Needs secrets/pushover/{app-token,user-key}
    '';

    offsiteBackup = {
      enable = mkEnableOption ''
        copying each nightly local backup to an S3-compatible bucket
        (restic copy), then pruning and checking it. Needs
        secrets/r2/s3-credentials.env (AWS_ACCESS_KEY_ID=..., AWS_SECRET_ACCESS_KEY=...)
      '';
      repository = mkOption {
        type = types.str;
        example = "s3:https://<account>.r2.cloudflarestorage.com/<bucket>";
        description = "restic repository URL.";
      };
    };

    hddSpindown.enable = mkEnableOption ''
      spinning the storage drives down after 5 idle minutes (for drives that
      ignore hdparm -S), logging each spin-down and wake, and their state on
      the dashboard. For rotating storageDrives only
    '';

    mediaFixup.enable = mkEnableOption ''
      media-fixup: every 15 minutes, rewrite new videos some Plex clients
      can't play (Dolby Vision profile 5 to HDR10, hybrid DV8 stripped, SRT
      font tags). Needs an Intel iGPU (x86_64)
    '';

    homebridge = {
      enable = mkEnableOption "Homebridge (HomeKit bridge, in Docker)";
      dummySwitches = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "Dummy Door Switch" ];
        description = "Stateful homebridge-dummy switches created on first setup.";
      };
    };

    claudeCode = {
      enable = mkEnableOption ''
        Claude Code Remote Control as a service, so the server can be driven
        from the Claude app. Runs as `user`; if that user is a superuser,
        Claude sessions have root. One-time login: see the README
      '';
      user = mkOption {
        type = types.str;
        description = "Login user the service runs as (one of `users`).";
      };
      name = mkOption {
        type = types.str;
        default = "spudbox";
        description = "Session name shown in the Claude app.";
      };
    };

    dataMounts = mkOption {
      type = types.attrsOf types.anything;
      internal = true;
      readOnly = true;
      description = "The fileSystems entries for the data drives and their pools (storage.nix); a VM test mounts them too.";
    };

    features = mkOption {
      type = types.listOf types.str;
      internal = true;
      readOnly = true;
      description = "Enabled optional features, exported to test.sh as FEATURES.";
    };
  };

  config.spudbox.features =
    lib.optional cfg.pushover.enable "pushover"
    ++ lib.optional cfg.offsiteBackup.enable "offsite-backup"
    ++ lib.optional cfg.hddSpindown.enable "hdd-spindown"
    ++ lib.optional cfg.mediaFixup.enable "media-fixup"
    ++ lib.optional cfg.homebridge.enable "homebridge"
    ++ lib.optional cfg.claudeCode.enable "claude-code"
    ++ lib.optional cfg.disableIPv6 "no-ipv6"
    ++ lib.optional (cfg.tls == "cloudflare") "tls-cloudflare";
}

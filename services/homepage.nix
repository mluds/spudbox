{ config, lib, ... }:

let
  cfg = config.spudbox;
  inherit (cfg)
    storageDrives
    storageDir
    domain
    driveStatusPort
    homepagePort
    secretsDir
    ;

  # homepage substitutes the contents of credential NAME (see credentials).
  file = name: "{{HOMEPAGE_FILE_${name}}}";
  local = name: "http://localhost:${toString config.spudbox."${name}Port"}";
  # homepage's <name> widget, talking to localhost:spudbox.<name>Port.
  widget =
    name: attrs:
    {
      type = name;
      url = local name;
    }
    // attrs;
  # A tile for <name>, linking to https://<name>.<domain>, with its widget
  # (null: none).
  tile = name: title: description: widgetAttrs: {
    ${title} = {
      icon = name;
      href = "https://${name}.${domain}";
      inherit description;
    }
    // lib.optionalAttrs (widgetAttrs != null) { widget = widget name widgetAttrs; };
  };
  bookmark = title: href: description: icon: { ${title} = [ { inherit href description icon; } ]; };

  uniqueDevices = lib.unique (map (drive: drive.device) storageDrives);
  # From drive-check.nix (spudbox.hddSpindown).
  driveWidgets = lib.optionals cfg.hddSpindown.enable (
    lib.imap1 (
      i: dev:
      let
        blockName = builtins.baseNameOf dev;
        label = if builtins.length uniqueDevices == 1 then "HDD" else "HDD ${toString i}";
      in
      {
        "${label}" = {
          icon = "mdi-harddisk";
          description = "Storage Drive (${dev})";
          widget = {
            type = "customapi";
            url = "http://localhost:${toString driveStatusPort}/status_${blockName}.json";
            refreshInterval = 30000;
            mappings = [
              {
                field = "state";
                label = "State";
                format = "text";
                remap = [
                  {
                    value = "active/idle";
                    to = "Spinning";
                  }
                  {
                    value = "standby";
                    to = "Standby";
                  }
                ];
              }
              {
                field = "lastAccess";
                label = "Last I/O";
                format = "relativeDate";
              }
            ];
          };
        };
      }
    ) uniqueDevices
  );
in

{
  systemd.services.homepage-dashboard =
    let
      # HOMEPAGE_FILE_<NAME> -> secret file. systemd copies each into this
      # unit's private credentials dir (%d), so /var/lib/secrets stays root-only.
      credentials = {
        PLEX_TOKEN = "plex/token";
        ABS_API_KEY = "audiobookshelf/apikey";
        RADARR_API_KEY = "radarr/api-key";
        SONARR_API_KEY = "sonarr/api-key";
        BAZARR_API_KEY = "bazarr/api-key";
        TAUTULLI_API_KEY = "tautulli/api-key";
        JELLYSEERR_API_KEY = "jellyseerr/api-key";
        SABNZBD_API_KEY = "sabnzbd/api-key";
        ADMIN_USERNAME = "admin/username";
        TRANSMISSION_PASSWORD = "transmission/password";
      };
    in
    {
      # Several keys are exported by these oneshots on first boot; a missing
      # credential fails the unit, so start after them and retry slowly.
      after = [
        "plex-config.service"
        "bazarr-config.service"
        "tautulli-config.service"
        "jellyseerr-config.service"
        "audiobookshelf-access.service"
      ];
      serviceConfig = {
        LoadCredential = lib.mapAttrsToList (name: path: "${name}:${secretsDir}/${path}") credentials;
        Environment = [
          # Loopback only; reached through Caddy.
          "HOSTNAME=127.0.0.1"
          "HOMEPAGE_ALLOWED_HOSTS=homepage.${domain}"
        ]
        ++ lib.mapAttrsToList (name: _: "HOMEPAGE_FILE_${name}=%d/${name}") credentials;
        RestartSec = "30s";
      };
    };
  services.homepage-dashboard = {
    enable = true;
    listenPort = homepagePort;
    openFirewall = false;
    settings = {
      inherit (cfg.homepage) title description;
      language = "en";
      theme = "dark";
      headerStyle = "underlined";
      disableCollapse = true;
      useEqualHeights = true;
      layout = [
        {
          Services = {
            header = false;
            style = "row";
            columns = 4;
          };
        }
        {
          Bookmarks = {
            header = false;
            style = "row";
            columns = 4;
          };
        }
      ];
    };
    widgets = [
      {
        "greeting" = {
          textSize = "2xl";
          text = cfg.homepage.title;
        };
      }
      {
        "resources" = {
          cpu = true;
          memory = true;
          disk = storageDir;
          cputemp = true;
          tempMin = 0;
          tempMax = 100;
          uptime = true;
          units = "imperial";
          refresh = 3000;
          diskUnits = "bytes";
          network = true;
        };
      }
    ];
    services = [
      {
        Services = [
          {
            Plex = {
              icon = "plex";
              href = "https://plex.${domain}";
              description = "Media Server";
              widgets = [
                (widget "plex" {
                  key = file "PLEX_TOKEN";
                  fields = [
                    "movies"
                    "tv"
                  ];
                })
                (widget "tautulli" {
                  key = file "TAUTULLI_API_KEY";
                  enableUser = true;
                  showEpisodeNumber = true;
                  expandOneStreamToTwoRows = false;
                })
              ];
            };
          }
          (tile "jellyseerr" "Jellyseerr" "Media Requests" {
            key = file "JELLYSEERR_API_KEY";
            fields = [
              "pending"
              "approved"
              "available"
            ];
          })
          (tile "audiobookshelf" "Audiobookshelf" "Audiobook Server" {
            key = file "ABS_API_KEY";
            fields = [
              "books"
              "booksDuration"
            ];
          })
          (tile "radarr" "Radarr" "Movie Management" {
            key = file "RADARR_API_KEY";
            fields = [
              "movies"
              "wanted"
              "missing"
              "queued"
            ];
            enableQueue = false;
          })
          (tile "sonarr" "Sonarr" "TV Show Management" {
            key = file "SONARR_API_KEY";
            fields = [
              "series"
              "wanted"
              "queued"
            ];
            enableQueue = false;
          })
          (tile "bazarr" "Bazarr" "Subtitles Management" {
            key = file "BAZARR_API_KEY";
            fields = [
              "missingEpisodes"
              "missingMovies"
            ];
          })
          (tile "sabnzbd" "SABnzbd" "Usenet Downloader" { key = file "SABNZBD_API_KEY"; })
          (tile "transmission" "Transmission" "Torrent Downloader" {
            username = file "ADMIN_USERNAME";
            password = file "TRANSMISSION_PASSWORD";
            fields = [
              "leech"
              "download"
              "seed"
              "upload"
            ];
            rpcUrl = "/transmission/";
            enableLeechProgress = false;
          })
        ]
        ++ driveWidgets
        ++ lib.optional cfg.homebridge.enable (tile "homebridge" "Homebridge" "Apple Home Integration" null)
        ++ [
          (tile "tautulli" "Tautulli" "Plex Monitoring" null)
          {
            Caddy = {
              icon = "caddy";
              description = "Service Gateway";
              widget = {
                type = "caddy";
                url = local "caddyAdmin";
                fields = [
                  "upstreams"
                  "requests"
                  "requests_failed"
                ];
              };
            };
          }
        ];
      }
    ];
    bookmarks = lib.optional (cfg.homepage.bookmarks != [ ]) {
      Bookmarks = map (b: bookmark b.title b.href b.description b.icon) cfg.homepage.bookmarks;
    };
  };
}

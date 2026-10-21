{ config, lib, ... }:

with config.my;

let
  uniqueDevices = lib.unique (map (drive: drive.device) storageDrives);
  driveWidgets = lib.imap1 (
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
          url = "http://localhost:9100/status_${blockName}.json";
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
  ) uniqueDevices;
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
        PROWLARR_API_KEY = "prowlarr/api-key";
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
        "prowlarr-config.service"
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
      title = "SpudBox";
      description = "Mike's Home Server";
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
          text = "SpudBox";
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
            "Plex" = {
              icon = "plex";
              href = "https://plex.${domain}";
              description = "Media Server";
              widgets = [
                {
                  type = "plex";
                  url = "http://localhost:${toString plexPort}";
                  key = "{{HOMEPAGE_FILE_PLEX_TOKEN}}";
                  fields = [
                    "movies"
                    "tv"
                  ];
                }
                {
                  type = "tautulli";
                  url = "http://localhost:${toString tautulliPort}";
                  key = "{{HOMEPAGE_FILE_TAUTULLI_API_KEY}}";
                  enableUser = true;
                  showEpisodeNumber = true;
                  expandOneStreamToTwoRows = false;
                }
              ];
            };
          }
          {
            "Jellyseerr" = {
              icon = "jellyseerr";
              href = "https://jellyseerr.${domain}";
              description = "Media Requests";
              widget = {
                type = "jellyseerr";
                url = "http://localhost:${toString jellyseerrPort}";
                key = "{{HOMEPAGE_FILE_JELLYSEERR_API_KEY}}";
                fields = [
                  "pending"
                  "approved"
                  "available"
                ];
              };
            };
          }
          {
            "Audiobookshelf" = {
              icon = "audiobookshelf";
              href = "https://audiobookshelf.${domain}";
              description = "Audiobook Server";
              widget = {
                type = "audiobookshelf";
                url = "http://localhost:${toString audiobookshelfPort}";
                key = "{{HOMEPAGE_FILE_ABS_API_KEY}}";
                fields = [
                  "books"
                  "booksDuration"
                ];
              };
            };
          }
          {
            "Radarr" = {
              icon = "radarr";
              href = "https://radarr.${domain}";
              description = "Movie Management";
              widget = {
                type = "radarr";
                fields = [
                  "movies"
                  "wanted"
                  "missing"
                  "queued"
                ];
                url = "http://localhost:${toString radarrPort}";
                key = "{{HOMEPAGE_FILE_RADARR_API_KEY}}";
                enableQueue = false;
              };
            };
          }
          {
            "Sonarr" = {
              icon = "sonarr";
              href = "https://sonarr.${domain}";
              description = "TV Show Management";
              widget = {
                type = "sonarr";
                fields = [
                  "series"
                  "wanted"
                  "queued"
                ];
                url = "http://localhost:${toString sonarrPort}";
                key = "{{HOMEPAGE_FILE_SONARR_API_KEY}}";
                enableQueue = false;
              };
            };
          }
          {
            "Bazarr" = {
              icon = "bazarr";
              href = "https://bazarr.${domain}";
              description = "Subtitles Management";
              widget = {
                type = "bazarr";
                fields = [
                  "missingEpisodes"
                  "missingMovies"
                ];
                url = "http://localhost:${toString bazarrPort}";
                key = "{{HOMEPAGE_FILE_BAZARR_API_KEY}}";
              };
            };
          }
          {
            "Prowlarr" = {
              icon = "prowlarr";
              href = "https://prowlarr.${domain}";
              description = "Torrent Index Management";
              widget = {
                type = "prowlarr";
                fields = [
                  "numberOfGrabs"
                  "numberOfQueries"
                  "numberOfFailGrabs"
                  "numberOfFailQueries"
                ];
                url = "http://localhost:${toString prowlarrPort}";
                key = "{{HOMEPAGE_FILE_PROWLARR_API_KEY}}";
              };
            };
          }
          {
            "SABnzbd" = {
              icon = "sabnzbd";
              href = "https://sabnzbd.${domain}";
              description = "Usenet Downloader";
              widget = {
                type = "sabnzbd";
                url = "http://localhost:${toString sabnzbdPort}";
                key = "{{HOMEPAGE_FILE_SABNZBD_API_KEY}}";
              };
            };
          }
          {
            "Transmission" = {
              icon = "transmission";
              href = "https://transmission.${domain}";
              description = "Torrent Downloader";
              widget = {
                type = "transmission";
                url = "http://localhost:${toString transmissionPort}";
                username = "{{HOMEPAGE_FILE_ADMIN_USERNAME}}";
                password = "{{HOMEPAGE_FILE_TRANSMISSION_PASSWORD}}";
                fields = [
                  "leech"
                  "download"
                  "seed"
                  "upload"
                ];
                rpcUrl = "/transmission/";
                enableLeechProgress = false;
              };
            };
          }
        ]
        ++ driveWidgets
        ++ [
          {
            "Homebridge" = {
              icon = "homebridge";
              href = "https://homebridge.${domain}";
              description = "Apple Home Integration";
            };
          }
          {
            "Tautulli" = {
              icon = "tautulli";
              href = "https://tautulli.${domain}";
              description = "Plex Monitoring";
            };
          }
          {
            "Caddy" = {
              icon = "caddy";
              description = "Service Gateway";
              widget = {
                type = "caddy";
                fields = [
                  "upstreams"
                  "requests"
                  "requests_failed"
                ];
                url = "http://localhost:${toString caddyAdminPort}";
              };
            };
          }
        ];
      }
    ];
    bookmarks = [
      {
        Bookmarks = [
          {
            Cloudflare = [
              {
                href = "https://dash.cloudflare.com/";
                description = "DNS Provider";
                icon = "cloudflare";
              }
            ];
          }
          {
            Namecheap = [
              {
                href = "https://ap.www.namecheap.com/";
                description = "Domain Registrar";
                icon = "namecheap";
              }
            ];
          }
          {
            NZBGeek = [
              {
                href = "https://nzbgeek.info/dashboard.php?myaccount";
                description = "Usenet Indexer";
                icon = "mdi-multimedia";
              }
            ];
          }
          {
            Frugal = [
              {
                href = "https://billing.frugalusenet.com/member";
                description = "Usenet Provider";
                icon = "mdi-multimedia";
              }
            ];
          }
          {
            Letterboxd = [
              {
                href = "https://letterboxd.com/official/story/official-lists-hq-directory/";
                description = "Movie Lists";
                icon = "si-letterboxd";
              }
            ];
          }
        ];
      }
    ];
  };
}

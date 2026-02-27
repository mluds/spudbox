{ config, ... }:

with config.my;

{
  systemd.services.homepage-dashboard = {
    serviceConfig = {
      Group = "media";
      SupplementaryGroups = "radarr";
      Environment = [
        "HOMEPAGE_ALLOWED_HOSTS=homepage.${domain}"
        "HOMEPAGE_FILE_PLEX_TOKEN=${secretsDir}/plex/token"
        "HOMEPAGE_FILE_ABS_API_KEY=${secretsDir}/audiobookshelf/apikey"
        "HOMEPAGE_FILE_RADARR_API_KEY=${secretsDir}/radarr/api-key"
        "HOMEPAGE_FILE_SONARR_API_KEY=${secretsDir}/sonarr/api-key"
        "HOMEPAGE_FILE_BAZARR_API_KEY=${secretsDir}/bazarr/api-key"
        "HOMEPAGE_FILE_PROWLARR_API_KEY=${secretsDir}/prowlarr/api-key"
        "HOMEPAGE_FILE_TAUTULLI_API_KEY=${secretsDir}/tautulli/api-key"
        "HOMEPAGE_FILE_JELLYSEERR_API_KEY=${secretsDir}/jellyseerr/api-key"
        "HOMEPAGE_FILE_SABNZBD_API_KEY=${secretsDir}/sabnzbd/api-key"
        "HOMEPAGE_FILE_ADMIN_USERNAME=${secretsDir}/admin/username"
        "HOMEPAGE_FILE_ADMIN_PASSWORD=${secretsDir}/admin/password"
      ];
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
                password = "{{HOMEPAGE_FILE_ADMIN_PASSWORD}}";
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
          {
            "Homebridge" = {
              icon = "homebridge";
              href = "https://homebridge.${domain}";
              description = "Apple Home Integration";
            };
          }
          {
            "ttyd" = {
              icon = "terminal";
              href = "https://ttyd.${domain}";
              description = "Web Terminal";
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

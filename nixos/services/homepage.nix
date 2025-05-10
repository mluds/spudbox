{ config, secrets, ... }:

with config.my;

{
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
    };
    services = [
      {
        "Media" = [
          {
            "Plex" = {
              icon = "plex";
              href = "https://plex.${domain}";
              description = "Media Server";
              widgets = [
                {
                  type = "plex";
                  url = "http://localhost:${toString plexPort}";
                  # key = secrets.plexToken;  # TODO get plexToken from user and pass
                  fields = [
                    "movies"
                    "tv"
                  ];
                }
                {
                  type = "tautulli";
                  url = "http://localhost:${toString tautulliPort}";
                  key = secrets.tautulliApiKey;
                  enableUser = true;
                  showEpisodeNumber = true;
                  expandOneStreamToTwoRows = false;
                }
              ];
            };
          }
          {
            "Overseerr" = {
              icon = "overseerr";
              href = "https://overseerr.${domain}";
              description = "Media Requests";
            };
          }
        ];
      }
      {
        "Media Management" = [
          {
            "Sonarr" = {
              icon = "sonarr";
              href = "https://sonarr.${domain}";
              description = "TV Show Management";
              widget = {
                type = "sonarr";
                fields = [
                  "wanted"
                  "queued"
                  "series"
                ];
                url = "http://localhost:${toString sonarrPort}";
                key = secrets.sonarrApiKey;
                enableQueue = false;
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
                  "wanted"
                  "missing"
                  "queued"
                  "movies"
                ];
                url = "http://localhost:${toString radarrPort}";
                key = secrets.radarrApiKey;
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
                key = secrets.bazarrApiKey;
              };
            };
          }
        ];
      }
      {
        "Downloaders" = [
          {
            "SABnzbd" = {
              icon = "sabnzbd";
              href = "https://sabnzbd.${domain}";
              description = "Usenet Downloader";
              widget = {
                type = "sabnzbd";
                url = "http://localhost:${toString sabnzbdPort}";
                key = secrets.sabnzbdApiKey;
              };
            };
          }
          {
            "qBittorrent" = {
              icon = "qbittorrent";
              href = "https://qbittorrent.${domain}";
              description = "Torrent Downloader";
              widget = {
                type = "qbittorrent";
                url = "http://localhost:${toString qbittorrentPort}";
                fields = [
                  "leech"
                  "download"
                  "seed"
                  "upload"
                ];
                enableLeechProgress = false;
              };
            };
          }
        ];
      }
      {
        "Home Automation" = [
          {
            "Home Assistant" = {
              icon = "home-assistant";
              href = "https://homeassistant.${domain}";
              description = "Home Automation";
            };
          }
          {
            "Z-Wave JS UI" = {
              icon = "zwavejs2mqtt";
              href = "https://zwavejs.${domain}";
              description = "Z-Wave Network Manager";
            };
          }
        ];
      }
      {
        "System" = [
          {
            "Cockpit" = {
              icon = "cockpit";
              description = "Linux Admin UI";
              href = "https://cockpit.${domain}";
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
          disk = "/data";
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
    bookmarks = [
      {
        Hosting = [
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
        ];
      }
      {
        Usenet = [
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
        ];
      }
    ];
  };

  systemd.services.homepage-dashboard = {
    serviceConfig = {
      Environment = [
        "HOMEPAGE_ALLOWED_HOSTS=homepage.${domain}"
      ];
    };
  };
}

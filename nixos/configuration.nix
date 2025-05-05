{ config, lib, pkgs, ... }:

let
  domain = "spudbox.win";
  plex_port = "32400";
  tautulli_port = "8181";
  stash_port = "9999";
  sonarr_port = "8989";
  radarr_port = "7878";
  bazarr_port = "6767";
  sabnzbd_port = "8081";
  qbittorrent_port = "8082";
  caddy_admin_port = "2019";
  plex_token = "fix_me";
  tautulli_apikey = "fix_me";
  stash_apikey = "fix_me";
  sonarr_api_key = "fix_me";
  radarr_api_key = "fix_me";
  bazarr_api_key = "fix_me";
  sabnzbd_api_key = "fix_me";
in {
  imports = [
    ./hardware-configuration.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.networkmanager.enable = true;

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  system.copySystemConfiguration = true;
  system.stateVersion = "24.11";

  users.users.luds = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    password = "a";
  };

  environment.systemPackages = with pkgs; [
    vim
  ];

  services.openssh.enable = true;
  services.homepage-dashboard = {
    enable = true;
    listenPort = 3000;
    openFirewall = true;
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
              container = "plex";
              widgets = [
                {
                  type = "plex";
                  url = "http://plex:${plex_port}";
                  key = "${plex_token}";
                  fields = ["movies" "tv"];
                }
                {
                  type = "tautulli";
                  url = "http://tautulli:${tautulli_port}";
                  key = "${tautulli_apikey}";
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
              container = "overseerr";
            };
          }
          {
            "Stash" = {
              icon = "stash";
              href = "https://stash.${domain}";
              description = "Media Browser";
              container = "stash";
              widget = {
                type = "stash";
                url = "http://stash:${stash_port}";
                key = "${stash_apikey}";
                fields = ["scenes" "sceneSize"];
              };
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
              container = "sonarr";
              widget = {
                type = "sonarr";
                fields = ["wanted" "queued" "series"];
                url = "http://sonarr:${sonarr_port}";
                key = "${sonarr_api_key}";
                enableQueue = false;
              };
            };
          }
          {
            "Radarr" = {
              icon = "radarr";
              href = "https://radarr.${domain}";
              description = "Movie Management";
              container = "radarr";
              widget = {
                type = "radarr";
                fields = ["wanted" "missing" "queued" "movies"];
                url = "http://radarr:${radarr_port}";
                key = "${radarr_api_key}";
                enableQueue = false;
              };
            };
          }
          {
            "Bazarr" = {
              icon = "bazarr";
              href = "https://bazarr.${domain}";
              description = "Subtitles Management";
              container = "bazarr";
              widget = {
                type = "bazarr";
                fields = ["missingEpisodes" "missingMovies"];
                url = "http://bazarr:${bazarr_port}";
                key = "${bazarr_api_key}";
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
              container = "sabnzbd";
              widget = {
                type = "sabnzbd";
                url = "http://sabnzbd:${sabnzbd_port}";
                key = "${sabnzbd_api_key}";
              };
            };
          }
          {
            "qBittorrent" = {
              icon = "qbittorrent";
              href = "https://qbittorrent.${domain}";
              description = "Torrent Downloader";
              container = "qbittorrent";
              widget = {
                type = "qbittorrent";
                url = "http://qbittorrent:${qbittorrent_port}";
                fields = ["leech" "download" "seed" "upload"];
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
              container = "homeassistant";
            };
          }
          {
            "Z-Wave JS UI" = {
              icon = "zwavejs2mqtt";
              href = "https://zwavejs.${domain}";
              description = "Z-Wave Network Manager";
              container = "zwavejs";
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
              container = "tautulli";
            };
          }
          {
            "Caddy" = {
              icon = "caddy";
              description = "Service Gateway";
              container = "caddy";
              widget = {
                type = "caddy";
                fields = ["upstreams" "requests" "requests_failed"];
                url = "http://caddy:${caddy_admin_port}";
              };
            };
          }
        ];
      }
    ];
    widgets = [
      {
        "greeting" = {
          text_size = "2xl";
          text = "SpudBox";
        };
      }
      {
        "resources" = {
          cpu = true;
          memory = true;
          disk = "/data";
          cputemp = true;
          tempmin = 0;
          tempmax = 100;
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
        "Hosting" = [
          {
            "Cloudflare" = {
              href = "https://dash.cloudflare.com/";
              description = "DNS Provider";
              icon = "cloudflare";
            };
          }
          {
            "Namecheap" = {
              href = "https://ap.www.namecheap.com/";
              description = "Domain Registrar";
              icon = "namecheap";
            };
          }
        ];
      }
      {
        "Usenet" = [
          {
            "NZBGeek" = {
              href = "https://nzbgeek.info/dashboard.php?myaccount";
              description = "Usenet Indexer";
              icon = "mdi-multimedia";
            };
          }
          {
            "Frugal" = {
              href = "https://billing.frugalusenet.com/member";
              description = "Usenet Provider";
              icon = "mdi-multimedia";
            };
          }
        ];
      }
    ];
  };
}

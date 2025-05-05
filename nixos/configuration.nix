{ config, lib, pkgs, ... }:

let
  domain = "spudbox.win";

  plex_port = 32400;
  tautulli_port = 8181;
  sonarr_port = 8989;
  radarr_port = 7878;
  bazarr_port = 6767;
  whisparr_port = 6969;
  sabnzbd_port = 8081;
  qbittorrent_port = 8082;
  caddy_admin_port = 2019;
  overseerr_port = 5055;
  homeassistant_port = 8123;
  zwavejs_port = 8091;
  homepage_port = 3000;
  cockpit_port = 9090;
  ariang_port = 6880;
  aria2_port = 6800;
  stash_port = 9999;
  stashvr_port = 9666;

  plex_token = "fix_me";
  tautulli_apikey = "fix_me";
  stash_apikey = "fix_me";
  sonarr_api_key = "fix_me";
  radarr_api_key = "fix_me";
  bazarr_api_key = "fix_me";
  sabnzbd_api_key = "fix_me";
  cloudflare_api_token = "fix_me";
  aria2_secret = "fix_me";

  admin_username = "fix_me";
  admin_password_hash = "fix_me";

  hostIP = "192.168.42.129";

  encodeBase64 = str:
    builtins.readFile (pkgs.runCommand "encoded" {} ''
      echo -n "${str}" | ${pkgs.coreutils}/bin/base64 -w0 > $out
    '');

  aria2_secret_encoded = encodeBase64 aria2_secret;
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
    listenPort = homepage_port;
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
                  url = "http://plex:${toString plex_port}";
                  key = "${plex_token}";
                  fields = ["movies" "tv"];
                }
                {
                  type = "tautulli";
                  url = "http://tautulli:${toString tautulli_port}";
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
                url = "http://stash:${toString stash_port}";
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
                url = "http://sonarr:${toString sonarr_port}";
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
                url = "http://radarr:${toString radarr_port}";
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
                url = "http://bazarr:${toString bazarr_port}";
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
                url = "http://sabnzbd:${toString sabnzbd_port}";
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
                url = "http://qbittorrent:${toString qbittorrent_port}";
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
                url = "http://caddy:${toString caddy_admin_port}";
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

  services.caddy = {
    enable = false;
    # FIX!
    #package = pkgs.caddy.withPlugins (plugins: [ plugins.cloudflare ]);
    configFile = pkgs.writeText "Caddyfile" ''
      {
        admin 0.0.0.0:${toString caddy_admin_port}
        # Wait for latest version!!
        #auto_https prefer_wildcard
      }

      *.${domain} {
        tls {
          issuer acme {
            dns cloudflare ${cloudflare_api_token}
            resolvers 1.1.1.1
            disable_http_challenge
            disable_tlsalpn_challenge
            preferred_chains smallest
          }
        }
      }

      (common_auth) {
        basic_auth {
          ${admin_username} ${admin_password_hash}
        }
      }

      sonarr.${domain} {
        reverse_proxy sonarr:${toString sonarr_port}
      }

      radarr.${domain} {
        reverse_proxy radarr:${toString radarr_port}
      }

      whisparr.${domain} {
        reverse_proxy whisparr:${toString whisparr_port}
      }

      bazarr.${domain} {
        reverse_proxy bazarr:${toString bazarr_port}
      }

      qbittorrent.${domain} {
        import common_auth
        reverse_proxy qbittorrent:${toString qbittorrent_port}
      }

      sabnzbd.${domain} {
        reverse_proxy sabnzbd:${toString sabnzbd_port}
      }

      plex.${domain} {
        reverse_proxy plex:${toString plex_port}
      }

      tautulli.${domain} {
        reverse_proxy tautulli:${toString tautulli_port}
      }

      overseerr.${domain} {
        reverse_proxy overseerr:${toString overseerr_port}
      }

      homeassistant.${domain} {
        reverse_proxy ${hostIP}:${toString homeassistant_port}
      }

      zwavejs.${domain} {
        import common_auth
        reverse_proxy zwavejs:${toString zwavejs_port}
      }

      homepage.${domain} {
        reverse_proxy homepage:${toString homepage_port}
      }

      cockpit.${domain} {
        reverse_proxy https://${hostIP}:${toString cockpit_port} {
          transport http {
            tls_insecure_skip_verify
          }
        }
      }

      ariang.${domain} {
        @no_cookie {
          not header Cookie *visited=*
        }
        handle @no_cookie {
          header Set-Cookie "visited=true; Path=/; Max-Age=31536000"
          redir "https://ariang.${domain}/#!/settings/rpc/set/https/aria2.${domain}/443/jsonrpc/${aria2_secret_encoded}" 302
        }
        handle {
          reverse_proxy ariang:${toString ariang_port}
        }
      }

      aria2.${domain} {
        reverse_proxy aria2:${toString aria2_port}
      }

      stash.${domain} {
        reverse_proxy stash:${toString stash_port}
      }

      stashvr.${domain} {
        reverse_proxy stashvr:${toString stashvr_port}
      }
    '';
  };
}

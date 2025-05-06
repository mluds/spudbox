{
  config,
  pkgs,
  ...
}:

let
  domain = "dev.spudbox.win";

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

  plexToken = "fix_me";
  tautulliApiKey = "fix_me";
  stashApiKey = "fix_me";
  sonarrApiKey = "fix_me";
  radarrApiKey = "fix_me";
  bazarrApiKey = "fix_me";
  sabnzbdApiKey = "fix_me";
  cloudflareApiToken = "fix_me";
  aria2Secret = "fix_me";

  adminUsername = "admin";
  adminPassword = "admin";
  adminPasswordHash = "fix_me";

  hostIp = "192.168.42.129";

  encodeBase64 =
    str:
    builtins.readFile (
      pkgs.runCommand "encoded" { } ''
        echo -n "${str}" | ${pkgs.coreutils}/bin/base64 -w0 > $out
      ''
    );

  aria2SecretEncoded = encodeBase64 aria2Secret;
in
{
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

  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
  };

  users.groups.media = {};
  users.groups.sonarr = {};

  users.users.luds = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    password = "a";
  };

  users.users.sonarr = {
    isSystemUser = true;
    group = "sonarr";
    extraGroups = [ "media" ];
    createHome = false;
    useDefaultShell = false;
  };

  environment.systemPackages = with pkgs; [
    vim
    pkgs.xmlstarlet
    ed
  ];

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 80 443 ];
  };

  services.openssh.enable = true;
  services.homepage-dashboard = {
    enable = true;
    listenPort = homepagePort;
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
                  url = "http://plex:${toString plexPort}";
                  key = "${plexToken}";
                  fields = [
                    "movies"
                    "tv"
                  ];
                }
                {
                  type = "tautulli";
                  url = "http://tautulli:${toString tautulliPort}";
                  key = "${tautulliApiKey}";
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
                url = "http://stash:${toString stashPort}";
                key = "${stashApiKey}";
                fields = [
                  "scenes"
                  "sceneSize"
                ];
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
                fields = [
                  "wanted"
                  "queued"
                  "series"
                ];
                url = "http://sonarr:${toString sonarrPort}";
                key = "${sonarrApiKey}";
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
                fields = [
                  "wanted"
                  "missing"
                  "queued"
                  "movies"
                ];
                url = "http://radarr:${toString radarrPort}";
                key = "${radarrApiKey}";
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
                fields = [
                  "missingEpisodes"
                  "missingMovies"
                ];
                url = "http://bazarr:${toString bazarrPort}";
                key = "${bazarrApiKey}";
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
                url = "http://sabnzbd:${toString sabnzbdPort}";
                key = "${sabnzbdApiKey}";
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
                url = "http://qbittorrent:${toString qbittorrentPort}";
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
                fields = [
                  "upstreams"
                  "requests"
                  "requests_failed"
                ];
                url = "http://caddy:${toString caddyAdminPort}";
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
    configFile = pkgs.writeText "Caddyfile" ''
      {
        admin 0.0.0.0:${toString caddyAdminPort}
      }

      *.${domain} {
        tls {
          issuer acme {
            dns cloudflare ${cloudflareApiToken}
            resolvers 1.1.1.1
            disable_http_challenge
            disable_tlsalpn_challenge
            preferred_chains smallest
          }
        }
      }

      (common_auth) {
        basic_auth {
          ${adminUsername} ${adminPasswordHash}
        }
      }

      sonarr.${domain} {
        reverse_proxy sonarr:${toString sonarrPort}
      }

      radarr.${domain} {
        reverse_proxy radarr:${toString radarrPort}
      }

      whisparr.${domain} {
        reverse_proxy whisparr:${toString whisparrPort}
      }

      bazarr.${domain} {
        reverse_proxy bazarr:${toString bazarrPort}
      }

      qbittorrent.${domain} {
        import common_auth
        reverse_proxy qbittorrent:${toString qbittorrentPort}
      }

      sabnzbd.${domain} {
        reverse_proxy sabnzbd:${toString sabnzbdPort}
      }

      plex.${domain} {
        reverse_proxy plex:${toString plexPort}
      }

      tautulli.${domain} {
        reverse_proxy tautulli:${toString tautulliPort}
      }

      overseerr.${domain} {
        reverse_proxy overseerr:${toString overseerrPort}
      }

      homeassistant.${domain} {
        reverse_proxy ${hostIp}:${toString homeassistantPort}
      }

      zwavejs.${domain} {
        import common_auth
        reverse_proxy zwavejs:${toString zwavejsPort}
      }

      homepage.${domain} {
        reverse_proxy homepage:${toString homepagePort}
      }

      cockpit.${domain} {
        reverse_proxy https://${hostIp}:${toString cockpitPort} {
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
          redir "https://ariang.${domain}/#!/settings/rpc/set/https/aria2.${domain}/443/jsonrpc/${aria2SecretEncoded}" 302
        }
        handle {
          reverse_proxy ariang:${toString ariangPort}
        }
      }

      aria2.${domain} {
        reverse_proxy aria2:${toString aria2Port}
      }

      stash.${domain} {
        reverse_proxy stash:${toString stashPort}
      }

      stashvr.${domain} {
        reverse_proxy stashvr:${toString stashvrPort}
      }
    '';
  };

  services.sonarr = {
    enable = true;
    user = "sonarr";
    openFirewall = true;
  };

  system.activationScripts.sonarrConfig = let
    xmlstarlet = "${pkgs.xmlstarlet}/bin/xmlstarlet";
    cfgFile = "${config.services.sonarr.dataDir}/config.xml";
  in ''
    ${xmlstarlet} ed -L \
      --subnode '/Config[not(Authentication)]' -t elem -n Authentication \
      --subnode '/Config/Authentication[not(Username)]' -t elem -n Username \
      --subnode '/Config/Authentication[not(Password)]' -t elem -n Password \
      -u "/Config/AuthenticationMethod" -v "Forms" \
      -u "/Config/Authentication/Username" -v "${adminUsername}" \
      -u "/Config/Authentication/Password" -v "${adminPassword}" \
      -u "/Config/ApiKey" -v "${sonarrApiKey}" \
      "${cfgFile}"
    if ${config.systemd.package}/bin/systemctl -q is-active sonarr.service; then
      ${config.systemd.package}/bin/systemctl restart sonarr.service
    fi
  '';
}

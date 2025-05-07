{ config, pkgs, ... }:

with config.my;

{
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
          ${builtins.readFile adminUsernamePath} ${adminPasswordHash}
        }
      }

      sonarr.${domain} {
        reverse_proxy sonarr:${sonarrPort}
      }

      radarr.${domain} {
        reverse_proxy radarr:${radarrPort}
      }

      whisparr.${domain} {
        reverse_proxy whisparr:${whisparrPort}
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
          redir "https://ariang.${domain}/#!/settings/rpc/set/https/aria2.${domain}/443/jsonrpc/${encodeBase64 aria2Secret}" 302
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
}

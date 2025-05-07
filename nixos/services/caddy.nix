{ config, pkgs, secrets, ... }:

with config.my;

{
  services.caddy = {
    enable = false;
    configFile = pkgs.writeText "Caddyfile" ''
      {
        admin 0.0.0.0:${caddyAdminPort}
      }

      *.${domain} {
        tls {
          issuer acme {
            dns cloudflare ${secrets.cloudflareApiToken}
            resolvers 1.1.1.1
            disable_http_challenge
            disable_tlsalpn_challenge
            preferred_chains smallest
          }
        }
      }

      (common_auth) {
        basic_auth {
          ${secrets.adminUsername} ${adminPasswordHash}
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
        reverse_proxy bazarr:${bazarrPort}
      }

      qbittorrent.${domain} {
        import common_auth
        reverse_proxy qbittorrent:${qbittorrentPort}
      }

      sabnzbd.${domain} {
        reverse_proxy sabnzbd:${sabnzbdPort}
      }

      plex.${domain} {
        reverse_proxy plex:${plexPort}
      }

      tautulli.${domain} {
        reverse_proxy tautulli:${tautulliPort}
      }

      overseerr.${domain} {
        reverse_proxy overseerr:${overseerrPort}
      }

      homeassistant.${domain} {
        reverse_proxy ${hostIp}:${homeassistantPort}
      }

      zwavejs.${domain} {
        import common_auth
        reverse_proxy zwavejs:${zwavejsPort}
      }

      homepage.${domain} {
        reverse_proxy homepage:${homepagePort}
      }

      cockpit.${domain} {
        reverse_proxy https://${hostIp}:${cockpitPort} {
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
          redir "https://ariang.${domain}/#!/settings/rpc/set/https/aria2.${domain}/443/jsonrpc/${encodeBase64 secrets.aria2Secret}" 302
        }
        handle {
          reverse_proxy ariang:${ariangPort}
        }
      }

      aria2.${domain} {
        reverse_proxy aria2:${aria2Port}
      }

      stash.${domain} {
        reverse_proxy stash:${stashPort}
      }

      stashvr.${domain} {
        reverse_proxy stashvr:${stashvrPort}
      }
    '';
  };
}

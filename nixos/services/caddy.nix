{ config, pkgs, secrets, ... }:

with config.my;

{
  services.caddy = {
    enable = true;
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/cloudflare@v0.2.1" ];
      hash = "sha256-saKJatiBZ4775IV2C5JLOmZ4BwHKFtRZan94aS5pO90=";
    };
    configFile = pkgs.writeText "Caddyfile" ''
      {
        admin 0.0.0.0:${toString caddyAdminPort}
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
          ${secrets.adminUsername} ${builtins.readFile (bcryptHash secrets.adminPassword)}
        }
      }

      sonarr.${domain} {
        reverse_proxy localhost:${toString sonarrPort}
      }

      radarr.${domain} {
        reverse_proxy localhost:${toString radarrPort}
      }

      whisparr.${domain} {
        reverse_proxy localhost:${toString whisparrPort}
      }

      bazarr.${domain} {
        reverse_proxy localhost:${toString bazarrPort}
      }

      qbittorrent.${domain} {
        import common_auth
        reverse_proxy localhost:${toString qbittorrentPort}
      }

      sabnzbd.${domain} {
        reverse_proxy localhost:${toString sabnzbdPort}
      }

      plex.${domain} {
        reverse_proxy localhost:${toString plexPort}
      }

      tautulli.${domain} {
        reverse_proxy localhost:${toString tautulliPort}
      }

      jellyseerr.${domain} {
        reverse_proxy localhost:${toString jellyseerrPort}
      }

      homeassistant.${domain} {
        reverse_proxy ${hostIp}:${toString homeassistantPort}
      }

      zwavejs.${domain} {
        import common_auth
        reverse_proxy localhost:${toString zwavejsPort}
      }

      homepage.${domain} {
        reverse_proxy localhost:${toString homepagePort}
      }

      cockpit.${domain} {
        reverse_proxy https://localhost:${toString cockpitPort} {
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
          reverse_proxy localhost:${toString ariangPort}
        }
      }

      aria2.${domain} {
        reverse_proxy localhost:${toString aria2Port}
      }

      stash.${domain} {
        reverse_proxy localhost:${toString stashPort}
      }

      stashvr.${domain} {
        reverse_proxy localhost:${toString stashvrPort}
      }
    '';
  };
}

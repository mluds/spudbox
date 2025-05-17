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

      prowlarr.${domain} {
        reverse_proxy localhost:${toString prowlarrPort}
      }

      transmission.${domain} {
        reverse_proxy localhost:${toString transmissionPort}
      }

      sabnzbd.${domain} {
        reverse_proxy localhost:${toString sabnzbdPort}
      }

      plex.${domain} {
        reverse_proxy localhost:${toString plexPort} {
          header_up X-Real-IP {http.request.remote.host}
          header_up X-Forwarded-For {http.request.remote.host}
          header_up X-Forwarded-Proto {http.request.scheme}
          header_up X-Plex-Client-Identifier {http.request.header.X-Plex-Client-Identifier}
          header_up X-Plex-Device {http.request.header.X-Plex-Device}
          header_up X-Plex-Device-Name {http.request.header.X-Plex-Device-Name}
          header_up X-Plex-Platform {http.request.header.X-Plex-Platform}
          header_up X-Plex-Platform-Version {http.request.header.X-Plex-Platform-Version}
          header_up X-Plex-Product {http.request.header.X-Plex-Product}
          header_up X-Plex-Token {http.request.header.X-Plex-Token}
          header_up X-Plex-Version {http.request.header.X-Plex-Version}
          header_up X-Plex-Nocache {http.request.header.X-Plex-Nocache}
          header_up X-Plex-Provides {http.request.header.X-Plex-Provides}
          header_up X-Plex-Device-Vendor {http.request.header.X-Plex-Device-Vendor}
          header_up X-Plex-Model {http.request.header.X-Plex-Model}
        }
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

{ config, pkgs, secrets, ... }:

with config.my;

let
  cloudflareTokenFile = "${secretsDir}/cloudflare/api-token";
in
{
  # Service to read and validate the Cloudflare API token file
  systemd.services.caddy-cloudflare-token = {
    description = "Prepare Cloudflare API token for Caddy";
    wantedBy = [ "caddy.service" ];
    before = [ "caddy.service" ];
    path = with pkgs; [ bash ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "read-cloudflare-token" ''
        set -e

        if [ ! -f "${cloudflareTokenFile}" ]; then
          echo "Error: Cloudflare API token file not found at ${cloudflareTokenFile}"
          exit 1
        fi

        token=$(cat "${cloudflareTokenFile}" | tr -d '[:space:]')

        if [ -z "$token" ]; then
          echo "Error: Cloudflare API token is empty in ${cloudflareTokenFile}"
          exit 1
        fi

        echo "Cloudflare API token loaded successfully"
      '';
    };
  };

  services.caddy = {
    enable = true;
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/cloudflare@v0.2.1" ];
      hash = "sha256-S1JN7brvH2KIu7DaDOH1zij3j8hWLLc0HdnUc+L89uU=";
    };
    configFile = pkgs.writeText "Caddyfile" ''
      {
        admin 0.0.0.0:${toString caddyAdminPort}
      }

      *.${domain} {
        tls {
          issuer acme {
            dns cloudflare {env.CLOUDFLARE_API_TOKEN}
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

      homepage.${domain} {
        reverse_proxy localhost:${toString homepagePort}
      }

      homebridge.${domain} {
        reverse_proxy localhost:${toString homebridgePort}
      }

      audiobookshelf.${domain} {
        encode gzip zstd
        reverse_proxy localhost:${toString audiobookshelfPort}
      }

      ttyd.${domain} {
        reverse_proxy localhost:${toString ttydPort}
      }
    '';

    # Set environment variable for Caddy service
    environmentFile = cloudflareTokenFile;
  };

  # Ensure the secrets directory exists and has proper permissions
  system.activationScripts.cloudflare-secrets = ''
    mkdir -p ${secretsDir}/cloudflare
    chmod 700 ${secretsDir}
    chmod 700 ${secretsDir}/cloudflare
    if [ -f "${cloudflareTokenFile}" ]; then
      chmod 600 ${cloudflareTokenFile}
    fi
  '';
}

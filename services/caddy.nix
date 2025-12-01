{ config, pkgs, secrets, ... }:

with config.my;

let
  # Script to generate the bcrypt hash and environment file
  hashScript = pkgs.writeScriptBin "caddy-generate-env" ''
    #!/bin/sh
    set -e

    ADMIN_USERNAME=$(cat ${secretsDir}/admin/username)
    ADMIN_PASSWORD=$(cat ${secretsDir}/admin/password)

    # Generate bcrypt hash
    ADMIN_PASSWORD_HASH=$(${pkgs.apacheHttpd}/bin/htpasswd -nBb -C 10 "$ADMIN_USERNAME" "$ADMIN_PASSWORD" | cut -d: -f2)

    # Create environment file
    cat > /run/caddy/env << EOF
    ADMIN_USERNAME=$ADMIN_USERNAME
    ADMIN_PASSWORD_HASH=$ADMIN_PASSWORD_HASH
    CLOUDFLARE_API_TOKEN=$(cat ${secretsDir}/cloudflare/api-token)
    EOF

    chmod 600 /run/caddy/env
  '';
in {
  services.caddy = {
    enable = true;
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/cloudflare@v0.2.1" ];
      hash = "sha256-S1JN7brvH2KIu7DaDOH1zij3j8hWLLc0HdnUc+L89uU=";
    };
    environmentFile = "/run/caddy/env";
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
          {env.ADMIN_USERNAME} {env.ADMIN_PASSWORD_HASH}
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
  };

  systemd.services.caddy-generate-env = {
    description = "Generate environment file for Caddy";
    wantedBy = [ "multi-user.target" ];
    before = [ "caddy.service" ];
    path = with pkgs; [ apacheHttpd ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = "${hashScript}/bin/caddy-generate-env";
    };
  };

  systemd.tmpfiles.rules = [
    "d /run/caddy 0755 root root -"
  ];
}

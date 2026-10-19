{ config, pkgs, ... }:

with config.my;

let
  caddyFile = "/etc/caddy/Caddyfile";
  configScript = pkgs.writeScriptBin "caddy-config" ''
    #!/bin/sh
    set -e

    # Read secrets from files
    CLOUDFLARE_API_TOKEN=$(cat ${secretsDir}/cloudflare/api-token)

    mkdir -p /etc/caddy

    cat > ${caddyFile} << CADDYEOF
    {
      admin localhost:${toString caddyAdminPort}
    }

    *.${domain} {
      tls {
        issuer acme {
          dns cloudflare $CLOUDFLARE_API_TOKEN
          resolvers 1.1.1.1
          disable_http_challenge
          disable_tlsalpn_challenge
          preferred_chains smallest
        }
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
    CADDYEOF

    chown caddy:caddy ${caddyFile}
    chmod 640 ${caddyFile}
  '';
in
{
  systemd.services.caddy-config = {
    description = "Caddy configuration";
    wantedBy = [ "caddy.service" ];
    before = [ "caddy.service" ];
    serviceConfig = {
      User = "root";
      Type = "oneshot";
      ExecStart = "${configScript}/bin/caddy-config";
    };
  };

  services.caddy = {
    enable = true;
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/cloudflare@v0.2.4" ];
      hash = "sha256-xRJ5evsAJ2akg47j3Bt6YDXJOgX88B/rKNP50KSVyNY=";
    };
    configFile = caddyFile;
  };
}

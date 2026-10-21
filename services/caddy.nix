{
  config,
  lib,
  pkgs,
  ...
}:

with config.my;

let
  # The Cloudflare token reaches Caddy only through its environment, so it
  # isn't in the Caddyfile or in the config served by the admin API (which
  # shows the {env.*} placeholder).
  envFile = "/run/caddy-config/caddy.env";
  configScript = pkgs.writeShellApplication {
    name = "caddy-config";
    text = ''
      umask 077
      mkdir -p "$(dirname ${envFile})"
      printf 'CLOUDFLARE_API_TOKEN=%s\n' "$(cat ${secretsDir}/cloudflare/api-token)" > ${envFile}
    '';
  };

  # Each one is served at https://<name>.${domain} -> localhost:<port>.
  # Caddy passes request headers (X-Plex-*) through and sets
  # X-Forwarded-For/-Proto itself; Plex only needs X-Real-IP added.
  proxies = {
    audiobookshelf = {
      port = audiobookshelfPort;
      extraConfig = "encode gzip zstd";
    };
    bazarr.port = bazarrPort;
    homebridge.port = homebridgePort;
    homepage.port = homepagePort;
    jellyseerr.port = jellyseerrPort;
    plex = {
      port = plexPort;
      proxyConfig = "header_up X-Real-IP {http.request.remote.host}";
    };
    prowlarr.port = prowlarrPort;
    radarr.port = radarrPort;
    sabnzbd.port = sabnzbdPort;
    sonarr.port = sonarrPort;
    tautulli.port = tautulliPort;
    transmission.port = transmissionPort;
  };

  virtualHost =
    {
      port,
      extraConfig ? "",
      proxyConfig ? null,
    }:
    {
      # No per-site access logs: Plex clients send X-Plex-Token in the query
      # string, which would end up on disk.
      logFormat = null;
      extraConfig = ''
        ${extraConfig}
        reverse_proxy localhost:${toString port}${
          lib.optionalString (proxyConfig != null) " {\n  ${proxyConfig}\n}"
        }
      '';
    };
in
{
  systemd.services.caddy-config = {
    description = "Caddy configuration";
    wantedBy = [ "caddy.service" ];
    before = [ "caddy.service" ];
    serviceConfig = {
      User = "root";
      Type = "oneshot";
      ExecStart = lib.getExe configScript;
    };
  };

  services.caddy = {
    enable = true;
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/cloudflare@v0.2.4" ];
      hash = "sha256-xRJ5evsAJ2akg47j3Bt6YDXJOgX88B/rKNP50KSVyNY=";
    };
    environmentFile = envFile;
    globalConfig = "admin localhost:${toString caddyAdminPort}";
    # Keep Caddy's own default (INFO, e.g. certificate renewals) in the journal.
    logFormat = "level INFO";
    # One wildcard certificate (DNS challenge) covers every subdomain.
    extraConfig = ''
      *.${domain} {
        tls {
          issuer acme {
            dns cloudflare {env.CLOUDFLARE_API_TOKEN}
            resolvers 1.1.1.1
            disable_http_challenge
            disable_tlsalpn_challenge
          }
        }
      }
    '';
    virtualHosts = lib.mapAttrs' (
      name: proxy: lib.nameValuePair "${name}.${domain}" (virtualHost proxy)
    ) proxies;
  };

  # caddy-config only runs before caddy starts (wantedBy), so restart caddy
  # when the script changes. Caddyfile changes reload Caddy on their own.
  systemd.services.caddy.restartTriggers = [ configScript ];

  # For test.sh: the proxied subdomains.
  environment.etc."spudbox/env".text = lib.toShellVar "CADDY_HOSTS" (lib.attrNames proxies);
}

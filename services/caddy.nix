{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.spudbox;
  inherit (cfg) secretsDir domain caddyAdminPort;
  cloudflare = cfg.tls == "cloudflare";

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

  # Each one is served at https://<name>.${domain} -> localhost:spudbox.<name>Port.
  # Caddy passes request headers (X-Plex-*) through and sets
  # X-Forwarded-For/-Proto itself; Plex only needs X-Real-IP added.
  proxyExtras = {
    audiobookshelf.extraConfig = "encode gzip zstd";
    plex.proxyConfig = "header_up X-Real-IP {http.request.remote.host}";
  };
  proxies = lib.genAttrs (
    [
      "audiobookshelf"
      "bazarr"
    ]
    ++ lib.optional cfg.homebridge.enable "homebridge"
    ++ [
      "homepage"
      "jellyseerr"
      "plex"
      "radarr"
      "sabnzbd"
      "sonarr"
      "tautulli"
      "transmission"
    ]
  ) (name: { port = cfg."${name}Port"; } // proxyExtras.${name} or { });

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
      # LAN only (private_ranges includes loopback), even if 80/443 were ever
      # port-forwarded by mistake. Remote Plex goes to 32400 directly.
      extraConfig = ''
        @outside not remote_ip private_ranges
        respond @outside 403
        ${extraConfig}
        reverse_proxy localhost:${toString port}${
          lib.optionalString (proxyConfig != null) " {\n  ${proxyConfig}\n}"
        }
      '';
    };
in
{
  systemd.services = {
    caddy-config = lib.mkIf cloudflare {
      description = "Caddy configuration";
      wantedBy = [ "caddy.service" ];
      before = [ "caddy.service" ];
      serviceConfig.ExecStart = lib.getExe configScript;
    };

    # The module sets only NoNewPrivileges, PrivateDevices and ProtectHome.
    # Caddy needs nothing but binding 80/443 (and outbound HTTPS for ACME).
    caddy.serviceConfig = {
      # "" resets upstream's unit, which also grants CAP_NET_ADMIN (only for
      # bigger HTTP/3 UDP buffers; Caddy logs a warning without it).
      CapabilityBoundingSet = [
        ""
        "CAP_NET_BIND_SERVICE"
      ];
      AmbientCapabilities = [
        ""
        "CAP_NET_BIND_SERVICE"
      ];
      ProtectSystem = "strict";
      PrivateTmp = true;
      ProtectProc = "invisible";
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      ProtectClock = true;
      ProtectHostname = true;
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      RemoveIPC = true;
      SystemCallArchitectures = "native";
      RestrictAddressFamilies = [
        "AF_UNIX"
        "AF_INET"
        "AF_INET6"
      ];
    };

    # caddy-config only runs before caddy starts (wantedBy), so restart caddy
    # when the script changes. Caddyfile changes reload Caddy on their own.
    caddy.restartTriggers = lib.mkIf cloudflare [ configScript ];
  };

  services.caddy = {
    enable = true;
    package = lib.mkIf cloudflare (
      pkgs.caddy.withPlugins {
        plugins = [ "github.com/caddy-dns/cloudflare@v0.2.4" ];
        hash = "sha256-xRJ5evsAJ2akg47j3Bt6YDXJOgX88B/rKNP50KSVyNY=";
      }
    );
    environmentFile = lib.mkIf cloudflare envFile;
    # local_certs: every site gets a certificate from Caddy's own CA.
    globalConfig =
      "admin localhost:${toString caddyAdminPort}" + lib.optionalString (!cloudflare) "\nlocal_certs";
    # Keep Caddy's own default (INFO, e.g. certificate renewals) in the journal.
    logFormat = "level INFO";
    # One wildcard certificate (DNS challenge) covers every subdomain.
    extraConfig = lib.mkIf cloudflare ''
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

  # For test.sh: the proxied subdomains.
  environment.etc."spudbox/env".text = lib.toShellVar "CADDY_HOSTS" (lib.attrNames proxies);
}

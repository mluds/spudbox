{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (config.my)
    cacheDir
    sabnzbdPort
    secretsDir
    usenetServerHosts
    usenetServerPort
    ;

  # Placeholder in settings -> secret file. systemd copies each file into the
  # unit's credentials dir (readable by the sabnzbd user only), and the
  # module's preStart substitutes them into sabnzbd.ini (mode 600).
  credentials = {
    admin_username = "admin/username";
    web_password = "sabnzbd/password";
    api_key = "sabnzbd/api-key";
    nzb_key = "sabnzbd/nzb-key";
    usenet_username = "usenet/username";
    usenet_password = "usenet/password";
  };
  secret = name: "@${name}@";

  category = order: dir: {
    name = dir;
    inherit order dir;
  };
in
{
  # Only values that differ from SABnzbd's (or the NixOS module's) defaults.
  # The existing sabnzbd.ini is merged underneath (allowConfigWrite), so
  # settings changed in the web UI survive until they're set here.
  services.sabnzbd = {
    enable = true;
    user = "sabnzbd";
    group = "media";
    openFirewall = false;
    configFile = null;
    allowConfigWrite = true;
    secretValues = lib.mapAttrs' (
      name: _: lib.nameValuePair (secret name) "/run/credentials/sabnzbd.service/${name}"
    ) credentials;
    settings = {
      misc = {
        host = "127.0.0.1"; # loopback only; reached through Caddy
        port = sabnzbdPort;
        enable_https = false; # Caddy terminates TLS
        username = secret "admin_username";
        password = secret "web_password";
        api_key = secret "api_key";
        nzb_key = secret "nzb_key";
        inet_exposure = 3;
        verify_xff_header = false;
        download_dir = "${cacheDir}/data/usenet/incomplete";
        complete_dir = "${cacheDir}/data/usenet/complete";
        download_free = "";
        permissions = "775";
        cache_limit = "1G";
        direct_unpack = true;
        refresh_rate = 1;
        fixed_ports = true;
        bandwidth_perc = 100; # of bandwidth_max, which is unset (no limit)
        # Markers for one-time prompts and migrations already done. Keep
        # config_conversion_version at SABnzbd's latest, or it re-runs them.
        config_conversion_version = 5;
        notified_new_skin = 2;
        direct_unpack_tested = true;
        sorters_converted = true;
      };
      servers = lib.listToAttrs (
        lib.imap0 (
          priority: host:
          lib.nameValuePair host {
            name = host;
            displayname = host;
            inherit host priority;
            port = usenetServerPort;
            username = secret "usenet_username";
            password = secret "usenet_password";
            connections = 20;
            ssl_verify = "strict";
          }
        ) usenetServerHosts
      );
      categories = {
        "*" = {
          name = "*";
          order = 0;
          pp = 3;
          script = "None";
          priority = 0;
        };
        movies = category 1 "movies";
        tv = category 2 "tv";
        books = category 3 "books";
      };
    };
  };

  systemd = {
    services = {
      sabnzbd.serviceConfig = import ./hardening.nix // {
        UMask = "0002";
        # Private state (ini, queue, logs); downloads live under cacheDir
        StateDirectoryMode = "0700";
        LoadCredential = lib.mapAttrsToList (name: path: "${name}:${secretsDir}/${path}") credentials;
      };

      sabnzbd-resume = {
        description = "Resume SABnzbd if paused";
        # No Requires=: the nightly backup stops SABnzbd (see radarr-auto-import).
        after = [ "sabnzbd.service" ];
        serviceConfig = {
          Type = "oneshot";
          # Unprivileged; the API key arrives via LoadCredential and is sent
          # in a POST body from a file, never in the URL or on a command line.
          DynamicUser = true;
          RuntimeDirectory = "sabnzbd-resume";
          LoadCredential = "sabnzbd-api-key:${secretsDir}/sabnzbd/api-key";
          ExecStart = lib.getExe (
            pkgs.writeShellApplication {
              name = "sabnzbd-resume";
              runtimeInputs = with pkgs; [
                curl
                jq
              ];
              text = ''
                umask 077
                API="http://localhost:${toString sabnzbdPort}/api"
                KEY=$(tr -d '\n' < "$CREDENTIALS_DIRECTORY/sabnzbd-api-key")
                printf 'mode=queue&output=json&apikey=%s' "$KEY" > "$RUNTIME_DIRECTORY/queue"
                printf 'mode=resume&output=json&apikey=%s' "$KEY" > "$RUNTIME_DIRECTORY/resume"
                if ! QUEUE=$(curl -sS --fail -d @"$RUNTIME_DIRECTORY/queue" "$API"); then
                  echo "SABnzbd not reachable; will retry"
                  exit 0
                fi
                PAUSED=$(jq -r '.queue.paused' <<< "$QUEUE")
                if [ "$PAUSED" = "true" ]; then
                  echo "SABnzbd is paused, resuming..."
                  curl -sS --fail -o /dev/null -d @"$RUNTIME_DIRECTORY/resume" "$API"
                fi
              '';
            }
          );
        };
      };
    };

    timers.sabnzbd-resume = {
      description = "Periodically resume SABnzbd if paused";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "hourly";
        Persistent = true;
      };
    };
  };
}

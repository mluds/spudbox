{
  config,
  lib,
  pkgs,
  helpers,
  ...
}:

let
  cfg = config.spudbox;
  inherit (cfg)
    domain
    homebridgePort
    secretsDir
    ;

  # spudbox.homebridge.dummySwitches, added on first setup
  dummySwitch = {
    platform = "HomebridgeDummy";
    name = "HomebridgeDummy";
    accessories = map (name: {
      type = "Switch";
      inherit name;
      stateful = true;
    }) cfg.homebridge.dummySwitches;
  };

  configScript = pkgs.writeShellApplication {
    name = "homebridge-config";
    runtimeInputs = with pkgs; [
      curl
      jq
      docker
      helpers
    ];
    text = ''
      BASE="http://localhost:${toString homebridgePort}/api"
      CONFIG_JSON=/var/lib/homebridge/volumes/config.json

      echo "Waiting for Homebridge to start..."
      wait-for-http "$BASE/auth/settings"

      # Bind the UI to loopback; Caddy reaches it at homebridge.${domain}.
      # The container uses host networking, so this is the host's loopback.
      if [ "$(jq -r '.platforms[] | select(.platform == "config") | .host // ""' $CONFIG_JSON)" != 127.0.0.1 ]; then
        echo "Binding Homebridge UI to 127.0.0.1..."
        jq '(.platforms[] | select(.platform == "config")).host = "127.0.0.1"' $CONFIG_JSON > $CONFIG_JSON.tmp
        cat $CONFIG_JSON.tmp > $CONFIG_JSON
        rm -f $CONFIG_JSON.tmp
        systemctl restart homebridge.service
        wait-for-http "$BASE/auth/settings"
      fi

      # Credentials and session tokens reach curl through files (-d @file,
      # -H @file), never as arguments, which any local user could read from
      # /proc/<pid>/cmdline.
      umask 077
      TMP=$(mktemp -d)
      trap 'rm -rf "$TMP"' EXIT
      creds() { # USERNAME_FILE PASSWORD_FILE
        jq -n --rawfile u "$1" --rawfile p "$2" \
          '{username: ($u | rtrimstr("\n")), password: ($p | rtrimstr("\n"))}'
      }
      creds ${secretsDir}/admin/username ${secretsDir}/homebridge/password > "$TMP/login.json"

      # login CREDS_FILE: on success write "Authorization: Bearer ..." to $TMP/auth
      login() {
        local token
        token=$(curl -s -X POST -H "Content-Type: application/json" \
          -d @"$1" "$BASE/auth/login" | jq -r '.access_token // empty')
        [ -n "$token" ] || return 1
        printf 'Authorization: Bearer %s\n' "$token" > "$TMP/auth"
      }
      # api METHOD PATH [curl args...]
      api() {
        local method=$1 path=$2
        shift 2
        curl -s -X "$method" -H @"$TMP/auth" -H "Content-Type: application/json" "$BASE/$path" "$@"
      }

      if [ "$(curl -s "$BASE/auth/settings" | jq -r '.env.setupWizardComplete')" = true ]; then
        if ! login "$TMP/login.json"; then
          echo "ERROR: homebridge/password doesn't log in to Homebridge"
          exit 1
        fi
        echo "Homebridge already set up."
        exit 0
      fi

      echo "Getting setup wizard token..."
      printf 'Authorization: Bearer %s\n' \
        "$(curl -s "$BASE/setup-wizard/get-setup-wizard-token" | jq -r '.access_token')" > "$TMP/auth"

      echo "Creating admin user..."
      jq '. + {name: .username, admin: true}' "$TMP/login.json" \
        | api POST setup-wizard/create-first-user -d @- >/dev/null

      echo "Logging in..."
      login "$TMP/login.json"

      ${lib.optionalString (cfg.homebridge.dummySwitches != [ ]) ''
        echo "Installing homebridge-dummy plugin..."
        docker exec homebridge npm install homebridge-dummy@1.6.1

        echo "Adding dummy switches to config..."
        api GET config-editor | jq --argjson dummy ${lib.escapeShellArg (builtins.toJSON dummySwitch)} \
          '.platforms += [$dummy]' | api POST config-editor -d @- >/dev/null
      ''}
      echo "Restarting Homebridge..."
      api PUT server/restart >/dev/null

      echo "Waiting for Homebridge to come back..."
      sleep 5
      wait-for-http "$BASE/auth/settings"

      echo "Logging in again..."
      login "$TMP/login.json"

      echo "Resetting cached accessories..."
      api PUT server/reset-cached-accessories >/dev/null

      echo "Homebridge setup complete."
    '';
  };
in
lib.mkIf cfg.homebridge.enable {
  # Docker runs only Homebridge.
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };
  environment.systemPackages = [ pkgs.docker-compose ];

  systemd = {
    tmpfiles.rules = [
      # Private: volumes/ holds auth.json and config.json (container runs as root)
      "d /var/lib/homebridge 0700 root root -"
      "d /var/lib/homebridge/volumes 0700 root root -"
    ];

    services.homebridge = {
      description = "Homebridge Docker Service";
      after = [
        "network.target"
        "docker.service"
      ];
      requires = [ "docker.service" ];
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [ docker ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        ExecStartPre = "${pkgs.docker}/bin/docker compose -f /etc/homebridge/docker-compose.yml down";
        ExecStart = "${pkgs.docker}/bin/docker compose -f /etc/homebridge/docker-compose.yml up";
        ExecStop = "${pkgs.docker}/bin/docker compose -f /etc/homebridge/docker-compose.yml down";
        WorkingDirectory = "/var/lib/homebridge";
      };
    };

    services.homebridge-config = {
      description = "Configure Homebridge";
      after = [ "homebridge.service" ];
      wants = [ "homebridge.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = lib.getExe configScript;
      };
    };
  };

  services.avahi = {
    enable = true;
    reflector = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };

  # The UI port (homebridgePort) stays closed: the UI is served over TLS by
  # Caddy at https://homebridge.<domain>, which reaches it via loopback.
  networking.firewall = {
    allowedTCPPorts = [
      51215 # homebridge HAP bridge port
    ];
    allowedUDPPorts = [
      5353 # mDNS/Bonjour discovery
    ];
  };

  # Image pinned by date tag + digest so a container restart can't silently
  # upgrade Homebridge. To bump, see "Hand-pinned versions" in the README.
  environment.etc."homebridge/docker-compose.yml" = {
    text = ''
      services:
        homebridge:
          image: homebridge/homebridge:2026-02-25@sha256:180e4ba165c4474d13d4f74e1de655bfb5afcf16a4ff3233de000bea4b8e2904
          container_name: homebridge
          restart: unless-stopped
          network_mode: host
          environment:
            - TZ=${config.time.timeZone}
            - HOMEBRIDGE_CONFIG_UI=1
            - HOMEBRIDGE_CONFIG_UI_PORT=${toString homebridgePort}
          volumes:
            - /var/lib/homebridge/volumes:/homebridge
          logging:
            driver: json-file
            options:
              max-size: "10mb"
              max-file: "1"
    '';
    mode = "0644";
  };
}

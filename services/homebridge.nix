{ config, pkgs, ... }:

with config.my;

let
  configScript = pkgs.writeScriptBin "homebridge-config" ''
    #!/bin/sh
    set -e

    CURL="${pkgs.curl}/bin/curl"
    JQ="${pkgs.jq}/bin/jq"
    BASE="http://localhost:${toString homebridgePort}"

    echo "Waiting for Homebridge to start..."
    until $CURL -sSf "$BASE/api/auth/settings" >/dev/null 2>&1; do
      sleep 2
    done

    # Bind the UI to loopback; Caddy reaches it at homebridge.${domain}.
    # The container uses host networking, so this is the host's loopback.
    CONFIG_JSON=/var/lib/homebridge/volumes/config.json
    if [ "$($JQ -r '.platforms[] | select(.platform == "config") | .host // ""' $CONFIG_JSON)" != "127.0.0.1" ]; then
      echo "Binding Homebridge UI to 127.0.0.1..."
      $JQ '(.platforms[] | select(.platform == "config")).host = "127.0.0.1"' $CONFIG_JSON > $CONFIG_JSON.tmp
      cat $CONFIG_JSON.tmp > $CONFIG_JSON
      rm -f $CONFIG_JSON.tmp
      systemctl restart homebridge.service
      until $CURL -sSf "$BASE/api/auth/settings" >/dev/null 2>&1; do
        sleep 2
      done
    fi

    SETUP_COMPLETE=$($CURL -s "$BASE/api/auth/settings" | $JQ -r '.env.setupWizardComplete')
    if [ "$SETUP_COMPLETE" = "true" ]; then
      echo "Homebridge already set up, skipping."
      exit 0
    fi

    # Credentials and session tokens reach curl through files (-d @file,
    # -H @file), never as arguments, which any local user could read from
    # /proc/<pid>/cmdline.
    umask 077
    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT
    $JQ -n --rawfile u ${secretsDir}/admin/username --rawfile p ${secretsDir}/admin/password \
      '{username: ($u | rtrimstr("\n")), password: ($p | rtrimstr("\n"))}' > "$TMP/login.json"

    # login: write a fresh "Authorization: Bearer ..." header to $TMP/auth
    login() {
      TOKEN=$($CURL -s -X POST -H "Content-Type: application/json" \
        -d @"$TMP/login.json" "$BASE/api/auth/login" | $JQ -r '.access_token')
      printf 'Authorization: Bearer %s\n' "$TOKEN" > "$TMP/auth"
    }

    echo "Getting setup wizard token..."
    TOKEN=$($CURL -s "$BASE/api/setup-wizard/get-setup-wizard-token" | $JQ -r '.access_token')
    printf 'Authorization: Bearer %s\n' "$TOKEN" > "$TMP/auth"

    echo "Creating admin user..."
    $JQ '. + {name: .username, admin: true}' "$TMP/login.json" |
      $CURL -s -X POST -H "Content-Type: application/json" -H @"$TMP/auth" \
        -d @- "$BASE/api/setup-wizard/create-first-user" >/dev/null

    echo "Logging in..."
    login

    echo "Installing homebridge-dummy plugin..."
    ${pkgs.docker}/bin/docker exec homebridge npm install homebridge-dummy

    echo "Adding dummy switch to config..."
    $CURL -s -H @"$TMP/auth" "$BASE/api/config-editor" |
      $JQ '.platforms += [{"platform": "HomebridgeDummy", "name": "HomebridgeDummy", "accessories": [{"type": "Switch", "name": "Dummy Door Switch", "stateful": true}]}]' |
      $CURL -s -X POST -H @"$TMP/auth" -H "Content-Type: application/json" \
        -d @- "$BASE/api/config-editor" >/dev/null

    echo "Restarting Homebridge..."
    $CURL -s -X PUT -H @"$TMP/auth" "$BASE/api/server/restart" >/dev/null

    echo "Waiting for Homebridge to come back..."
    sleep 5
    until $CURL -sSf "$BASE/api/auth/settings" >/dev/null 2>&1; do
      sleep 2
    done

    echo "Logging in again..."
    login

    echo "Resetting cached accessories..."
    $CURL -s -X PUT -H @"$TMP/auth" "$BASE/api/server/reset-cached-accessories" >/dev/null

    echo "Homebridge setup complete."
  '';
in
{
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
        Type = "oneshot";
        User = "root";
        ExecStart = "${configScript}/bin/homebridge-config";
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
  # upgrade Homebridge. To bump, see "Hand-pinned versions" in CLAUDE.md.
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

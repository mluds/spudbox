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

    SETUP_COMPLETE=$($CURL -s "$BASE/api/auth/settings" | $JQ -r '.env.setupWizardComplete')
    if [ "$SETUP_COMPLETE" = "true" ]; then
      echo "Homebridge already set up, skipping."
      exit 0
    fi

    ADMIN_USERNAME=$(cat ${secretsDir}/admin/username)
    ADMIN_PASSWORD=$(cat ${secretsDir}/admin/password)

    echo "Getting setup wizard token..."
    SETUP_TOKEN=$($CURL -s "$BASE/api/setup-wizard/get-setup-wizard-token" | $JQ -r '.access_token')

    echo "Creating admin user..."
    $CURL -s -X POST -H "Content-Type: application/json" \
      -H "Authorization: Bearer $SETUP_TOKEN" \
      -d "{\"name\": \"$ADMIN_USERNAME\", \"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\", \"admin\": true}" \
      "$BASE/api/setup-wizard/create-first-user" >/dev/null

    echo "Logging in..."
    AUTH_TOKEN=$($CURL -s -X POST -H "Content-Type: application/json" \
      -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}" \
      "$BASE/api/auth/login" | $JQ -r '.access_token')

    AUTH="Authorization: Bearer $AUTH_TOKEN"

    echo "Installing homebridge-dummy plugin..."
    ${pkgs.docker}/bin/docker exec homebridge npm install homebridge-dummy

    echo "Adding dummy switch to config..."
    CONFIG=$($CURL -s -H "$AUTH" "$BASE/api/config-editor")
    UPDATED=$(echo "$CONFIG" | $JQ '.platforms += [{"platform": "HomebridgeDummy", "name": "HomebridgeDummy", "accessories": [{"type": "Switch", "name": "Dummy Door Switch", "stateful": true}]}]')
    echo "$UPDATED" | $CURL -s -X POST -H "$AUTH" -H "Content-Type: application/json" \
      -d @- "$BASE/api/config-editor" >/dev/null

    echo "Restarting Homebridge..."
    $CURL -s -X PUT -H "$AUTH" "$BASE/api/server/restart" >/dev/null

    echo "Waiting for Homebridge to come back..."
    sleep 5
    until $CURL -sSf "$BASE/api/auth/settings" >/dev/null 2>&1; do
      sleep 2
    done

    echo "Logging in again..."
    AUTH_TOKEN=$($CURL -s -X POST -H "Content-Type: application/json" \
      -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}" \
      "$BASE/api/auth/login" | $JQ -r '.access_token')
    AUTH="Authorization: Bearer $AUTH_TOKEN"

    echo "Resetting cached accessories..."
    $CURL -s -X PUT -H "$AUTH" "$BASE/api/server/reset-cached-accessories" >/dev/null

    echo "Homebridge setup complete."
  '';
in
{
  systemd = {
    tmpfiles.rules = [
      "d /var/lib/homebridge 0755 root root -"
      "d /var/lib/homebridge/volumes 0755 root root -"
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

  networking.firewall = {
    allowedTCPPorts = [
      homebridgePort
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

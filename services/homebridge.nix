{ config, pkgs, ... }:

with config.my;

{
  systemd.tmpfiles.rules = [
    "d /var/lib/homebridge 0755 root root -"
    "d /var/lib/homebridge/volumes 0755 root root -"
  ];

  networking.firewall = {
    allowedTCPPorts = [ homebridgePort ];
  };

  systemd.services.homebridge = {
    description = "Homebridge Docker Service";
    after = [ "network.target" "docker.service" ];
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

  environment.etc."homebridge/docker-compose.yml" = {
    text = ''
      version: '3'
      services:
        homebridge:
          image: homebridge/homebridge:latest
          container_name: homebridge
          restart: unless-stopped
          network_mode: host
          environment:
            - TZ=${config.time.timeZone}
            - HOMEBRIDGE_CONFIG_UI=1
            - HOMEBRIDGE_CONFIG_UI_PORT=8581
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

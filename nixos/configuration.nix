{ config, lib, pkgs, ... }:

let
  domain = "spudbox.win";
in {
  imports = [
    ./hardware-configuration.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.networkmanager.enable = true;

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  system.copySystemConfiguration = true;
  system.stateVersion = "24.11";

  users.users.luds = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    password = "a";
  };

  environment.systemPackages = with pkgs; [
    vim
  ];

  services.openssh.enable = true;
  services.homepage-dashboard = {
    enable = true;
    listenPort = 3000;
    openFirewall = true;
    settings = {
      title = "SpudBox";
      description = "Mike's Home Server";
      language = "en";
      theme = "dark";
      headerStyle = "underlined";
      disableCollapse = true;
    };
    services = [
      {
        "Media" = [
          {
            "Plex" = {
              icon = "plex";
              href = "https://plex.${domain}";
              description = "Media Server";
            };
          }
        ];
      }
      {
        "Media Management" = [
          {
            "Sonarr" = {
              icon = "sonarr";
              href = "https://sonarr.${domain}";
              description = "TV Show Management";
            };
          }
        ];
      }
    ];
  };
}

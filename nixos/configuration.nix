{ pkgs, lib, secrets, ... }:

{
  imports = [
    ./common/vars.nix
    ./environments/default.nix
    ./services/caddy.nix
    ./services/homepage.nix
    ./services/sonarr.nix
    ./services/sabnzbd.nix
  ];

  environment.systemPackages = with pkgs; [
    vim
    xmlstarlet
    ed
    sqlite
    python314
    openssl_3
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  networking.networkmanager.enable = true;
  programs.nix-ld.enable = true;
  services.openssh.enable = true;
    security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
  };

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
  system.stateVersion = "24.11";
  nixpkgs.config.allowUnfree = true;

  users.groups.media = {};

  users.users = lib.listToAttrs (lib.forEach secrets.users (user: {
    name = user.username;
    value = {
      isNormalUser = true;
      password = user.password;
      extraGroups = lib.optional user.superuser "wheel";
    };
  }));

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 80 443 ];
  };
}

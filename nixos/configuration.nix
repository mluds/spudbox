{ config, pkgs, lib, secrets, disko, ... }:

with config.my;

{
  imports = [
    ./common/vars.nix
    ./environments/default.nix
    ./services/caddy.nix
    ./services/homepage.nix
    ./services/sabnzbd.nix
    ./services/plex.nix
    ./services/transmission.nix
    ./services/servarr/sonarr.nix
    ./services/servarr/radarr.nix
    ./services/servarr/bazarr.nix
    ./services/servarr/jellyseerr.nix
    ./services/servarr/prowlarr.nix
  ];

  environment.systemPackages = with pkgs; [
    vim
    xmlstarlet
    ed
    sqlite
    python314
    openssl_3
    jq
    curl
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
  system.stateVersion = "25.05";
  nixpkgs.config.allowUnfree = true;

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 80 443 ];
  };

  systemd.tmpfiles.rules =
  let
    mediaDirs = [
      "${storageDir}/data/media/movies"
      "${storageDir}/data/media/tv"
      "${storageDir}/data/misc"
      "${cacheDir}/data"
      "${cacheDir}/data/usenet"
      "${cacheDir}/data/usenet/complete"
      "${cacheDir}/data/usenet/complete/movies"
      "${cacheDir}/data/usenet/complete/tv"
      "${cacheDir}/data/usenet/incomplete"
      "${cacheDir}/data/usenet/incomplete/movies"
      "${cacheDir}/data/usenet/incomplete/tv"
      "${cacheDir}/data/torrents"
      "${cacheDir}/data/torrents/complete"
      "${cacheDir}/data/torrents/complete/movies"
      "${cacheDir}/data/torrents/complete/tv"
      "${cacheDir}/data/torrents/incomplete"
      "${cacheDir}/data/torrents/incomplete/movies"
      "${cacheDir}/data/torrents/incomplete/tv"
      "${cacheDir}/data/downloads"
      "${cacheDir}/appdata"
    ];

    appdataDirs = [
      { path = "${appdataDir}/sabnzbd"; uid = "sabnzbd"; gid = "sabnzbd"; }
      { path = "${appdataDir}/radarr"; uid = "radarr"; gid = "radarr"; }
      { path = "${appdataDir}/sonarr"; uid = "sonarr"; gid = "sonarr"; }
      { path = "${appdataDir}/whisparr"; uid = "whisparr"; gid = "whisparr"; }
      { path = "${appdataDir}/bazarr"; uid = "bazarr"; gid = "bazarr"; }
      { path = "${appdataDir}/plex"; uid = "plex"; gid = "media"; }
      { path = "${appdataDir}/jellyseerr"; uid = "jellyseerr"; gid = "jellyseerr"; }
      { path = "${appdataDir}/qbittorrent/qBittorrent"; uid = "qbittorrent"; gid = "qbittorrent"; }
      { path = "${appdataDir}/caddy/conf"; uid = "caddy"; gid = "caddy"; }
      { path = "${appdataDir}/caddy/data"; uid = "caddy"; gid = "caddy"; }
      { path = "${appdataDir}/homeassistant"; uid = "homeassistant"; gid = "homeassistant"; }
      { path = "${appdataDir}/zwavejs"; uid = "zwavejs"; gid = "zwavejs"; }
      { path = "${appdataDir}/homepage"; uid = "homepage"; gid = "homepage"; }
      { path = "${appdataDir}/aria2/config"; uid = "aria2"; gid = "aria2"; }
      { path = "${appdataDir}/tautulli"; uid = "tautulli"; gid = "tautulli"; }
    ];
  in
    (map (path: "d ${path} 0775 media media - -") mediaDirs)
    ++
    (map (dir: "d ${dir.path} 0755 ${dir.uid} ${dir.gid} - -") appdataDirs);
}

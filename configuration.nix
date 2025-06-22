{ config, pkgs, lib, secrets, ... }:

with config.my;

let
  mediaDirs = [
    "${storageDir}/data/media/movies"
    "${storageDir}/data/media/tv"
    "${storageDir}/data/media/audiobooks"
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
    # { path = "${appdataDir}/sabnzbd"; uid = "sabnzbd"; gid = "sabnzbd"; }
  ];

  createDirsScript = pkgs.writeScript "create-media-dirs.sh" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    ${lib.concatMapStringsSep "\n" (dir: ''
      echo "Creating media directory: ${dir}"
      mkdir -p "${dir}"
      chown -R media:media "${dir}"
      chmod -R 0775 "${dir}"
    '') mediaDirs}

    ${lib.concatMapStringsSep "\n" (dir: ''
      echo "Creating appdata directory: ${dir.path} (owner: ${dir.uid}:${dir.gid})"
      mkdir -p "${dir.path}"
      chown ${dir.uid}:${dir.gid} "${dir.path}"
      chmod 0755 "${dir.path}"
    '') appdataDirs}
  '';
in {
  imports = [
    ./storage.nix
    ./common/vars.nix
    ./environments/default.nix
    ./services/caddy.nix
    ./services/homepage.nix
    ./services/sabnzbd.nix
    ./services/plex.nix
    ./services/transmission.nix
    ./services/tautulli.nix
    ./services/servarr/sonarr.nix
    ./services/servarr/radarr.nix
    ./services/servarr/bazarr.nix
    ./services/servarr/jellyseerr.nix
    ./services/servarr/prowlarr.nix
    ./services/audiobookshelf.nix
    ./services/ttyd.nix
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
    hdparm
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  networking.networkmanager.enable = true;
  programs.nix-ld.enable = true;
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };
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

  users.groups.media = {};
  users.users = lib.mkMerge [
    (lib.listToAttrs (lib.forEach secrets.users (user: {
      name = user.username;
      value = {
        isNormalUser = true;
        password = user.password;
        openssh.authorizedKeys.keys = [ user.sshPublicKey ];
        extraGroups = lib.optional user.superuser "wheel";
      };
    })))
    {
      media = {
        isSystemUser = true;
        group = "media";
        createHome = false;
        useDefaultShell = false;
      };
    }
    {
      root.password = secrets.rootPassword;
    }
  ];
  users.mutableUsers = false;

  systemd.services.create-dirs = {
    description = "Create directories";
    after = [ "local-fs.target" ];
    requires = [ "local-fs.target" ];
    serviceConfig = {
      Type = "exec";
      ExecStart = "${createDirsScript}";
    };
    wantedBy = [ "multi-user.target" ];
  };
}

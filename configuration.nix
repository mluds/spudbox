{
  config,
  pkgs,
  lib,
  ...
}:

with config.my;

let
  mediaDirs = [
    "${storageDir}/data/media/movies"
    "${storageDir}/data/media/tv"
    "${storageDir}/data/media/audiobooks"
    "${storageDir}/data/misc"
    "${cacheDir}/data"
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

  usenetDirs = [
    "${cacheDir}/data/usenet"
    "${cacheDir}/data/usenet/complete"
    "${cacheDir}/data/usenet/complete/movies"
    "${cacheDir}/data/usenet/complete/tv"
    "${cacheDir}/data/usenet/incomplete"
    "${cacheDir}/data/usenet/incomplete/movies"
    "${cacheDir}/data/usenet/incomplete/tv"
  ];

  createDirsScript = pkgs.writeScript "create-dirs.sh" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    ${lib.concatMapStringsSep "\n" (dir: ''
      echo "Creating media directory: ${dir}"
      mkdir -p "${dir}"
      chown -R media:media "${dir}"
      chmod -R 0775 "${dir}"
    '') mediaDirs}

    ${lib.concatMapStringsSep "\n" (dir: ''
      echo "Creating usenet directory: ${dir}"
      mkdir -p "${dir}"
      chown -R sabnzbd:media "${dir}"
      chmod -R 0775 "${dir}"
    '') usenetDirs}

    # Lock down all secrets: readable by media group (services that need them)
    chown -R root:media ${secretsDir}
    chmod 750 ${secretsDir}
    find ${secretsDir} -type d -exec chmod 750 {} \;
    find ${secretsDir} -type f -exec chmod 640 {} \;

    # Radarr reads its own API key directly
    chown -R radarr:radarr ${secretsDir}/radarr
    chmod 750 ${secretsDir}/radarr
    find ${secretsDir}/radarr -type f -exec chmod 640 {} \;

    # Backup password and R2 credentials: root only (restic runs as root)
    for dir in ${secretsDir}/restic ${secretsDir}/r2; do
      [ -d "$dir" ] || continue
      chown -R root:root "$dir"
      chmod 700 "$dir"
      find "$dir" -type f -exec chmod 600 {} \;
    done
  '';
in
{
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
    ./services/backup.nix
    ./services/drive-check.nix
    ./services/docker.nix
    ./services/homebridge.nix
    ./services/claude-code.nix
  ];

  environment.systemPackages = with pkgs; [
    vim
    xmlstarlet
    ed
    sqlite
    python314
    openssl
    jq
    curl
    hdparm
    lsof
    statix
    deadnix
    nixfmt-rfc-style
    git
    gh
    tmux
  ];

  nix = {
    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
    # Weekly: prune system generations to the newest 5 (rollback targets),
    # then GC everything no longer reachable. Count-based rather than
    # --delete-older-than so a quiet month can't leave only one generation.
    gc = {
      automatic = true;
      dates = "weekly";
    };
    optimise.automatic = true;
  };
  systemd.services.nix-gc.preStart = ''
    ${config.nix.package}/bin/nix-env -p /nix/var/nix/profiles/system --delete-generations +5
  '';

  boot.loader = {
    systemd-boot = {
      enable = true;
      # Matches the 5 generations kept by nix-gc; keeps /boot (487M) from filling.
      configurationLimit = 5;
    };
    efi.canTouchEfiVariables = true;
  };
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

  networking = {
    # IPv6 off: the ISP hands out a global address (announced to torrent
    # peers), and nothing here needs IPv6. enableIPv6 sets disable_ipv6 via
    # sysctl, but NetworkManager re-enables it when it activates a profile
    # with ipv6.method=auto, so the wired profile must say "disabled" too
    # (NetworkManager.conf can't default it). See "IPv6" in CLAUDE.md.
    enableIPv6 = false;
    networkmanager.enable = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [
        80
        443
      ];
    };
  };

  users = {
    groups.media = { };
    users = lib.mkMerge [
      (lib.listToAttrs (
        lib.forEach users (user: {
          name = user.username;
          value = {
            isNormalUser = true;
            hashedPasswordFile = "${secretsDir}/users/${user.username}/hashed";
            openssh.authorizedKeys.keys = [ user.sshPublicKey ];
            extraGroups = lib.optional user.superuser "wheel";
          };
        })
      ))
      {
        media = {
          isSystemUser = true;
          group = "media";
          createHome = false;
          useDefaultShell = false;
        };
      }
      {
        root.hashedPasswordFile = "${secretsDir}/users/root/hashed";
      }
    ];
    mutableUsers = false;
  };

  systemd.services.create-dirs = {
    description = "Create directories";
    after = [ "local-fs.target" ];
    requires = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${createDirsScript}";
    };
    wantedBy = [ "multi-user.target" ];
  };
}

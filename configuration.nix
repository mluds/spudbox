{
  config,
  pkgs,
  lib,
  ...
}:

let
  inherit (config.my) storageDir cacheDir secretsDir;

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

  # Each has its own web login password in secrets/<name>/password (finding
  # #5). Exported for test.sh; scripts/generate-service-passwords.sh keeps its
  # own copy because it runs on the Mac.
  passwordServices = [
    "sonarr"
    "radarr"
    "bazarr"
    "sabnzbd"
    "transmission"
    "tautulli"
    "homebridge"
    "audiobookshelf"
  ]
  ++ lib.optional config.my.prowlarr.enable "prowlarr";

  createDirsScript = pkgs.writeShellApplication {
    name = "create-dirs";
    text = ''
      # The directories themselves only, not their contents: a recursive
      # chmod made every media file executable and walked the whole library
      # (spinning up the HDD) on each boot. The apps set their own file modes.
      ${lib.concatMapStringsSep "\n" (dir: ''
        mkdir -p "${dir}"
        chown media:media "${dir}"
        chmod 0775 "${dir}"
      '') mediaDirs}

      ${lib.concatMapStringsSep "\n" (dir: ''
        mkdir -p "${dir}"
        chown sabnzbd:media "${dir}"
        chmod 0775 "${dir}"
      '') usenetDirs}

      # Secrets are root-only. Everything that reads them runs as root (the
      # *-config oneshots, restic, transmission's ExecStartPre); other units
      # get theirs via LoadCredential.
      chown -R root:root ${secretsDir}
      find ${secretsDir} -type d -exec chmod 700 {} \;
      find ${secretsDir} -type f -exec chmod 600 {} \;

      # Login passwords in plaintext are for recovery only; they stay in the
      # repo and the password manager, never on the server (deploy.sh skips them).
      rm -f ${secretsDir}/users/*/plaintext

      # Retired secrets (deploy.sh never deletes): the pre-git-crypt file, the
      # shared admin password (finding #5), the unused Gmail SMTP login.
      rm -rf ${secretsDir}/default.json ${secretsDir}/admin/password ${secretsDir}/gmail
    '';
  };
in
{
  imports = [
    ./storage.nix
    ./common/vars.nix
    ./common/env.nix
    ./common/helpers.nix
    ./environments/default.nix
    ./services/caddy.nix
    ./services/homepage.nix
    ./services/sabnzbd.nix
    ./services/plex.nix
    ./services/transmission.nix
    ./services/tautulli.nix
    ./services/servarr/sonarr.nix
    ./services/servarr/radarr.nix
    ./services/servarr/arr-rescan.nix
    ./services/servarr/bazarr.nix
    ./services/servarr/jellyseerr.nix
    ./services/servarr/prowlarr.nix
    ./services/audiobookshelf.nix
    ./services/backup.nix
    ./services/drive-check.nix
    ./services/docker.nix
    ./services/homebridge.nix
    ./services/claude-code.nix
    ./services/media-fixup.nix
    ./services/notify.nix
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
    nixfmt
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
        lib.forEach config.my.users (user: {
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
      ExecStart = lib.getExe createDirsScript;
    };
    wantedBy = [ "multi-user.target" ];
  };

  environment.etc."spudbox/env".text = lib.toShellVar "PASSWORD_SERVICES" passwordServices;
}

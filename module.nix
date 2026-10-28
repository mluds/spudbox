{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.spudbox;
  inherit (cfg) storageDir cacheDir secretsDir;

  mediaDirs = [
    "${storageDir}/data/media/movies"
    "${storageDir}/data/media/tv"
    "${storageDir}/data/media/audiobooks"
    "${storageDir}/data/media/videos" # Transmission's download-dir
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

  # Each has its own web login password in secrets/<name>/password, generated
  # on the server unless the instance supplies one (secrets.nix). Exported
  # for test.sh.
  passwordServices = [
    "sonarr"
    "radarr"
    "bazarr"
    "sabnzbd"
    "transmission"
    "tautulli"
  ]
  ++ lib.optional cfg.homebridge.enable "homebridge"
  ++ [ "audiobookshelf" ];

  # Plex is pinned by hand, ahead of nixpkgs; see "Hand-pinned versions" in
  # CLAUDE.md.
  plexOverlay = final: prev: {
    plexRaw = prev.plexRaw.overrideAttrs (_: rec {
      version = "1.43.4.10903-e5521bd8c";
      src =
        let
          debs = {
            x86_64-linux = {
              arch = "amd64";
              hash = "sha256-b2ocgzbXeeHyAVGmk0NJiEutb2pmsYorGJuW5Vw7Pts=";
            };
            aarch64-linux = {
              arch = "arm64";
              hash = "sha256-lF6G0FFPYUkrUWm76sbpGJKzNvaJXXhjK+wBe1kI5as=";
            };
          };
          deb = debs.${final.stdenv.hostPlatform.system};
        in
        prev.fetchurl {
          url = "https://downloads.plex.tv/plex-media-server-new/${version}/debian/plexmediaserver_${version}_${deb.arch}.deb";
          inherit (deb) hash;
        };
    });
  };

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

      # The local restic repo (also made by each backup; here so it exists
      # before the first one).
      mkdir -p ${cfg.backupDir}
      chmod 700 ${cfg.backupDir}

      # Login passwords in plaintext are for recovery only; they stay in the
      # repo and the password manager, never on the server (deploy.sh skips them).
      rm -f ${secretsDir}/users/*/plaintext
    '';
  };
in
{
  imports = [
    ./storage.nix
    ./common/options.nix
    ./common/env.nix
    ./common/helpers.nix
    ./common/secrets.nix
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
    ./services/audiobookshelf.nix
    ./services/backup.nix
    ./services/drive-check.nix
    ./services/homebridge.nix
    ./services/claude-code.nix
    ./services/media-fixup.nix
    ./services/notify.nix
  ];

  environment.systemPackages = with pkgs; [
    # The checks a deploy runs (deploy.sh test): spudbox-test [CATEGORY...], as
    # a superuser (it uses sudo itself).
    (writeShellScriptBin "spudbox-test" (builtins.readFile ./test.sh))
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
    git
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

  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";
  nixpkgs = {
    overlays = [ plexOverlay ];
    config.allowUnfree = true;
  };

  networking = {
    # IPv6 off (spudbox.disableIPv6): an ISP's global address would be
    # announced to torrent peers, and nothing here needs IPv6. enableIPv6
    # sets disable_ipv6 via sysctl, but NetworkManager re-enables it when it
    # activates a profile with ipv6.method=auto, so the wired profile must say
    # "disabled" too (NetworkManager.conf can't default it). See the README,
    # "First run".
    enableIPv6 = !cfg.disableIPv6;
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
        lib.forEach config.spudbox.users (user: {
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

  systemd = {
    # Before the first deploy, which streams the secrets into it.
    tmpfiles.rules = [ "d ${secretsDir} 0700 root root -" ];

    # The data pools are mounted nofail (storage.nix), so these never start
    # on an unmounted pool and fill the boot disk; they stay down instead.
    services = lib.mkMerge [
      (lib.genAttrs
        [
          "create-dirs"
          "plex"
          "sonarr"
          "radarr"
          "bazarr"
          "transmission"
          "sabnzbd"
          "audiobookshelf"
        ]
        (_: {
          unitConfig.RequiresMountsFor = [
            storageDir
            cacheDir
          ];
        })
      )
      {
        nix-gc.preStart = ''
          ${config.nix.package}/bin/nix-env -p /nix/var/nix/profiles/system --delete-generations +5
        '';

        create-dirs = {
          description = "Create directories";
          # Ordering only: Requires= would stop it whenever a switch restarts
          # local-fs.target, and nothing would start it again. The pools it
          # writes to come from RequiresMountsFor above.
          after = [ "local-fs.target" ];
          # Their download and library dirs must exist when they start (on a
          # fresh install, Transmission's sandbox refuses to start without them).
          before = [
            "transmission.service"
            "sabnzbd.service"
            "sonarr.service"
            "radarr.service"
            "plex.service"
            "audiobookshelf.service"
          ];
          serviceConfig.ExecStart = lib.getExe createDirsScript;
          wantedBy = [ "multi-user.target" ];
        };
      }
    ];
  };

  spudbox.passwordServices = passwordServices;
  environment.etc."spudbox/env".text = lib.toShellVar "PASSWORD_SERVICES" passwordServices;
}

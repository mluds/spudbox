{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (config.spudbox)
    adminUserId
    audiobookshelfPort
    secretsDir
    storageDir
    users
    ;

  # Runs on every boot/switch, after audiobookshelf-config's first-time setup
  # (which does nothing once there are users): checks that
  # audiobookshelf/password logs in as root, and gives homepage a revocable
  # API key for a read-only "homepage" user rather than a forged,
  # never-expiring root token.
  accessScript = pkgs.writers.writePython3Bin "audiobookshelf-access" {
    libraries = with pkgs.python3Packages; [ requests ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./audiobookshelf-access.py);

  configScript = pkgs.writers.writePython3Bin "audiobookshelf-config" {
    libraries = with pkgs.python3Packages; [
      requests
      bcrypt
      pyjwt
    ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./audiobookshelf-config.py);

  environment = {
    SECRETS_DIR = secretsDir;
    ABS_PORT = toString audiobookshelfPort;
  };
  configEnvironment = environment // {
    ABS_DB = "/var/lib/audiobookshelf/config/absdatabase.sqlite";
    LIBRARY_DIR = "${storageDir}/data/media/audiobooks";
    ADMIN_USER_ID = adminUserId;
    AUDIOBOOKSHELF_USERS = builtins.toJSON (
      map (user: {
        inherit (user) username superuser;
      }) users
    );
  };
in
{
  services.audiobookshelf = {
    enable = true;
    openFirewall = false;
    port = audiobookshelfPort;
    group = "media";
  };

  # The DB holds user password hashes and the root API token
  systemd.services = {
    audiobookshelf.serviceConfig = import ./hardening.nix // {
      StateDirectoryMode = "0700";
    };

    audiobookshelf-access = {
      description = "Audiobookshelf root password and homepage API key";
      after = [ "audiobookshelf.service" ];
      wants = [ "audiobookshelf.service" ];
      wantedBy = [ "multi-user.target" ];
      # On a fresh install, the first-time setup first (ABS_IF_EMPTY: a no-op
      # once the database has users).
      environment = configEnvironment // {
        ABS_IF_EMPTY = "1";
      };
      serviceConfig = {
        ExecStartPre = lib.getExe configScript;
        ExecStart = lib.getExe accessScript;
      };
    };

    audiobookshelf-config = {
      description = "Configure Audiobookshelf";
      environment = configEnvironment;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe configScript;
      };
    };
  };
}

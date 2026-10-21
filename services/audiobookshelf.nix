{
  config,
  lib,
  pkgs,
  ...
}:

with config.my;

let
  # Runs on every boot/switch (unlike the one-off audiobookshelf-config):
  #  1. The root account uses its own password (audiobookshelf/password). An
  #     install still on the shared admin/password is rotated through
  #     PATCH /api/me/password (finding #5).
  #  2. Homepage gets a revocable API key for a read-only "homepage" user,
  #     rather than a forged, never-expiring root token.
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
      inherit environment;
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = lib.getExe accessScript;
      };
    };

    audiobookshelf-config = {
      description = "Configure Audiobookshelf";
      environment = environment // {
        ABS_DB = "/var/lib/audiobookshelf/config/absdatabase.sqlite";
        LIBRARY_DIR = "${storageDir}/data/media/audiobooks";
        ADMIN_USER_ID = adminUserId;
        AUDIOBOOKSHELF_USERS = builtins.toJSON (
          map (user: {
            inherit (user) username superuser;
          }) users
        );
      };
      serviceConfig = {
        User = "root";
        Type = "oneshot";
        ExecStart = lib.getExe configScript;
      };
    };
  };
}

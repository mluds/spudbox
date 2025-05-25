{ config, secrets, lib, disko, ... }:

with config.my;

{
  disko.devices = {
    disk.boot = {
      type = "disk";
      device = bootDrive;
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            type = "EF00";
            size = "500M";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=077" ];
            };
          };
          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    };
  };

  users.groups.media = {};
  users.users = lib.listToAttrs (lib.forEach secrets.users (user: {
    name = user.username;
    value = {
      isNormalUser = true;
      password = user.password;
      openssh.authorizedKeys.keys = [ user.sshPublicKey ];
      extraGroups = lib.optional user.superuser "wheel";
    };
  })) // {
    media = {
      isSystemUser = true;
      group = "media";
      createHome = false;
      useDefaultShell = false;
    };
  };
}

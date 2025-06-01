{ config, lib, pkgs, ... }:

with config.my;

let
  ensurePartitionScript = pkgs.writeScript "ensure-partition.sh" ''
    #!/bin/sh
    set -e
    DEVICE="$1"
    PARTITION="$2"

    # Wait for base device to appear
    lsblk "$DEVICE" >/dev/null 2>&1 || sleep 5

    # Check if partition device exists
    if [ ! -e "$PARTITION" ]; then
      echo "Creating partition on $DEVICE"
      echo -e "g\nn\n1\n\n\nw" | fdisk "$DEVICE"
      partprobe "$DEVICE"

      # Wait for partition device node
      COUNT=0
      while [ ! -e "$PARTITION" ] && [ $COUNT -lt 10 ]; do
        sleep 1
        COUNT=$((COUNT+1))
      done

      if [ ! -e "$PARTITION" ]; then
        echo "ERROR: Partition $PARTITION failed to appear!"
        exit 1
      fi
    fi

    if ! xfs_admin -l "$PARTITION" >/dev/null 2>&1; then
      echo "Creating XFS filesystem on $PARTITION"
      mkfs.xfs -f "$PARTITION"

      # Verify filesystem creation
      if ! xfs_admin -l "$PARTITION" >/dev/null 2>&1; then
        echo "ERROR: XFS creation failed on $PARTITION!"
        exit 1
      else
        echo "XFS filesystem verified"
      fi
    else
      echo "XFS filesystem already exists on $PARTITION"
    fi
  '';

  allDrives = cacheDrives ++ storageDrives;
in {
  boot.supportedFilesystems = [ "xfs" "fuse.mergerfs" ];
  environment.systemPackages = with pkgs; [
    mergerfs
    parted
    xfsprogs
    gptfdisk
    inotify-tools
  ];

  systemd.services = lib.listToAttrs (map (drive: {
    name = "ensure-partition-${lib.replaceStrings ["/"] ["-"] drive.device}";
    value = {
      description = "Ensure partition and filesystem for ${drive.device}";
      before = [ "local-fs.target" ];
      path = with pkgs; [ util-linux parted xfsprogs ];
      serviceConfig = {
        Type = "exec";
        ExecStart = "${pkgs.bash}/bin/bash ${ensurePartitionScript} ${drive.device} ${drive.partition}";
      };
    };
  }) allDrives);

  fileSystems = let
    commonMount = drive: {
      name = drive.mount;
      value = {
        device = drive.partition;
        fsType = "xfs";
        options = [ "defaults" "nofail" ];
      };
    };
  in lib.listToAttrs (map commonMount allDrives) // {
    "${cacheDir}" = {
      device = lib.concatStringsSep ":" (map (d: d.mount) cacheDrives);
      fsType = "fuse.mergerfs";
      options = [ "defaults" "allow_other" "use_ino" "cache.files=partial" ];
      depends = map (d: d.mount) cacheDrives;
    };
    "${storageDir}" = {
      device = lib.concatStringsSep ":" (map (d: d.mount) storageDrives);
      fsType = "fuse.mergerfs";
      options = [ "defaults" "allow_other" "use_ino" "cache.files=partial" ];
      depends = map (d: d.mount) storageDrives;
    };
  };

  services.udev.extraRules = ''
    ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", RUN+="${pkgs.hdparm}/bin/hdparm -S 60 -B 127 /dev/%k"
  '';
}

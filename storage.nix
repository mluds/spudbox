{ config, lib, pkgs, ... }:

with config.my;

let
  ensurePartitionScript = pkgs.writeScript "ensure-partition.sh" ''
    #!/bin/sh
    set -e
    DEVICE="$1"
    PARTITION="$2"

    echo "Waiting for base device $DEVICE..."
    COUNT=0
    while [ ! -e "$DEVICE" ] && [ $COUNT -lt 30 ]; do
      sleep 1
      COUNT=$((COUNT+1))
    done
    if [ ! -e "$DEVICE" ]; then
      echo "ERROR: Base device $DEVICE not found!"
      exit 1
    fi

    # Check if partition exists
    if [ ! -e "$PARTITION" ]; then
      echo "Creating partition on $DEVICE"
      echo -e "g\nn\n1\n\n\nw" | fdisk "$DEVICE"

      # Force kernel to re-read partition table
      blockdev --rereadpt "$DEVICE" || true
      udevadm settle -t 5  # Wait for udev events

      # Wait longer for partition device
      echo "Waiting for partition $PARTITION..."
      COUNT=0
      while [ ! -e "$PARTITION" ] && [ $COUNT -lt 30 ]; do
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
      if ! xfs_admin -l "$PARTITION" >/dev/null 2>&1; then
        echo "ERROR: XFS creation failed!"
        exit 1
      else
        echo "XFS filesystem verified"
      fi
    else
      echo "XFS filesystem already exists"
    fi
  '';

  allDrives = cacheDrives ++ storageDrives ++ backupDrives;
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
    mergerfsMount = dir: drives: lib.optionalAttrs (drives != []) {
      "${dir}" = {
        device = lib.concatStringsSep ":" (map (d: d.mount) drives);
        fsType = "fuse.mergerfs";
        options = [ "defaults" "allow_other" "use_ino" "cache.files=partial" ];
        depends = map (d: d.mount) drives;
      };
    };
  in lib.listToAttrs (map commonMount allDrives)
    // mergerfsMount cacheDir cacheDrives
    // mergerfsMount storageDir storageDrives
    // mergerfsMount backupDir backupDrives;

  services.udev.extraRules = ''
    ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", RUN+="${pkgs.hdparm}/bin/hdparm -S 60 -B 127 /dev/%k"
  '';
}

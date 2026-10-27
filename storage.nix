{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

let
  inherit (config.spudbox)
    backupDir
    backupDrives
    cacheDir
    cacheDrives
    storageDir
    storageDrives
    ;

  # ensure-partition DEVICE PARTITION: give a blank disk one GPT partition
  # with an XFS filesystem. Leaves existing partitions and filesystems alone.
  ensurePartitionScript = pkgs.writeShellApplication {
    name = "ensure-partition";
    runtimeInputs = with pkgs; [
      util-linux
      xfsprogs
      systemd
    ];
    text = ''
      DEVICE="$1"
      PARTITION="$2"

      # In use already (e.g. started by a switch, not at boot): nothing to do.
      if [ -e "$PARTITION" ] && findmnt -rn -S "$(readlink -f "$PARTITION")" >/dev/null; then
        echo "$PARTITION is mounted; nothing to do"
        exit 0
      fi

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

      # Only ever initialise blank disks. Kernel names like /dev/sda can move
      # between boots, so a disk with any partition table or filesystem
      # signature is left alone rather than repartitioned or reformatted.
      # (blkid -p exits 0 when it finds a signature, 2 when there is none.)
      if [ ! -e "$PARTITION" ]; then
        if blkid -p "$DEVICE" >/dev/null 2>&1; then
          echo "ERROR: $DEVICE has a partition table or filesystem but no $PARTITION; refusing to repartition it"
          exit 1
        fi
        echo "Creating partition on blank disk $DEVICE"
        printf 'g\nn\n1\n\n\nw\n' | fdisk "$DEVICE"

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

      # blkid -p reads signatures only, so a dirty XFS log doesn't matter.
      # Exit 2: no signature at all. Anything else (another filesystem, or
      # conflicting signatures) is left alone; mkfs.xfs without -f would
      # refuse to overwrite one too.
      RC=0
      TYPE=$(blkid -p -s TYPE -o value "$PARTITION") || RC=$?
      if [ "$RC" -eq 0 ] && [ "$TYPE" = xfs ]; then
        echo "XFS filesystem already exists"
      elif [ "$RC" -ne 2 ]; then
        echo "ERROR: $PARTITION isn't blank XFS (blkid: ''${TYPE:-exit $RC}); refusing to format it"
        exit 1
      else
        echo "Creating XFS filesystem on blank partition $PARTITION"
        mkfs.xfs "$PARTITION"
        if [ "$(blkid -p -s TYPE -o value "$PARTITION" || true)" != xfs ]; then
          echo "ERROR: XFS creation failed!"
          exit 1
        fi
        echo "XFS filesystem verified"
      fi
    '';
  };

  allDrives = cacheDrives ++ storageDrives ++ backupDrives;
in
{
  boot.supportedFilesystems = [
    "xfs"
    "fuse.mergerfs"
  ];
  environment.systemPackages = with pkgs; [
    mergerfs
    parted
    xfsprogs
    gptfdisk
    inotify-tools
  ];

  systemd.services = lib.listToAttrs (
    map (drive: {
      name = "ensure-partition-${lib.replaceStrings [ "/" ] [ "-" ] drive.device}";
      # Runs just before the drive's mount, so a new blank disk is
      # partitioned and formatted on the first boot that sees it. Disks with
      # anything on them are left alone (see the script).
      value =
        let
          mount = "${utils.escapeSystemdPath drive.mount}.mount";
        in
        {
          description = "Ensure partition and filesystem for ${drive.device}";
          wantedBy = [ mount ];
          before = [ mount ];
          # Mounts come before sysinit.target, which ordinary services wait for.
          unitConfig.DefaultDependencies = false;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${lib.getExe ensurePartitionScript} ${drive.device} ${drive.partition}";
          };
        };
    }) allDrives
  );

  fileSystems =
    let
      commonMount = drive: {
        name = drive.mount;
        value = {
          device = drive.partition;
          fsType = "xfs";
          options = [
            "defaults"
            "nofail"
          ];
        };
      };
      mergerfsMount =
        dir: drives:
        lib.optionalAttrs (drives != [ ]) {
          "${dir}" = {
            device = lib.concatStringsSep ":" (map (d: d.mount) drives);
            fsType = "fuse.mergerfs";
            options = [
              "defaults"
              "allow_other"
              "use_ino"
              "cache.files=partial"
            ];
            depends = map (d: d.mount) drives;
          };
        };
    in
    lib.listToAttrs (map commonMount allDrives)
    // mergerfsMount cacheDir cacheDrives
    // mergerfsMount storageDir storageDrives
    // mergerfsMount backupDir backupDrives;

  # Spindown after 5 min (-S 60) and moderate APM (-B 127) for rotating SATA
  # disks. The current WD Ultrastar ignores -S, so drive-check.nix also spins
  # it down itself; the rule stays for drives that do honour it.
  services.udev.extraRules = ''
    ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", RUN+="${pkgs.hdparm}/bin/hdparm -S 60 -B 127 /dev/%k"
  '';
}

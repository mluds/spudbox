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

      # wait_for PATH: up to 30 s for a device node to appear
      wait_for() {
        for _ in {1..30}; do
          [ -e "$1" ] && return
          sleep 1
        done
        [ -e "$1" ]
      }

      # In use already (e.g. started by a switch, not at boot): nothing to do.
      if [ -e "$PARTITION" ] && findmnt -rn -S "$(readlink -f "$PARTITION")" >/dev/null; then
        echo "$PARTITION is mounted; nothing to do"
        exit 0
      fi

      echo "Waiting for base device $DEVICE..."
      if ! wait_for "$DEVICE"; then
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

        # fdisk has the kernel re-read the table itself. Don't do it again
        # (blockdev --rereadpt): the new partition's device would vanish and
        # reappear, failing the fsck and mount systemd has bound to it.
        udevadm settle -t 5

        echo "Waiting for partition $PARTITION..."
        if ! wait_for "$PARTITION"; then
          echo "ERROR: Partition $PARTITION failed to appear!"
          exit 1
        fi
      fi

      # The partition's signatures (wipefs lists them without erasing; it
      # reads superblocks only, so a dirty XFS log doesn't matter). blkid -p
      # won't do: it also reports the partition-table entry, blank or not.
      # Anything but none or a lone XFS is left alone; mkfs.xfs without -f
      # would refuse to overwrite one too.
      SIGNATURES=$(wipefs --noheadings --output TYPE "$PARTITION" | sort -u | paste -sd ' ')
      if [ "$SIGNATURES" = xfs ]; then
        echo "XFS filesystem already exists"
      elif [ -n "$SIGNATURES" ]; then
        echo "ERROR: $PARTITION isn't blank or XFS (found: $SIGNATURES); refusing to format it"
        exit 1
      else
        echo "Creating XFS filesystem on blank partition $PARTITION"
        mkfs.xfs "$PARTITION"
        if [ "$(wipefs --noheadings --output TYPE "$PARTITION")" != xfs ]; then
          echo "ERROR: XFS creation failed!"
          exit 1
        fi
        echo "XFS filesystem verified"
      fi
    '';
  };

  allDrives = cacheDrives ++ storageDrives ++ backupDrives;

  # The data drives and their mergerfs pools.
  dataMounts =
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
              # Like the drives under it: a missing disk must not stop the
              # boot in emergency mode, where a headless server (root locked)
              # can't be reached. The apps that use the pools wait for them
              # (RequiresMountsFor, in module.nix) instead.
              "nofail"
            ];
            depends = map (d: d.mount) drives;
          };
        };
    in
    lib.listToAttrs (map commonMount allDrives)
    // mergerfsMount cacheDir cacheDrives
    // mergerfsMount storageDir storageDrives
    // mergerfsMount backupDir backupDrives;
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

  spudbox.dataMounts = dataMounts;
  fileSystems = dataMounts;

  # Spindown after 5 min (-S 60) and moderate APM (-B 127) for rotating SATA
  # disks. The current WD Ultrastar ignores -S, so drive-check.nix also spins
  # it down itself; the rule stays for drives that do honour it.
  services.udev.extraRules = ''
    ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", RUN+="${pkgs.hdparm}/bin/hdparm -S 60 -B 127 /dev/%k"
  '';
}

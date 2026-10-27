#!/usr/bin/env bash
# ERASES a disk and makes it the spudbox boot disk: GPT, a 512 MB EFI system
# partition (label "BOOT") and the rest ext4 (label "nixos"), mounted at
# /mnt/boot and /mnt, ready for `./deploy.sh hardware` and `./deploy.sh install`.
#
# Runs on the NixOS installer, as root. From your instance repo:
#   ssh root@<ip> CONFIRM=nvme0n1 bash -s -- /dev/nvme0n1 < partition-boot-disk.sh
# CONFIRM must repeat the disk's name: nothing is erased without it.
# Data disks don't go through this: spudbox formats blank ones on first boot.
set -euo pipefail

die() {
  echo "ERROR: $*" >&2
  exit 1
}

DEV=${1:?usage: CONFIRM=<name> partition-boot-disk.sh /dev/<disk>}
NAME=$(basename "$(readlink -f "$DEV")")

[ "$(id -u)" -eq 0 ] || die "run as root"
# Only ever on the installer, never on an installed system.
mountpoint -q /iso || die "this isn't the NixOS installer (no /iso); refusing"
[ -b "$DEV" ] || die "$DEV is not a block device"
[ "$(lsblk -dno TYPE "$DEV")" = disk ] || die "$DEV is not a whole disk"
if lsblk -nrpo MOUNTPOINTS "$DEV" | grep -q .; then
  die "something on $DEV is mounted (the installer's own USB stick?); refusing"
fi
if mountpoint -q /mnt; then
  die "/mnt is already mounted; unmount it first (umount -R /mnt)"
fi

echo "Disk to ERASE:"
lsblk -o NAME,SIZE,MODEL,SERIAL,FSTYPE,LABEL "$DEV"
[ "${CONFIRM:-}" = "$NAME" ] || die "set CONFIRM=$NAME to erase $DEV"

echo "Erasing $DEV..."
wipefs --all --force "$DEV" >/dev/null
parted -s "$DEV" -- mklabel gpt
parted -s -a optimal "$DEV" -- mkpart ESP fat32 1MiB 512MiB
parted -s "$DEV" -- set 1 esp on
parted -s -a optimal "$DEV" -- mkpart nixos ext4 512MiB 100%
udevadm settle

# nvme0n1 -> nvme0n1p1, sda -> sda1: take the names from the kernel.
mapfile -t parts < <(lsblk -nrpo NAME,TYPE "$DEV" | awk '$2 == "part" {print $1}')
[ "${#parts[@]}" -eq 2 ] || die "expected 2 partitions on $DEV, found ${#parts[@]}"
ESP=${parts[0]}
ROOT=${parts[1]}

mkfs.fat -F 32 -n BOOT "$ESP" >/dev/null
mkfs.ext4 -q -F -L nixos "$ROOT"

udevadm settle
# Explicit types: the installer may not have loaded ext4 yet, and guessing
# from the filesystems it has (vfat, iso9660, ...) fails.
mount -t ext4 "$ROOT" /mnt
mkdir -p /mnt/boot
mount -t vfat -o umask=077 "$ESP" /mnt/boot

echo "Done: $ROOT on /mnt, $ESP on /mnt/boot."

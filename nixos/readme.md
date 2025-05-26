### Installation
Boot from the NixOS ISO and run these commands to get an initial SSH connection.
```
sudo passwd
ip a
```

Run this from the deployment host.
```
export HOST_IP="<IP ADDRESS>"
rm ~/.ssh/known_hosts
ssh -o StrictHostKeyChecking=accept-new root@${HOST_IP}
```

Run these commands. You will be prompted for a password.
Just use a simple password to SSH in again, as it will be disabled in the next step.
```
export BOOT_DEV=/dev/nvme0n1
parted $BOOT_DEV -- mklabel gpt
parted -s -a optimal $BOOT_DEV -- mkpart root ext4 512MB 100%
parted -s $BOOT_DEV -- mkpart ESP fat32 1MB 512MB
parted -s $BOOT_DEV -- set 2 esp on
mkfs.ext4 -L nixos ${BOOT_DEV}p1
mkfs.fat -F 32 -n boot ${BOOT_DEV}p2
mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot
mount -o umask=077 /dev/disk/by-label/boot /mnt/boot
nixos-generate-config --root /mnt
cat > /mnt/etc/nixos/configuration.nix <<'EOF'
{ config, lib, pkgs, ... }:
{
  system.stateVersion = "25.05";
  imports = [ ./hardware-configuration.nix ];
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = true;
  services.openssh.settings.PermitRootLogin = "yes";
}
EOF
nixos-install --root /mnt
reboot
```

SSH in again and run these commands:
```
scp -r ./nixos/* root@${HOST_IP}:~/deploy/ && \
ssh root@${HOST_IP} "cd ~/deploy && nixos-rebuild switch --flake .#spudbox-dev"
```

After this, root login will be disabled and you must login using one of the users specified in `secrets/defaults.json`.

### Deployment
```
scp -r -i ~/.ssh/spudnet ./nixos/* admin@nix-dev:~/deploy/ && \
ssh -i ~/.ssh/spudnet admin@nix-dev "cd ~/deploy && sudo nixos-rebuild switch --flake .#spudbox-dev"
```

### Secrets
Initial setup:
```
brew install git-crypt
git-crypt init
# Save this to password manager
git-crypt export-key - | base64
```

Unlocking:
```
echo -n "<GIT CRYPT KEY>" | base64 -d > ~/git-crypt-key
git-crypt unlock ~/git-crypt-key
```

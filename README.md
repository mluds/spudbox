### Installation

Install the NixOS minimal ISO on a USB drive using a tool like balenaEtcher.

Boot from the USB drive and run these commands to get an initial SSH connection.
```bash
sudo passwd
ip a
```

Run this from the deployment host.

Dev:
```bash
export HOST_IP="192.168.42.130"
export FLAKE=spudbox-dev
```

Prod:
```bash
export HOST_IP="192.168.1.42"
export FLAKE=spudbox-prod
```

```bash
ssh-keygen -R ${HOST_IP}  # forget only this host's old key
ssh -o StrictHostKeyChecking=accept-new root@${HOST_IP}
```

Run these commands. You will be prompted for a password.
Just use a simple password to SSH in again, as it will be disabled in the next step.

Dev:
```bash
export BOOT_DEV=/dev/nvme0n1
export BOOT_PART_1=${BOOT_DEV}p1
export BOOT_PART_2=${BOOT_DEV}p2
```

Prod:
```bash
export BOOT_DEV=/dev/nvme0n1
export BOOT_PART_1=${BOOT_DEV}p1
export BOOT_PART_2=${BOOT_DEV}p2
```

```bash
wipefs --all --force $BOOT_PART_1
wipefs --all --force $BOOT_PART_2
partprobe $BOOT_DEV
sgdisk --zap-all $BOOT_DEV
parted $BOOT_DEV -- mklabel gpt
parted -s -a optimal $BOOT_DEV -- mkpart root ext4 512MB 100%
parted -s $BOOT_DEV -- mkpart ESP fat32 1MB 512MB
parted -s $BOOT_DEV -- set 2 esp on
mkfs.ext4 -L nixos ${BOOT_PART_1}
mkfs.fat -F 32 -n boot ${BOOT_PART_2}
mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot
mount -o umask=077 /dev/disk/by-label/boot /mnt/boot
nixos-generate-config --root /mnt
cat > /mnt/etc/nixos/configuration.nix <<EOF
{ config, lib, pkgs, ... }:
{
  imports = [ ./hardware-configuration.nix ];
  system.stateVersion = "25.05"; # match configuration.nix
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

Prod's flake reads its hardware config from `hosts/prod-hardware.nix`, and a
reinstall gets new disk UUIDs. So for prod, first replace that file with the
new install's config, then commit it:
```bash
ssh root@${HOST_IP} nixos-generate-config --show-hardware-config > hosts/prod-hardware.nix
```

Now run these commands from the deployment host to install the full system:
```bash
ssh-keygen -R ${HOST_IP} && \
scp -o StrictHostKeyChecking=accept-new -r ./* root@${HOST_IP}:~/deploy/ && \
ssh root@${HOST_IP} "cd ~/deploy && nixos-rebuild switch --impure --flake .#${FLAKE}"
```

After this, root login will be disabled and you must log in as one of the users in `my.users` (`environments/default.nix`), with its SSH key.

### Manual Steps

#### Plex

Claim the Plex server by opening an SSH tunnel.
```
ssh -i ~/.ssh/spudbox -L 32400:localhost:32400 luds@192.168.1.42
```

Then visit http://localhost:32400/web in a browser and follow the setup. (Plex _requires_ claiming from localhost)

#### Sonarr

Open Sonarr. Go to Library Import, click the path, then click Import.

#### Radarr

Open Radarr. Go to Library Import, click the path, then click Import.

#### Jellyseerr

Open Jellyseerr. Follow the setup steps. Plex, Sonarr, and Radarr settings should be pre-filled.

#### Claude Code

Lets you drive Claude Code on the server from the Claude mobile app (Code tab)
or claude.ai/code. Requires a Pro/Max claude.ai subscription. Over SSH as `luds`:

```
curl -fsSL https://claude.ai/install.sh | bash   # native install to ~/.local/bin, self-updating
claude auth login                                # pick the claude.ai option; open the URL on any device
cd ~/workspace && claude remote-control          # answer y to trust + enable prompts, then Ctrl+C
sudo systemctl start claude-remote-control
```

The `spudbox` session then appears in the app's session list. The service skips
startup until `~/.claude/.credentials.json` exists.

### Deploy Updates

See "Deploying" in `CLAUDE.md`.

### Secrets

#### Initial setup
```bash
brew install git-crypt
git-crypt init
# Save this to password manager
git-crypt export-key - | base64
```

#### Unlocking
```bash
echo -n "<GIT CRYPT KEY>" | base64 -d > ~/git-crypt-key
git-crypt unlock ~/git-crypt-key
```

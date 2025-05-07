### First Install
```
sudo su
parted /dev/nvme0n1 -- mklabel gpt
parted -s -a optimal /dev/nvme0n1 -- mkpart root ext4 512MB 100%
parted -s /dev/nvme0n1 -- mkpart ESP fat32 1MB 512MB
parted -s /dev/nvme0n1 -- set 2 esp on
mkfs.ext4 -L nixos /dev/nvme0n1p1
mkfs.fat -F 32 -n boot /dev/nvme0n1p2
mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot
mount -o umask=077 /dev/disk/by-label/boot /mnt/boot
nixos-generate-config --root /mnt
nixos-install --no-root-passwd
reboot
```

### Deploy Updates
```
scp -r -i /Users/mludwig/.ssh/spudnet ./nixos/* luds@nix-dev:~/tmp/ && \
ssh -i /Users/mludwig/.ssh/spudnet luds@nix-dev "cd ~/tmp && sudo nixos-rebuild switch --flake .#spudbox-dev"
```

### Secrets
```
brew install git-crypt
git-crypt init
# Save this to password manager
git-crypt export-key - | base64
```

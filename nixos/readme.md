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
nix --extra-experimental-features nix-command --extra-experimental-features flakes profile install nixpkgs#nixos-rebuild
```

```
scp -i /Users/mludwig/.ssh/spudnet ./nixos/* luds@nix-dev:~/tmp/ && \
ssh -i /Users/mludwig/.ssh/spudnet luds@nix-dev "cd ~/tmp && sudo nixos-rebuild switch --flake .#spudbox"
```

### Secrets
```
brew install age
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
sops --encrypt --in-place secrets.yaml
ssh -i /Users/mludwig/.ssh/spudnet luds@nix-dev "sudo mkdir -p /var/lib/sops-nix && sudo chmod 777 /var/lib/sops-nix"
scp -i /Users/mludwig/.ssh/spudnet ~/.config/sops/age/keys.txt luds@nix-dev:/var/lib/sops-nix/keys.txt
ssh -i /Users/mludwig/.ssh/spudnet luds@nix-dev "sudo chown -R root:root /var/lib/sops-nix & sudo chmod 600 /var/lib/sops-nix"
```

```
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt sops secrets.yaml
```

# spudbox

A self-hosted media server on NixOS, configured end to end from one settings
file:

- **Plex** (hardware transcoding) and **Tautulli**
- **Sonarr**, **Radarr** and **Bazarr**, wired to **SABnzbd** (usenet), your
  indexers and each other
- **Jellyseerr** for requests, **Transmission** (with the Flood UI),
  **Audiobookshelf**
- **Caddy** in front of every web UI at `https://<service>.<your domain>`,
  LAN only, and a **homepage** dashboard
- Nightly **restic** backups of all app state, optionally copied off-site
- Optional extras: Pushover failure alerts, HDD spin-down, Homebridge,
  media-fixup (Dolby Vision fixes for picky Plex clients), Claude Code

Every app is set up through its own API on boot: logins, API keys, download
clients, indexers, quality profiles, libraries. Each web UI gets its own
generated password. A fresh install comes up ready to use, apart from the few
manual steps in [First run](#first-run).

## How it fits together

Two repositories:

- **This one** is the code: a NixOS module (`spudbox.*` options), a test
  suite, and a template.
- **Yours**, made from [`template/`](template), holds only what's specific to
  your server: `spudbox.nix` (settings), `hardware.nix`, `secrets/`
  (encrypted), and `deploy.sh`. Its `flake.lock` pins a version of this
  repository; `./deploy.sh update` moves it.

`deploy.sh` runs on your own computer, which doesn't need Nix. It copies your
repository to the server and the server builds.

## Requirements

- An x86_64 machine for the server: a boot SSD, and one or more data disks
  for the library. An Intel iGPU is needed for hardware transcoding and
  media-fixup.
- A domain, with a wildcard record `*.yourdomain` pointing at the server's
  LAN address. For trusted certificates the domain's DNS must be on
  Cloudflare (`tls = "cloudflare"`); otherwise Caddy's own CA is used.
- A usenet provider and a Newznab indexer (e.g. NZBGeek) for SABnzbd, Sonarr
  and Radarr; a plex.tv account.
- On your computer: `git`, `ssh`, `rsync`, and [git-crypt](https://github.com/AGWA/git-crypt)
  to keep your secrets encrypted in git.

## Setting up a server

### 1. Make your instance repository

```bash
git clone https://github.com/mluds/spudbox
cp -r spudbox/template my-spudbox      # or, with Nix: nix flake init -t github:mluds/spudbox
cd my-spudbox && git init
git-crypt init                          # secrets/ is encrypted from the first commit
git-crypt export-key - | base64         # save this in your password manager
```

Keep it private. Then:

- **`spudbox.nix`**: your domain, login user and SSH key, data disks (by
  `/dev/disk/by-id/...`), usenet servers, indexers, which extras you want.
  Every option is described in [`common/options.nix`](common/options.nix).
- **`deploy.env`**: the server's address once installed (`HOST=you@192.168.1.10`)
  and your SSH key.
- **`secrets/`**: one file per secret. [`secrets/README.md`](template/secrets/README.md)
  lists which ones your settings need. Everything internal (web UI passwords,
  API keys, the backup password) is generated on the server.

### 2. Boot the installer and partition the boot disk

Boot the [NixOS minimal ISO](https://nixos.org/download/#nixos-iso) from a
USB stick. On its console, set a temporary root password and find the address:

```bash
sudo passwd
ip a
```

From your computer, `ssh root@<ip>` and partition the **boot disk** (this
erases it; data disks are formatted automatically on first boot if they're
blank, and left alone if they aren't):

```bash
BOOT_DEV=/dev/nvme0n1                    # check with lsblk
wipefs --all --force ${BOOT_DEV}
parted -s $BOOT_DEV -- mklabel gpt
parted -s -a optimal $BOOT_DEV -- mkpart root ext4 512MB 100%
parted -s $BOOT_DEV -- mkpart ESP fat32 1MB 512MB
parted -s $BOOT_DEV -- set 2 esp on
mkfs.ext4 -L nixos ${BOOT_DEV}p1         # sda1/sda2 for a SATA disk
mkfs.fat -F 32 -n boot ${BOOT_DEV}p2
mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot
mount -o umask=077 /dev/disk/by-label/boot /mnt/boot
```

### 3. Install

From your instance repository (unlocked, if you use git-crypt):

```bash
./deploy.sh hardware root@<ip>   # writes hardware.nix from the machine
./deploy.sh install root@<ip>    # copies config + secrets, runs nixos-install
git add -A && git commit -m "Install"   # hardware.nix and flake.lock
ssh root@<ip> reboot
```

Root's password stays locked. Log in as your user with your SSH key; from
now on everything goes through `./deploy.sh`.

### 4. First run

After the reboot, give the apps a few minutes to configure each other, then:

```bash
./deploy.sh test          # all checks should pass, apart from what's below
./deploy.sh ssh
sudo spudbox-passwords    # the web UI logins (save them)
```

The few things that can't be automated:

- **Plex**: claim the server, which Plex only allows from localhost. Open a
  tunnel, `ssh -L 32400:localhost:32400 you@<server>`, visit
  http://localhost:32400/web and follow the setup. Then
  `sudo systemctl restart plex-config tautulli-config jellyseerr-config`.
- **Audiobookshelf** (once, on a fresh install): `sudo systemctl start
  audiobookshelf-config` creates the root account, the Audiobooks library and
  your users. It refuses to run once there are users. A login user gets an
  account only if `/var/lib/secrets/users/<name>/plaintext` holds their
  password at that moment; copy it there by hand (the next boot deletes it).
- **IPv6** (with `disableIPv6`, the default): NetworkManager re-enables IPv6
  per connection profile, so turn it off on the wired one once:
  ```bash
  sudo nmcli connection modify "Wired connection 1" ipv6.method disabled
  sudo nmcli device reapply eno1      # your interface, from `ip a`
  ```
- **Sonarr/Radarr**: existing folders on the data disks are imported
  automatically. Any they couldn't match are listed as `Not found:` in
  `journalctl -u sonarr-config` (or `radarr-config`); add those by hand
  under Library Import.
- **Claude Code** (with `claudeCode.enable`): as that user, `curl -fsSL
  https://claude.ai/install.sh | bash`, `claude auth login`, then `cd
  ~/workspace && claude remote-control` once to accept the prompts (Ctrl+C),
  and `sudo systemctl start claude-remote-control`.

## Day to day

```bash
./deploy.sh            # copy, rebuild, wait for the apps, run the checks
./deploy.sh switch     # copy and rebuild, no checks
./deploy.sh test       # the checks only (spudbox-test on the server)
./deploy.sh update     # move flake.lock to the newest spudbox, then deploy
./deploy.sh ssh
```

A deploy copies your working tree (uncommitted changes included) and streams
`secrets/` into `/var/lib/secrets` (root-only), never into the Nix store. If a
secret changed, the setup units re-run so the apps pick it up.

To undo a bad deploy: `ssh you@server sudo nixos-rebuild switch --rollback`,
or revert and deploy again.

## Backups and restores

`restic-backups-local` runs nightly at 02:30: it stops the apps, backs up
`/var/lib` (app configs and databases, minus caches and logs) to
`<storageDir>/backups/restic` on the data disks, and starts them again. With
`offsiteBackup`, the snapshots are then copied to your S3/R2 bucket, pruned
and checked. Media isn't backed up.

Both repositories are encrypted with `/var/lib/secrets/restic/password`.
**Copy it into your password manager**: without it nothing can be restored.

```bash
sudo restic-local snapshots
sudo restic-local restore latest --target /tmp/restore --include /var/lib/sonarr
# stop the service, copy the files back into /var/lib/<app>, fix ownership, start it
```

(`restic-r2` is the same for the off-site copy.) After reinstalling a server,
restore `/var/lib` from the local repository on the data disks before the
apps build fresh state: deploy once, `sudo systemctl stop` the apps listed in
`services/backup.nix`, restore, then reboot.

## Settings reference

All options are in [`common/options.nix`](common/options.nix), with
descriptions and defaults. The main ones:

| Option | Default | |
| --- | --- | --- |
| `domain` | (required) | `https://<service>.<domain>` |
| `users` | (required) | Login users and SSH keys; `superuser` gets passwordless sudo |
| `tls` | `"internal"` | `"cloudflare"` for a Let's Encrypt wildcard certificate |
| `storageDrives`, `cacheDrives` | `[ ]` | Data disks, pooled with mergerfs at `/mnt/storage`, `/mnt/cache` |
| `usenet.servers` | `[ ]` | Usenet servers in priority order |
| `indexers` | `[ ]` | Newznab indexers for Sonarr and Radarr |
| `subtitleProviders` | `[ ]` | `opensubtitlescom`, `assrt` |
| `bazarr.languageProfiles` | English | Subtitle languages |
| `disableIPv6` | `true` | |
| `pushover.enable` | off | Alerts when a setup unit, backup or timer job fails |
| `offsiteBackup.enable` | off | Copy backups to an S3 bucket |
| `hddSpindown.enable` | off | Spin idle data HDDs down, show their state on the dashboard |
| `mediaFixup.enable` | off | Fix Dolby Vision profile 5 and hybrid DV files (Intel iGPU) |
| `homebridge.enable` | off | HomeKit bridge in Docker |
| `claudeCode.enable` | off | Claude Code Remote Control as a service (see its security note) |
| `homepage.*` | | Dashboard title and bookmarks |
| `*Port` | | Each app's (loopback) port |

`spudbox.nix` is an ordinary NixOS module, so any other NixOS option can go
there too (`time.timeZone`, extra packages, ...).

## Security model

- Web UIs listen on 127.0.0.1 only; Caddy serves them over HTTPS and refuses
  anything outside private address ranges. Plex's port 32400 is open (and can
  be port-forwarded) for remote streaming.
- Secrets are root-only in `/var/lib/secrets`, never in the Nix store or on a
  command line; services that need one get it through systemd's
  `LoadCredential`.
- Apps that handle downloaded files run sandboxed (`systemd-analyze security`).
- `spudbox-test` checks all of the above on every deploy.

## Working on spudbox

See [CLAUDE.md](CLAUDE.md) for the layout, conventions and how to test a
change against a real server before it's released.

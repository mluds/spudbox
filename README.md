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

**The easy way:** clone this repository, run [Claude Code](https://claude.com/claude-code)
in it and type `/install-spudbox`. It asks for your settings, makes your
instance repository, has you type in the secrets, partitions the boot disk
(after you confirm which one), installs, and walks you through the first-run
steps. You'll still boot the machine from a USB stick and click through
Plex's setup yourself. The steps it automates are below.

### 1. Make your instance repository

```bash
git clone https://github.com/mluds/spudbox
cp -r spudbox/template ~/spudbox-home   # or, with Nix: nix flake init -t github:mluds/spudbox
cd ~/spudbox-home && git init
git-crypt init                          # secrets/ is encrypted from the first commit
git-crypt export-key - | base64         # save this in your password manager
```

Keep it private. Then:

- **`spudbox.nix`**: your domain, login user and SSH key, data disks (by
  `/dev/disk/by-id/...`), usenet servers, indexers, which extras you want.
  Every option is described in [`common/options.nix`](common/options.nix).
- **`deploy.env`**: your SSH key, and the server's address once installed
  (`HOST=you@192.168.1.10`).
- **`secrets/`**: [`secrets/README.md`](template/secrets/README.md) lists
  which ones your settings need. Type each in with `./deploy.sh secret
  usenet/password` (input hidden). Everything internal (web UI passwords,
  API keys, the backup password) is generated on the server.

### 2. Boot the installer and partition the boot disk

Boot the [NixOS minimal ISO](https://nixos.org/download/#nixos-iso) (the
release in this repo's `flake.nix`) from a USB stick, in UEFI mode. On its
console, set a temporary root password and find the address:

```bash
sudo passwd
ip -4 addr
```

From your computer, authorize your key, look at the disks, and erase and
partition the **boot disk** with [`scripts/partition-boot-disk.sh`](scripts/partition-boot-disk.sh).
`CONFIRM` must repeat the disk's name; the script refuses to run anywhere but
the installer, or on a disk with anything mounted:

```bash
SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
ssh-copy-id -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@<ip>
$SSH root@<ip> lsblk -o NAME,SIZE,MODEL,SERIAL,FSTYPE
$SSH root@<ip> CONFIRM=nvme0n1 bash -s -- /dev/nvme0n1 < spudbox/scripts/partition-boot-disk.sh
```

Data disks aren't touched here: on first boot, spudbox gives each **blank**
one an XFS partition, mounts one that already has a single XFS partition as
it is, and leaves anything else alone.

### 3. Install

From your instance repository (unlocked, if you use git-crypt):

```bash
./deploy.sh hardware root@<ip>   # writes hardware.nix from the machine
./deploy.sh install root@<ip>    # copies config + secrets, runs nixos-install
git add -A && git commit -m "Install"   # hardware.nix and flake.lock
ssh root@<ip> reboot             # and remove the USB stick
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

Set up by themselves on first boot: Plex is claimed for your plex.tv
account (from `plex/username` + `plex/password`, or `plex/token`) and gets
its libraries; Audiobookshelf gets its root account and library; IPv6 is
turned off in NetworkManager's wired profiles. What's left:

- **Plex, if it didn't claim itself** (`journalctl -u plex-config`; e.g. a
  wrong password, or two-factor auth without `plex/token`): fix the secret
  and deploy, or claim it by hand through a tunnel,
  `ssh -L 32400:localhost:32400 you@<server>`, at
  http://localhost:32400/web. Then
  `sudo systemctl restart plex-config tautulli-config jellyseerr-config`.
- **Audiobookshelf**: add other people as users in its web UI.
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

To put the apps' state back (after a reinstall, or a bad day):

```bash
./deploy.sh restore              # the latest local snapshot; asks first
./deploy.sh restore r2 4f2a91c0  # a given snapshot from the off-site copy
```

That runs `sudo spudbox-restore` on the server: it stops the apps, restores
each app's state directory and the snapshot's secrets (the apps match the
secrets they were backed up with), re-owns the files to the current service
users, starts the apps and re-runs the setup units. The local repository is on
the data disks, so it survives reinstalling the boot disk; restore it after
the first deploy. For single files, `sudo restic-local snapshots` and
`sudo restic-local restore latest --target /tmp/restore --include <path>`
(`restic-r2` for the off-site copy).

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
| `hddSpindown.enable` | off | Spin idle data HDDs down, show their state on the dashboard, and log what wakes them (`sudo drive-wakes`) |
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
change against a real server before it's released. CI runs the lint, both
evaluation checks and a VM test of a fresh install (`tests/vm.nix`) on every
push.

## License

MIT; see [LICENSE](LICENSE).

# spudbox

**Turn a spare PC into a home media server that runs itself.**

spudbox is a ready-made setup for a home server that streams your movies,
TV shows and audiobooks to every screen in the house, the way Netflix does,
from a library you own. Ask for a movie or a show and it finds it, downloads
it, files it, adds subtitles and puts it in Plex, without you touching a
folder.

It's built on [NixOS](https://nixos.org), a Linux distribution configured
by code. You describe your server in one settings file and spudbox installs
and connects about a dozen apps that would otherwise each need their own
setup. Rebuilding the server from scratch gives you the same server again.

You don't need to know NixOS. You do need to be comfortable opening a
terminal. An AI coding agent such as [Claude Code](https://claude.com/claude-code)
can do most of the install for you (see
[the easy way](#the-easy-way-let-an-ai-agent-install-it)).

## What you get

Once it's installed, every app is up, logged in and connected to the others.
They're on your home network at `https://<app>.<your domain>`:

| Address | App | What it's for |
| --- | --- | --- |
| `homepage.<domain>` | [Homepage](https://gethomepage.dev) | Your start page: every app, its status, and what's downloading |
| `plex.<domain>` | [Plex](https://www.plex.tv) | Watch your library. Plex's apps for TVs, phones, Roku, Apple TV and so on find the server through your plex.tv account |
| `jellyseerr.<domain>` | [Jellyseerr](https://github.com/seerr-team/seerr) | Browse and request movies and shows; share it with your household |
| `sonarr.<domain>` | [Sonarr](https://sonarr.tv) | Tracks your TV shows: grabs new episodes, upgrades quality, names and files them |
| `radarr.<domain>` | [Radarr](https://radarr.video) | The same for movies |
| `sabnzbd.<domain>` | [SABnzbd](https://sabnzbd.org) | Downloads from usenet, for Sonarr and Radarr |
| `bazarr.<domain>` | [Bazarr](https://www.bazarr.media) | Finds subtitles in your languages |
| `tautulli.<domain>` | [Tautulli](https://tautulli.com) | Plex statistics: who watched what, and when |
| `audiobookshelf.<domain>` | [Audiobookshelf](https://www.audiobookshelf.org) | Audiobooks and podcasts, with its own phone apps |
| `transmission.<domain>` | [Transmission](https://transmissionbt.com) + [Flood](https://flood.js.org) | A torrent client, for downloads you add by hand (it isn't connected to Sonarr or Radarr) |
| `homebridge.<domain>` | [Homebridge](https://homebridge.io) | Optional: a HomeKit bridge |

**How a request flows:** you ask for a movie in Jellyseerr. Radarr searches
your usenet indexer for it and hands the best match to SABnzbd. When the
download is done, Radarr renames it into `Movies` and Plex picks it up.
Bazarr then fetches subtitles. TV shows go the same way through Sonarr, and
new episodes keep arriving on their own.

**Behind the scenes:**

- **Already set up.** Logins, API keys, download clients, indexers, quality
  profiles and the Plex libraries (Movies, TV Shows, Videos) are all done on
  first boot, through each app's own API. There are no setup wizards to
  click through, apart from the few steps in [First run](#4-first-run).
- **One password per app,** generated on the server. `sudo spudbox-passwords`
  prints them.
- **Nightly backups** of every app's settings and database, kept on your
  data disks and optionally copied off-site (S3 or Cloudflare R2), with a
  one-command restore. Your media files aren't backed up (see
  [Hardware](#hardware)).
- **A health check.** `./deploy.sh test` runs about 250 checks: every app
  answers, logins are enforced, secrets are locked down, the disks are
  mounted, and the last backup is under two days old.
- **Updates in one command.** `./deploy.sh update` moves to the newest
  spudbox and NixOS packages, and a bad update rolls back in one command.
- **Optional extras:** phone alerts when something fails (Pushover), spinning
  idle hard drives down, fixing Dolby Vision files that some Plex clients
  can't play, a HomeKit bridge, and [Claude Code](https://claude.com/claude-code)
  on the server for maintenance.

**What it doesn't do:**

- It comes with no media and no accounts. You bring a usenet provider, an
  indexer and a plex.tv account (see [What you need](#what-you-need)).
- The web apps are reachable on your home network only. Plex is the
  exception: you can stream from outside your home (port 32400). For
  anything else away from home, set up a VPN yourself (e.g.
  [Tailscale](https://tailscale.com) or WireGuard).
- Its data disks aren't RAID: if a disk dies, the media on it is gone. Keep
  your own copy of anything you can't download again.

What you download is your responsibility: use it for content you have the
right to.

## What you need

### Hardware

Any ordinary 64-bit PC works. A used office desktop is a good, cheap choice.
It runs around the clock, so a low-power one pays off.

| | Minimum | Recommended |
| --- | --- | --- |
| **CPU** | 64-bit Intel or AMD | Intel with integrated graphics (Quick Sync), 8th-gen Core or newer, or an N100-class mini PC |
| **Memory** | 8 GB | 16 GB |
| **Boot disk** | 256 GB SSD | 1-2 TB NVMe SSD |
| **Data disks** | none (the library goes on the boot disk) | one or more large hard drives (8-20 TB each) |
| **Network** | wired Ethernet | gigabit Ethernet |

Things worth knowing when picking one:

- **Intel graphics matter for Plex.** When a TV or phone can't play a file
  as it is, Plex converts it on the fly. With Intel Quick Sync this is easy
  even on a cheap CPU; without it, the CPU does all the work. Plex's
  hardware transcoding needs a [Plex Pass](https://www.plex.tv/plex-pass/).
  The Dolby Vision fix-up extra needs an Intel iGPU too.
- **The boot disk holds more than the system.** It also holds every app's
  database, Plex's artwork, and downloads in progress (unless you add a
  separate cache disk with `cacheDrives`). That's why 1 TB or more is
  comfortable.
- **Data disks are pooled, not mirrored.** spudbox merges your data disks
  into one big folder (`/mnt/storage`) with [mergerfs](https://github.com/trapexit/mergerfs).
  You can add disks of different sizes later. A blank disk is formatted on
  first boot. A disk that already has a single XFS partition is used as it
  is, existing files included. spudbox leaves any other disk alone.
- **Room for hard drives.** A tower or small-form-factor case takes
  3.5-inch drives. Most mini PCs don't.
- **Memory.** The apps use about 3 GB. Updates are built on the server
  itself, so extra memory makes them quicker.
- **x86_64 is what's tested.** The module also evaluates for 64-bit ARM, but
  no ARM install has been tried, and the install steps assume a PC.

For a sense of scale, spudbox was built on an Intel Core i5-8400 (UHD 630
graphics) with 16 GB of memory, a 2 TB NVMe boot disk and one 14 TB hard
drive. At idle it uses about 3 GB of memory.

**For the install only:** a USB stick (2 GB or more), and a monitor and
keyboard on the server for a few minutes. The server boots in UEFI mode;
turn Secure Boot off.

### Accounts

| | What for | Cost |
| --- | --- | --- |
| A domain name | Gives each app its address. Point a wildcard record (`*.yourdomain`) at the server's home address | About $10 a year |
| A plex.tv account | Plex | Free; [Plex Pass](https://www.plex.tv/plex-pass/) is optional |
| A usenet provider | Where downloads come from | Paid subscription |
| A usenet indexer (e.g. [NZBGeek](https://nzbgeek.info)) | How Sonarr and Radarr search usenet | Usually a small yearly fee |
| Optional: [Cloudflare](https://www.cloudflare.com) DNS for your domain | Real HTTPS certificates. Without it the apps use spudbox's own certificate, which browsers warn about until you trust it | Free |
| Optional: [OpenSubtitles](https://www.opensubtitles.com) | Subtitles in Bazarr | Free tier |
| Optional: an S3 bucket (e.g. Cloudflare R2), [Pushover](https://pushover.net) | Off-site backups; failure alerts | Pay as you go; one-time app purchase |

### Your own computer

macOS or Linux (on Windows, WSL should work but hasn't been tried), with
`git`, `ssh` and `rsync`. [git-crypt](https://github.com/AGWA/git-crypt) is
recommended: it keeps your passwords encrypted in git. You don't need NixOS
or Nix: the server builds everything itself.

## Setting up a server

Plan on about an hour of your own time, plus waiting while the server builds
(10 to 60 minutes, depending on the machine).

Two repositories are involved:

- **This one** holds the code: a NixOS module (the `spudbox.*` settings), a
  test suite, and a template.
- **Yours** is made from [`template/`](template). It holds only what's
  specific to your server: `spudbox.nix` (your settings), `hardware.nix`,
  `secrets/` (encrypted) and `deploy.sh`. Its `flake.lock` pins a version of
  this repository, and `./deploy.sh update` moves it. Keep it private.

`deploy.sh` runs on your own computer. It copies your repository to the
server over SSH, and the server builds.

### The easy way: let an AI agent install it

The install is packaged as a step-by-step guide for AI coding agents,
[`.claude/skills/install-spudbox/SKILL.md`](.claude/skills/install-spudbox/SKILL.md).
The agent runs the commands on your computer and on the server, and asks
you whenever a step needs your hands or a decision.

**With Claude Code** (needs a Claude subscription or an Anthropic API key):

```bash
curl -fsSL https://claude.ai/install.sh | bash   # or see claude.com/claude-code
git clone https://github.com/mluds/spudbox
cd spudbox
claude
```

Then type `/install-spudbox`.

**With another agent** (Codex, Gemini CLI, Cursor, Copilot, Aider, ...):
clone the repository, start the agent in it, and tell it:

> Read `.claude/skills/install-spudbox/SKILL.md` and follow it to install
> spudbox on my server.

Agents that read [`AGENTS.md`](AGENTS.md) are pointed there already. The
guide is plain Markdown, so any agent that can run shell commands can follow
it.

What the agent does, in order:

1. Checks your computer has what it needs, and makes an SSH key if you don't
   have one.
2. Asks for your settings in a few short rounds: domain, login user, usenet
   servers and indexers, subtitle languages, extras.
3. Creates your private instance repository, with encryption for the
   secrets.
4. Gives you a command to type each password or API key into **your own
   terminal**. Secrets never go through the chat, and the agent only checks
   that they exist.
5. Tells you how to boot the server from the NixOS USB stick, then connects
   to it.
6. Lists the disks and has you pick the boot disk. It erases it only after
   you type that disk's name back, and it never wipes a data disk without
   the same confirmation.
7. Installs, reboots, waits for the apps to configure each other and runs the
   health check.
8. Walks you through the first-run steps and hands over: where your logins
   are, and what to save in your password manager.

If it stops partway, start it again: it works out where it got to.

**What you do yourself:** write the USB stick and boot the server from it,
type a temporary password on the server's console, type in your secrets, and
check the boot disk before it's erased. You'll also add the DNS record, and
finish Plex's setup in a browser if it couldn't sign in to your account by
itself.

### By hand

These are the same steps the agent follows.

#### 1. Make your instance repository

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

#### 2. Boot the installer and partition the boot disk

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

#### 3. Install

From your instance repository (unlocked, if you use git-crypt):

```bash
./deploy.sh hardware root@<ip>   # writes hardware.nix from the machine
./deploy.sh install root@<ip>    # copies config + secrets, runs nixos-install
git add -A && git commit -m "Install"   # hardware.nix and flake.lock
ssh root@<ip> reboot             # and remove the USB stick
```

Root's password stays locked. Log in as your user with your SSH key; from
now on everything goes through `./deploy.sh`.

#### 4. First run

After the reboot, give the apps a few minutes to configure each other, then:

```bash
./deploy.sh test          # all checks should pass, apart from what's below
./deploy.sh ssh
sudo spudbox-passwords    # the web UI logins (save them)
```

To reach the apps by name:

- Give the server a fixed address (a DHCP reservation in your router).
- Add a wildcard DNS record, `*.<domain>`, pointing at that address. At
  Cloudflare, set it to "DNS only", not proxied. A router or Pi-hole that can
  answer for your domain works too.
- With `tls = "internal"`, have your devices trust Caddy's root certificate,
  `/var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt` on the
  server. Until then, browsers show a warning.

Then open `https://homepage.<domain>`.

**Already have media?** Copy it into the library folders on the server
(`/mnt/storage/data/media/movies`, `tv`, `videos` and `audiobooks`) with
`sudo`, then hand it to the apps' group:
`sudo chown -R media:media /mnt/storage/data/media`. Plex picks it up by
itself. Sonarr and Radarr adopt existing folders on their next setup run:
`sudo systemctl restart sonarr-config radarr-config`.

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

# spudbox

**Turn a spare PC into a home media server that runs itself.**

spudbox sets up a server that streams your movies, TV shows and audiobooks
to every screen in the house. Once it's installed:

- **Watch** in the Plex app on your TV, phone, tablet or browser. Streaming
  away from home needs a [Plex Pass](https://www.plex.tv/plex-pass/).
- **Request** a movie or show in Jellyseerr. It's downloaded, filed and
  subtitled, and shows up in Plex when the download finishes. New episodes
  of the shows you follow arrive on their own.
- **Share** your library with family and friends. They can make requests
  too.
- **Leave it alone.** It backs itself up every night and can alert your
  phone when something fails.

You describe the server in one settings file, and spudbox installs and
connects about a dozen apps on [NixOS](https://nixos.org). You don't need to
know NixOS: an AI agent such as [Claude Code](https://claude.com/claude-code)
can do most of the install for you (see
[Setting up a server](#setting-up-a-server)).

## Requirements

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
| A plex.tv account | Plex | Free. A [Plex Pass](https://www.plex.tv/plex-pass/) adds hardware transcoding and streaming away from home |
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

### Install with an AI agent

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

No agent? The guide is plain step-by-step instructions, so you can follow it
yourself.

**What you do yourself:** write the USB stick and boot the server from it,
type a temporary password on the server's console, type in your secrets, and
check the boot disk before it's erased. You'll also add the DNS record, and
finish Plex's setup in a browser if it couldn't sign in to your account by
itself.

## Apps

Every app is up, logged in and connected to the others. Each has its own
page on your home network, at `https://<app>.<your domain>`:

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
  click through, apart from the few first-run steps the install walks you
  through.
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

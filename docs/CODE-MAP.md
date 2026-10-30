# spudbox: code map and improvement log

Loaded into every Claude session through `CLAUDE.md`. **Check this file before
starting any cleanup, hardening or review**, so work isn't duplicated and
settled questions aren't re-raised.

Keeping it current:

- **Starting an item:** set its Status in *Open improvements* to `In progress (<who>, <date>)`.
- **Finishing one:** delete its row and add a line at the top of *Done*:
  date, commit, one-line summary.
- **Deciding against one:** move it to *Won't fix*, with the reason.
- **Finding something new:** add a row to *Open improvements*.
- **Changing the layout** (new service, file or convention): update *Code outline* and *Notes*.

History before the module was split out of the original single-server repo
(2026-10-18 to 2026-10-26: reviews, hardening, sandboxing, efficiency) is
in that server's instance repository.

## Code outline

About 5,000 lines. `module.nix` imports one module per service. Most
services also have a `*-config` oneshot that sets up the app through its
HTTP API, config file or SQLite DB on every boot, and on a switch that
changes the unit. Caddy is the only way into the web UIs from the LAN; Plex
on 32400 is the exception. Optional features are off unless an instance
enables them.

| Path | What it does |
| --- | --- |
| `flake.nix` | `nixosModules.default`, `lib.mkSystem`, `templates.default`, lint `devShell`, `checks.*.template`. One `nixpkgs` input. |
| `module.nix` | Imports, base packages, nix GC (5 generations), SSH (keys only), sudo, firewall, users, IPv6 off (`networkmanager-ipv6-off` sets every wired NetworkManager profile to `ipv6.method=disabled`). Plex overlay. `create-dirs` oneshot: media dirs (non-recursive), secrets perms, backup dir. Apps that use the pools get `RequiresMountsFor`. `spudbox-test`. |
| `storage.nix` | Mounts the XFS data disks (`nofail`), pools them with mergerfs. `ensure-partition-*` formats a blank disk before its mount. hdparm udev rule. |
| `common/options.nix` | Every setting (`spudbox.*`) and its default; `spudbox.features`. The internal `revision` and `onFailure` are declared next to their code (`env.nix`, `notify.nix`). |
| `common/env.nix` | `/etc/spudbox/env` for `test.sh` and `deploy.sh`. |
| `common/secrets.nix` | `spudbox-secrets` (generates internal secrets, lists missing third-party ones), `spudbox-passwords`. Exports `REQUIRED_SECRETS`, `GENERATED_SECRETS`, `PASSWORD_SERVICES` (the web UIs with their own password). |
| `common/helpers.nix` | The `helpers` module arg: `read-secret`, `wait-for-http`. |
| `services/caddy.nix` | Reverse proxy per subdomain (`<name>` to `spudbox.<name>Port`), LAN-only (`remote_ip private_ranges`). `tls`: Cloudflare DNS-challenge wildcard cert (`caddy-config` writes the token env file) or `local_certs`. Sandboxed: only `CAP_NET_BIND_SERVICE`. |
| `services/hardening.nix` | Shared systemd sandbox settings, merged into units that handle untrusted input. |
| `services/plex.nix` + `plex-config.py` | Plex (GPU-only device access, no capabilities), plus token sign-in, claiming an unclaimed server for the account (a plex.tv claim token posted to the local `/myplex/claim`), libraries and remote-access settings. `ExecStop` signals Plex itself, not the FHS env's `bwrap`, so it stops cleanly. |
| `services/tautulli.nix` + `tautulli-config.py` | Rewrites `config.ini` (login hash, Plex link). Exports the API key. |
| `services/sabnzbd.nix` | SABnzbd via NixOS `settings` + `secretValues`; servers from `usenet.*`. Hourly `sabnzbd-resume` (no `Requires=`; exits 0 if SABnzbd is down). |
| `services/transmission.nix` | Transmission 4 + Flood UI. RPC credentials built in `ExecStartPre`. |
| `services/audiobookshelf.nix` + `audiobookshelf-access.py` | Every boot: checks the root password, issues homepage's read-only API key. |
| `services/audiobookshelf-config.py` | First-time setup (run by `audiobookshelf-access` while the DB has no users): seeds the root user in SQLite, library, users. By hand it refuses if users exist, unless `ABS_FORCE=1`. |
| `services/homepage.nix` | Dashboard, built with `tile`/`widget` helpers; title and bookmarks from `homepage.*`. Keys come through `LoadCredential`. |
| `services/homebridge.nix` | `homebridge.enable`: Homebridge in Docker (pinned digest; Docker only for this). `homebridge-config` does first setup (pinned `homebridge-dummy` for `dummySwitches`) and checks the password. Avahi. |
| `services/backup.nix` | restic: nightly `/var/lib` backup to the data disks; with `offsiteBackup`, `restic copy` to an S3 bucket, prune, check. Skips caches, poster art, logs and app-internal backups. `spudbox-restore`: stops the apps, restores their state dirs (rsync `--delete`, re-owned to today's owners) and the secrets (never deleting newer ones), restarts them and the setup units. |
| `services/drive-check.nix` + `drive-wakes.py` | `hddSpindown`: 5-minute timer that forces idle data HDDs into standby, logging each spin-down and wake. `drive-status-http` serves JSON for homepage. Resolves by-id paths for `/sys/block`. `drive-wake-trace` (bpftrace): every first disk request after 60 s of quiet, with the cgroups that asked a mergerfs pool for something in the 30 s before (a kprobe on `__fuse_simple_request`; the disk itself only sees mergerfs and kernel threads). `sudo drive-wakes [--since WHEN]` turns it into a timeline of wakes and their likely causes. |
| `services/media-fixup.{nix,sh}` | `mediaFixup`: 15-minute timer, DV5 to HDR10, hybrid DV8 strip, SRT `<font>` cleanup. x86_64 + Intel iGPU. Sandboxed as user `media-fixup` (CAP_CHOWN only, writes only `<storageDir>/data`). |
| `services/notify.nix` | Lists the setup oneshots and timer jobs. With `pushover`, `notify-failure@` sends a Pushover alert with the journal tail when one fails (`spudbox.onFailure`). Setup oneshots get `Type=oneshot` and `RemainAfterExit` here. Exports `ALERT_UNITS` and `SETUP_UNITS`. |
| `services/claude-code.nix` | `claudeCode`: Claude Code Remote Control as `claudeCode.user`. Never restarted by a switch (`restartIfChanged = false`). Status-screen redraws filtered from the journal. |
| `services/servarr/mkArrConfig.nix` | Returns the Sonarr/Radarr module: the app (loopback only) plus its `*-config` unit (login, `indexers`, SABnzbd, quality, custom formats, folder import). |
| `services/servarr/{sonarr,radarr}.nix` | The apps plus their mkArrConfig args. Radarr also has the `radarr-auto-import` timer: skips permanently rejected files, tries each download once, no `Requires=` on Radarr. No scheduled disk rescan (`rescanAfterRefresh = "afterManual"`). |
| `services/servarr/qualityDefinitions.nix` | Size limits and quality profiles. |
| `services/servarr/set-config-xml.nix` | Writes secret files into `config.xml` without putting them on argv. |
| `services/servarr/bazarr.nix` + `bazarr-config.py` | Merges a YAML template into the config (providers from `subtitleProviders`; Bazarr keeps its own API key). Rewrites language profiles from `bazarr.languageProfiles`. |
| `services/servarr/jellyseerr.nix` | seerr under a fixed user, sandboxed, config always in `/var/lib/jellyseerr/config`. First-run setup, Plex/arr links, Pushover. |
| `test.sh` | About 250 server checks, gated on `FEATURES`. Installed as `spudbox-test`. |
| `tests/vm.nix` | `checks.x86_64-linux.vm`: a fresh install of the template's settings in a VM, offline, with a blank data disk: secrets, disk format + pool, setup units, IPv6, Caddy with its CA, anonymous API refused, backup then `spudbox-restore`. Several minutes. |
| `.github/workflows/check.yml` | CI on every push: lint, the two evaluation checks, the VM test (KVM). |
| `lint.sh` + `ruff.toml`, `_typos.toml`, `.gitleaks.toml` | statix, deadnix, nixfmt, shellcheck, ruff check/format, gitleaks, typos (`nix develop -c ./lint.sh`). |
| `template/` | A new instance: `flake.nix`, example `spudbox.nix`, placeholder `hardware.nix`, `deploy.sh` (+ `install`, `hardware`, `update`, `secret NAME`; `SSH_OPTS`), `deploy.env`, `secrets/README.md`. |
| `scripts/partition-boot-disk.sh` | Erases and partitions the boot disk on the NixOS installer (ESP + ext4, mounted at `/mnt`). Refuses off the installer (`/iso`), on a disk with anything mounted, or without `CONFIRM=<disk name>`. Mounts with explicit types (the installer may not have ext4 loaded). |
| `.claude/skills/install-spudbox/` | The `/install-spudbox` Claude Code skill: settings → instance repo → secrets (typed by the person, never through the chat) → installer → partition (typed confirmation) → `deploy.sh install` → first-run steps. Resumable, and self-contained: it asks for and explains everything, so a newcomer never needs the README. Keep it in step with `deploy.sh` and `docs/GUIDE.md`'s Requirements. |
| `README.md`, `docs/GUIDE.md` | The front page (what spudbox is, how to start the install) and the user guide (requirements, apps, day to day, backups, Claude Code login, settings, security model). |
| `AGENTS.md` | Points other AI agents at the install skill (installing) and at `CLAUDE.md` (changing the module). |

## Notes and gotchas

**Secrets**

- Never put a secret on argv. See `CLAUDE.md` "Script conventions".
- Four kinds of secret, all in `secretsDir` (root-only): supplied by the
  instance (`REQUIRED_SECRETS`, third-party accounts), generated by
  `spudbox-secrets` if absent (`GENERATED_SECRETS`), exported at runtime by
  the setup units (below), and the instance's optional `users/<name>/hashed`.
- Non-root units get secrets via `LoadCredential=`, never through group access.
- Exported at runtime by the setup units: the Plex token and the Bazarr,
  Tautulli, Jellyseerr and Audiobookshelf API keys. Homepage starts after
  those units for this reason. The Sonarr, Radarr and SABnzbd keys are
  generated up front (they're written into the apps' configs).
- `users/*/plaintext` are recovery copies and are never deployed. `create-dirs`
  deletes them if they appear. (So Audiobookshelf's setup creates only its
  root account; other people are added in its UI.)
- `deploy.sh` copies secrets but never deletes them on the server
  (runtime-generated keys live next to them). Remove a retired secret by hand.

**Config oneshots**

- The setup oneshots (`SETUP_UNITS`: the `*-config` units, `create-dirs`,
  `audiobookshelf-access`) run on every boot, so they must be idempotent. They
  stay active afterwards (`RemainAfterExit`), so a switch re-runs only those
  whose unit changed. `deploy.sh` re-runs all of them when a secret changed.
  To re-apply one by hand: `sudo systemctl restart sonarr-config`.
- `sonarr-config` and `radarr-config` empty the app's `Users` table (with a
  30 s SQLite busy timeout: a just-started app holds the lock; on a first
  start they wait for the table, which appears after the file), rewrite
  `config.xml` and restart the app every time. POSTs for things that already
  exist fail, and the script skips them on purpose.
- `tautulli-config` and `bazarr-config` stop their app, edit its files, then
  start it again. Bazarr's language profiles are deleted and re-inserted each run.
- `audiobookshelf-config` runs as `audiobookshelf-access`'s `ExecStartPre`
  with `ABS_IF_EMPTY=1`: it waits for Audiobookshelf and does nothing once
  the database has users. Started by hand it runs `DELETE FROM users`, so it
  refuses on a live install unless `ABS_FORCE=1`.
- A setup unit must never block on restarting a unit ordered after it
  (`homepage-dashboard` is after the units that export its keys): use
  `systemctl --no-block`, or the first boot deadlocks.

**Networking**

- Every web UI binds 127.0.0.1. sonarr and radarr do this through
  `settings.server.bindaddress`, an env var that overrides `config.xml`.
- IPv6 is off by default (`disableIPv6`): sysctl, plus
  `networkmanager-ipv6-off` for NetworkManager's wired profiles (it re-enables
  IPv6 per profile, and that can't be a global default). A new NIC's profile
  is handled on the next boot.
- Homebridge uses host networking. `homebridge-config` keeps its UI on loopback.

**Storage**

- `sudo drive-wakes` (from `drive-wake-trace`) names what woke the disks:
  the nearest process that asked the pool for something before the disk's
  first request. A request served from cache can sit closer than the real
  cause, so read the "also asking" line too. `journalctl -u
  check-drive-status` has the raw spin-downs and wakes. media-fixup's 15-minute scan was
  measured at 0 disk reads (the directory tree stays cached).
- Sonarr and Radarr never rescan the library on a schedule
  (`rescanAfterRefresh = "afterManual"`). Files added, renamed or deleted
  outside the apps show up only after a manual Refresh in the app.
  media-fixup asks for a rescan of each file it rewrites.
- `ensure-partition-*` runs before each data drive's mount and only touches
  disks with no signature at all, because `/dev/sdX` names can move between
  boots (instances should use `/dev/disk/by-id`). A blank disk is
  partitioned and formatted XFS on the first boot that sees it.
- The backup stops the apps at 02:30. Units that talk to one of them must not
  have `Requires=` on it, because the stop propagates. A timer job gets killed
  mid-run (a `notify-failure@` alert) and can start the app again mid-backup:
  use `after` alone and exit 0 when the app doesn't answer. A setup oneshot is
  deactivated until the next switch: use `after` + `wants` (`plex-config`).
- `spudbox-restore` re-owns each restored dir to its service's `User=`/`Group=`,
  not to the dir's current owner: `/var/lib/radarr` is root's while Radarr's
  files under it aren't (the VM test caught Radarr crash-looping on that).
- Mounts are `nofail`. The local backup has `RequiresMountsFor`, so it never
  writes to the NVMe by mistake.
- Some drives (the WD Ultrastar this was written for) ignore `hdparm -S`, so
  `check-drive-status` (`hddSpindown`) spins them down itself after 300 s
  idle. It never calls `hdparm -C`, which resets the idle timer.

**Deploy and test**

- An instance's `deploy.sh` copies the working tree, not git, so uncommitted
  edits ship (the revision ends in `-dirty`).
- `~/deploy` on the server is not a git checkout, so `nixos-rebuild` copies
  all of it into the world-readable Nix store. That's why secrets must never
  land there.
- `test.sh` reads every list it loops over from `/etc/spudbox/env`. The
  state-dir and sandboxed-unit lists stay hand-kept on purpose: they are what
  the tests assert.
- A switch that changes a `*-config` unit re-runs it, and that restarts its
  app (Sonarr, Radarr, Bazarr, Tautulli). Let them settle before running
  `spudbox-test`, or you get spurious port failures.
- `claude-remote-control` is never restarted by a switch, because a deploying
  Claude session lives in it. Changes to it apply at the next boot or after
  `sudo systemctl restart claude-remote-control` over SSH.
- Building from a git worktree on the server: use a `path:` flake ref
  (`path:.#default`); a plain `.#` git flake fails there with libgit2
  "object not found".

## Open improvements

None open. Add new findings here as rows:

| # | Priority | Recommendation | Where | Why | Status |
| --- | --- | --- | --- | --- | --- |

Ideas considered and not done (2026-10-23):

- Run Homebridge natively instead of in Docker: drops the Docker daemon
  (~60 MB RAM, ~400 s CPU/week, 2.4 GB disk) but risks the HomeKit pairing.
- Turn off Avahi's reflector (not needed with host networking): ~190 s
  CPU/week, but HomeKit discovery is at stake.

## Done

Newest first. Don't redo these.

| Date | Commit | Change |
| --- | --- | --- |
| 2026-10-30 | `be55ada`, `477f0c4` | `/install-spudbox` run end to end by a fresh headless Claude Code session against a QEMU VM (real 26.05 minimal ISO, UEFI, NVMe boot disk, blank data disk), with a person answering: it asked for everything it needed and caught the VM's low memory. It found: `deploy.sh install` on a new instance (no `flake.lock`) failed with a NAR hash mismatch, because nixos-install wrote the lock mid-evaluation (now locked first; earlier tests used `SPUDBOX_SRC`, which already did); `sonarr-config` on first boot queried the database before Sonarr had created its tables ("no such table: Users"; `*arr-config` now waits for the table). The skill now expects the backup unit to show failed before Plex is set up (homepage can't restart), and apps restarted by a backup to need a minute. VM test 6/6. |
| 2026-10-29 | `711caaf`..`1b6f22d` | README cut to a front page: the intro, a minimal Installation (Claude Code, then `/install-spudbox`) and the license. Everything else (requirements and a hardware guide, the apps, day to day, backups, settings, security model) is in `docs/GUIDE.md`, with the Claude Code login added. The install skill is the one set of install steps and assumes the person has read neither: a Step 0 checks hardware and accounts, it says where to find each secret, and walks through DNS, trusting the internal CA, first-run steps and day-to-day commands. `AGENTS.md` points other agents at the skill. |
| 2026-10-29 | `15f2da7` | The review's open items: `spudbox-secrets` reports a missing plex.tv login (`plex/username` + `plex/password`) unless `plex/token` exists; `homebridge.service` has `restartTriggers` on its compose file (a new pin restarts it on deploy); `parted`, `gptfdisk`, `inotify-tools` no longer installed. |
| 2026-10-29 | `247e7ce` | Review pass (simplify, dead code, smells): `passwordServices` moved into `common/secrets.nix` (internal option gone); `bazarr.languageProfiles` into `options.nix`; `adminUserId` option → constant; duplicated loops in `create-dirs` and `ensure-partition` factored; plex/tautulli-config read secret paths from `SECRETS_DIR` (and no sleep after `systemctl stop`); homebridge compose command named once; redundant `Type=`/timer `Unit=` dropped; `deploy.sh` ssh command spelled once; stale nmcli/`set -e`/finding-#5 comments fixed. Evaluated system diffed: only those units change. VM test 6/6. |
| 2026-10-28 | `e724e12`, `5902502`, `a3d3e4e`, `b848e4e` | Disk-wake monitor: `drive-wake-trace` + `sudo drive-wakes` (ignores the spin-down command itself; logs the first request after it starts). It showed every HDD wake (~75 a day) was media-fixup: its temp dir lived on the pool (now in the state dir; pool scratch only when a video is rewritten), and three releases with 2097 modification times matched `-newer` every run (now `-cnewer`). After both, its runs leave the HDD in standby and take 1 s instead of ~55 s. |
| 2026-10-27 | `55a50b5` | Plex claims itself for the account; `networkmanager-ipv6-off` replaces the manual `nmcli` step; `spudbox-restore` / `./deploy.sh restore`; VM test (`tests/vm.nix`, all six subtests pass) and CI (`.github/workflows/check.yml`); history-specific checks dropped from `test.sh` (retired Gmail/admin secrets, `default.json`, seerr email). The VM test found and fixed: restore re-owning to the wrong user (Radarr crash loop), restore stopping when one app doesn't start, `*arr-config`'s SQLite "database is locked" after the app (re)starts; data mounts exposed as `spudbox.dataMounts` for the test. disko declined (Won't fix). |
| 2026-10-27 | `08f1aa5` | Review pass: `deploy.sh` carries on after a switch that only had failed units (exit 4) instead of skipping the setup re-runs, wait and tests; `checks.x86_64-linux.all-features` evaluates every optional feature; Audiobookshelf's never-reachable user creation from plaintext files removed; stale comments fixed. |
| 2026-10-27 | `7b01503` | `/install-spudbox` skill and `scripts/partition-boot-disk.sh`; `deploy.sh secret`, `SSH_OPTS`, installer-safe SSH. Tested end to end in a QEMU VM (UEFI, NVMe boot disk, blank virtio data disk) from the real 26.05 minimal ISO; that found and fixed: partition mount without `-t ext4`; `ensure-partition`'s blank check (blkid reports partition entries; now wipefs) and its double re-read that sent the first boot to emergency mode; mergerfs pools now `nofail` and the apps `RequiresMountsFor` them; Sonarr/Radarr config before their `config.xml` exists; Transmission before its dirs (`create-dirs` ordered first, `videos` dir added, no `Requires=local-fs.target`); a first-boot deadlock (blocking homepage restart in `audiobookshelf-access`); Audiobookshelf setup now automatic while the DB is empty; Tautulli locked down (login, loopback) and kept running before Plex has a token; `test.sh` without `set -e`, Caddy-CA aware, usenet-gated; backup dir created up front. Not testable without a real plex.tv account: the Plex sign-in chain. |
| 2026-10-26 | `3a991ca` | Split out of the single-server repo as a shareable module: `spudbox.*` options with defaults, personal values moved to the instance's `spudbox.nix`; optional `pushover`, `offsiteBackup`, `hddSpindown`, `mediaFixup`, `homebridge`, `claudeCode`, `tls = "internal"`; `indexers`, `usenet.*`, `subtitleProviders`, `bazarr.languageProfiles`, `homepage.*` options; `spudbox-secrets` generates internal secrets; `spudbox-test`; `ensure-partition` runs before each mount; drive-check resolves by-id paths; seerr config dir pinned; template + `deploy.sh install/hardware/update`. Evaluated config diffed against the single-server one: only the intended changes. |

## Won't fix

Don't re-raise these unless the setup changes.

| Item | Reason |
| --- | --- |
| Plex 32400 reachable directly | Needed for remote streaming. |
| Homebridge container runs as root with host networking | HomeKit needs mDNS on the host network. The UI is loopback-only. |
| Bazarr stores an unsalted MD5 password | It's Bazarr's own format. |
| No scheduled Sonarr/Radarr library rescan (2026-10-23) | Spares the HDD; manual Refresh when files change outside the apps. |
| `claudeCode` as a superuser gives Claude root | Documented on the option; it's the instance owner's call. |
| Declarative boot-disk partitioning with disko (2026-10-27) | The step it would remove is already automated (`scripts/partition-boot-disk.sh`, run by the install skill, tested in a VM). disko would add a second, untested path and a flake input, and conflict with existing installs' generated `fileSystems`. |

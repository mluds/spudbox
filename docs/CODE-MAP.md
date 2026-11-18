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
| `flake.nix` | `nixosModules.default`, `lib.mkSystem`, `templates.default`, lint `devShell`, `checks.*.template`, x86_64 `all-features`, `vm`, `caddy-cloudflare` (built). One `nixpkgs` input. |
| `module.nix` | Imports, base packages, nix GC (5 generations), SSH (keys only), sudo, firewall, users, IPv6 off (`networkmanager-ipv6-off` sets every wired NetworkManager profile to `ipv6.method=disabled`). `create-dirs` oneshot: media dirs (non-recursive), secrets perms, backup dir. Apps that use the pools get `RequiresMountsFor`. `spudbox-test`. |
| `storage.nix` | Mounts the XFS data disks (`nofail`), pools them with mergerfs. `ensure-partition-*` formats a blank disk before its mount. hdparm udev rule. `smartd` on every disk (skips sleeping ones); with `pushover`, its warnings go out through `notify-failure@smartd`. |
| `common/options.nix` | Every setting (`spudbox.*`) and its default; `spudbox.features`. The internal `revision` and `onFailure` are declared next to their code (`env.nix`, `notify.nix`). |
| `common/env.nix` | `/etc/spudbox/env` for `test.sh` and `deploy.sh`. |
| `common/secrets.nix` | `spudbox-secrets` (generates internal secrets, lists missing third-party ones), `spudbox-passwords`. Exports `REQUIRED_SECRETS`, `GENERATED_SECRETS`, `PASSWORD_SERVICES` (the web UIs with their own password). |
| `common/helpers.nix` | The `helpers` module arg: `read-secret`, `wait-for-http`. |
| `services/caddy.nix` | Reverse proxy per subdomain (`<name>` to `spudbox.<name>Port`), LAN-only (`remote_ip private_ranges`). `tls`: Cloudflare DNS-challenge wildcard cert (`caddy-config` writes the token env file) or `local_certs`. Sandboxed: only `CAP_NET_BIND_SERVICE`. |
| `services/hardening.nix` | Shared systemd sandbox settings, merged into units that handle untrusted input. |
| `services/plex.nix` + `plex-config.py` | Plex at the version in `plex.json` (an overlay, ahead of nixpkgs; bumped daily by `update.yml`). GPU-only device access, no capabilities; plus token sign-in, claiming an unclaimed server for the account (a plex.tv claim token posted to the local `/myplex/claim`), libraries and remote-access settings. `ExecStop` signals Plex itself, not the FHS env's `bwrap`, so it stops cleanly. |
| `services/tautulli.nix` + `tautulli-config.py` | Rewrites `config.ini` (login hash, Plex link). Exports the API key. |
| `services/sabnzbd.nix` | SABnzbd via NixOS `settings` + `secretValues`; servers from `usenet.*`. Hourly `sabnzbd-resume` (no `Requires=`; exits 0 if SABnzbd is down). |
| `services/transmission.nix` | Transmission 4 + Flood UI. RPC credentials built in `ExecStartPre`. |
| `services/audiobookshelf.nix` + `audiobookshelf-access.py` | Every boot: checks the root password, issues homepage's read-only API key. |
| `services/audiobookshelf-config.py` | First-time setup (run by `audiobookshelf-access` while the DB has no users): seeds the root user in SQLite, library, users. By hand it refuses if users exist, unless `ABS_FORCE=1`. |
| `services/homepage.nix` | Dashboard, built with `tile`/`widget` helpers; title and bookmarks from `homepage.*`. Keys come through `LoadCredential`. |
| `services/homebridge.nix` | `homebridge.enable`: Homebridge in Docker (pinned digest; Docker only for this). `homebridge-config` does first setup (pinned `homebridge-dummy` for `dummySwitches`) and checks the password. Avahi. |
| `services/backup.nix` | restic: nightly `/var/lib` backup to the data disks; with `offsiteBackup`, `restic copy` to an S3 bucket, prune, check. Skips caches, poster art, logs and app-internal backups. `spudbox-restore`: stops the apps, restores their state dirs (rsync `--delete`, re-owned to today's owners) and the secrets (never deleting newer ones), restarts them and the setup units. |
| `services/drive-check.nix` + `drive-wakes.py` | `hddSpindown`: 5-minute timer that forces idle data HDDs into standby, logging each spin-down and wake. `drive-status-http` serves JSON for homepage. Resolves by-id paths for `/sys/block`. `drive-wake-trace` (bpftrace): every first disk request after 60 s of quiet, with the cgroups that asked a mergerfs pool for something in the 30 s before (a kprobe on `__fuse_simple_request`; the disk itself only sees mergerfs and kernel threads). `sudo drive-wakes [--since WHEN]` turns it into a timeline of wakes and their likely causes. `vm.vfs_cache_pressure = 10` keeps the pool's directory tree cached. |
| `services/media-fixup.{nix,sh}` | `mediaFixup`: 15-minute timer, DV5 to HDR10, DV8 strip, SRT `<font>` cleanup. x86_64 + Intel iGPU. Sandboxed as user `media-fixup` (CAP_CHOWN only, writes only `<storageDir>/data`). |
| `services/notify.nix` | Lists the setup oneshots and timer jobs. With `pushover`, `notify-failure@` sends a Pushover alert with the journal tail when one fails (`spudbox.onFailure`). Setup oneshots get `Type=oneshot` and `RemainAfterExit` here. Exports `ALERT_UNITS` and `SETUP_UNITS`. |
| `services/auto-update.nix` | `autoUpdate`: nightly timer (04:30, after the backup) that fetches the instance repo with a generated deploy key (`secrets/auto-update/deploy-key`), and if the branch moved past the running `REVISION`, deploys it like `deploy.sh` (tree without `.git`/`secrets`, `.revision`), waits out Plex streams (up to 3 h), runs `spudbox-test` (twice if needed) and rolls back the system profile if it fails. Never restarted by a switch. Skips (and alerts after 3 days) when running a `-dirty` or off-branch revision; doesn't retry a failed commit. Exports `AUTO_UPDATE_REPOSITORY`/`_BRANCH`. |
| `services/claude-code.nix` | `claudeCode`: Claude Code Remote Control as `claudeCode.user`. Never restarted by a switch (`restartIfChanged = false`). Status-screen redraws filtered from the journal. |
| `services/servarr/mkArrConfig.nix` | Returns the Sonarr/Radarr module: the app (loopback only) plus its `*-config` unit (login, `indexers`, SABnzbd, quality, custom formats, folder import). |
| `services/servarr/{sonarr,radarr}.nix` | The apps plus their mkArrConfig args. Radarr also has the `radarr-auto-import` timer: skips permanently rejected files, tries each download once, no `Requires=` on Radarr. No scheduled disk rescan (`rescanAfterRefresh = "afterManual"`). |
| `services/servarr/qualityDefinitions.nix` | Size limits and quality profiles. |
| `services/servarr/set-config-xml.nix` | Writes secret files into `config.xml` without putting them on argv. |
| `services/servarr/bazarr.nix` + `bazarr-config.py` | Merges a YAML template into the config (providers from `subtitleProviders`; Bazarr keeps its own API key). Rewrites language profiles from `bazarr.languageProfiles`. |
| `services/servarr/jellyseerr.nix` | seerr under a fixed user, sandboxed, config always in `/var/lib/jellyseerr/config`. First-run setup, Plex/arr links, Pushover. |
| `test.sh` | About 250 server checks, gated on `FEATURES`. Installed as `spudbox-test`. |
| `tests/vm.nix` | `checks.x86_64-linux.vm`: a fresh install of the template's settings in a VM, offline, with a blank data disk: secrets, disk format + pool, setup units, IPv6, Caddy with its CA, anonymous API refused, backup then `spudbox-restore`. Several minutes. |
| `.github/workflows/check.yml` | CI on every push: lint, the two evaluation checks, the Caddy plugin build, the VM test (KVM). Also callable (`workflow_call` with a `ref`). |
| `.github/workflows/update.yml` + `scripts/update*.sh` | Daily: `update.sh` runs `update-{nixpkgs,caddy,plex,homebridge}.sh` (one commit each, a failed one skipped) on the `update` branch, then `check.yml` on it, then `main` fast-forwards through the refs API. Pins: `flake.lock`, `services/{caddy,plex,homebridge}.json`. See CLAUDE.md "Pinned versions". |
| `lint.sh` + `ruff.toml`, `_typos.toml`, `.gitleaks.toml` | statix, deadnix, nixfmt, shellcheck, ruff check/format, gitleaks, typos (`nix develop -c ./lint.sh`). |
| `template/` | A new instance: `flake.nix`, example `spudbox.nix`, placeholder `hardware.nix`, `deploy.sh` (+ `install`, `hardware`, `update`, `secret NAME`; `SSH_OPTS`; refuses to deploy a checkout behind `origin`), `deploy.env`, `secrets/README.md`, `.github/workflows/update-lock.yml` (daily `nix flake update spudbox`, evaluated, committed). |
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
- On a first start Sonarr/Radarr write `config.xml` in steps, so the file
  exists before it's complete; `*-arr-config` waits for the database too,
  which the app creates only after saving the config (~0.4 s later).
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
  measured at 0 disk reads (the directory tree stays cached), but it still
  woke the disk 1-2 times a day, after reclaim had dropped the tree's
  inodes: hence `vm.vfs_cache_pressure = 10` with `hddSpindown`.
  A wake whose disk request is a write or flush of 0 bytes after only
  lookups/readdirs (`rw=FF`/`WSM` in `journalctl -u drive-wake-trace`) is
  metadata being journalled, not a read: in the week to 2026-11-15 that was
  all 50 of the scan's wakes (relatime's daily atime write per directory
  read; now `noatime`), so they weren't cache misses.
- The trace records the requester's cgroup *name* when it asks the pool:
  `cgroup_path()` is resolved only when a wake is printed, so a unit that
  had stopped by then (media-fixup's `find`) showed up as "kernel".
- smartd uses `-n standby`: a check skips a sleeping disk. SMART commands
  don't show in `/sys/block/*/stat`, so they don't keep a disk awake for
  `check-drive-status` either (measured). Starting smartd (boot, or a deploy
  that changes it) can spin the disks up once. No scheduled self-tests: a
  long test on a big disk takes about a day and can't coexist with spindown.
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
- The update chain, all daily (times in New York): `update` (module,
  ~01:15) → `update-lock` (instance, ~02:45) → `spudbox-auto-update` (server,
  04:30). Bot pushes use `GITHUB_TOKEN`, which doesn't trigger other
  workflows: that's why `update` calls `check.yml` itself.
  GitHub runs these schedules late (observed 2026-11-16: both ~9.5 h after
  their cron time, still in order), so an update reaches a server at the
  04:30 after it lands, about a day later. Order isn't guaranteed: an
  `update-lock` that runs before `update` just picks it up the next day.
- CI never runs Homebridge, and evaluates rather than builds the
  all-features system: the Caddy plugin is the one piece of it built there
  (its hash breaks on nixpkgs bumps). A bad Homebridge image shows up only
  in the server's `spudbox-test`, which rolls the update back.
- `spudbox-auto-update` runs `nixos-rebuild switch` from inside a unit, so
  it has `restartIfChanged = false` (like `claude-remote-control`).
  It runs `spudbox-test` with `/run/wrappers/bin` and the system profile on
  `PATH`: a unit's own PATH has no `sudo`, and the first live run failed
  157 checks (and rolled back) without them. Its stubbed tests couldn't
  see that; test a change to it with a real run on the server.
  It compares only the instance revision: a deploy with `SPUDBOX_SRC` (an
  unreleased module) is replaced by the branch the next time the branch
  moves, so push module work before the instance's next `update-lock`.
- Building from a git worktree on the server: use a `path:` flake ref
  (`path:.#default`); a plain `.#` git flake fails there with libgit2
  "object not found".

## Open improvements

Add new findings here as rows:

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
| 2026-11-18 | (this commit) | The daily `update` run's VM test failed: `sonarr-config` read `config.xml` while Sonarr was still writing it on its first start ("Extra content at the end of the document"; Sonarr logged the save 0.13 s later). The script waited only for the file to exist, then for the `Users` table only if the database already existed, which Sonarr creates ~0.4 s after the save. A race with the 2 s poll (~10-20% of runs): the same commit passed 3/3 locally. With the poll forced to 0.05 s it failed every time before the fix and passed twice after; the real VM test 6/6. Now waits for `config.xml` and the database. Not caused by the nixpkgs bump it was testing (no app versions changed). |
| 2026-11-15 | `e75661a`, `91fcd0a` | Every pin updates daily, not just Plex: `update.yml` (was `update-plex.yml`) runs `scripts/update.sh` → `update-{nixpkgs,caddy,plex,homebridge}.sh`, one commit each, a failed one skipped (run marked failed). Caddy plugin and Homebridge pins moved to `services/{caddy,homebridge}.json` (all-features system unchanged); `checks.x86_64-linux.caddy-cloudflare` builds the plugin in CI. First run (`98252d8`..`b603f28`): nixpkgs 26f4107 → f1e5c35 (Linux 6.18.63, Sonarr 4.0.20, Transmission 4.1.4), a new Caddy plugin hash for the same Caddy 2.11.7 (the old one no longer built), Homebridge 2026-02-25 → 2026-11-15; CI incl. the VM test passed before `main` moved. |
| 2026-11-15 | `6c5ea97`, `8f590fb` | Hands-off updates. Plex's pin moved to `services/plex.json`, which the daily `update-plex` workflow bumps (SHA-1 checked against plex.tv, then `check.yml` incl. the VM test before `main` fast-forwards). Instances get `update-lock.yml` (daily `nix flake update spudbox`, evaluated, committed) and `spudbox.autoUpdate`: a 04:30 deploy of the instance branch via a generated deploy key, waiting out Plex streams, with `spudbox-test` and a rollback on failure. `deploy.sh` refuses a checkout behind `origin`. The evaluated template was unchanged by the refactor (x86_64, aarch64); the update script's decision paths (up to date, deploy, failed tests → rollback + no retry, build failure, exit 4, dirty/off-branch skip + 3-day alert, Plex streaming wait) were tested against a scratch repo with stubs. VM test 6/6. |
| 2026-11-15 | `af8258e` | Fewer HDD wakes: `drive-wakes` showed 84 in a week. 50 were media-fixup's scan and ~5 Bazarr's 6-hourly health check, all relatime's once-a-day atime write per directory read (0-byte flushes after cached lookups), so the data XFS mounts are now `noatime`. Most of Bazarr's ~18 read wakes were its subtitle searches reading 64 KB from each end of every video for an OpenSubtitles hash no enabled provider uses: `general.skip_hashing = true`. Left: Plex's nightly 02:00 maintenance scan and real playback. `spudbox-test` checks both settings; VM test 6/6. |
| 2026-11-15 | `1dde8bd` | The `sonarrPort`, `radarrPort`, `bazarrPort`, `jellyseerrPort` and `transmissionPort` options now reach the apps (`settings.server.port`, `listenPort`, `services.seerr.port`, `rpc-port`); before, only the clients read them, so a changed port broke the Caddy route and setup unit. Template and all-features check derivations unchanged at the default ports; an evaluation with every one changed shows each app on its new port. |
| 2026-11-15 | `3560010`..`70f85b5` | Simplify pass over the whole tree (most of it was already clean after `247e7ce`): Caddy's proxied-app list in one block (`genAttrs` ignores order); Audiobookshelf's two environment attrsets merged (the first was only ever merged into the second); `flake.nix` checks name `pkgs` and an `evaluates NAME NIXOS` helper instead of repeating `writeText (unsafeDiscardStringContext ...drvPath)` around a 40-line `extendModules`. The template, all-features and vm check derivations are identical to before (x86_64 and aarch64), so both evaluated systems are byte-identical. Found the unwired `*Port` options (Open #1). Declined deduplications are under Won't fix. |
| 2026-11-07 | `7ce6c6a` | media-fixup strips the DV layer from every Dolby Vision profile 8 file, not only ones named "hybrid": a UHD Blu-ray encode converted from profile 7 (The Secret Agent, `…UHD.BluRay…DV.HDR.x265-hallowed`, DV 8.1 with an HDR10 base) wouldn't play on the Apple TV in Plex, and its name gave no hint. Radarr's "DV without HDR fallback" format still lets these through (they have HDR10). Deployed from the server with `--override-input` (with `main`'s undeployed `4af00f1`); 255/255. |
| 2026-11-02 | `c87aaaa` | Audit of the running server (journal, resource use, SMART, `drive-wakes`): no failed units, `spudbox-test` 255/255, backups clean. Since the media-fixup fix the HDD wakes ~5 times a day: Plex's 02:00 maintenance, media-fixup's `find` 1-2 times (reported as "kernel": now named, and `vfs_cache_pressure` lowered), and Bazarr re-probing unreadable files. Added `smartd` (nothing watched the disks; both healthy, HDD 45k hours) with Pushover alerts; seerr at `info`. VM test 6/6. |
| 2026-10-30 | `1f42dea` | Second `/install-spudbox` VM run, with the real plex.tv, usenet and NZBGeek accounts: 208/208 after re-running the setup units; NZBGeek's indexer test passes in Sonarr and Radarr, and SABnzbd shows all five servers active with no errors. It found `plex-config` adding the first library a few seconds after claiming Plex, which Plex refuses with 400 "the server is still starting up. Please retry later" (now retried for up to two minutes); `jellyseerr-config` then found no Plex libraries, which follows from that. The skill now says what each account is for, with sign-up links (Plex, a few usenet providers and indexers, registrars). Claiming the test VM left it on the real plex.tv account. |
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
| Shared helpers for small repeated snippets (2026-11-15): the `LoadCredential` mapping (homepage, sabnzbd, media-fixup), `json = escapeShellArg (toJSON ...)` (mkArrConfig, jellyseerr), `uniqueDevices` (homepage, drive-check), `read_secret`/`read_file` in the Python scripts | Each is a one-liner. A shared home (a Nix lib module argument, a Python module on every script's path) costs more to follow than the repetition does. |
| Unifying media-fixup's Sonarr/Radarr `rescan` branches, or the units listed in `module.nix`'s `RequiresMountsFor` and `create-dirs.before` (2026-11-15) | The branches differ in endpoint, jq filter and command; the two unit lists differ (Bazarr is only in the first), so deriving one from the other would change unit ordering. |
| Declarative boot-disk partitioning with disko (2026-10-27) | The step it would remove is already automated (`scripts/partition-boot-disk.sh`, run by the install skill, tested in a VM). disko would add a second, untested path and a flake input, and conflict with existing installs' generated `fileSystems`. |

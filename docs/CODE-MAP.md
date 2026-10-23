# spudbox: code map and improvement log

Loaded into every Claude session through `CLAUDE.md`. **Check this file before
starting any cleanup, hardening or review**, so work isn't duplicated and
settled questions aren't re-raised. Operations (deploy, rollback, upgrades,
restores) stay in `CLAUDE.md` and `README.md`.

Keeping it current:

- **Starting an item:** set its Status in *Open improvements* to `In progress (<who>, <date>)`.
- **Finishing one:** delete its row and add a line at the top of *Done*:
  date, commit, one-line summary.
- **Deciding against one:** move it to *Accepted risks / won't fix*, with the reason.
- **Finding something new:** add a row to *Open improvements*.
- **Changing the layout** (new service, file or convention): update *Code outline* and *Notes*.

Last full review: 2026-10-22, at commit `b0918aa`.

## Code outline

One NixOS flake, about 5,400 lines. `configuration.nix` imports one module per
service. Most services also have a `*-config` oneshot that sets up the app
through its HTTP API, config file or SQLite DB on every boot and switch. Caddy is
the only way into the web UIs from the LAN; Plex on 32400 is the exception.

| Path | What it does |
| --- | --- |
| `flake.nix` | One `nixpkgs` input. Hosts `spudbox-prod` (x86_64) and `spudbox-dev` (aarch64). Hand-pinned Plex overlay. Sets `system.configurationRevision`. |
| `hosts/prod-hardware.nix` | Prod's generated hardware config, so prod builds pure. Lint skips it; regenerate rather than edit. |
| `configuration.nix` | Shared config: imports, packages, nix GC, SSH, sudo, firewall, users, IPv6 off. `create-dirs` oneshot: media dirs (non-recursive), secrets perms, deletes retired secrets. |
| `storage.nix` | Formats blank XFS disks (`ensure-partition-*`), mounts them, pools them with mergerfs. hdparm udev rule. |
| `common/vars.nix` | Typed `my.*` options (ports, dirs, drives, users, `prowlarr.enable`). |
| `common/env.nix` | Writes `/etc/spudbox/env` (dirs, domain, `REVISION`, every `*_PORT`) for `test.sh` and `deploy.sh`. Modules append `CADDY_HOSTS`, `PASSWORD_SERVICES`, `ALERT_UNITS`, `PROWLARR_ENABLED`. |
| `common/helpers.nix` | The `helpers` module arg: `read-secret`, `wait-for-http`. |
| `environments/default.nix` | Ports, dirs, usenet hosts, users. `{prod,dev}.nix`: domain and drives per host. |
| `services/caddy.nix` | Reverse proxy per subdomain, LAN-only (`remote_ip private_ranges`). Cloudflare DNS-challenge wildcard cert. `caddy-config` writes the token env file. Sandboxed: only `CAP_NET_BIND_SERVICE`. |
| `services/hardening.nix` | Shared systemd sandbox settings, merged into units that handle untrusted input. |
| `services/plex.nix` + `plex-config.py` | Plex (GPU-only device access, no capabilities), plus libraries, token sign-in and remote-access settings. |
| `services/tautulli.nix` + `tautulli-config.py` | Rewrites `config.ini` (login hash, Plex link). Exports the API key. |
| `services/sabnzbd.nix` | SABnzbd via NixOS `settings` + `secretValues`. Hourly `sabnzbd-resume`. |
| `services/transmission.nix` | Transmission 4 + Flood UI. RPC credentials built in `ExecStartPre`. |
| `services/audiobookshelf.nix` + `audiobookshelf-access.py` | Every boot: checks the root password, issues homepage's read-only API key. |
| `services/audiobookshelf-config.py` | One-off, started by hand: seeds the root user in SQLite, library, users. Refuses if users exist, unless `ABS_FORCE=1`. |
| `services/homepage.nix` | Dashboard. Keys come through `LoadCredential`. |
| `services/homebridge.nix` | Homebridge in Docker (pinned digest). `homebridge-config` does first setup (pinned `homebridge-dummy`) and checks the password. Avahi. |
| `services/docker.nix` | Docker, used only by Homebridge. |
| `services/backup.nix` | restic: nightly `/var/lib` backup to the HDD, then `restic copy` to Cloudflare R2. Skips caches, poster art, logs and app-internal backups. |
| `services/drive-check.nix` | 5-minute timer that forces the HDD into standby when idle, logging each spin-down and wake. `drive-status-http` serves JSON for homepage. |
| `services/media-fixup.{nix,sh}` | 15-minute timer: DV5 to HDR10, hybrid DV8 strip, SRT `<font>` cleanup. x86_64 only. Sandboxed as user `media-fixup` (CAP_CHOWN only, writes only `/mnt/storage/data`). |
| `services/notify.nix` | Lists the setup oneshots and timer jobs. `notify-failure@` sends a Pushover alert with the journal tail when one fails. Setup oneshots get `RemainAfterExit` (run once per boot or change). Exports `ALERT_UNITS` and `SETUP_UNITS`. |
| `services/claude-code.nix` | Claude Code Remote Control, running as `luds`. Never restarted by a switch (`restartIfChanged = false`). Its status-screen redraws are filtered from the journal. |
| `services/servarr/mkArrConfig.nix` | Shared `sonarr-config`/`radarr-config` builder: login, indexer, SABnzbd, quality, custom formats, folder import. |
| `services/servarr/{sonarr,radarr}.nix` | The apps plus their mkArrConfig args. Radarr also has the `radarr-auto-import` timer: skips permanently rejected files, tries each download once. The scheduled metadata refresh doesn't rescan the disk (`rescanAfterRefresh = "afterManual"`): files changed outside the apps show up after a manual refresh. |
| `services/servarr/qualityDefinitions.nix` | Size limits and quality profiles. |
| `services/servarr/set-config-xml.nix` | Writes secret files into `config.xml` without putting them on argv. |
| `services/servarr/prowlarr.nix` | Prowlarr, **off** (`my.prowlarr.enable = false`; code kept). Enabling it restores its Caddy site, homepage tile, backup stop, alerts and tests. Add sandboxing when re-enabling (it scored 8.2). |
| `services/servarr/bazarr.nix` + `bazarr-config.py` | Merges a YAML template into the config. Rewrites language profiles. |
| `services/servarr/jellyseerr.nix` | seerr under a fixed user, sandboxed. First-run setup, Plex/arr links, Pushover. Email is gone. |
| `deploy.sh` | Runs on the Mac: refuses a locked checkout, rsyncs the tree (no secrets) to prod `~/deploy`, writes `.revision`, streams secrets into `/var/lib/secrets` via tar, pure `nixos-rebuild switch`, wait, `test.sh`. |
| `test.sh` / `lint.sh` | About 240 server checks / statix, deadnix, nixfmt. |
| `scripts/generate-service-passwords.sh` | Creates and commits per-service passwords. Refuses if git-crypt is locked. |
| `secrets/` | git-crypt encrypted. Deployed to `/var/lib/secrets`, root-only. Locked (ciphertext) in the checkout on prod. |

## Notes and gotchas

**Secrets**

- Never put a secret on argv. See `CLAUDE.md` "Script conventions".
- Non-root units get secrets via `LoadCredential=`, never through group access.
- Some secrets are generated at runtime and exported into `/var/lib/secrets` by
  the `*-config` units: the Plex token and the arr, Tautulli, Jellyseerr,
  SABnzbd and Audiobookshelf keys. Homepage starts after those units for this
  reason.
- `users/*/plaintext` are recovery copies and are never deployed. `create-dirs`
  deletes them if they appear.

**Config oneshots**

- The setup oneshots (`SETUP_UNITS`: the `*-config` units, `create-dirs`,
  `audiobookshelf-access`) run on every boot, so they must be idempotent. They
  stay active afterwards (`RemainAfterExit`), so a switch re-runs only those
  whose unit changed. `deploy.sh` re-runs all of them when a secret changed.
  To re-apply one by hand: `sudo systemctl restart sonarr-config`.
- `sonarr-config` and `radarr-config` empty the app's `Users` table, rewrite
  `config.xml` and restart the app every time. POSTs for things that already
  exist fail, and the script skips them on purpose.
- `tautulli-config` and `bazarr-config` stop their app, edit its files, then
  start it again. Bazarr's language profiles are deleted and re-inserted each run.
- `audiobookshelf-config` is **not** started automatically. It runs
  `DELETE FROM users`, so running it on a live install wipes every user.

**Networking**

- Every web UI binds 127.0.0.1. sonarr, radarr and prowlarr do this through
  `settings.server.bindaddress`, an env var that overrides `config.xml`.
- IPv6 is off. The NetworkManager profile is set by hand (see `CLAUDE.md`).
- Homebridge uses host networking. `homebridge-config` keeps its UI on loopback.

**Storage**

- `journalctl -u check-drive-status` logs every HDD spin-down and wake. Use it
  before blaming a timer for waking the disk. media-fixup's 15-minute scan was
  measured at 0 disk reads (the directory tree stays cached).
- `ensure-partition` only touches disks with no signature, because `/dev/sdX`
  names can move between boots.
- Mounts are `nofail`. The local backup has `RequiresMountsFor`, so it never
  writes to the NVMe by mistake.
- The WD Ultrastar ignores `hdparm -S`, so `check-drive-status` spins it down
  itself after 300 s idle. It never calls `hdparm -C`, which resets the idle timer.

**Deploy and test**

- `deploy.sh` rsyncs the working tree, not git, so uncommitted edits ship. It is
  hardcoded to prod.
- `~/deploy` is not a git checkout, so `nixos-rebuild` copies all of it into the
  world-readable Nix store. That's why secrets must never land there.
- Secrets are copied but never deleted on the server: runtime-generated keys
  live next to them. Remove a retired secret from `/var/lib/secrets` by hand.
- `test.sh` reads its password-service and oneshot lists from
  `/etc/spudbox/env`. The state-dir and sandboxed-unit lists stay hand-kept on
  purpose: they are what the tests assert.
- To switch from a git worktree on the server, run
  `git describe --always --dirty > .revision`, then
  `nixos-rebuild switch --sudo --flake path:.#spudbox-prod`. A plain
  `.#` git flake fails there with libgit2 "object not found".
- A switch that changes a `*-config` unit re-runs it, and that restarts its
  app (Sonarr, Radarr, Bazarr, Tautulli). Let them settle before running
  `test.sh`, or you get spurious port failures.
- `claude-remote-control` is never restarted by a switch, because the deploying
  session lives in it. Changes to it apply at the next boot or after
  `sudo systemctl restart claude-remote-control` over SSH, which ends running
  Claude sessions.
- Auto mode can block `nixos-rebuild` and even `test.sh` on prod. The
  `Bash(sudo systemd-run:*)` allow rule in `~/.claude/settings.json` skips the
  check, but only use it when the user has approved that step.

## Open improvements

All 21 items from the 2026-10-22 review are done (see *Done*). Add new
findings here as rows: `| # | Priority | Recommendation | Where | Why | Status |`.

Follow-ups left by the review:

- Revoke the old Gmail app password in the Google account (owner). It is gone
  from the repo and server but stays valid until revoked.
- When Prowlarr is re-enabled, sandbox it like seerr (it scored 8.2).
- Dev's hardware config isn't in the repo, so `spudbox-dev` still needs `--impure`.
- Apply the `claude-remote-control` log filter: `sudo systemctl restart
  claude-remote-control` over SSH (ends running Claude sessions), or reboot.
- After a few days, count HDD wakes (`journalctl -u check-drive-status | grep woke`)
  and match them to what ran just before. Only then decide on further HDD work.

Efficiency ideas considered and not done (2026-10-23):

- Run Homebridge natively instead of in Docker: drops the Docker daemon
  (~60 MB RAM, ~400 s CPU/week, 2.4 GB disk) but risks the HomeKit pairing.
- Turn off Avahi's reflector (not needed with host networking): ~190 s
  CPU/week, but HomeKit discovery is at stake.

## Done

Newest first. Don't redo these.

| Date | Commit | Change |
| --- | --- | --- |
| 2026-10-23 | `9ca27ce`, `dd3f8a9` | Efficiency: setup oneshots run once per boot or change (`RemainAfterExit`) instead of every deploy restarting Sonarr/Radarr/Bazarr/Tautulli; `deploy.sh` re-runs them when a secret changed. Journal noise cut: claude-remote-control status redraws (~400k lines/day, filtered) and Plex debug. `claude-remote-control` never restarted by a switch. restic skips ~1 GB of caches/posters/logs. HDD spin-downs/wakes logged; standby sent once. Sonarr/Radarr no longer rescan the disk after each 12-24 h refresh (manual refresh only; a weekly rescan timer was tried and dropped). |
| 2026-10-23 | see git log | Review items 5-21. Sandboxing for caddy (7.8 to 3.0), plex (7.0 to 4.0) and seerr (6.1 to 2.9). Shared `admin/password` and Gmail secrets retired. Prowlarr switched off (code kept). `radarr-auto-import` skips rejected files and tries each once (one item had looped 5,137 times). Python setup scripts: umask, timeouts, Bazarr key bug, ABS guard. All shell in `writeShellApplication`. `PASSWORD_SERVICES`/`ALERT_UNITS` generated for `test.sh`. Deployed revision recorded. `homebridge-dummy` pinned. hdparm rule documented. Prod builds pure (`hosts/prod-hardware.nix`). `inherit (config.my)` instead of `with`. Caddy sites LAN-only. |
| 2026-10-23 | `0d9d571`, `432f58f`, see git log | Review items 1-4: media-fixup sandboxed as its own user (exposure 9.6 to 3.4); create-dirs no longer `chmod -R`s the library (3,157 files un-exec'd once); `notify-failure@` Pushover alerts on backups, oneshots and timers; `deploy.sh` refuses a locked checkout and streams secrets straight into `/var/lib/secrets`. |
| 2026-10-22 | `b0918aa` | media-fixup (DV5 to HDR10, hybrid DV8 strip, SRT font tags). Arrs reject DV-without-HDR releases. |
| 2026-10-21 | `105e0bc` | Tidy-up: shared `helpers`, typed `my.*` options, generated `/etc/spudbox/env`, shared `mkArrConfig`. |
| 2026-10-21 | `05d3b63` | Prowlarr login set through its API (salted PBKDF2). Three `test.sh` fixes. |
| 2026-10-21 | `d2a342f`, `f7941a4` | Per-service web login passwords (finding #5). |
| 2026-10-21 | `65a4f57` | Tests that every API, direct and through Caddy, rejects anonymous requests. |
| 2026-10-21 | `85c7215` | Legacy `secrets/default.json` removed, auto-format guard, README fixes. |
| 2026-10-21 | `7e5a06b` | `hardening.nix` on bazarr, sabnzbd, audiobookshelf, tautulli, drive-status. Dynamic users for the small timers. |
| 2026-10-20 | `c7b00b4` | Secrets kept off command lines everywhere. |
| 2026-10-20 | `7097944` | Claude Code root access documented as an accepted risk. |
| 2026-10-20 | `7862bc1` | Cloudflare token moved out of the Caddy config and admin API. Cert chain fixed. |
| 2026-10-20 | `93682c1`, `96897da` | Per-service state dirs set to 0700. `/var/lib/secrets` made root-only. |
| 2026-10-20 | `70831bf`, `6ce677e` | IPv6 restricted, then disabled. |
| 2026-10-20 | `08233a1`, `370941a`, `d073e0c` | Web UIs bound to loopback (Caddy only). Homebridge UI port closed. |
| 2026-10-20 | `429cf79` | sabnzbd-config deadlock fixed. |
| 2026-10-20 | `c9cbeeb` | autorestic replaced with restic to the HDD plus R2. |
| 2026-10-20 | `6cd8d3b` | Strict usenet TLS verification. Homebridge image pinned by digest. |
| 2026-10-20 | `c2b626b` | WireGuard removed. Plex remote access enabled. |
| 2026-10-19 | `04b6eb6`, `031a632`, `71b6ab3` | Weekly nix GC (5 generations). ttyd removed. lint.sh glob fixed. |
| 2026-10-18 | `1db180a`, `5a0f7c4`, `2ca3e2c` | nixpkgs, Plex and caddy plugin update. Letterboxd list removed. `gh` installed. |

## Accepted risks / won't fix

Don't re-raise these unless the setup changes. The main one is in `CLAUDE.md`
"Accepted risks".

| Item | Reason |
| --- | --- |
| Claude Code runs on prod with root (2026-10-20) | See `CLAUDE.md` "Accepted risks". |
| Plex 32400 reachable directly and port-forwarded | Needed for remote streaming. |
| Homebridge container runs as root with host networking | HomeKit needs mDNS on the host network. The UI is loopback-only. |
| Bazarr stores an unsalted MD5 password | It's Bazarr's own format. |

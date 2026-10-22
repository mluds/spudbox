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
| `flake.nix` | One `nixpkgs` input. Hosts `spudbox-prod` (x86_64) and `spudbox-dev` (aarch64). Hand-pinned Plex overlay. |
| `configuration.nix` | Shared config: imports, packages, nix GC, SSH, sudo, firewall, users, IPv6 off. `create-dirs` oneshot: media dirs, per-service password seeding, secrets perms. |
| `storage.nix` | Formats blank XFS disks (`ensure-partition-*`), mounts them, pools them with mergerfs. hdparm udev rule. |
| `common/vars.nix` | Typed `my.*` options (ports, dirs, drives, users). |
| `common/env.nix` | Writes `/etc/spudbox/env` (dirs, domain, every `*_PORT`) for `test.sh` and `deploy.sh`. |
| `common/helpers.nix` | The `helpers` module arg: `read-secret`, `wait-for-http`. |
| `environments/default.nix` | Ports, dirs, usenet hosts, users. `{prod,dev}.nix`: domain and drives per host. |
| `services/caddy.nix` | Reverse proxy per subdomain. Cloudflare DNS-challenge wildcard cert. `caddy-config` writes the token env file. |
| `services/hardening.nix` | Shared systemd sandbox settings, merged into units that handle untrusted input. |
| `services/plex.nix` + `plex-config.py` | Plex, plus libraries, token sign-in and remote-access settings. |
| `services/tautulli.nix` + `tautulli-config.py` | Rewrites `config.ini` (login hash, Plex link). Exports the API key. |
| `services/sabnzbd.nix` | SABnzbd via NixOS `settings` + `secretValues`. Hourly `sabnzbd-resume`. |
| `services/transmission.nix` | Transmission 4 + Flood UI. RPC credentials built in `ExecStartPre`. |
| `services/audiobookshelf.nix` + `audiobookshelf-access.py` | Every boot: root password rotation, read-only API key for homepage. |
| `services/audiobookshelf-config.py` | One-off, started by hand: seeds the root user in SQLite, library, users. |
| `services/homepage.nix` | Dashboard. Keys come through `LoadCredential`. |
| `services/homebridge.nix` | Homebridge in Docker (pinned digest). `homebridge-config` does first setup and password rotation. Avahi. |
| `services/docker.nix` | Docker, used only by Homebridge. |
| `services/backup.nix` | restic: nightly `/var/lib` backup to the HDD, then `restic copy` to Cloudflare R2. |
| `services/drive-check.nix` | 5-minute timer that forces the HDD into standby when idle. `drive-status-http` serves JSON for homepage. |
| `services/media-fixup.{nix,sh}` | 15-minute timer: DV5 to HDR10, hybrid DV8 strip, SRT `<font>` cleanup. x86_64 only. Sandboxed as user `media-fixup` (CAP_CHOWN only, writes only `/mnt/storage/data`). |
| `services/notify.nix` | `notify-failure@` template: a Pushover alert with the journal tail. Attached to the oneshots, timers and backups through `onFailure`. |
| `services/claude-code.nix` | Claude Code Remote Control, running as `luds`. |
| `services/servarr/mkArrConfig.nix` | Shared `sonarr-config`/`radarr-config` builder: login, indexer, SABnzbd, quality, custom formats, folder import. |
| `services/servarr/{sonarr,radarr}.nix` | The apps plus their mkArrConfig args. Radarr also has the `radarr-auto-import` timer. |
| `services/servarr/qualityDefinitions.nix` | Size limits and quality profiles. |
| `services/servarr/set-config-xml.nix` | Writes secret files into `config.xml` without putting them on argv. |
| `services/servarr/prowlarr.nix` | Prowlarr. Login set through its API. |
| `services/servarr/bazarr.nix` + `bazarr-config.py` | Merges a YAML template into the config. Rewrites language profiles. |
| `services/servarr/jellyseerr.nix` | seerr under a fixed user. First-run setup, Plex/arr links, Pushover. |
| `deploy.sh` | Runs on the Mac: refuses a locked checkout, rsyncs the tree (no secrets) to prod `~/deploy`, streams secrets into `/var/lib/secrets` via tar, `nixos-rebuild switch`, wait, `test.sh`. |
| `test.sh` / `lint.sh` | About 190 server checks / statix, deadnix, nixfmt. |
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

- Most `*-config` units run on every boot and switch, so they must be idempotent.
  So does `create-dirs`: an inactive oneshot is started again by every switch.
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
- The service, password-service and state-dir lists in `test.sh` are maintained
  by hand. They partly duplicate lists in the Nix code.

## Open improvements

These items come from a full review on 2026-10-22. Sandbox scores come from
`systemd-analyze security <unit>` on prod (0 = locked down, 10 = unsafe).

| # | Priority | Recommendation | Where | Why | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | High | Run media-fixup as a dedicated user in the `media` group, with `hardening.nix` (keep `/dev/dri`) and API keys via `LoadCredential`. | `services/media-fixup.nix:76` | ffmpeg parses untrusted downloads as root. Exposure score 9.6 (UNSAFE). | Fixed on branch `fix/high-priority`; awaiting deploy |
| 2 | High | Make create-dirs' `chown`/`chmod` of the media dirs non-recursive (it stays a unit, so it can run after the mergerfs mount), then reset media files to 664 once. | `configuration.nix:58-70` | Every media file on prod is mode 775 (executable), and each boot walks the whole HDD. | Fixed on branch `fix/high-priority`; awaiting deploy + one-time chmod |
| 3 | High | Add an `OnFailure=` Pushover notifier (credentials exist) for `restic-backups-*`, `media-fixup` and the `*-config` units. | `services/backup.nix`, oneshots | A failed nightly backup only shows up when someone runs `test.sh`. | Fixed on branch `fix/high-priority`; awaiting deploy |
| 4 | High | Stream secrets straight into `/var/lib/secrets` (tar over ssh, umask 077, root-owned), never via `~/deploy`. Refuse if `secrets/admin/password` starts with `GITCRYPT`. | `deploy.sh:31` | From a locked checkout, the deploy overwrote live secrets with ciphertext. Secrets sat in `~/deploy` until the `find -delete` ran. (Deleting retired secrets stays manual; see Notes.) | Fixed on branch `fix/high-priority`; awaiting deploy |
| 5 | Medium | Extend `hardening.nix` to prowlarr (8.2), seerr (6.1) and plex (7.0, needs `/dev/dri`). Give caddy (7.8) a capability bounding set. | `prowlarr.nix`, `jellyseerr.nix`, `plex.nix`, `caddy.nix` | Network-facing services with no sandbox. sonarr, radarr and transmission score 1.4 to 1.5. | Open |
| 6 | Medium | Retire the shared `admin/password`: drop the create-dirs seeding fallback and the old-password rotation paths, then delete the secret. Wait until the `test.sh` "per-service web passwords" check passes. | `configuration.nix:72-79`, `homebridge.nix:61-91`, `audiobookshelf-access.py:43-64` | All 9 per-service passwords exist. The fallback is dead code plus a spare credential. | Open |
| 7 | Medium | Drop the disabled Jellyseerr email agent and the `gmail/*` secrets, then revoke the Gmail app password. | `jellyseerr.nix:25-39, 124-136` | Email is off (Pushover replaced it), but the app password is still written into `settings.json` each boot. | Open |
| 8 | Medium | Make `radarr-auto-import` skip manual-import candidates that have `rejections`. | `radarr.nix:76-83` | It moves every candidate into the library, so samples or wrong files can be imported. | Open |
| 9 | Medium | Decide whether Prowlarr is used. Sonarr and Radarr use NZBGeek directly, and `prowlarr-config` adds no indexers or apps. If unused, remove it. | `prowlarr.nix` | One less exposed service (8.2) and one less password. | Open (question for owner) |
| 10 | Medium | Set `os.umask(0o077)` at the top of the Python config scripts. | `tautulli-config.py:136-140`, `bazarr-config.py:168-174`, `plex-config.py:31` | Exported keys are created 0644 on first write. The 0700 dir protects them, but `test.sh` flags them until the next boot. | Open |
| 11 | Low | Add `timeout=` to every `requests` call. Bound the wait loop in `tautulli-config.py`. | `plex-config.py`, `audiobookshelf-config.py`, `tautulli-config.py:13` | One hung app blocks its oneshot, and everything ordered after it, forever. | Open |
| 12 | Low | Fix `if service in new_config` so it checks `key`. | `bazarr-config.py:58` | For `auth`, the bug replaces the whole block. It works today only because `auth.type` is set again below. | Open |
| 13 | Low | Delete `audiobookshelf-config.py`, or make it refuse when `users` is non-empty. Move its import-time work into `main()`. | `audiobookshelf-config.py` | A manual start on the live install wipes every user. | Open |
| 14 | Low | Move the remaining inline scripts to `writeShellApplication`: create-dirs, `sabnzbd-resume`, `transmission-credentials`, `radarr-auto-import`. | `configuration.nix:54`, `sabnzbd.nix:125`, `transmission.nix:53`, `radarr.nix:54` | The repo's own convention: strict mode plus shellcheck. | Open |
| 15 | Low | Generate the hand-kept lists (password services, state dirs, sandboxed units, oneshots) into `/etc/spudbox/env`, as `CADDY_HOSTS` already is. | `test.sh`, `configuration.nix:42, 236`, `scripts/generate-service-passwords.sh` | The password-service list is copied in 4 places. | Open |
| 16 | Low | Record the deployed revision (`git describe --always --dirty`) in `/etc/spudbox/revision` or `system.configurationRevision`. | `deploy.sh`, `common/env.nix` | Nothing on the server says which commit is live, and several sessions deploy. | Open |
| 17 | Low | Pin the version of `homebridge-dummy` in the setup `npm install`. | `homebridge.nix:108` | An unpinned npm package goes into a root container. | Open |
| 18 | Low | Remove the `hdparm -S 60` udev rule, or note why it stays. | `storage.nix:146-148` | `drive-check.nix` says this drive ignores `-S`. | Open |
| 19 | Low | Commit each host's `hardware-configuration.nix` and drop `--impure`. | `flake.nix:40`, `deploy.sh:36` | Builds become reproducible from the repo, and `nix flake check` works off-box. | Open |
| 20 | Low | Replace module-wide `with config.my;` with `inherit (config.my) …`. | most modules | Makes clear where each name comes from. | Open |
| 21 | Low | Optional: limit each Caddy site to `remote_ip private_ranges`. | `caddy.nix:48-64` | Keeps the UIs LAN-only even if 80 or 443 is ever port-forwarded by mistake. | Open |

## Done

Newest first. Don't redo these.

| Date | Commit | Change |
| --- | --- | --- |
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

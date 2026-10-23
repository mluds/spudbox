# CLAUDE.md

Operational guide for the `spudbox` NixOS media server. For first-time OS
install and per-app manual setup steps, see `README.md`.

Code map, notes, and the log of improvements done / open / declined — check it
before any cleanup, hardening, or review, and keep it current:

@docs/CODE-MAP.md

## What this is

A NixOS flake config for a self-hosted media stack (Plex, the *arr apps,
Jellyseerr/seerr, sabnzbd, transmission, audiobookshelf, Caddy, homepage,
homebridge). Almost every package version flows from a single
`nixpkgs` flake input; a few things are pinned by hand (see Upgrades).

- `flake.nix` — inputs + `nixosConfigurations.spudbox-{dev,prod}`; also the Plex
  version overlay and `system.configurationRevision` (the deployed commit).
- `hosts/prod-hardware.nix` — prod's `nixos-generate-config` output, committed
  so prod builds without `--impure`. After hardware changes, regenerate it on
  prod (`nixos-generate-config --show-hardware-config`) and commit. Dev still
  reads `/etc/nixos/hardware-configuration.nix`, so dev needs `--impure`.
- `configuration.nix` — shared config, `environment.systemPackages`, imports of
  every `services/*.nix`.
- `common/vars.nix` — typed declarations of the `my.*` options (a typo is an
  eval error). `environments/default.nix` — all ports, dirs, and the `my.*`
  values; `environments/{prod,dev}.nix` — per-host domain and drives.
- `common/env.nix` — writes `/etc/spudbox/env` (dirs, domain, `REVISION`, every
  `my.*Port` as `FOO_PORT`; modules append `CADDY_HOSTS`, `PASSWORD_SERVICES`,
  `ALERT_UNITS`, `PROWLARR_ENABLED`); `test.sh` and the `deploy.sh` wait loop
  source it instead of hard-coding ports and service lists.
- `common/helpers.nix` — the `helpers` module argument: `read-secret NAME`
  and `wait-for-http URL [INTERVAL]`, for scripts' `runtimeInputs`.
- `services/**` — one file per service, each typically defining the NixOS
  service plus a `*-config` oneshot that configures it via its HTTP API on boot.
  Sonarr and Radarr share theirs (`services/servarr/mkArrConfig.nix`).
- `services/media-fixup.{nix,sh}` — a 15-minute timer that rewrites newly
  imported videos some Plex clients can't play: Dolby Vision profile 5 →
  HDR10 (re-encoded on the Intel iGPU), "Hybrid" DV profile 8 → DV layer
  stripped (it stalls the Apple TV), SRT `<font>` tags removed (tiny
  subtitles). Sonarr/Radarr also reject profile-5 releases via a
  "DV without HDR fallback" custom format. Run `sudo media-fixup FILE…` to
  fix specific files by hand; logs are in `journalctl -u media-fixup`.
- `secrets/` — git-crypt encrypted (see README "Secrets"). Deployed to
  `/var/lib/secrets` as root-only (700/600). Only root-run units read it; a
  non-root service that needs a secret gets it via `LoadCredential=` (see
  `services/homepage.nix`), never group access. `users/*/plaintext` are
  recovery copies and are never copied to the server.

### Script conventions

- Shell scripts use `pkgs.writeShellApplication` (strict mode, `runtimeInputs`,
  shellcheck at build time); Python ones are `.py` files next to their module,
  built with `pkgs.writers.writePython3Bin` (flake8 at build time). Values
  from Nix reach Python through the unit's environment.
- Secrets never go on a command line (`/proc/<pid>/cmdline` is world-readable):
  pass them to curl as files (`-H @file`, `-d @file`/`-d @-`, `-K file`), to jq
  with `--rawfile`, to config.xml with `set-config-xml`, to sqlite on stdin.
  Write temp files under `umask 077`.

## Hosts

| Env | Flake | System | IP | Domain |
|-----|-------|--------|-----|--------|
| prod | `spudbox-prod` | x86_64-linux | `192.168.1.42` | `spudbox.online` |
| dev | `spudbox-dev` | aarch64-linux | `192.168.42.130` | `dev.spudbox.online` |

`deploy.sh` is hardcoded to **prod** (`luds@192.168.1.42`, key `~/.ssh/spudbox`).
There is no dev deploy path — changes land directly on prod.

## Connecting

```bash
./deploy.sh ssh                      # opens a shell on prod
ssh -i ~/.ssh/spudbox luds@192.168.1.42
```

`luds` is a passwordless-sudo wheel user. Web UIs listen on loopback only and
are reverse-proxied by Caddy at `https://<service>.spudbox.online`; that's the
only way in from the LAN. Plex (32400) is the exception and is reachable
directly. On the server itself you can curl services by port (see
`environments/default.nix` or `/etc/spudbox/env`, e.g. sabnzbd 8081, seerr 5055).

### IPv6

IPv6 is disabled (`networking.enableIPv6 = false`). NetworkManager turns it
back on for any profile with `ipv6.method=auto`, and that can't be set as a
global default, so the wired profile is set by hand. It's saved in
`/etc/NetworkManager/system-connections/`, outside the Nix config. On a
fresh install, run this once (it keeps the profile's UUID and DHCP lease):

```bash
sudo nmcli connection modify "Wired connection 1" ipv6.method disabled
sudo nmcli device reapply eno1
```

`test.sh` fails if any interface has a global IPv6 address or an active
ethernet profile still has IPv6 enabled.

## Deploying

```bash
./deploy.sh          # sync → rebuild switch → wait for services → test.sh  (default)
./deploy.sh switch   # sync → rebuild switch (no tests)
./deploy.sh sync     # rsync working tree to ~/deploy on the server, no rebuild
./deploy.sh test     # run test.sh on the server
./deploy.sh lint     # sync + lint.sh (statix, deadnix, nixfmt)
```

Notes:
- Deploy rsyncs the **working tree** (not git, no secrets) to `~/deploy` on the
  server, writes `git describe --always --dirty` to `~/deploy/.revision`, streams
  the secrets into `/var/lib/secrets`, then runs
  `nixos-rebuild switch --flake .#spudbox-prod`. Uncommitted changes deploy fine
  (the revision ends in `-dirty`); committing is separate.

### Before committing

There are no git hooks — run these manually before every commit:

- **Lint**: `./deploy.sh lint` — syncs and runs `lint.sh` (statix, deadnix,
  nixfmt).
- **Test**: `./deploy.sh all` — deploys and runs `test.sh`; or `./deploy.sh test`
  if the current code is already deployed.

Commit only on a green run of both (`N passed, 0 failed`).

### Rollback

The previous generation stays bootable. To undo a bad switch:

```bash
ssh -i ~/.ssh/spudbox luds@192.168.1.42 'sudo nixos-rebuild switch --rollback'
# or revert the offending files locally and re-run:
./deploy.sh switch
```

## Upgrades (nix + all packages)

Everything from `nixpkgs` upgrades together by moving the flake input. **Nix is
not installed on the Mac** — `flake.lock` must be regenerated on a machine that
has Nix (the server does, at `192.168.1.42`).

1. Bump the channel in `flake.nix`, e.g. `nixos-25.11` → `nixos-26.05`.
2. Regenerate the lock **on the server** (no local nix), then pull it back:
   ```bash
   KEY=~/.ssh/spudbox HOST=luds@192.168.1.42 TMP=/tmp/spudbox-lock
   ssh -i $KEY $HOST "rm -rf $TMP && mkdir -p $TMP"
   scp -i $KEY flake.nix flake.lock $HOST:$TMP/
   ssh -i $KEY $HOST "cd $TMP && nix flake update"
   scp -i $KEY $HOST:$TMP/flake.lock ./flake.lock
   ssh -i $KEY $HOST "rm -rf $TMP"
   ```
   (A throwaway dir with just the flake files is enough — `flake update` only
   resolves inputs, it doesn't evaluate outputs.)
3. `./deploy.sh all` and work through any failures (see below).
4. Keep `system.stateVersion` (currently `25.05`) as-is — it pins data-migration
   behavior and must NOT be bumped just because the channel moved. Some modules
   gate breaking changes on it (e.g. the seerr config-dir move is gated on
   `>= 26.05`, so staying at 25.05 preserves `/var/lib/jellyseerr`).
5. **Also bump Plex** as part of any general upgrade — it's pinned by hand and
   won't move with nixpkgs. See "Hand-pinned versions" below. Do it in the same
   pass so Plex doesn't silently stay behind.

### Things that commonly break on a channel jump

A big jump won't be a clean one-shot. Expected failure classes, all seen on the
25.11→26.05 upgrade:

- **Caddy vendor-hash mismatch** — `services/caddy.nix` pins a `withPlugins`
  build `hash`. When Caddy core moves, the hash changes; Nix prints
  `specified:`/`got:` — paste the `got:` value in. This hash bump is *required*,
  not optional.
- **Flaky package test** — a package (e.g. `paho-mqtt`) fails its test suite
  during build, often because Hydra hasn't cached it for the fresh commit so
  you build from source and hit a flake. Nix does not cache build failures;
  rebuild that one derivation directly to retry:
  `ssh … "nix build '/nix/store/<hash>-<pkg>.drv^*' --no-link"`. If it passes,
  re-run the deploy (it's now realized in the store).
- **Renamed NixOS options / units** — eval warnings like
  `The option 'services.X' has been renamed to 'services.Y'` mean the produced
  systemd unit renamed too. Update the option, any `systemd.services.X`
  override, `after`/`wants` references, and any `systemctl` calls in
  `services/**`, `services/backup.nix` hooks, and `test.sh`
  (`check_service "Y.service"`). Grep before editing:
  `grep -rn "X\.service\|services\.X\|systemctl.*X" --include=*.nix .`
- **Deprecation warnings** are non-fatal — the build still succeeds. Fix
  opportunistically, not required.

### Hand-pinned versions (upgrade separately from nixpkgs)

- **Plex** — overlay in `flake.nix`. Upgrade it alongside every general nixpkgs
  upgrade (step 5 above). Procedure:
  1. Get the latest version string from the Plex downloads API:
     `curl -s https://plex.tv/api/downloads/5.json | jq -r '.computer.Linux.version'`
     (e.g. `1.43.3.10828-00f62d37d`).
  2. Get the SRI hashes of the `.deb`s by prefetching on the server — `amd64`
     for prod (x86_64) and `arm64` for dev (aarch64):
     ```bash
     VER=<version>
     for ARCH in amd64 arm64; do
       ssh -i ~/.ssh/spudbox luds@192.168.1.42 \
         "nix store prefetch-file --json 'https://downloads.plex.tv/plex-media-server-new/${VER}/debian/plexmediaserver_${VER}_${ARCH}.deb'" | jq -r .hash
     done
     ```
  3. Update `version` and both `hash`es in the overlay, then `./deploy.sh all`.
- **Caddy cloudflare-dns plugin** — `services/caddy.nix`: plugin ref + `hash`.
  The Caddyfile itself is generated by the NixOS module (`services.caddy.virtualHosts`,
  one entry per `proxies` attr) at `/etc/caddy/caddy_config`.
- **homebridge** — `services/homebridge.nix` pins the docker image by date tag
  + digest. Pick the newest plain `YYYY-MM-DD` tag (skip `alpha-`/`beta-`) and
  its digest:
  ```bash
  TAG=<YYYY-MM-DD>
  curl -s "https://hub.docker.com/v2/repositories/homebridge/homebridge/tags/$TAG" | jq -r .digest
  ```
  Update the `image:` line, deploy, then `sudo systemctl restart homebridge`
  (the compose file lives in /etc, so a switch alone doesn't restart it).

## Backups

`services/backup.nix` — restic, nightly at 02:30, backs up `/var/lib` (app
configs + DBs, ~5 GB; excludes Docker images and the Plex cache). Media is not
backed up.

- **local** — `/mnt/storage/backups/restic` on the HDD. Services are stopped for
  the backup and restarted afterwards (even on failure).
- **r2** — Cloudflare R2 bucket `spudbox-backups`, filled by `restic copy` from
  the local repo once the local backup succeeds, then pruned and checked.
- Retention on both: 7 daily, 4 weekly, 12 monthly.

Secrets (root-only, in `/var/lib/secrets`): `restic/password` (shared by both
repos — **without it nothing can be restored; keep it in the password
manager**), `r2/s3-credentials.env` (R2 S3 keys), `r2/account-id`,
`r2/api-token` (the Cloudflare token the S3 keys are derived from).

Restoring — `restic-local` / `restic-r2` are wrappers with the repo and
credentials preset:

```bash
sudo restic-local snapshots
sudo restic-local restore latest --target /tmp/restore --include /var/lib/sonarr
# stop the service, copy files back into /var/lib/<app>, fix ownership, start it
```

If the server is gone, restore from R2 on any machine with restic: repo
`s3:https://8b37a4bbd0f5e7e52c56476fd07bc4f8.r2.cloudflarestorage.com/spudbox-backups`,
the `AWS_*` values from `r2/s3-credentials.env`, and the restic password.

## Verifying

`./deploy.sh test` runs `test.sh` on the server — ~190 checks across services,
ports, HTTP health, config integration, storage, and security. A
green run (`N passed, 0 failed`) is the bar for a good deploy. The deploy's
built-in wait loop polls the main service ports before tests run.

## Accepted risks

Decided on purpose; don't re-raise these in reviews or audits unless the
setup they describe changes.

- **Claude Code runs on prod with root (decided 2026-10-20).** The
  `claude-remote-control` service (`services/claude-code.nix`) runs as
  `luds`, which has passwordless sudo, so a Claude session here can rebuild
  and reconfigure prod without approval of each command. Anyone who controls
  the claude.ai account, or a prompt injection reaching a session (web pages,
  file names, downloads), effectively gets root. Accepted so Claude can
  deploy and run `test.sh` end to end. Alternatives considered: a separate
  non-sudo user (Claude could no longer deploy or test), a sudo password
  (breaks `deploy.sh`), a command allowlist (`nixos-rebuild` is root anyway).

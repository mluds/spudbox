# CLAUDE.md

The spudbox NixOS module: a self-hosted media stack (Plex, the *arr apps,
Jellyseerr/seerr, SABnzbd, Transmission, Audiobookshelf, Caddy, homepage,
optional Homebridge) configured end to end from `spudbox.*` options.
`README.md` is the user guide (install, first run, backups).

Code map, notes, and the log of improvements done / open / declined — check it
before any cleanup, hardening, or review, and keep it current:

@docs/CODE-MAP.md

## Two repositories

- **This one** (public): the module, `test.sh`, `lint.sh`, and `template/`
  (what a new instance starts from). No secrets, hostnames, addresses or
  personal settings belong here; they go in an instance's `spudbox.nix`.
- **An instance** (private, one per server): `flake.nix` (input
  `spudbox.url = "github:mluds/spudbox"`, `nixosConfigurations.default =
  spudbox.lib.mkSystem { ... }`), `spudbox.nix`, `hardware.nix`, `secrets/`,
  `deploy.sh` + `deploy.env`. Its `flake.lock` pins this repo; nixpkgs
  follows this repo's lock.

## Layout

- `flake.nix`: `nixosModules.default` (= `module.nix`), `lib.mkSystem`
  (instance revision → `system.configurationRevision`, this repo's →
  `spudbox.revision`), `templates.default`, a `devShell` with the lint tools,
  and `checks.*.template` (the template's settings evaluate to a full system).
- `module.nix`: imports every module; base system (packages, nix GC, SSH,
  sudo, firewall, users, IPv6), `create-dirs`, the hand-pinned Plex overlay,
  and `spudbox-test` (= `test.sh`) on the PATH.
- `common/options.nix`: every `spudbox.*` option with its default. Optional
  features are `spudbox.<feature>.enable`, collected into
  `spudbox.features` (→ `FEATURES` for `test.sh`).
- `common/env.nix`: writes `/etc/spudbox/env` (dirs, domain, `REVISION`,
  `SPUDBOX_REVISION`, `FEATURES`, `INDEXERS`, `SUBTITLE_PROVIDERS`,
  `STORAGE_DEVICES`, every `*Port` as `FOO_PORT`; modules append
  `CADDY_HOSTS`, `PASSWORD_SERVICES`, `ALERT_UNITS`, `SETUP_UNITS`,
  `REQUIRED_SECRETS`, `GENERATED_SECRETS`). `test.sh` and `deploy.sh` source it.
- `common/secrets.nix`: `spudbox-secrets` (before `basic.target`) generates
  missing internal secrets and lists missing third-party ones;
  `spudbox-passwords` prints the logins.
- `common/helpers.nix`: the `helpers` module argument: `read-secret NAME`,
  `wait-for-http URL [INTERVAL]`.
- `services/**`: one file per service, typically the NixOS service plus a
  `*-config` oneshot that configures the app through its API, config file or
  DB on boot (and on a switch that changes it). Sonarr and Radarr share
  `services/servarr/mkArrConfig.nix`.
- `tests/vm.nix`: the VM test of a fresh install (see "Verifying a change").
- `template/`: a new instance (flake, example `spudbox.nix`, placeholder
  `hardware.nix`, `deploy.sh`, `deploy.env`, `secrets/README.md`). Instances
  copy `deploy.sh`; changes to it reach them only when they copy it again.

### Script conventions

- Shell scripts use `pkgs.writeShellApplication` (strict mode, `runtimeInputs`,
  shellcheck at build time); Python ones are `.py` files next to their module,
  built with `pkgs.writers.writePython3Bin` (flake8 at build time). Values
  from Nix reach Python through the unit's environment; structured values
  through a `pkgs.writeText` JSON file (systemd's `Environment=` strips
  quotes).
- Secrets never go on a command line (`/proc/<pid>/cmdline` is world-readable):
  pass them to curl as files (`-H @file`, `-d @file`/`-d @-`, `-K file`), to jq
  with `--rawfile`, to config.xml with `set-config-xml`, to sqlite on stdin.
  Write temp files under `umask 077`.
- A new secret: add it to `generated` (if the server can make it) or
  `required` (third-party) in `common/secrets.nix`, and to
  `template/secrets/README.md`.
- A new optional feature: an option in `common/options.nix`, an entry in
  `spudbox.features`, `lib.mkIf` in its module, `has <feature>` guards in
  `test.sh` (as `if has X; then ...; fi`: a function ending in a failed
  `has X && ...` stops the run under `set -e`), and a line in the README's
  settings table.

## Verifying a change

1. **Lint**: `nix develop -c ./lint.sh` (statix, deadnix, nixfmt, shellcheck,
   ruff, gitleaks, typos). Fix formatting with `nixfmt $(find . -name '*.nix')`
   and `ruff format .`. Allowlist a deliberate finding in that tool's config,
   or `# noqa: <code>` with a reason, rather than switching a rule off.
2. **Evaluate and test**: `nix flake check` evaluates the template with
   every feature off and with every feature on, and runs the VM test
   (`tests/vm.nix`: a fresh install, offline; several minutes; on its own:
   `nix build -L .#checks.x86_64-linux.vm`). CI runs all of it on every
   push (`.github/workflows/check.yml`).
3. **Against a real instance**, without deploying: from the instance checkout,
   ```bash
   nix build --no-link "path:$PWD#nixosConfigurations.default.config.system.build.toplevel" \
     --override-input spudbox path:<this checkout> --no-write-lock-file
   ```
   and compare with the deployed system to see exactly what a deploy would
   change: `nix-diff /run/current-system <new>` (`nix shell nixpkgs#nix-diff`),
   or diff two `.drvPath`s.
4. **Deploy and test**: from the instance, with `SPUDBOX_SRC=<this checkout>`
   in its `deploy.env`, `./deploy.sh` (copies both trees, builds with
   `--override-input`, runs `spudbox-test`). `N passed, 0 failed` is the bar.
   To run the new checks before deploying: `SPUDBOX_ENV=<new system>/etc/spudbox/env
   <new system>/sw/bin/spudbox-test` on the server.

Commit only on a green lint and test run.

## Upgrades

Everything from `nixpkgs` moves together with this repo's `nixpkgs` input;
instances follow it.

1. Bump the channel in `flake.nix` (e.g. `nixos-26.05` → `nixos-26.11`) and
   `nix flake update` (on any machine with Nix).
2. Build against an instance and deploy with `SPUDBOX_SRC` (above); work
   through failures (below).
3. **Also bump Plex** (below) in the same pass so it doesn't silently fall
   behind.
4. Never change `system.stateVersion` here: it's per instance, set once at
   install. Modules that gate migrations on it (seerr's config dir) are
   pinned to one path in `services/servarr/jellyseerr.nix`.
5. Commit and push; instances run `./deploy.sh update`.

### Things that commonly break on a channel jump

All seen on the 25.11→26.05 upgrade:

- **Caddy vendor-hash mismatch**: `services/caddy.nix` pins a `withPlugins`
  build `hash`. When Caddy core moves, Nix prints `specified:`/`got:`; paste
  the `got:` value in. Required, not optional.
- **Flaky package test**: a package (e.g. `paho-mqtt`) fails its test suite
  while building from source because Hydra hasn't cached it yet. Nix doesn't
  cache failures; rebuild that derivation (`nix build '/nix/store/<hash>-<pkg>.drv^*'
  --no-link`) and deploy again.
- **Renamed NixOS options / units**: `The option 'services.X' has been
  renamed to 'services.Y'` means the systemd unit renamed too. Update the
  option, `systemd.services.X` overrides, `after`/`wants`, `systemctl` calls
  in `services/**` (and `services/backup.nix`'s stop list), and `test.sh`.
  `grep -rn "X\.service\|services\.X\|systemctl.*X" .`
- **Deprecation warnings** are non-fatal; fix opportunistically.

### Hand-pinned versions (upgrade separately from nixpkgs)

- **Plex**: overlay in `module.nix`.
  1. Latest version: `curl -s https://plex.tv/api/downloads/5.json | jq -r '.computer.Linux.version'`.
  2. SRI hashes of the `.deb`s, `amd64` and `arm64`:
     ```bash
     VER=<version>
     for ARCH in amd64 arm64; do
       nix store prefetch-file --json "https://downloads.plex.tv/plex-media-server-new/${VER}/debian/plexmediaserver_${VER}_${ARCH}.deb" | jq -r .hash
     done
     ```
  3. Update `version` and both `hash`es.
- **Caddy cloudflare-dns plugin**: `services/caddy.nix`, plugin ref + `hash`.
- **Homebridge**: `services/homebridge.nix` pins the image by date tag +
  digest. Pick the newest plain `YYYY-MM-DD` tag (not `alpha-`/`beta-`):
  `curl -s "https://hub.docker.com/v2/repositories/homebridge/homebridge/tags/$TAG" | jq -r .digest`.
  After deploying, `sudo systemctl restart homebridge` (the compose file is
  in /etc, so a switch alone doesn't restart it).

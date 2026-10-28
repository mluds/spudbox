---
name: install-spudbox
description: Install a new spudbox media server (NixOS + Plex, Sonarr, Radarr, SABnzbd, ...) on a machine, end to end - gathers the settings, creates the user's private instance repo, collects secrets safely, partitions the boot disk from the NixOS installer, installs, and walks through the first-run steps. Use when someone wants to install, set up or reinstall a spudbox server, or resume an install that stopped partway.
---

# Install a spudbox server

You are guiding someone through installing spudbox on their own machine. You
run commands on **their computer** (where this repo is checked out), and over
SSH on the **server**, first while it's booted into the NixOS installer and
then once it's installed. Some steps need their hands (booting from USB,
typing passwords, a browser); for those, tell them exactly what to do and
wait.

Read `README.md` ("Setting up a server", "First run") and
`template/spudbox.nix` before starting: they are the reference this skill
automates. Option details are in `common/options.nix`.

## Safety rules (never break these)

1. **Disks.** The only command that erases a disk is
   `scripts/partition-boot-disk.sh`, and only for the boot disk the person
   chose. Before running it: show the disk's name, size, model and serial,
   say plainly that everything on it will be erased, and have them **type the
   disk's name** (e.g. `nvme0n1`) back to you. Pass exactly that as
   `CONFIRM`. Never run `wipefs`, `parted`, `mkfs`, `dd` or `sgdisk` yourself,
   except `wipefs` on a data disk under the same typed-confirmation rule
   (see Step 5).
2. **Secrets never go through the chat.** Don't ask for passwords, API keys or
   tokens in the conversation, and never print a secret file (`cat`, `head`,
   ...). They type each one into `./deploy.sh secret NAME` in their **own
   terminal**. You only check that a file exists and is non-empty (`test -s`).
   The same goes for the passwords printed by `spudbox-passwords` and the
   restic password: they run those commands themselves.
3. **The instance repo is private.** It holds their secrets (encrypted with
   git-crypt if they use it). Never push it to a public remote; if they want a
   remote, it must be a private repository.
4. **Confirm before anything that leaves their machine** (pushing, reboots of
   the installed server) unless they already asked for it.
5. Long commands (`./deploy.sh install`, the first `./deploy.sh`) can take
   10-60 minutes: run them in the background and wait for them to finish
   rather than polling.

## Resuming

If an install was started before, work out where it got to before asking
anything again: the instance directory exists? `spudbox.nix` filled in
(no `example.com`)? which secrets exist (`find secrets -type f`)?
`hardware.nix` still has `SPUDBOX-PLACEHOLDER`? does `flake.lock` exist
(installed)? does `ssh` to `HOST` from `deploy.env` work (booted)? Continue
from the first step that isn't done.

## Step 1: Their computer

- Check this is the spudbox repo (`module.nix`, `template/` exist).
- Check for `git`, `ssh`, `rsync`, `tar` (all needed) and `git-crypt`
  (recommended: it keeps the secrets encrypted in git). Offer to install
  missing ones (`brew install git-crypt` on macOS, the distro's package
  manager on Linux). Nix is **not** needed on their computer.
- SSH key: if they have none they want to use, create a dedicated one,
  `ssh-keygen -t ed25519 -f ~/.ssh/spudbox -C spudbox`. If it has a
  passphrase, it must be loaded in their ssh-agent so your commands don't
  prompt.

## Step 2: Settings

Ask in a few short rounds (use multiple-choice questions where there are
options), explaining briefly what each is for. Defaults in parentheses.

1. **Where to keep their instance repo** (`~/spudbox-home`).
2. **Domain.** Each web UI will be `https://<service>.<domain>`, LAN only. They
   need a wildcard DNS record `*.<domain>` → the server's LAN IP (done in
   Step 7). **TLS:** `cloudflare` if the domain's DNS is on Cloudflare (real
   certificates; needs an API token with Zone:DNS:Edit), otherwise
   `internal` (Caddy's own CA; browsers warn until they trust its root).
3. **Login user**: name (lowercase; not `root` or `admin`), and the public key
   from Step 1. They get passwordless sudo.
4. **Time zone** (detect from their computer: `readlink /etc/localtime`).
5. **Usenet**: provider server hostnames (in priority order), and **indexers**
   (name + Newznab API URL, e.g. NZBGeek `https://api.nzbgeek.info/`). Both
   can be empty, but then nothing downloads automatically.
6. **Subtitles** (Bazarr): `opensubtitlescom` and/or `assrt`, or none;
   languages (`en`).
7. **Extras** (all off by default; one multi-select): Pushover alerts,
   off-site backup to S3/R2 (ask for the restic repository URL), HDD
   spin-down (rotating data disks), media-fixup (needs an Intel iGPU),
   Homebridge, Claude Code on the server (warn: if the user is a superuser,
   Claude sessions there have root).

Then create the instance:

```bash
cp -r template <dir> && cd <dir> && git init -q
git-crypt init   # if they use git-crypt
git-crypt export-key <somewhere private>   # they store it in their password manager, then delete the file
```

Without git-crypt, add `secrets/*` and `!secrets/README.md` to `.gitignore`
so secrets are never committed, and tell them to back up `secrets/` themselves.

Write `spudbox.nix` from their answers (keep the template's comments that
still apply; drive settings come in Step 5), set `system.stateVersion` to
the release in this repo's `flake.nix` (`nixos-XX.YY` → `"XX.YY"`), and set
`SSH_KEY` in `deploy.env` (`HOST` comes in Step 7; add
`SSH_OPTS="-p <port>"` there if their SSH isn't on port 22).

## Step 3: Secrets

Work out the required secrets from the settings. The authority is `required`
in `common/secrets.nix`; summarised in `template/secrets/README.md`:

- always: `plex/username`, `plex/password` (their plex.tv login; with
  two-factor auth on, use `plex/token` instead: Plex's support article
  "Finding an authentication token")
- `usenet/username`, `usenet/password` if there are usenet servers
- `<lowercased indexer name>/api-key` per indexer
- `cloudflare/api-token` for `tls = "cloudflare"`
- `opensubtitles/username` + `password`, `assrt/api-token` per provider
- `pushover/app-token`, `pushover/user-key`; `r2/s3-credentials.env`
  (two lines, `AWS_ACCESS_KEY_ID=...` and `AWS_SECRET_ACCESS_KEY=...`, so
  for this one have them create the file with an editor)

Give them the list as commands to run **in their own terminal**, from the
instance directory, one per secret:

```bash
./deploy.sh secret usenet/username
```

Then check each with `test -s secrets/<name>`. Everything else (web UI
passwords, API keys, the backup password) is generated on the server.

## Step 4: Boot the installer

Tell them to:

1. Download the NixOS **minimal** ISO matching this repo's release:
   `https://channels.nixos.org/nixos-XX.YY/latest-nixos-minimal-x86_64-linux.iso`.
2. Write it to a USB stick (balenaEtcher is easiest) and boot the server
   from it (UEFI mode; turn Secure Boot off).
3. On the server's console: `sudo passwd` (any temporary password), then
   `ip -4 addr` and tell you the LAN address.
4. In their own terminal (it prompts for that password):
   `ssh-copy-id -i <key>.pub -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@<ip>`

Then check you can get in without a password, and that it really is the
installer:

```bash
ssh -i <key> -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
  root@<ip> 'mountpoint -q /iso && echo installer'
```

(Every installer command below uses those same options: the installer's
host key changes on each boot.)

## Step 5: Disks

List them on the server:

```bash
lsblk -d -o NAME,SIZE,ROTA,TRAN,MODEL,SERIAL
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS
ls -l /dev/disk/by-id/ | grep -v -- -part
```

Show a short table and ask:

- **Boot disk** (gets erased; usually the SSD/NVMe, 64 GB or more). Never the
  installer's USB stick (it has mounted partitions; the script refuses it).
- **Data disks** for the library (`storageDrives`), optionally a fast
  `cacheDrives` disk for downloads in progress. Each goes in `spudbox.nix` by
  its stable id:
  ```nix
  { device = "/dev/disk/by-id/<id>"; partition = "/dev/disk/by-id/<id>-part1"; mount = "/mnt/storage1"; }
  ```
  On first boot spudbox gives a **blank** data disk one XFS partition. A disk
  that already has one XFS partition is mounted as it is (keeps existing
  media). Anything else on it (NTFS, ext4, several partitions) is left alone
  and won't mount: if they want to reuse such a disk, it must be wiped, which
  destroys its contents. Only with the typed confirmation of rule 1:
  `wipefs --all /dev/<name>` on the installer.
- No data disks is fine: the library then lives on the boot disk.

With rotating data disks, suggest `hddSpindown.enable`.

Partition the boot disk, after the confirmation in rule 1, from **this**
(spudbox) repo, where the script is:

```bash
ssh <installer options> root@<ip> CONFIRM=<name> bash -s -- /dev/<name> < scripts/partition-boot-disk.sh
```

It prints the disk and the two new partitions, mounted at `/mnt` and
`/mnt/boot`. If it refuses, tell them why rather than working around it.

## Step 6: Install

From the instance directory:

```bash
./deploy.sh hardware root@<ip>   # writes hardware.nix; show them a summary
./deploy.sh install root@<ip>    # background: copies everything, runs nixos-install
```

`install` refuses if secrets are git-crypt-locked or `hardware.nix` is still
the placeholder. "password file ... does not exist" warnings are expected for
users without a `secrets/users/<name>/hashed` (SSH keys only). When it finishes it writes `flake.lock`. Commit:

```bash
git add -A && git commit -m "Install spudbox"
```

(`git-crypt status` first if they use it: every file under `secrets/` except
the README must say `encrypted`.)

Then reboot it (`ssh <installer options> root@<ip> reboot`) and tell them to
remove the USB stick.

## Step 7: First boot

- Suggest a DHCP reservation for the server in their router, so its address
  stays put. Set `HOST=<user>@<ip>` in `deploy.env`.
- Wait for SSH (`./deploy.sh ssh` may take a minute or two; if their
  `known_hosts` has an old key for that address, `ssh-keygen -R <ip>`).
- The apps configure each other on first boot; give it ~5 minutes, then
  look: `systemctl --failed` and `journalctl -u spudbox-secrets` on the
  server (any `MISSING:` line → back to Step 3, then `./deploy.sh`).
  Expected until Step 8: `plex-config` and the units after it
  (`tautulli-config`, `jellyseerr-config`) fail, and `homepage-dashboard`
  keeps restarting, because Plex isn't claimed yet (no Plex token).
- DNS: a wildcard `A` record `*.<domain>` → the server's LAN IP (at
  Cloudflare: "DNS only", not proxied), or the same in their router/Pi-hole.
  With `tls = "internal"`, they can trust Caddy's root certificate from
  `/var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt`.

## Step 8: First-run steps

Do these with them (README "First run" has the details):

1. **Claim Plex.** Start a tunnel in the background:
   `ssh -i <key> <SSH_OPTS> -N -L 32400:localhost:32400 <user>@<ip>`. They open
   http://localhost:32400/web, sign in and finish the setup. Then stop the
   tunnel and run, on the server:
   `sudo systemctl restart plex-config tautulli-config jellyseerr-config`.
2. **IPv6** (with the default `disableIPv6`): find the wired connection and
   device (`nmcli -t -f NAME,DEVICE,TYPE connection show --active`), then
   `sudo nmcli connection modify "<name>" ipv6.method disabled` and
   `sudo nmcli device reapply <device>` (the connection may blip).
3. **First backup** (optional, otherwise it runs at 02:30):
   `sudo systemctl start restic-backups-local` (stops the apps for a minute or two).
4. **Claude Code** if enabled: README "First run" (interactive login: they
   do it in their own SSH session).

Then `./deploy.sh test`. Everything should pass, except "restic local: no
snapshots" until the first backup has run. If Plex isn't claimed yet, everything
that needs its token fails too: `plex/token`, `jellyseerr/api-key`, the
`plex-config`/`tautulli-config`/`jellyseerr-config` units, homepage, the
Jellyseerr and Plex library checks, and "plex rejects anonymous" (an
unclaimed Plex answers anyone on localhost). Tautulli restarts each time
`tautulli-config` runs; if its checks fail right after a deploy, run the
test again a minute later.

## Step 9: Hand-over

Tell them, and have them do these themselves (secrets, rule 2):

- `./deploy.sh ssh`, then `sudo spudbox-passwords`: the web UI logins. Save
  them in a password manager.
- `sudo cat /var/lib/secrets/restic/password` into the password manager too:
  without it no backup can be restored.
- The git-crypt key, if they haven't saved it yet.
- Optionally push the instance repo to a **private** remote.

Day to day it's `./deploy.sh` after editing `spudbox.nix`, and
`./deploy.sh update` to move to a newer spudbox (README "Day to day").

## If something fails

- `./deploy.sh switch` or `./deploy.sh` ends with "the following units
  failed": before Plex is claimed that's the Plex-dependent units above, and
  harmless.
- `./deploy.sh install` fails while building: show the last error lines.
  An eval error usually means a typo in `spudbox.nix`; fix it and run
  `install` again (it's safe to repeat while still in the installer).
- A setup unit failed: `journalctl -u <unit> -n 50` on the server; fix the
  cause (often a missing or wrong secret), then
  `sudo systemctl restart <unit>`. A secret fix needs `./deploy.sh` first.
- A data disk didn't mount: `journalctl -u ensure-partition-<...>` says why
  (usually "isn't blank XFS").

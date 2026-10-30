#!/usr/bin/env bash
# Deploys this spudbox instance to its server. Runs on your own machine (no
# Nix needed there); the server builds. Settings are in deploy.env.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# HOST (user@address), SSH_KEY, and optionally SPUDBOX_SRC: a local checkout
# of the spudbox module to deploy instead of the version in flake.lock.
# shellcheck source=/dev/null
source ./deploy.env
: "${HOST:?set HOST in deploy.env}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
SPUDBOX_SRC="${SPUDBOX_SRC:-}"
# Extra ssh options for both the server and the installer, e.g. "-p 2222".
SSH_OPTS="${SSH_OPTS:-}"
# The server's host key is trusted on first use. SERVER_SSH is the command
# without the host (for rsync -e); SSH runs one on the server.
SERVER_SSH="ssh -i $SSH_KEY -o StrictHostKeyChecking=accept-new $SSH_OPTS"
SSH="$SERVER_SSH $HOST"
# The installer makes a new host key every boot, so it isn't remembered.
INSTALLER_SSH="ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR $SSH_OPTS"
NIX="nix --extra-experimental-features 'nix-command flakes'"

usage() {
  cat <<EOF
Usage: ./deploy.sh [command]

Commands:
  all                 Sync, rebuild, test (default)
  switch              Sync, rebuild and switch (no tests)
  sync                Copy this checkout and the secrets to the server, no rebuild
  test [CATEGORY...]  Run the checks on the server (spudbox-test)
  update              Move flake.lock to the newest spudbox (built on the server)
  restore [local|r2] [SNAPSHOT]
                      Put a backup's app state back (asks before changing anything)
  lint                Lint the SPUDBOX_SRC checkout on the server
  ssh                 Shell on the server
  secret NAME         Type a secret into secrets/NAME (input hidden), e.g. usenet/password
  hardware ROOT@IP    Write hardware.nix from a machine booted into the installer
  install ROOT@IP     Install onto a machine booted into the NixOS installer,
                      its disks mounted at /mnt (/install-spudbox does this)
EOF
  exit 1
}

# A locked git-crypt checkout holds ciphertext; deploying it would replace
# every live secret with it.
check_unlocked() {
  local file
  [ -d secrets ] || return 0
  file=$(find secrets -type f ! -name README.md | head -n 1)
  if [ -n "$file" ] && [ "$(head -c 9 "$file" | tr -d '\0')" = GITCRYPT ]; then
    echo "ERROR: secrets are git-crypt encrypted here; run 'git-crypt unlock <key>' first" >&2
    exit 1
  fi
}

check_hardware() {
  if grep -q SPUDBOX-PLACEHOLDER hardware.nix; then
    echo "ERROR: hardware.nix is still the template's; run ./deploy.sh hardware root@<ip> first" >&2
    exit 1
  fi
}

# secrets_tar: the secrets as a tar stream. Plaintext login passwords
# (users/*/plaintext) are recovery copies and never leave this machine.
# ustar: no macOS xattr/pax headers for GNU tar to warn about.
secrets_tar() {
  (cd secrets &&
    find . -type f ! -path './users/*/plaintext' ! -name README.md -print |
    COPYFILE_DISABLE=1 tar --format ustar -cf - -T -)
}

# revision DIR: its commit (-dirty: with uncommitted changes), or
# "uncommitted" in a repo without commits yet.
revision() {
  git -C "$1" describe --always --dirty 2>/dev/null || echo uncommitted
}

# copy_tree SRC SSH_CMD DEST: SRC's files (no .git, no secrets) to DEST, and
# its commit to DEST/.revision (-dirty: with uncommitted changes).
copy_tree() {
  local src=$1 ssh=$2 dest=$3
  (cd "$src" && COPYFILE_DISABLE=1 tar --exclude=./.git --exclude=./secrets --exclude=./result -cf - .) |
    $ssh "rm -rf $dest && mkdir -p $dest && tar -xf - -C $dest"
  revision "$src" | $ssh "cat > $dest/.revision"
}

sync_files() {
  check_unlocked
  check_hardware
  if [ ! -f flake.lock ] && [ -z "$SPUDBOX_SRC" ]; then
    echo "ERROR: no flake.lock; run ./deploy.sh update first" >&2
    exit 1
  fi

  echo "Syncing files to server..."
  # Secrets never land in ~/deploy: the flake there isn't a git checkout, so
  # nixos-rebuild copies the whole directory into the world-readable store.
  rsync -az --delete --delete-excluded --exclude='/.git' --exclude='/secrets/' --exclude='/result' \
    -e "$SERVER_SSH" "$SCRIPT_DIR/" "$HOST:~/deploy/"
  revision . | $SSH "cat > ~/deploy/.revision"
  if [ -n "$SPUDBOX_SRC" ]; then
    echo "Syncing the spudbox module from $SPUDBOX_SRC..."
    rsync -az --delete --exclude='/.git' --exclude='/result' \
      -e "$SERVER_SSH" "$SPUDBOX_SRC/" "$HOST:~/deploy-spudbox/"
    revision "$SPUDBOX_SRC" | $SSH "cat > ~/deploy-spudbox/.revision"
  fi

  echo "Installing secrets..."
  # Streamed straight into the root-only dir, new files 600 / dirs 700 (umask),
  # owned by root. If any secret changed, a marker in /run tells rebuild() to
  # re-run the setup units: they stay active between switches and wouldn't
  # notice.
  # shellcheck disable=SC2016 # runs on the server
  local install='umask 077 && install -d -m 700 /var/lib/secrets && cd /var/lib/secrets
    digest() { find . -type f -exec sha256sum {} + | sort | sha256sum; }
    before=$(digest)
    tar --no-same-owner --no-same-permissions -xf -
    [ "$(digest)" = "$before" ] || touch /run/spudbox-secrets-changed'
  secrets_tar | $SSH "sudo sh -c '$install'"
}

override_flags() {
  # shellcheck disable=SC2016 # $HOME is the server's
  [ -z "$SPUDBOX_SRC" ] || echo '--override-input spudbox path:$HOME/deploy-spudbox'
}

rebuild() {
  echo "Rebuilding NixOS configuration..."
  # Exit 4: the new system is active, but some units failed to start (e.g.
  # the Plex-dependent ones before Plex is set up). Carry on, so the setup
  # units, the wait and the tests still run and show what's wrong.
  local rc=0
  $SSH "cd ~/deploy && sudo env PATH=\$PATH nixos-rebuild switch --flake .#default $(override_flags)" || rc=$?
  if [ "$rc" -eq 4 ]; then
    echo "WARNING: switched, but some units failed (see above); continuing" >&2
  elif [ "$rc" -ne 0 ]; then
    exit "$rc"
  fi
  # shellcheck disable=SC2016 # expanded on the server, from its /etc/spudbox/env
  $SSH 'if [ -e /run/spudbox-secrets-changed ]; then
      source /etc/spudbox/env
      echo "Secrets changed; re-running the setup units..."
      sudo systemctl restart spudbox-secrets.service "${SETUP_UNITS[@]/%/.service}"
      sudo rm -f /run/spudbox-secrets-changed
    fi'
  echo "Waiting for services to start..."
  # shellcheck disable=SC2016 # expanded on the server, from its /etc/spudbox/env
  $SSH 'source /etc/spudbox/env
    for path in "$TAUTULLI_PORT" "$BAZARR_PORT" "$SONARR_PORT" "$RADARR_PORT" "$JELLYSEERR_PORT" "$SABNZBD_PORT" "$PLEX_PORT/identity"; do
      for _ in $(seq 1 60); do
        code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://localhost:$path" 2>/dev/null) || true
        [ "$code" != "000" ] && break
        sleep 5
      done
    done'
}

run_tests() {
  echo "Running tests..."
  $SSH "spudbox-test $*"
}

run_lint() {
  : "${SPUDBOX_SRC:?lint checks the spudbox module: set SPUDBOX_SRC in deploy.env}"
  sync_files
  echo "Running lint..."
  $SSH "cd ~/deploy-spudbox && $NIX develop -c bash lint.sh"
}

# The server resolves the newest spudbox (and its nixpkgs) and the new
# flake.lock comes back here. Commit it, then deploy.
update_lock() {
  local tmp=/tmp/spudbox-lock
  $SSH "rm -rf $tmp && mkdir -p $tmp"
  local files=(flake.nix)
  if [ -f flake.lock ]; then files+=(flake.lock); fi
  COPYFILE_DISABLE=1 tar -cf - "${files[@]}" | $SSH "tar -xf - -C $tmp"
  $SSH "cd $tmp && $NIX flake update"
  $SSH "cat $tmp/flake.lock" > flake.lock
  $SSH "rm -rf $tmp"
  git --no-pager diff --stat -- flake.lock || true
}

write_hardware() {
  local target=${1:?usage: ./deploy.sh hardware root@<ip>}
  $INSTALLER_SSH "$target" nixos-generate-config --root /mnt --show-hardware-config > hardware.nix.new
  mv hardware.nix.new hardware.nix
  echo "Wrote hardware.nix; commit it."
}

# secret NAME: read a secret without echoing it (nor putting it in shell
# history or on a command line) into secrets/NAME, without a trailing newline.
write_secret() {
  local name=${1:?usage: ./deploy.sh secret <name>, e.g. usenet/password}
  local value
  case $name in /* | *..*) echo "ERROR: give a path inside secrets/" >&2; exit 1 ;; esac
  read -rsp "secrets/$name: " value
  echo
  [ -n "$value" ] || { echo "Empty; nothing written." >&2; exit 1; }
  (umask 077 && mkdir -p "secrets/$(dirname "$name")" && printf '%s' "$value" > "secrets/$name")
  echo "Wrote secrets/$name"
}

# From the NixOS installer, booted with the disks partitioned and mounted at
# /mnt: copies this instance (and the secrets, into the new system's
# /var/lib/secrets) and runs nixos-install. Root's password stays locked; log
# in afterwards as one of spudbox.users, with your SSH key.
install_system() {
  local target=${1:?usage: ./deploy.sh install root@<ip>}
  local ssh="$INSTALLER_SSH $target"
  check_unlocked
  check_hardware
  $ssh 'mountpoint -q /mnt && mountpoint -q /mnt/boot' ||
    { echo "ERROR: mount the new root at /mnt and the ESP at /mnt/boot first" >&2; exit 1; }

  echo "Copying the instance..."
  copy_tree "$SCRIPT_DIR" "$ssh" /tmp/deploy
  if [ -n "$SPUDBOX_SRC" ]; then
    echo "Copying the spudbox module from $SPUDBOX_SRC..."
    copy_tree "$SPUDBOX_SRC" "$ssh" /tmp/deploy-spudbox
    $ssh "cd /tmp/deploy && $NIX flake lock --override-input spudbox path:/tmp/deploy-spudbox"
  fi

  echo "Installing secrets..."
  secrets_tar | $ssh 'install -d -m 700 /mnt/var/lib/secrets &&
    cd /mnt/var/lib/secrets && umask 077 && tar --no-same-owner --no-same-permissions -xf -'

  echo "Installing NixOS (this takes a while)..."
  $ssh "nixos-install --root /mnt --no-root-passwd --flake /tmp/deploy#default"
  # Without one, nixos-install locked the newest spudbox; keep that lock.
  if [ ! -f flake.lock ] && [ -z "$SPUDBOX_SRC" ]; then
    $ssh "cat /tmp/deploy/flake.lock" > flake.lock
    echo "Wrote flake.lock; commit it."
  fi
  echo
  echo "Done. Reboot the server (ssh root@${target#*@} reboot), then log in as one of"
  echo "spudbox.users with your SSH key; from then on use ./deploy.sh."
}

CMD="${1:-all}"
[ $# -gt 0 ] && shift

case "$CMD" in
  sync) sync_files ;;
  switch)
    sync_files
    rebuild
    ;;
  test) run_tests "$@" ;;
  lint) run_lint ;;
  all)
    sync_files
    rebuild
    run_tests
    ;;
  update) update_lock ;;
  ssh) exec $SSH ;;
  restore)
    # -t: spudbox-restore asks for confirmation on the terminal.
    exec $SERVER_SSH -t "$HOST" sudo spudbox-restore --from "${1:-local}" "${2:-latest}"
    ;;
  secret) write_secret "$@" ;;
  hardware) write_hardware "$@" ;;
  install) install_system "$@" ;;
  *) usage ;;
esac

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOST="luds@192.168.1.42"
SSH_KEY="$HOME/.ssh/spudbox"
FLAKE="spudbox-prod"
SSH="ssh -i $SSH_KEY $HOST"

usage() {
  cat <<EOF
Usage: ./deploy.sh [command]

Commands:
  sync       Sync files to server (no rebuild)
  switch     Sync, rebuild, and switch configuration
  test       Run test suite on server
  lint       Run linters on server
  all        Sync, rebuild, test (default)
  ssh        Open SSH session to server
EOF
  exit 1
}

sync_files() {
  # A locked git-crypt checkout holds ciphertext; deploying it would replace
  # every live secret with it.
  if [ "$(head -c 9 "$SCRIPT_DIR/secrets/admin/username" | tr -d '\0')" = "GITCRYPT" ]; then
    echo "ERROR: secrets are git-crypt encrypted here; run 'git-crypt unlock <key>' first" >&2
    exit 1
  fi

  echo "Syncing files to server..."
  # Secrets never land in ~/deploy: the flake there isn't a git checkout, so
  # nixos-rebuild copies the whole directory into the world-readable store.
  rsync -az --delete --delete-excluded --exclude='/.git' --exclude='/secrets/' \
    -e "ssh -i $SSH_KEY" "$SCRIPT_DIR/" "$HOST:~/deploy/"
  # Which commit this is (-dirty: with uncommitted changes); the flake puts
  # it in system.configurationRevision and /etc/spudbox/env (REVISION).
  git -C "$SCRIPT_DIR" describe --always --dirty | $SSH "cat > ~/deploy/.revision"

  echo "Installing secrets..."
  # Streamed straight into the root-only dir, new files 600 / dirs 700 (umask),
  # owned by root. Plaintext login passwords are recovery copies and never
  # leave this machine; secrets/default.json is the old unencrypted file.
  # ustar: no macOS xattr/pax headers for GNU tar to warn about.
  # If any secret changed, a marker in /run tells rebuild() to re-run the
  # setup units: they stay active between switches and wouldn't notice.
  # shellcheck disable=SC2016 # runs on the server
  local install='umask 077 && cd /var/lib/secrets
    digest() { find . -type f -exec sha256sum {} + | sort | sha256sum; }
    before=$(digest)
    tar --no-same-owner --no-same-permissions -xf -
    [ "$(digest)" = "$before" ] || touch /run/spudbox-secrets-changed'
  (cd "$SCRIPT_DIR/secrets" &&
    find . -type f ! -path './users/*/plaintext' ! -path './default.json' -print |
    COPYFILE_DISABLE=1 tar --format ustar -cf - -T -) |
    $SSH "sudo sh -c '$install'"
}

rebuild() {
  echo "Rebuilding NixOS configuration..."
  $SSH "cd ~/deploy && sudo env PATH=\$PATH nixos-rebuild switch --flake .#$FLAKE"
  # shellcheck disable=SC2016 # expanded on the server, from its /etc/spudbox/env
  $SSH 'if [ -e /run/spudbox-secrets-changed ]; then
      source /etc/spudbox/env
      echo "Secrets changed; re-running the setup units..."
      sudo systemctl restart "${SETUP_UNITS[@]/%/.service}"
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
  $SSH "bash ~/deploy/test.sh"
}

run_lint() {
  echo "Running lint..."
  $SSH "cd ~/deploy && bash lint.sh"
}

CMD="${1:-all}"

case "$CMD" in
  sync)
    sync_files
    ;;
  switch)
    sync_files
    rebuild
    ;;
  test)
    run_tests
    ;;
  lint)
    sync_files
    run_lint
    ;;
  all)
    sync_files
    rebuild
    run_tests
    ;;
  ssh)
    exec ssh -i "$SSH_KEY" "$HOST"
    ;;
  *)
    usage
    ;;
esac

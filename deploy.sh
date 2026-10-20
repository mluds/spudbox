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
  echo "Syncing files to server..."
  # Plaintext login passwords are recovery copies; they never leave this machine.
  rsync -az --delete --exclude='.git' --exclude='secrets/users/*/plaintext' -e "ssh -i $SSH_KEY" "$SCRIPT_DIR/" "$HOST:~/deploy/"
  $SSH "sudo cp -r ~/deploy/secrets/* /var/lib/secrets/ && find ~/deploy/secrets/ -type f ! -name 'default.json' -delete"
}

rebuild() {
  echo "Rebuilding NixOS configuration..."
  $SSH "cd ~/deploy && sudo env PATH=\$PATH nixos-rebuild switch --impure --flake .#$FLAKE"
  echo "Waiting for services to start..."
  $SSH 'for url in http://localhost:8181 http://localhost:6767 http://localhost:8989 http://localhost:7878 http://localhost:5055 http://localhost:8081 http://localhost:32400/identity; do
    for i in $(seq 1 60); do
      code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "$url" 2>/dev/null) || true
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

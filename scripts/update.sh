#!/usr/bin/env bash
# Runs every updater, each change as its own commit (git's own identity), in
# order: nixpkgs first, since the Caddy plugin's hash depends on its Caddy.
# One failing updater doesn't stop the others; the exit status is then 2.
# Run daily by .github/workflows/update.yml; fine to run by hand.
set -euo pipefail

cd "$(dirname "$0")/.."
# It commits with -a and resets a failed updater's changes: never on yours.
if [ -n "$(git status --porcelain)" ]; then
  echo "ERROR: uncommitted changes; commit or stash them first" >&2
  exit 1
fi
status=0
for updater in nixpkgs caddy plex homebridge; do
  if ! message=$("scripts/update-$updater.sh"); then
    echo "WARNING: update-$updater.sh failed; skipped" >&2
    git checkout -- .
    status=2
    continue
  fi
  [ -n "$message" ] || continue
  git commit -q -a -F - <<<"$message"
  head -n 1 <<<"$message"
done
exit "$status"

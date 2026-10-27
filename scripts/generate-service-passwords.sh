#!/usr/bin/env bash
# Give each web UI its own login password (finding #5: one shared admin
# password meant one leaked config unlocked every service). Run on the Mac,
# in an unlocked git-crypt checkout, then deploy:
#
#   ./scripts/generate-service-passwords.sh
#   ./deploy.sh
#
# The deploy rotates each service to its new password (Homebridge and
# Audiobookshelf through their APIs, the rest via their *-config scripts).
# Existing files are kept; delete secrets/<service>/password to rotate one.
# The username stays secrets/admin/username.
set -euo pipefail
cd "$(dirname "$0")/.."

# Keep in step with passwordServices in configuration.nix (this runs on the
# Mac, so it can't read /etc/spudbox/env).
services=(sonarr radarr bazarr sabnzbd transmission tautulli homebridge audiobookshelf)

# A locked checkout has no git-crypt filter, so `git add` would commit the
# new passwords in plaintext. Refuse unless it's unlocked.
command -v git-crypt >/dev/null || { echo "git-crypt not installed" >&2; exit 1; }
if [ -z "$(git config --get filter.git-crypt.clean || true)" ] ||
  [ "$(head -c 9 secrets/admin/username | tr -d '\0')" = "GITCRYPT" ]; then
  echo "git-crypt is locked; run 'git-crypt unlock <key>' first" >&2
  exit 1
fi

umask 077
created=()
for svc in "${services[@]}"; do
  file="secrets/$svc/password"
  if [ -s "$file" ]; then
    echo "keep     $file"
    continue
  fi
  mkdir -p "secrets/$svc"
  # 32 alphanumerics (~190 bits); no newline, like the other secrets. Reads a
  # fixed amount of randomness: `tr </dev/urandom | head` dies of SIGPIPE
  # under pipefail.
  pw=$(LC_ALL=C tr -dc 'A-Za-z0-9' < <(head -c 1024 /dev/urandom))
  pw=${pw:0:32}
  [ ${#pw} -eq 32 ] || { echo "ERROR: password generation failed" >&2; exit 1; }
  printf '%s' "$pw" >"$file"
  created+=("$file")
  echo "created  $file"
done

if [ ${#created[@]} -eq 0 ]; then
  echo "Nothing to do."
  exit 0
fi

git add -- "${created[@]}"
# Belt and braces: make sure git-crypt really encrypts every new file
for file in "${created[@]}"; do
  if ! git-crypt status -- "$file" | grep -q '^ *encrypted:'; then
    git reset -q -- "${created[@]}"
    echo "ERROR: $file would not be encrypted; nothing committed" >&2
    exit 1
  fi
done
git commit -q -m "Add per-service web login passwords" -- "${created[@]}"

echo
echo "Committed ${#created[@]} encrypted password(s). Save them in the password manager"
echo "(username for each: $(cat secrets/admin/username)):"
for file in "${created[@]}"; do
  printf '  %-15s %s\n' "$(basename "$(dirname "$file")")" "$(cat "$file")"
done
echo
echo "Next: ./deploy.sh"

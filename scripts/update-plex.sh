#!/usr/bin/env bash
# Moves services/plex.json to the newest public Plex Media Server release:
# its version and the SRI hashes of its amd64 and arm64 .debs. Prints a commit
# message, or nothing when it's already current. Needs curl, jq and nix.
# Run daily by scripts/update.sh.
set -euo pipefail
shopt -s inherit_errexit # a failed check inside $(hash ...) stops the script

cd "$(dirname "$0")/.."
PIN=services/plex.json

releases=$(curl -fsS --retry 3 https://plex.tv/api/downloads/5.json)
version=$(jq -r '.computer.Linux.version' <<<"$releases")
current=$(jq -r .version "$PIN")
if [[ ! $version =~ ^[0-9]+(\.[0-9]+)+-[0-9a-f]+$ ]]; then
  echo "ERROR: unexpected version from plex.tv: '$version'" >&2
  exit 1
fi
[ "$version" = "$current" ] && exit 0

# hash ARCH: the SRI hash of that .deb, once its SHA-1 matches the one
# plex.tv lists for it.
hash() {
  local release url fetched
  release=$(jq -c --arg arch "$1" \
    '.computer.Linux.releases[] | select(.distro == "debian" and (.url | endswith("_\($arch).deb")))' \
    <<<"$releases")
  url=$(jq -r .url <<<"$release")
  [ "$url" = "https://downloads.plex.tv/plex-media-server-new/$version/debian/plexmediaserver_${version}_$1.deb" ] || {
    echo "ERROR: plex.tv lists '$url' for $1; services/plex.nix builds the URL differently" >&2
    exit 1
  }
  fetched=$(nix --extra-experimental-features nix-command store prefetch-file --json "$url")
  sha1sum -c --quiet <<<"$(jq -r .checksum <<<"$release")  $(jq -r .storePath <<<"$fetched")" >&2
  jq -r .hash <<<"$fetched"
}

amd64=$(hash amd64)
arm64=$(hash arm64)
jq -n --arg version "$version" --arg amd64 "$amd64" --arg arm64 "$arm64" \
  '{version: $version, hashes: {amd64: $amd64, arm64: $arm64}}' >"$PIN.tmp"
mv "$PIN.tmp" "$PIN"
echo "Plex $version"

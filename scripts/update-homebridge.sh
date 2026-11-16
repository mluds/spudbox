#!/usr/bin/env bash
# Moves services/homebridge.json to the newest plain date tag (YYYY-MM-DD;
# not alpha-/beta-) of the Homebridge image, pinned by its digest. Prints a
# commit message, or nothing when it's already current. Needs curl and jq.
set -euo pipefail
shopt -s inherit_errexit

cd "$(dirname "$0")/.."
PIN=services/homebridge.json
REPO=homebridge/homebridge

latest=$(curl -fsS --retry 3 "https://hub.docker.com/v2/repositories/$REPO/tags?page_size=100&ordering=last_updated" |
  jq -c '[.results[] | select(.name | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$"))] | sort_by(.name) | last')
tag=$(jq -r .name <<<"$latest")
digest=$(jq -r .digest <<<"$latest")
if [[ ! $tag =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ || ! $digest =~ ^sha256:[0-9a-f]{64}$ ]]; then
  echo "ERROR: unexpected tag or digest from Docker Hub: '$tag' '$digest'" >&2
  exit 1
fi
image="$REPO:$tag@$digest"
[ "$image" = "$(jq -r .image "$PIN")" ] && exit 0

jq -n --arg image "$image" '{image: $image}' >"$PIN.tmp"
mv "$PIN.tmp" "$PIN"
echo "Homebridge $tag"

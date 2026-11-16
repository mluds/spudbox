#!/usr/bin/env bash
# Moves services/caddy.json to the newest release of the Cloudflare DNS
# plugin and to the hash of the build's Go modules, which also changes when
# nixpkgs moves Caddy itself (so run this after update-nixpkgs.sh). Builds
# the plugin to get the hash, then again to check it. Prints a commit message,
# or nothing when it's already current. Needs curl, jq and nix.
set -euo pipefail
shopt -s inherit_errexit

cd "$(dirname "$0")/.."
PIN=services/caddy.json

module=$(jq -r '.plugin | split("@")[0]' "$PIN")
version=$(curl -fsS --retry 3 "https://proxy.golang.org/$module/@latest" | jq -r .Version)
if [[ ! $version =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: unexpected version from the Go proxy: '$version'" >&2
  exit 1
fi
plugin="$module@$version"

# build HASH: build Caddy with the plugin and that hash (Nix output on stderr).
build() {
  nix --extra-experimental-features 'nix-command flakes' build --no-link --impure --expr "
    (builtins.getFlake \"path:$PWD\").inputs.nixpkgs.legacyPackages.\${builtins.currentSystem}.caddy.withPlugins {
      plugins = [ \"$plugin\" ];
      hash = \"$1\";
    }"
}

current_plugin=$(jq -r .plugin "$PIN")
if [ "$plugin" = "$current_plugin" ] && build "$(jq -r .hash "$PIN")" 2>/dev/null; then
  exit 0
fi
# With an empty hash, Nix fails and reports the real one ("got: sha256-...").
if log=$(build "" 2>&1); then
  echo "ERROR: the build succeeded with an empty hash" >&2
  exit 1
fi
hash=$(sed -n 's/^ *got: *\(sha256-[A-Za-z0-9+/=]*\)$/\1/p' <<<"$log" | tail -n 1)
if [ -z "$hash" ]; then
  echo "$log" >&2
  echo "ERROR: no hash in the build's output" >&2
  exit 1
fi
build "$hash" 2>/dev/null

caddy=$(nix --extra-experimental-features 'nix-command flakes' eval --raw --impure --expr \
  "(builtins.getFlake \"path:$PWD\").inputs.nixpkgs.legacyPackages.\${builtins.currentSystem}.caddy.version")
jq -n --arg plugin "$plugin" --arg hash "$hash" '{plugin: $plugin, hash: $hash}' >"$PIN.tmp"
mv "$PIN.tmp" "$PIN"
if [ "$plugin" = "$current_plugin" ]; then
  echo "Caddy ${module##*/} plugin: new build hash (nixpkgs changed Caddy $caddy's build)"
else
  echo "Caddy ${module##*/} plugin ${current_plugin##*@} -> $version (Caddy $caddy)"
fi

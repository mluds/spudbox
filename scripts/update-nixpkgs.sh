#!/usr/bin/env bash
# Moves flake.lock's nixpkgs to the newest commit of its channel (the branch
# in flake.nix: security fixes and backports, never a channel jump). Prints a
# commit message listing the apps whose version changed, or nothing when it's
# already current. Needs jq and nix.
set -euo pipefail
shopt -s inherit_errexit

cd "$(dirname "$0")/.."
NIX=(nix --extra-experimental-features 'nix-command flakes')

# The template's system (every feature off) and each app's version in it.
versions() {
  "${NIX[@]}" eval --json --impure --expr "
    let
      flake = builtins.getFlake \"path:$PWD\";
      c = (flake.inputs.nixpkgs.lib.nixosSystem {
        modules = [ ./module.nix ./template/spudbox.nix {
          nixpkgs.hostPlatform = builtins.currentSystem;
          fileSystems.\"/\" = { device = \"/dev/null\"; fsType = \"ext4\"; };
          boot.loader.grub.enable = false;
        } ];
      }).config;
      s = c.services;
    in {
      Linux = c.boot.kernelPackages.kernel.version;
      Sonarr = s.sonarr.package.version;
      Radarr = s.radarr.package.version;
      Bazarr = s.bazarr.package.version;
      SABnzbd = s.sabnzbd.package.version;
      Transmission = s.transmission.package.version;
      Tautulli = s.tautulli.package.version;
      seerr = s.seerr.package.version;
      Audiobookshelf = s.audiobookshelf.package.version;
      Caddy = s.caddy.package.version;
      Homepage = s.homepage-dashboard.package.version;
      restic = s.restic.backups.local.package.version;
    }"
}

old_rev=$(jq -r .nodes.nixpkgs.locked.rev flake.lock)
before=$(versions)
"${NIX[@]}" flake update nixpkgs 2>/dev/null
new_rev=$(jq -r .nodes.nixpkgs.locked.rev flake.lock)
[ "$new_rev" = "$old_rev" ] && exit 0
after=$(versions)

date=$(jq -r '.nodes.nixpkgs.locked.lastModified | todate[:10]' flake.lock)
branch=$(jq -r '.nodes.nixpkgs.original.ref' flake.lock)
echo "nixpkgs $branch $date (${old_rev:0:7} -> ${new_rev:0:7})"
changes=$(jq -rn --argjson a "$before" --argjson b "$after" \
  '$b | to_entries[] | select($a[.key] != .value) | "- \(.key) \($a[.key]) -> \(.value)"')
if [ -n "$changes" ]; then
  printf '\n%s\n' "$changes"
fi

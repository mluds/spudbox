# SPUDBOX-PLACEHOLDER: replaced by your machine's own hardware config. Boot
# the NixOS installer, mount the new system at /mnt, then run
#   ./deploy.sh hardware root@<ip>
# (it runs nixos-generate-config there and writes this file).
_: throw "hardware.nix is still the template's placeholder; run ./deploy.sh hardware root@<ip>"

{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs =
    { self, nixpkgs, ... }:
    let
      # Plex is pinned by hand; see "Hand-pinned versions" in CLAUDE.md.
      plexOverlay = final: prev: {
        plexRaw = prev.plexRaw.overrideAttrs (_: rec {
          version = "1.43.4.10903-e5521bd8c";
          src =
            let
              debs = {
                x86_64-linux = {
                  arch = "amd64";
                  hash = "sha256-b2ocgzbXeeHyAVGmk0NJiEutb2pmsYorGJuW5Vw7Pts=";
                };
                aarch64-linux = {
                  arch = "arm64";
                  hash = "sha256-lF6G0FFPYUkrUWm76sbpGJKzNvaJXXhjK+wBe1kI5as=";
                };
              };
              deb = debs.${final.stdenv.hostPlatform.system};
            in
            prev.fetchurl {
              url = "https://downloads.plex.tv/plex-media-server-new/${version}/debian/plexmediaserver_${version}_${deb.arch}.deb";
              inherit (deb) hash;
            };
        });
      };

      # Which commit is deployed: the flake's own rev in a git checkout, else
      # the .revision file deploy.sh writes into ~/deploy (not a git checkout).
      revision =
        self.rev or self.dirtyRev or (
          if builtins.pathExists ./.revision then
            nixpkgs.lib.removeSuffix "\n" (builtins.readFile ./.revision)
          else
            null
        );

      mkHost =
        system: hardware: environment:
        nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            {
              nixpkgs.overlays = [ plexOverlay ];
              system.configurationRevision = revision;
            }
            hardware
            environment
            ./configuration.nix
          ];
        };
    in
    {
      nixosConfigurations = {
        # Dev's hardware config isn't in the repo, so dev still needs --impure.
        spudbox-dev = mkHost "aarch64-linux" /etc/nixos/hardware-configuration.nix ./environments/dev.nix;
        # From nixos-generate-config on prod; regenerate it there after
        # hardware changes (see CLAUDE.md).
        spudbox-prod = mkHost "x86_64-linux" ./hosts/prod-hardware.nix ./environments/prod.nix;
      };
    };
}

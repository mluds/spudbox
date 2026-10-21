{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs =
    { nixpkgs, ... }:
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

      mkHost =
        system: environment:
        nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            { nixpkgs.overlays = [ plexOverlay ]; }
            /etc/nixos/hardware-configuration.nix
            environment
            ./configuration.nix
          ];
        };
    in
    {
      nixosConfigurations = {
        spudbox-dev = mkHost "aarch64-linux" ./environments/dev.nix;
        spudbox-prod = mkHost "x86_64-linux" ./environments/prod.nix;
      };
    };
}

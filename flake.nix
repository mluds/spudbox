{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs =
    { nixpkgs, ... }@inputs:
    let
      plexOverlay = final: prev: {
        plexRaw = prev.plexRaw.overrideAttrs (_: rec {
          version = "1.43.4.10903-e5521bd8c";
          src = prev.fetchurl {
            url =
              "https://downloads.plex.tv/plex-media-server-new/${version}/debian/plexmediaserver_${version}_${
                if final.stdenv.hostPlatform.system == "aarch64-linux" then "arm64" else "amd64"
              }.deb";
            sha256 = "sha256-b2ocgzbXeeHyAVGmk0NJiEutb2pmsYorGJuW5Vw7Pts=";
          };
        });
      };
    in
    {
      nixosConfigurations = {
        "spudbox-dev" = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            { nixpkgs.overlays = [ plexOverlay ]; }
            /etc/nixos/hardware-configuration.nix
            ./environments/dev.nix
            ./configuration.nix
          ];
        };

        "spudbox-prod" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            { nixpkgs.overlays = [ plexOverlay ]; }
            /etc/nixos/hardware-configuration.nix
            ./environments/prod.nix
            ./configuration.nix
          ];
        };
      };
    };
}

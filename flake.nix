{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs =
    { nixpkgs, ... }@inputs:
    let
      plexOverlay = final: prev: {
        plexRaw = prev.plexRaw.overrideAttrs (_: rec {
          version = "1.43.1.10561-69cc2fd8d";
          src = prev.fetchurl {
            url =
              "https://downloads.plex.tv/plex-media-server-new/${version}/debian/plexmediaserver_${version}_${
                if final.stdenv.hostPlatform.system == "aarch64-linux" then "arm64" else "amd64"
              }.deb";
            sha256 = "sha256-o2oZ2pz4opdPd8/gzq8E4oaC0NxqDw3RFcgInJdBGIs=";
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

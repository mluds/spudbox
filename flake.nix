{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs =
    { nixpkgs, ... }@inputs:
    let
      plexOverlay = final: prev: {
        plexRaw = prev.plexRaw.overrideAttrs (_: rec {
          version = "1.43.0.10492-121068a07";
          src = prev.fetchurl {
            url =
              "https://downloads.plex.tv/plex-media-server-new/${version}/debian/plexmediaserver_${version}_${
                if final.stdenv.hostPlatform.system == "aarch64-linux" then "arm64" else "amd64"
              }.deb";
            sha256 = "sha256-HA779rkjy8QBlW2+IsRmgu4t5PT2Gy0oaqcJm+9zCYE=";
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

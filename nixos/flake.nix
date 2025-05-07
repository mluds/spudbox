{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... } @ inputs:
    let
      secrets = builtins.fromJSON (builtins.readFile "${self}/secrets/default.json");
    in
    {
      nixosConfigurations = {
        "spudbox-dev" = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          specialArgs = { inherit inputs secrets; };
          modules = [
            ./hosts/spudbox-dev/hardware.nix
            ./environments/dev.nix
            ./configuration.nix
          ];
        };

        "spudbox-prod" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs secrets; };
          modules = [
            ./environments/prod.nix
            ./configuration.nix
          ];
        };
      };
    };
}

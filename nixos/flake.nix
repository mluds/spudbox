{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, disko, ... } @ inputs:
    let
      secrets = builtins.fromJSON (builtins.readFile "${self}/secrets/default.json");
    in
    {
      nixosConfigurations = {
        "spudbox-dev" = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          specialArgs = { inherit inputs secrets; };
          modules = [
            disko.nixosModules.disko
            ./hosts/spudbox-dev/hardware.nix
            ./environments/dev.nix
            ./configuration.nix
          ];
        };

        "spudbox-prod" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs secrets; };
          modules = [
            disko.nixosModules.disko
            ./environments/prod.nix
            ./configuration.nix
          ];
        };
      };
    };
}

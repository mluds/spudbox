{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/24.11";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, sops-nix, ... } @ inputs:
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

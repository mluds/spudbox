{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/24.11";
    deploy-rs.url = "github:serokell/deploy-rs";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, deploy-rs, nixpkgs, sops-nix, ... } @ inputs: {
    nixosConfigurations.spudbox = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      specialArgs = {
        inherit inputs;
        pkgs = import nixpkgs {
          system = "aarch64-linux";
          config.allowUnsupportedSystem = true;  # Critical override
        };
        # pkgs = import nixpkgs {
        #   # system = "aarch64-linux";
        #   inherit (self.nixosConfigurations.spudbox) system;
        #   config.allowUnsupportedSystem = true;
        # };
      };
      modules = [
        ./configuration.nix
      ];
    };

    deploy = {
      nodes.spudbox = {
        hostname = "nix-dev";
        profiles.system = {
          user = "luds";
          path = deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.spudbox;
        };
      };
    };
  };
}

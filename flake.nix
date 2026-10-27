{
  description = "spudbox: a self-hosted NixOS media server (Plex, Sonarr, Radarr, Bazarr, Jellyseerr, SABnzbd, Transmission, Audiobookshelf) behind Caddy";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs =
    { self, nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;

      # A checkout's commit: the flake's own rev in a git checkout, else the
      # .revision file deploy.sh writes into a copied tree (not a git
      # checkout), else null.
      revisionOf =
        src:
        src.rev or src.dirtyRev or (
          if builtins.pathExists "${src}/.revision" then
            lib.removeSuffix "\n" (builtins.readFile "${src}/.revision")
          else
            null
        );

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = lib.genAttrs systems;
    in
    {
      nixosModules.default = ./module.nix;

      lib = {
        # The NixOS system for an instance: `instance` is the instance flake
        # (for its revision), `modules` its settings and hardware config. The
        # architecture comes from the hardware config (nixpkgs.hostPlatform).
        mkSystem =
          {
            instance,
            modules,
            specialArgs ? { },
          }:
          lib.nixosSystem {
            inherit specialArgs;
            modules = [
              self.nixosModules.default
              {
                system.configurationRevision = revisionOf instance;
                spudbox.revision = revisionOf self;
              }
            ]
            ++ modules;
          };
      };

      templates.default = {
        path = ./template;
        description = "A spudbox instance: your settings, hardware config and secrets";
      };

      # Tools for lint.sh: nix develop -c ./lint.sh
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              statix
              deadnix
              nixfmt
              shellcheck
              ruff
              gitleaks
              typos
            ];
          };
        }
      );

      # The template's example settings evaluate to a full system (only
      # evaluated, not built: nix flake check stays quick).
      checks = forAllSystems (
        system:
        let
          example = lib.nixosSystem {
            modules = [
              ./module.nix
              ./template/spudbox.nix
              {
                nixpkgs.hostPlatform = system;
                fileSystems."/" = {
                  device = "/dev/disk/by-label/nixos";
                  fsType = "ext4";
                };
                boot.loader.grub.enable = false;
              }
            ];
          };
        in
        {
          template = nixpkgs.legacyPackages.${system}.writeText "spudbox-template-eval" (
            builtins.unsafeDiscardStringContext example.config.system.build.toplevel.drvPath
          );
        }
      );
    };
}

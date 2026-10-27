{
  # Your spudbox server: settings (spudbox.nix), hardware config and
  # secrets. The code comes from the spudbox flake, pinned in flake.lock
  # (./deploy.sh update moves it).
  inputs.spudbox.url = "github:mluds/spudbox";

  outputs =
    { self, spudbox }:
    {
      nixosConfigurations.default = spudbox.lib.mkSystem {
        instance = self;
        modules = [
          ./hardware.nix
          ./spudbox.nix
        ];
      };
    };
}

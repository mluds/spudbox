{ lib, ... }:

{
  options.my = lib.mkOption {
    type = lib.types.attrs;
    default = { };
    description = "Custom configuration options";
  };
}

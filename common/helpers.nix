{ config, pkgs, ... }:

# Small commands shared by the *-config scripts, passed to every module as the
# `helpers` argument; add it to a writeShellApplication's runtimeInputs.
{
  _module.args.helpers = pkgs.symlinkJoin {
    name = "spudbox-helpers";
    paths = [
      # read-secret NAME: print a secret from secretsDir, e.g. plex/token.
      (pkgs.writeShellApplication {
        name = "read-secret";
        text = ''exec cat "${config.spudbox.secretsDir}/$1"'';
      })
      # wait-for-http URL [INTERVAL]: block until URL answers without an HTTP error.
      (pkgs.writeShellApplication {
        name = "wait-for-http";
        runtimeInputs = [ pkgs.curl ];
        text = ''
          until curl -sf -o /dev/null "$1"; do
            sleep "''${2:-2}"
          done
        '';
      })
    ];
  };
}

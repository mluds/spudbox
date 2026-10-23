{ config, lib, ... }:

# /etc/spudbox/env: dirs, domain and every `my.*Port` as shell variables
# (sonarrPort -> SONARR_PORT), so test.sh and deploy.sh don't hard-code them.
# `text` is a lines option, so other modules can append to it (see caddy.nix).
let
  cfg = config.my;
  toEnvName =
    name:
    lib.toUpper (
      lib.concatMapStrings (c: if lib.toLower c != c then "_${c}" else c) (lib.stringToCharacters name)
    );
  ports = lib.filterAttrs (name: _: lib.hasSuffix "Port" name) cfg;
in
{
  environment.etc."spudbox/env".text = lib.concatLines (
    [
      (lib.toShellVar "DOMAIN" cfg.domain)
      (lib.toShellVar "SECRETS_DIR" cfg.secretsDir)
      (lib.toShellVar "STORAGE_DIR" cfg.storageDir)
      (lib.toShellVar "CACHE_DIR" cfg.cacheDir)
      (lib.toShellVar "BACKUP_DIR" cfg.backupDir)
      (lib.toShellVar "REVISION" (toString config.system.configurationRevision))
    ]
    ++ lib.mapAttrsToList (name: value: lib.toShellVar (toEnvName name) value) ports
  );
}

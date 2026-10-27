{ config, lib, ... }:

# /etc/spudbox/env: dirs, domain, enabled FEATURES and every `spudbox.*Port` as shell variables
# (sonarrPort -> SONARR_PORT), so test.sh and deploy.sh don't hard-code them.
# `text` is a lines option, so other modules can append to it (see caddy.nix).
let
  cfg = config.spudbox;
  toEnvName =
    name:
    lib.toUpper (
      lib.concatMapStrings (c: if lib.toLower c != c then "_${c}" else c) (lib.stringToCharacters name)
    );
  ports = lib.filterAttrs (name: _: lib.hasSuffix "Port" name) cfg;
in
{
  options.spudbox.revision = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    internal = true;
    description = "Commit of the spudbox module itself (set by lib.mkSystem); the instance's is system.configurationRevision.";
  };

  config.environment.etc."spudbox/env".text = lib.concatLines (
    [
      (lib.toShellVar "DOMAIN" cfg.domain)
      (lib.toShellVar "SECRETS_DIR" cfg.secretsDir)
      (lib.toShellVar "STORAGE_DIR" cfg.storageDir)
      (lib.toShellVar "CACHE_DIR" cfg.cacheDir)
      (lib.toShellVar "BACKUP_DIR" cfg.backupDir)
      (lib.toShellVar "REVISION" (toString config.system.configurationRevision))
      (lib.toShellVar "SPUDBOX_REVISION" (toString cfg.revision))
      (lib.toShellVar "FEATURES" cfg.features)
      (lib.toShellVar "INDEXERS" (map (indexer: indexer.name) cfg.indexers))
      (lib.toShellVar "USENET_SERVERS" cfg.usenet.servers)
      (lib.toShellVar "SUBTITLE_PROVIDERS" cfg.subtitleProviders)
      # Block device names (sda), as drive-check names its status files
      (lib.toShellVar "STORAGE_DEVICES" (
        lib.unique (map (drive: baseNameOf drive.device) cfg.storageDrives)
      ))
    ]
    ++ lib.mapAttrsToList (name: value: lib.toShellVar (toEnvName name) value) ports
  );
}

{
  config,
  lib,
  pkgs,
  helpers,
  ...
}:

with config.my;

let
  mkArrConfig = import ./mkArrConfig.nix {
    inherit
      config
      lib
      pkgs
      helpers
      ;
  };
  configScript = mkArrConfig {
    name = "sonarr";
    port = sonarrPort;
    rootFolder = {
      name = "TV";
      path = "${storageDir}/data/media/tv";
    };
    sabCategory = "tv";
    indexerFields = [
      {
        name = "categories";
        value = [
          5020
          5030
          5040
          5045
        ];
      }
      {
        name = "animeCategories";
        value = [ 5070 ];
      }
      {
        name = "animeStandardFormatSearch";
        value = true;
      }
    ];
    inherit (import ./qualityDefinitions.nix) qualityProfile;
    lookupPath = "series/lookup";
    addPath = "series";
    addOptions = {
      monitor = "existing";
      searchForMissingEpisodes = false;
      searchForCutoffUnmetEpisodes = false;
    };
    rescanCommand = "RescanSeries";
    # "Title (2020)" -> "Title"
    searchTermSed = "s/([^)]*)$//; s/ *$//";
  };
in
{
  services.sonarr = {
    enable = true;
    user = "sonarr";
    group = "media";
    openFirewall = false;
    # Loopback only; reached through Caddy (env var overrides config.xml).
    settings.server.bindaddress = "127.0.0.1";
  };

  systemd.services.sonarr.serviceConfig.StateDirectoryMode = "0700";

  systemd.services.sonarr-config = {
    wantedBy = [ "multi-user.target" ];
    after = [ "sonarr.service" ];
    serviceConfig = {
      User = "root";
      Type = "oneshot";
      ExecStart = lib.getExe configScript;
    };
  };
}

{
  config,
  lib,
  pkgs,
  helpers,
  ...
}:

let
  inherit (config.spudbox)
    sonarrPort
    storageDir
    ;

  mkArrConfig = import ./mkArrConfig.nix {
    inherit
      config
      lib
      pkgs
      helpers
      ;
  };
in
lib.mkMerge [
  (mkArrConfig {
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
    qualityProfile = (import ./qualityDefinitions.nix).sonarrQualityProfile;
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
  })
  { systemd.services.sonarr.serviceConfig.StateDirectoryMode = "0700"; }
]

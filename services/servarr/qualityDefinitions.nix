let
  sized =
    sizes: names:
    builtins.listToAttrs (
      map (name: {
        inherit name;
        value = sizes;
      }) names
    );

  # Quality profile entries. `quality` is the app's own quality record;
  # a group bundles several qualities under one rank.
  allowed = quality: {
    inherit quality;
    allowed = true;
    items = [ ];
  };
  blocked = quality: allowed quality // { allowed = false; };
  group = id: name: qualities: {
    inherit id name;
    allowed = true;
    items = map allowed qualities;
  };

  # Sonarr quality record.
  tv = id: name: source: resolution: {
    inherit
      id
      name
      source
      resolution
      ;
  };
  # Radarr quality record (has a modifier too).
  movie = id: name: source: resolution: modifier: {
    inherit
      id
      name
      source
      resolution
      modifier
      ;
  };
in
{
  # Per-quality size limits (MB per minute), shared by Sonarr and Radarr.
  qualitySettings =
    sized
      {
        minSize = 0;
        preferredSize = 95;
        maxSize = 100;
      }
      [
        "Unknown"
        "WORKPRINT"
        "CAM"
        "TELESYNC"
        "TELECINE"
        "REGIONAL"
        "DVDSCR"
        "SDTV"
        "DVD"
        "DVD-R"
        "WEBDL-480p"
        "WEBRip-480p"
        "Bluray-480p"
        "Bluray-576p"
        "HDTV-720p"
        "WEBDL-720p"
        "WEBRip-720p"
        "Bluray-720p"
        "HDTV-1080p"
        "WEBDL-1080p"
        "WEBRip-1080p"
      ]
    //
      sized
        {
          minSize = 0;
          preferredSize = 150;
          maxSize = 200;
        }
        [
          "Bluray-1080p"
          "Bluray-1080p Remux"
          "Remux-1080p"
          "HDTV-2160p"
          "WEBDL-2160p"
          "WEBRip-2160p"
          "Bluray-2160p"
          "Remux-2160p"
          "Bluray-2160p Remux"
          "BR-DISK"
          "Raw-HD"
        ];

  # Sonarr profile 1 ("Any").
  sonarrQualityProfile = {
    id = 1;
    name = "Any";
    upgradeAllowed = false;
    cutoff = 1;
    minFormatScore = 0;
    cutoffFormatScore = 0;
    minUpgradeFormatScore = 1;
    formatItems = [ ];
    items = [
      (blocked (tv 0 "Unknown" "unknown" 0))
      (allowed (tv 1 "SDTV" "television" 480))
      (group 1000 "WEB 480p" [
        (tv 12 "WEBRip-480p" "webRip" 480)
        (tv 8 "WEBDL-480p" "web" 480)
      ])
      (allowed (tv 2 "DVD" "dvd" 480))
      (allowed (tv 13 "Bluray-480p" "bluray" 480))
      (allowed (tv 22 "Bluray-576p" "bluray" 576))
      (allowed (tv 4 "HDTV-720p" "television" 720))
      (allowed (tv 9 "HDTV-1080p" "television" 1080))
      (blocked (tv 10 "Raw-HD" "televisionRaw" 1080))
      (group 1001 "WEB 720p" [
        (tv 14 "WEBRip-720p" "webRip" 720)
        (tv 5 "WEBDL-720p" "web" 720)
      ])
      (allowed (tv 6 "Bluray-720p" "bluray" 720))
      (group 1002 "WEB 1080p" [
        (tv 15 "WEBRip-1080p" "webRip" 1080)
        (tv 3 "WEBDL-1080p" "web" 1080)
      ])
      (allowed (tv 7 "Bluray-1080p" "bluray" 1080))
      (blocked (tv 20 "Bluray-1080p Remux" "blurayRaw" 1080))
      (allowed (tv 16 "HDTV-2160p" "television" 2160))
      (group 1003 "WEB 2160p" [
        (tv 17 "WEBRip-2160p" "webRip" 2160)
        (tv 18 "WEBDL-2160p" "web" 2160)
      ])
      (allowed (tv 19 "Bluray-2160p" "bluray" 2160))
      (blocked (tv 21 "Bluray-2160p Remux" "blurayRaw" 2160))
    ];
  };

  # Radarr profile 1 ("Any").
  radarrQualityProfile = {
    id = 1;
    name = "Any";
    language = {
      id = -2;
      name = "Original";
    };
    upgradeAllowed = false;
    cutoff = 20;
    minFormatScore = 0;
    cutoffFormatScore = 0;
    minUpgradeFormatScore = 1;
    formatItems = [ ];
    items = [
      (blocked (movie 0 "Unknown" "unknown" 0 "none"))
      (blocked (movie 24 "WORKPRINT" "workprint" 0 "none"))
      (blocked (movie 25 "CAM" "cam" 0 "none"))
      (blocked (movie 26 "TELESYNC" "telesync" 0 "none"))
      (blocked (movie 27 "TELECINE" "telecine" 0 "none"))
      (allowed (movie 29 "REGIONAL" "dvd" 480 "regional"))
      (allowed (movie 28 "DVDSCR" "dvd" 480 "screener"))
      (allowed (movie 1 "SDTV" "tv" 480 "none"))
      (allowed (movie 2 "DVD" "dvd" 0 "none"))
      (allowed (movie 23 "DVD-R" "dvd" 480 "remux"))
      (group 1000 "WEB 480p" [
        (movie 8 "WEBDL-480p" "webdl" 480 "none")
        (movie 12 "WEBRip-480p" "webrip" 480 "none")
      ])
      (allowed (movie 20 "Bluray-480p" "bluray" 480 "none"))
      (allowed (movie 21 "Bluray-576p" "bluray" 576 "none"))
      (allowed (movie 4 "HDTV-720p" "tv" 720 "none"))
      (group 1001 "WEB 720p" [
        (movie 5 "WEBDL-720p" "webdl" 720 "none")
        (movie 14 "WEBRip-720p" "webrip" 720 "none")
      ])
      (allowed (movie 6 "Bluray-720p" "bluray" 720 "none"))
      (allowed (movie 9 "HDTV-1080p" "tv" 1080 "none"))
      (group 1002 "WEB 1080p" [
        (movie 3 "WEBDL-1080p" "webdl" 1080 "none")
        (movie 15 "WEBRip-1080p" "webrip" 1080 "none")
      ])
      (allowed (movie 7 "Bluray-1080p" "bluray" 1080 "none"))
      (allowed (movie 30 "Remux-1080p" "bluray" 1080 "remux"))
      (allowed (movie 16 "HDTV-2160p" "tv" 2160 "none"))
      (group 1003 "WEB 2160p" [
        (movie 18 "WEBDL-2160p" "webdl" 2160 "none")
        (movie 17 "WEBRip-2160p" "webrip" 2160 "none")
      ])
      (allowed (movie 19 "Bluray-2160p" "bluray" 2160 "none"))
      (allowed (movie 31 "Remux-2160p" "bluray" 2160 "remux"))
      (blocked (movie 22 "BR-DISK" "bluray" 1080 "brdisk"))
      (blocked (movie 10 "Raw-HD" "tv" 1080 "rawhd"))
    ];
  };
}

{
  qualitySettings = {
    "Unknown" = { minSize = 0; preferredSize = 95; maxSize = 100; };
    "WORKPRINT" = { minSize = 0; preferredSize = 95; maxSize = 100; };
    "CAM" = { minSize = 0; preferredSize = 95; maxSize = 100; };
    "TELESYNC" = { minSize = 0; preferredSize = 95; maxSize = 100; };
    "TELECINE" = { minSize = 0; preferredSize = 95; maxSize = 100; };
    "REGIONAL" = { minSize = 0; preferredSize = 95; maxSize = 100; };
    "DVDSCR" = { minSize = 0; preferredSize = 95; maxSize = 100; };
    "SDTV" = { minSize = 0; preferredSize = 95; maxSize = 100; };
    "DVD" = { minSize = 0; preferredSize = 95; maxSize = 100; };
    "DVD-R" = { minSize = 0; preferredSize = 95; maxSize = 100; };
    "WEBDL-480p" = { minSize = 0; preferredSize = 95; maxSize = 100; };
    "WEBRip-480p" = { minSize = 0; preferredSize = 95; maxSize = 100; };
    "Bluray-480p" = { minSize = 0; preferredSize = 95; maxSize = 100; };
    "Bluray-576p" = { minSize = 0; preferredSize = 95; maxSize = 100; };
    "HDTV-720p" = { minSize = 0; preferredSize = 95; maxSize = 100; };
    "WEBDL-720p" = { minSize = 0; preferredSize = 95; maxSize = 100; };
    "WEBRip-720p" = { minSize = 0; preferredSize = 95; maxSize = 100; };
    "Bluray-720p" = { minSize = 0; preferredSize = 95; maxSize = 100; };
    "HDTV-1080p" = { minSize = 0; preferredSize = 95; maxSize = 100; };
    "WEBDL-1080p" = { minSize = 0; preferredSize = 95; maxSize = 100; };
    "WEBRip-1080p" = { minSize = 0; preferredSize = 95; maxSize = 100; };
    "Bluray-1080p" = { minSize = 0; preferredSize = 150; maxSize = 200; };
    "Bluray-1080p Remux" = { minSize = 0; preferredSize = 150; maxSize = 200; };
    "Remux-1080p" = { minSize = 0; preferredSize = 150; maxSize = 200; };
    "HDTV-2160p" = { minSize = 0; preferredSize = 150; maxSize = 200; };
    "WEBDL-2160p" = { minSize = 0; preferredSize = 150; maxSize = 200; };
    "WEBRip-2160p" = { minSize = 0; preferredSize = 150; maxSize = 200; };
    "Bluray-2160p" = { minSize = 0; preferredSize = 150; maxSize = 200; };
    "Remux-2160p" = { minSize = 0; preferredSize = 150; maxSize = 200; };
    "Bluray-2160p Remux" = { minSize = 0; preferredSize = 150; maxSize = 200; };
    "BR-DISK" = { minSize = 0; preferredSize = 150; maxSize = 200; };
    "Raw-HD" = { minSize = 0; preferredSize = 150; maxSize = 200; };
  };
  qualityProfile = {
    cutoff = 1;
    cutoffFormatScore = 0;
    formatItems = [];
    id = 1;
    items = [
      {
        allowed = false;
        items = [];
        quality = {
          id = 0;
          name = "Unknown";
          resolution = 0;
          source = "unknown";
        };
      }
      {
        allowed = true;
        items = [];
        quality = {
          id = 1;
          name = "SDTV";
          resolution = 480;
          source = "television";
        };
      }
      {
        allowed = true;
        id = 1000;
        items = [
          {
            allowed = true;
            items = [];
            quality = {
              id = 12;
              name = "WEBRip-480p";
              resolution = 480;
              source = "webRip";
            };
          }
          {
            allowed = true;
            items = [];
            quality = {
              id = 8;
              name = "WEBDL-480p";
              resolution = 480;
              source = "web";
            };
          }
        ];
        name = "WEB 480p";
      }
      {
        allowed = true;
        items = [];
        quality = {
          id = 2;
          name = "DVD";
          resolution = 480;
          source = "dvd";
        };
      }
      {
        allowed = true;
        items = [];
        quality = {
          id = 13;
          name = "Bluray-480p";
          resolution = 480;
          source = "bluray";
        };
      }
      {
        allowed = true;
        items = [];
        quality = {
          id = 22;
          name = "Bluray-576p";
          resolution = 576;
          source = "bluray";
        };
      }
      {
        allowed = true;
        items = [];
        quality = {
          id = 4;
          name = "HDTV-720p";
          resolution = 720;
          source = "television";
        };
      }
      {
        allowed = true;
        items = [];
        quality = {
          id = 9;
          name = "HDTV-1080p";
          resolution = 1080;
          source = "television";
        };
      }
      {
        allowed = false;
        items = [];
        quality = {
          id = 10;
          name = "Raw-HD";
          resolution = 1080;
          source = "televisionRaw";
        };
      }
      {
        allowed = true;
        id = 1001;
        items = [
          {
            allowed = true;
            items = [];
            quality = {
              id = 14;
              name = "WEBRip-720p";
              resolution = 720;
              source = "webRip";
            };
          }
          {
            allowed = true;
            items = [];
            quality = {
              id = 5;
              name = "WEBDL-720p";
              resolution = 720;
              source = "web";
            };
          }
        ];
        name = "WEB 720p";
      }
      {
        allowed = true;
        items = [];
        quality = {
          id = 6;
          name = "Bluray-720p";
          resolution = 720;
          source = "bluray";
        };
      }
      {
        allowed = true;
        id = 1002;
        items = [
          {
            allowed = true;
            items = [];
            quality = {
              id = 15;
              name = "WEBRip-1080p";
              resolution = 1080;
              source = "webRip";
            };
          }
          {
            allowed = true;
            items = [];
            quality = {
              id = 3;
              name = "WEBDL-1080p";
              resolution = 1080;
              source = "web";
            };
          }
        ];
        name = "WEB 1080p";
      }
      {
        allowed = true;
        items = [];
        quality = {
          id = 7;
          name = "Bluray-1080p";
          resolution = 1080;
          source = "bluray";
        };
      }
      {
        allowed = false;
        items = [];
        quality = {
          id = 20;
          name = "Bluray-1080p Remux";
          resolution = 1080;
          source = "blurayRaw";
        };
      }
      {
        allowed = true;
        items = [];
        quality = {
          id = 16;
          name = "HDTV-2160p";
          resolution = 2160;
          source = "television";
        };
      }
      {
        allowed = true;
        id = 1003;
        items = [
          {
            allowed = true;
            items = [];
            quality = {
              id = 17;
              name = "WEBRip-2160p";
              resolution = 2160;
              source = "webRip";
            };
          }
          {
            allowed = true;
            items = [];
            quality = {
              id = 18;
              name = "WEBDL-2160p";
              resolution = 2160;
              source = "web";
            };
          }
        ];
        name = "WEB 2160p";
      }
      {
        allowed = true;
        items = [];
        quality = {
          id = 19;
          name = "Bluray-2160p";
          resolution = 2160;
          source = "bluray";
        };
      }
      {
        allowed = false;
        items = [];
        quality = {
          id = 21;
          name = "Bluray-2160p Remux";
          resolution = 2160;
          source = "blurayRaw";
        };
      }
    ];
    minFormatScore = 0;
    minUpgradeFormatScore = 1;
    name = "Any";
    upgradeAllowed = false;
  };
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
      {
        quality = {
          id = 0;
          name = "Unknown";
          source = "unknown";
          resolution = 0;
          modifier = "none";
        };
        items = [ ];
        allowed = false;
      }
      {
        quality = {
          id = 24;
          name = "WORKPRINT";
          source = "workprint";
          resolution = 0;
          modifier = "none";
        };
        items = [ ];
        allowed = false;
      }
      {
        quality = {
          id = 25;
          name = "CAM";
          source = "cam";
          resolution = 0;
          modifier = "none";
        };
        items = [ ];
        allowed = false;
      }
      {
        quality = {
          id = 26;
          name = "TELESYNC";
          source = "telesync";
          resolution = 0;
          modifier = "none";
        };
        items = [ ];
        allowed = false;
      }
      {
        quality = {
          id = 27;
          name = "TELECINE";
          source = "telecine";
          resolution = 0;
          modifier = "none";
        };
        items = [ ];
        allowed = false;
      }
      {
        quality = {
          id = 29;
          name = "REGIONAL";
          source = "dvd";
          resolution = 480;
          modifier = "regional";
        };
        items = [ ];
        allowed = true;
      }
      {
        quality = {
          id = 28;
          name = "DVDSCR";
          source = "dvd";
          resolution = 480;
          modifier = "screener";
        };
        items = [ ];
        allowed = true;
      }
      {
        quality = {
          id = 1;
          name = "SDTV";
          source = "tv";
          resolution = 480;
          modifier = "none";
        };
        items = [ ];
        allowed = true;
      }
      {
        quality = {
          id = 2;
          name = "DVD";
          source = "dvd";
          resolution = 0;
          modifier = "none";
        };
        items = [ ];
        allowed = true;
      }
      {
        quality = {
          id = 23;
          name = "DVD-R";
          source = "dvd";
          resolution = 480;
          modifier = "remux";
        };
        items = [ ];
        allowed = true;
      }
      {
        name = "WEB 480p";
        items = [
          {
            quality = {
              id = 8;
              name = "WEBDL-480p";
              source = "webdl";
              resolution = 480;
              modifier = "none";
            };
            items = [ ];
            allowed = true;
          }
          {
            quality = {
              id = 12;
              name = "WEBRip-480p";
              source = "webrip";
              resolution = 480;
              modifier = "none";
            };
            items = [ ];
            allowed = true;
          }
        ];
        allowed = true;
        id = 1000;
      }
      {
        quality = {
          id = 20;
          name = "Bluray-480p";
          source = "bluray";
          resolution = 480;
          modifier = "none";
        };
        items = [ ];
        allowed = true;
      }
      {
        quality = {
          id = 21;
          name = "Bluray-576p";
          source = "bluray";
          resolution = 576;
          modifier = "none";
        };
        items = [ ];
        allowed = true;
      }
      {
        quality = {
          id = 4;
          name = "HDTV-720p";
          source = "tv";
          resolution = 720;
          modifier = "none";
        };
        items = [ ];
        allowed = true;
      }
      {
        name = "WEB 720p";
        items = [
          {
            quality = {
              id = 5;
              name = "WEBDL-720p";
              source = "webdl";
              resolution = 720;
              modifier = "none";
            };
            items = [ ];
            allowed = true;
          }
          {
            quality = {
              id = 14;
              name = "WEBRip-720p";
              source = "webrip";
              resolution = 720;
              modifier = "none";
            };
            items = [ ];
            allowed = true;
          }
        ];
        allowed = true;
        id = 1001;
      }
      {
        quality = {
          id = 6;
          name = "Bluray-720p";
          source = "bluray";
          resolution = 720;
          modifier = "none";
        };
        items = [ ];
        allowed = true;
      }
      {
        quality = {
          id = 9;
          name = "HDTV-1080p";
          source = "tv";
          resolution = 1080;
          modifier = "none";
        };
        items = [ ];
        allowed = true;
      }
      {
        name = "WEB 1080p";
        items = [
          {
            quality = {
              id = 3;
              name = "WEBDL-1080p";
              source = "webdl";
              resolution = 1080;
              modifier = "none";
            };
            items = [ ];
            allowed = true;
          }
          {
            quality = {
              id = 15;
              name = "WEBRip-1080p";
              source = "webrip";
              resolution = 1080;
              modifier = "none";
            };
            items = [ ];
            allowed = true;
          }
        ];
        allowed = true;
        id = 1002;
      }
      {
        quality = {
          id = 7;
          name = "Bluray-1080p";
          source = "bluray";
          resolution = 1080;
          modifier = "none";
        };
        items = [ ];
        allowed = true;
      }
      {
        quality = {
          id = 30;
          name = "Remux-1080p";
          source = "bluray";
          resolution = 1080;
          modifier = "remux";
        };
        items = [ ];
        allowed = true;
      }
      {
        quality = {
          id = 16;
          name = "HDTV-2160p";
          source = "tv";
          resolution = 2160;
          modifier = "none";
        };
        items = [ ];
        allowed = true;
      }
      {
        name = "WEB 2160p";
        items = [
          {
            quality = {
              id = 18;
              name = "WEBDL-2160p";
              source = "webdl";
              resolution = 2160;
              modifier = "none";
            };
            items = [ ];
            allowed = true;
          }
          {
            quality = {
              id = 17;
              name = "WEBRip-2160p";
              source = "webrip";
              resolution = 2160;
              modifier = "none";
            };
            items = [ ];
            allowed = true;
          }
        ];
        allowed = true;
        id = 1003;
      }
      {
        quality = {
          id = 19;
          name = "Bluray-2160p";
          source = "bluray";
          resolution = 2160;
          modifier = "none";
        };
        items = [ ];
        allowed = true;
      }
      {
        quality = {
          id = 31;
          name = "Remux-2160p";
          source = "bluray";
          resolution = 2160;
          modifier = "remux";
        };
        items = [ ];
        allowed = true;
      }
      {
        quality = {
          id = 22;
          name = "BR-DISK";
          source = "bluray";
          resolution = 1080;
          modifier = "brdisk";
        };
        items = [ ];
        allowed = true;
      }
      {
        quality = {
          id = 10;
          name = "Raw-HD";
          source = "tv";
          resolution = 1080;
          modifier = "rawhd";
        };
        items = [ ];
        allowed = false;
      }
    ];
  };
}

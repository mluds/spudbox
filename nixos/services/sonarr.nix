{ config, pkgs, secrets, ... }:

with config.my;

{
  users.groups.sonarr = {};

  users.users.sonarr = {
    isSystemUser = true;
    group = "sonarr";
    extraGroups = [ "media" ];
    createHome = false;
    useDefaultShell = false;
  };

  services.sonarr = {
    enable = true;
    user = "sonarr";
    openFirewall = false;
  };

  system.activationScripts.sonarrConfig = let
    xmlstarlet = "${pkgs.xmlstarlet}/bin/xmlstarlet";
    sqlite = "${pkgs.sqlite}/bin/sqlite3";
    cfgFile = "${config.services.sonarr.dataDir}/config.xml";
    dbFile = "${config.services.sonarr.dataDir}/sonarr.db";
  in ''
    if [ -f "${dbFile}" ]; then
      ${sqlite} "${dbFile}" "DELETE FROM \"Users\";"
    fi
    ${xmlstarlet} ed -L \
      --subnode '/Config[not(Authentication)]' -t elem -n Authentication \
      --subnode '/Config/Authentication[not(Username)]' -t elem -n Username \
      --subnode '/Config/Authentication[not(Password)]' -t elem -n Password \
      -u "/Config/AuthenticationMethod" -v "Forms" \
      -u "/Config/Authentication/Username" -v "${secrets.adminUsername}" \
      -u "/Config/Authentication/Password" -v "${secrets.adminPassword}" \
      -u "/Config/ApiKey" -v "${secrets.sonarrApiKey}" \
      "${cfgFile}"
    if ${config.systemd.package}/bin/systemctl -q is-active sonarr.service; then
      ${config.systemd.package}/bin/systemctl restart sonarr.service
    fi
  '';

  systemd.services.sonarr-post-config = {
    wantedBy = [ "multi-user.target" ];
    after = [ "sonarr.service" ];
    requires = [ "sonarr.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "sonarr";
      Group = "sonarr";
    };
    path = with pkgs; [ curl jq ];
    script = let
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
    in ''
      echo "Waiting for Sonarr to start..."
      while ! curl -sSf "http://localhost:${toString sonarrPort}/login" >/dev/null; do
        sleep 2
      done

      echo "Adding root folder..."
      curl -X POST "http://localhost:${toString sonarrPort}/api/v3/rootfolder" \
        -H "X-Api-Key: ${secrets.sonarrApiKey}" \
        -H "Content-Type: application/json" \
        -d '{"name": "TV", "path": "${storageDir}/data/media/tv"}' \
        --fail --silent --show-error || echo "Root folder may already exist"

      echo "Configuring NZBGeek..."
      curl -X POST "http://localhost:${toString sonarrPort}/api/v3/indexer" \
        -H "X-Api-Key: ${secrets.sonarrApiKey}" \
        -H "Content-Type: application/json" \
        -d '{
          "name": "NZBGeek",
          "implementationName": "Newznab",
          "implementation": "Newznab",
          "configContract": "NewznabSettings",
          "enable": true,
          "protocol": "usenet",
          "enableRss": true,
          "enableAutomaticSearch": true,
          "enableInteractiveSearch": true,
          "supportsRss": true,
          "supportsSearch": true,
          "fields": [
            {"name": "baseUrl", "value": "https://api.nzbgeek.info/"},
            {"name": "apiPath", "value": "/api"},
            {"name": "apiKey", "value": "${secrets.nzbgeekApiKey}"},
            {"name": "categories", "value": [5020, 5030, 5040, 5045]},
            {"name": "animeCategories", "value": [5070]},
            {"name": "animeStandardFormatSearch", "value": true}
          ]
        }' \
        --fail --silent --show-error || echo "NZBGeek may already be configured"

      echo "Configuring SABnzbd..."
      curl -X POST "http://localhost:${toString sonarrPort}/api/v3/downloadclient" \
        -H "X-Api-Key: ${secrets.sonarrApiKey}" \
        -H "Content-Type: application/json" \
        -d '{
          "name": "SABnzbd",
          "enable": true,
          "protocol": "usenet",
          "implementation": "Sabnzbd",
          "configContract": "SabnzbdSettings",
          "fields": [
            {"name": "host", "value": "localhost"},
            {"name": "port", "value": ${toString sabnzbdPort}},
            {"name": "apiKey", "value": "${secrets.sabnzbdApiKey}"},
            {"name": "category", "value": "tv"}
          ]
        }' \
        --fail --silent --show-error || echo "SABnzbd may already be configured"

      echo "Updating quality profiles..."
      qualityDefs=$(curl -sS "http://localhost:${toString sonarrPort}/api/v3/qualitydefinition" \
        -H "X-Api-Key: ${secrets.sonarrApiKey}")

      echo '${builtins.toJSON qualitySettings}' > /tmp/quality_settings.json

      echo "$qualityDefs" | jq --argjson settings "$(cat /tmp/quality_settings.json)" '
        map(
          . as $def |
          ($def.quality.name) as $name |
          if $settings | has($name) then
            $def * {
              minSize: $settings[$name].minSize,
              maxSize: $settings[$name].maxSize,
              preferredSize: $settings[$name].preferredSize
            }
          else
            $def
          end
        )
      ' | jq -c '.[]' | while read def; do
        id=$(jq -r '.id' <<< "$def")
        echo "Updating $id..."
        curl -X PUT "http://localhost:${toString sonarrPort}/api/v3/qualitydefinition/$id" \
          -H "X-Api-Key: ${secrets.sonarrApiKey}" \
          -H "Content-Type: application/json" \
          -d "$def" \
          --fail --silent --show-error || echo "Failed to update $id"
      done
      rm -f /tmp/quality_settings.json

      echo "Applying quality profile..."
      curl -X PUT "http://localhost:${toString sonarrPort}/api/v3/qualityprofile/1" \
        -H "X-Api-Key: ${secrets.sonarrApiKey}" \
        -H "Content-Type: application/json" \
        -d '${builtins.toJSON qualityProfile}' \
        --fail --silent --show-error
    '';
  };
}

{
  config,
  pkgs,
  lib,
  helpers,
  ...
}:

let
  cfg = config.spudbox;
  inherit (cfg)
    secretsDir
    storageDir
    domain
    plexPort
    radarrPort
    sonarrPort
    jellyseerrPort
    ;

  settingsFile = "/var/lib/jellyseerr/config/settings.json";

  json = value: lib.escapeShellArg (builtins.toJSON value);

  plexSettings = {
    ip = "127.0.0.1";
    port = plexPort;
    useSsl = false;
    # Periodic full scan catches movies that were unmatched when first added
    # to Plex (race between add and metadata match).
    periodicScanning = 21600;
  };

  # apiKey filled in from radarr/sonarr secrets at runtime.
  radarr = {
    name = "Radarr";
    hostname = "localhost";
    port = radarrPort;
    useSsl = false;
    externalUrl = "https://radarr.${domain}";
    activeProfileId = 1;
    activeProfileName = "Any";
    activeDirectory = "${storageDir}/data/media/movies";
    is4k = false;
    minimumAvailability = "released";
    tags = [ ];
    isDefault = true;
    syncEnabled = true;
    preventSearch = false;
    tagRequests = false;
  };
  sonarr = {
    name = "Sonarr";
    hostname = "localhost";
    port = sonarrPort;
    useSsl = false;
    externalUrl = "https://sonarr.${domain}";
    baseUrl = "";
    activeProfileId = 1;
    activeProfileName = "Any";
    activeDirectory = "${storageDir}/data/media/tv";
    tags = [ ];
    animeTags = [ ];
    is4k = false;
    isDefault = true;
    enableSeasonFolders = false;
    syncEnabled = true;
    preventSearch = false;
    tagRequests = false;
  };

  configScript = pkgs.writeShellApplication {
    name = "jellyseerr-config";
    runtimeInputs = with pkgs; [
      curl
      jq
      helpers
    ];
    text = ''
      umask 077
      BASE="http://localhost:${toString jellyseerrPort}/api/v1"
      # Secrets reach curl and jq through files, never as arguments, which any
      # local user could read from /proc/<pid>/cmdline.
      TMP=$(mktemp -d)
      trap 'rm -rf "$TMP"' EXIT

      # api METHOD PATH [curl args...]: authenticated with the API key, or
      # with the session cookie before setup has created a key.
      api() {
        local method=$1 path=$2
        shift 2
        curl -s -X "$method" "$BASE/$path" -H 'Content-Type: application/json' \
          -H @"$TMP/key" -b "$TMP/cookies" "$@"
      }
      touch "$TMP/key" "$TMP/cookies"

      echo "Waiting for Jellyseerr to start..."
      wait-for-http "$BASE/settings/public"

      # First run: sign in with the Plex token (which creates the API key),
      # finish the setup wizard and add Radarr and Sonarr.
      FRESH=false
      if [ "$(api GET settings/public | jq -r '.initialized')" != true ]; then
        FRESH=true
        echo "Authenticating with Plex..."
        jq -n --rawfile token ${secretsDir}/plex/token '{authToken: ($token | rtrimstr("\n"))}' \
          | api POST auth/plex -c "$TMP/cookies" -d @- >/dev/null

        echo "Marking setup as complete..."
        api POST settings/initialize >/dev/null

        # add_arr BODY APP: POST BODY with its apiKey set to APP's secret.
        add_arr() {
          jq -n --argjson body "$1" --rawfile key "${secretsDir}/$2/api-key" \
            '$body + {apiKey: ($key | rtrimstr("\n"))}' \
            | api POST "settings/$2" -d @- >/dev/null
        }
        echo "Adding Radarr..."
        add_arr ${json radarr} radarr
        echo "Adding Sonarr..."
        add_arr ${json sonarr} sonarr
      fi

      printf 'X-Api-Key: %s\n' "$(jq -r '.main.apiKey' ${settingsFile})" > "$TMP/key"
      echo "Exporting API key..."
      mkdir -p ${secretsDir}/jellyseerr
      jq -r '.main.apiKey' ${settingsFile} > ${secretsDir}/jellyseerr/api-key

      echo "Configuring Plex settings..."
      api POST settings/plex -d ${json plexSettings} >/dev/null
      # Enable all libraries for scanning
      LIB_IDS=$(api GET "settings/plex/library?sync=true" | jq -r '[.[].id] | join(",")')
      api GET "settings/plex/library?sync=true&enable=$LIB_IDS" >/dev/null
      # Run recently added scan once daily instead of every 5 minutes
      # to avoid waking the HDD with constant Plex API queries
      api POST settings/jobs/plex-recently-added-scan/schedule \
        -d '{"schedule": "0 0 6 * * *"}' >/dev/null

      ${lib.optionalString cfg.pushover.enable ''
        echo "Configuring Pushover notifications..."
        jq -n --rawfile token ${secretsDir}/pushover/app-token \
          --rawfile user ${secretsDir}/pushover/user-key \
          '{enabled: true, types: 24, options: {
            accessToken: ($token | rtrimstr("\n")),
            userToken: ($user | rtrimstr("\n")),
            sound: "pushover"
          }}' \
          | api POST settings/notifications/pushover -d @- >/dev/null
      ''}
      if [ "$FRESH" = true ]; then
        echo "Restarting Jellyseerr..."
        systemctl restart seerr
      fi
      echo "Jellyseerr configured."
    '';
  };
in
{
  users.groups.jellyseerr = { };
  users.users.jellyseerr = {
    isSystemUser = true;
    group = "jellyseerr";
    extraGroups = [ "media" ];
    createHome = false;
    useDefaultShell = false;
  };

  services.seerr = {
    enable = true;
    openFirewall = false;
    # The pre-26.05 location on every install (upstream moves it to
    # /var/lib/seerr for stateVersion >= 26.05), so scripts and tests have one path.
    configDir = "/var/lib/jellyseerr/config";
  };

  systemd.services.seerr = {
    # Loopback only; reached through Caddy.
    environment.HOST = "127.0.0.1";
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "jellyseerr";
      Group = "jellyseerr";
      StateDirectory = lib.mkForce "jellyseerr";
      # settings.json holds the Plex token and API keys
      StateDirectoryMode = "0700";
      # On top of the module's ProtectSystem=strict etc. Node's JIT rules
      # out MemoryDenyWriteExecute.
      CapabilityBoundingSet = "";
      ProtectProc = "invisible";
      RestrictNamespaces = true;
      LockPersonality = true;
      SystemCallArchitectures = "native";
      RestrictAddressFamilies = [
        "AF_UNIX"
        "AF_INET"
        "AF_INET6"
        "AF_NETLINK" # getifaddrs (Node's os.networkInterfaces)
      ];
    };
  };

  systemd.services.jellyseerr-config = {
    description = "Configure Jellyseerr";
    after = [
      "seerr.service"
      "plex-config.service"
      "radarr-config.service"
      "sonarr-config.service"
    ];
    wants = [ "seerr.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig.ExecStart = lib.getExe configScript;
  };
}

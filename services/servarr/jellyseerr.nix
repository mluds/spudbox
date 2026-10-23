{
  config,
  pkgs,
  lib,
  helpers,
  ...
}:

let
  inherit (config.my)
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

      # Rewrite settings.json through a jq filter (extra jq args first).
      edit_settings() {
        jq "$@" ${settingsFile} > ${settingsFile}.tmp
        mv ${settingsFile}.tmp ${settingsFile}
        chown jellyseerr:jellyseerr ${settingsFile}
      }

      echo "Waiting for Jellyseerr to start..."
      wait-for-http "$BASE/settings/public"

      use_api_key() {
        printf 'X-Api-Key: %s\n' "$(jq -r '.main.apiKey' ${settingsFile})" > "$TMP/key"
      }

      export_api_key() {
        echo "Exporting API key..."
        mkdir -p ${secretsDir}/jellyseerr
        jq -r '.main.apiKey' ${settingsFile} > ${secretsDir}/jellyseerr/api-key
      }

      # Email notifications were replaced by Pushover; an earlier version
      # stored a Gmail app password here. Blank it, then restart so seerr
      # doesn't write its in-memory copy back.
      clear_email() {
        if [ -n "$(jq -r '.notifications.agents.email.options.authPass // empty' ${settingsFile})" ]; then
          echo "Removing the old email credentials..."
          edit_settings '.notifications.agents.email.enabled = false
            | .notifications.agents.email.options |= (.authUser = "" | .authPass = "" | .emailFrom = "")'
          systemctl restart seerr
        fi
      }

      configure_pushover() {
        echo "Configuring Pushover notifications..."
        jq -n --rawfile token ${secretsDir}/pushover/app-token \
          --rawfile user ${secretsDir}/pushover/user-key \
          '{enabled: true, types: 24, options: {
            accessToken: ($token | rtrimstr("\n")),
            userToken: ($user | rtrimstr("\n")),
            sound: "pushover"
          }}' \
          | api POST settings/notifications/pushover -d @- >/dev/null
      }

      configure_plex() {
        echo "Configuring Plex settings..."
        api POST settings/plex -d ${json plexSettings} >/dev/null

        # Enable all libraries for scanning
        LIB_IDS=$(api GET settings/plex/library | jq -r '[.[].id] | join(",")')
        api GET "settings/plex/library?sync=true&enable=$LIB_IDS" >/dev/null

        # Run recently added scan once daily instead of every 5 minutes
        # to avoid waking the HDD with constant Plex API queries
        api POST settings/jobs/plex-recently-added-scan/schedule \
          -d '{"schedule": "0 0 6 * * *"}' >/dev/null
      }

      set_external_urls() {
        echo "Setting external URLs for Radarr/Sonarr..."
        # shellcheck disable=SC2016 # jq program, not shell
        edit_settings \
          '.radarr = [.radarr[] | .externalUrl = ${builtins.toJSON radarr.externalUrl}]
          | .sonarr = [.sonarr[] | .externalUrl = ${builtins.toJSON sonarr.externalUrl}]'
      }

      # add_arr BODY SECRET PATH: POST BODY with its apiKey set to the secret.
      add_arr() {
        jq -n --argjson body "$1" --rawfile key "${secretsDir}/$2" \
          '$body + {apiKey: ($key | rtrimstr("\n"))}' \
          | api POST "$3" -d @- >/dev/null
      }

      if [ "$(api GET settings/public | jq -r '.initialized')" = true ]; then
        echo "Jellyseerr already initialized, skipping setup."
        use_api_key
        export_api_key
        configure_plex
        configure_pushover
        set_external_urls
        clear_email
        exit 0
      fi

      echo "Authenticating with Plex..."
      jq -n --rawfile token ${secretsDir}/plex/token '{authToken: ($token | rtrimstr("\n"))}' \
        | api POST auth/plex -c "$TMP/cookies" -d @- >/dev/null

      echo "Marking setup as complete..."
      api POST settings/initialize >/dev/null

      echo "Configuring Plex server..."
      api POST settings/plex -d ${json plexSettings} >/dev/null

      echo "Syncing Plex libraries..."
      api GET "settings/plex/library?sync=true" >/dev/null

      echo "Adding Radarr..."
      add_arr ${json radarr} radarr/api-key settings/radarr

      echo "Adding Sonarr..."
      add_arr ${json sonarr} sonarr/api-key settings/sonarr

      use_api_key
      export_api_key
      configure_plex
      configure_pushover

      echo "Restarting Jellyseerr..."
      systemctl restart seerr

      echo "Jellyseerr setup complete."
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
  };

  systemd.services.seerr = {
    # Loopback only; reached through Caddy.
    environment.HOST = "127.0.0.1";
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "jellyseerr";
      Group = "jellyseerr";
      StateDirectory = "jellyseerr";
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

    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = lib.getExe configScript;
    };
  };
}

{
  config,
  lib,
  pkgs,
  helpers,
  ...
}:

let
  inherit (config.my) secretsDir prowlarrPort;
  cfgFile = "/var/lib/prowlarr/config.xml";
  # The web login is set through the host-config API, as the UI does, and
  # Prowlarr stores a salted PBKDF2 hash. Unlike Sonarr/Radarr, Prowlarr
  # 2.x drops credentials put in config.xml without creating a user, and
  # inserting the row directly meant an unsalted SHA-256 hash. Secrets go
  # to curl and jq through files, never on a command line.
  configScript = pkgs.writeShellApplication {
    name = "prowlarr-config";
    runtimeInputs = with pkgs; [
      curl
      jq
      xmlstarlet
      helpers
    ];
    text = ''
      umask 077
      TMP=$(mktemp -d)
      trap 'rm -rf "$TMP"' EXIT
      API="http://localhost:${toString prowlarrPort}/api/v1"

      echo "Waiting for Prowlarr to start..."
      wait-for-http "http://localhost:${toString prowlarrPort}/ping"

      echo "Exporting Prowlarr API key..."
      mkdir -p ${secretsDir}/prowlarr
      xmlstarlet sel -t -v '/Config/ApiKey' ${cfgFile} > ${secretsDir}/prowlarr/api-key
      printf 'X-Api-Key: %s\n' "$(read-secret prowlarr/api-key)" > "$TMP/key"

      echo "Setting the web login..."
      curl -sS --fail -H @"$TMP/key" "$API/config/host" > "$TMP/host.json"
      jq --rawfile user ${secretsDir}/admin/username \
        --rawfile pass ${secretsDir}/prowlarr/password \
        '($pass | rtrimstr("\n")) as $pass
        | .authenticationMethod = "forms"
        | .username = ($user | rtrimstr("\n"))
        | .password = $pass
        | .passwordConfirmation = $pass' \
        "$TMP/host.json" > "$TMP/new.json"
      curl -sS --fail -X PUT -H @"$TMP/key" -H 'Content-Type: application/json' \
        -d @"$TMP/new.json" "$API/config/host/$(jq '.id' "$TMP/host.json")" > /dev/null
    '';
  };
in
# Off by default (my.prowlarr.enable): Sonarr and Radarr query NZBGeek
# directly and nothing was configured in Prowlarr. Its state in
# /var/lib/private/prowlarr is kept; enabling it brings back the service, its
# Caddy site, homepage tile, backup stop and test.sh checks.
lib.mkIf config.my.prowlarr.enable {
  environment.etc."spudbox/env".text = "PROWLARR_ENABLED=1";

  services.prowlarr = {
    enable = true;
    openFirewall = false;
    # Loopback only; reached through Caddy (env var overrides config.xml).
    settings.server.bindaddress = "127.0.0.1";
  };

  systemd.services.prowlarr-config = {
    description = "Configure Prowlarr";
    after = [ "prowlarr.service" ];
    wants = [ "prowlarr.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = "root";
      Type = "oneshot";
      ExecStart = lib.getExe configScript;
    };
  };
}

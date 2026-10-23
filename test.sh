#!/usr/bin/env bash
set -euo pipefail

# ─── Configuration ──────────────────────────────────────────────
# Dirs, domain, every *_PORT, REVISION, and the CADDY_HOSTS, PASSWORD_SERVICES
# and ALERT_UNITS lists, generated from the Nix config (common/env.nix and the
# modules that append to it). SPUDBOX_ENV overrides the path.
# shellcheck source=/dev/null
source "${SPUDBOX_ENV:-/etc/spudbox/env}"

# ─── Counters & Helpers ────────────────────────────────────────
PASS_COUNT=0
FAIL_COUNT=0

pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf "  \033[32mPASS\033[0m  %s\n" "$1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf "  \033[31mFAIL\033[0m  %s\n" "$1"; }
section() { printf "\n\033[1m── %s ──\033[0m\n" "$1"; }

# check LABEL CMD...: pass if CMD succeeds
check() {
  local label=$1
  shift
  if "$@" >/dev/null 2>&1; then pass "$label"; else fail "$label"; fi
}

# check_eq LABEL ACTUAL EXPECTED
check_eq() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (got '$2', expected '$3')"; fi
}

# Prowlarr is off unless my.prowlarr.enable (services/servarr/prowlarr.nix)
prowlarr_on() { [ "${PROWLARR_ENABLED:-0}" = 1 ]; }

read_secret() { sudo cat "$SECRETS_DIR/$1" 2>/dev/null | tr -d '\n'; }

# Secrets reach curl and grep through files in this private dir, never as
# arguments, which any local user could read from /proc/<pid>/cmdline.
AUTH=$(umask 077 && mktemp -d)
trap 'rm -rf "$AUTH"' EXIT
# auth_file NAME FORMAT SECRET...: write FORMAT filled with the secrets to $AUTH/NAME
auth_file() {
  local name=$1 format=$2 values=()
  shift 2
  for s in "$@"; do values+=("$(read_secret "$s")"); done
  # shellcheck disable=SC2059 # FORMAT is ours
  printf "$format" "${values[@]}" > "$AUTH/$name"
}
auth_file radarr 'X-Api-Key: %s\n' radarr/api-key
auth_file sonarr 'X-Api-Key: %s\n' sonarr/api-key
if prowlarr_on; then auth_file prowlarr 'X-Api-Key: %s\n' prowlarr/api-key; fi
auth_file bazarr 'X-API-KEY: %s\n' bazarr/api-key
auth_file jellyseerr 'X-Api-Key: %s\n' jellyseerr/api-key
auth_file abs 'Authorization: Bearer %s\n' audiobookshelf/apikey
auth_file plex 'X-Plex-Token: %s\n' plex/token
auth_file tautulli 'apikey=%s' tautulli/api-key
auth_file sabnzbd 'apikey=%s' sabnzbd/api-key
auth_file transmission 'user = "%s:%s"\n' admin/username transmission/password
auth_file cloudflare '%s\n' cloudflare/api-token

http_code() {
  local url="$1"; shift
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$@" "$url" 2>/dev/null) || true
  echo "${code:-000}"
}

http_get() {
  local url="$1"; shift
  curl -s --max-time 5 "$@" "$url" 2>/dev/null || true
}

# App APIs, authenticated from $AUTH. APP PATH [curl args...]
radarr() { http_get "http://localhost:$RADARR_PORT/api/v3/$1" -H @"$AUTH/radarr" "${@:2}"; }
sonarr() { http_get "http://localhost:$SONARR_PORT/api/v3/$1" -H @"$AUTH/sonarr" "${@:2}"; }
bazarr() { http_get "http://localhost:$BAZARR_PORT/api/$1" -H @"$AUTH/bazarr" "${@:2}"; }
seerr() { http_get "http://localhost:$JELLYSEERR_PORT/api/v1/$1" -H @"$AUTH/jellyseerr" "${@:2}"; }
abs() { http_get "http://localhost:$AUDIOBOOKSHELF_PORT/api/$1" -H @"$AUTH/abs" "${@:2}"; }
plex() { http_get "http://localhost:$PLEX_PORT/$1" -H @"$AUTH/plex" "${@:2}"; }
# The key goes in the POST body: QUERY is e.g. "mode=queue&output=json"
sabnzbd() { http_get "http://localhost:$SABNZBD_PORT/api" -d @"$AUTH/sabnzbd" -d "$1"; }
tautulli() { http_get "http://localhost:$TAUTULLI_PORT/api/v2" -d @"$AUTH/tautulli" -d "cmd=$1"; }

# check_json LABEL FILTER CMD...: pass if jq FILTER is truthy on CMD's output
check_json() {
  local label=$1 filter=$2
  shift 2
  if "$@" | jq -e "$filter" >/dev/null 2>&1; then pass "$label"; else fail "$label"; fi
}

check_secret() { check "$1" sudo test -s "$SECRETS_DIR/$1"; }
check_service() { check "$1" systemctl is-active --quiet "$1"; }
check_oneshot() { check "$1" not systemctl is-failed --quiet "$1"; }
not() { ! "$@"; }
# no_match PATTERN_FILE [FILE]: grep found none of the patterns (and no error)
no_match() {
  local rc=0
  grep -qFf "$@" || rc=$?
  [ "$rc" -eq 1 ]
}

check_port() {
  local port="$1" proto="$2" label="$3"
  check "$label :${port}/${proto}" grep -q ":${port} " <<< "$(ss -"${proto}lnp")"
}

check_http() {
  local url="$1" expected="$2" label="$3"
  shift 3
  local code
  code=$(http_code "$url" "$@")
  if grep -qw "$code" <<< "$expected"; then
    pass "$label (HTTP $code)"
  else
    fail "$label (HTTP $code, expected $expected)"
  fi
}

# ─── Test Categories ───────────────────────────────────────────

test_secrets() {
  section "Secrets"

  local s
  # Deployed secrets
  for s in admin/username plex/username plex/password \
    cloudflare/api-token usenet/username usenet/password nzbgeek/api-key \
    opensubtitles/username opensubtitles/password assrt/api-token \
    audiobookshelf/token-secret \
    pushover/app-token pushover/user-key users/luds/hashed users/root/hashed \
    restic/password r2/s3-credentials.env; do
    check_secret "$s"
  done
  for s in "${PASSWORD_SERVICES[@]}"; do
    check_secret "$s/password"
  done

  # Runtime-generated secrets
  for s in plex/token radarr/api-key sonarr/api-key bazarr/api-key \
    sabnzbd/api-key sabnzbd/nzb-key tautulli/api-key \
    jellyseerr/api-key audiobookshelf/apikey; do
    check_secret "$s"
  done
  if prowlarr_on; then check_secret prowlarr/api-key; fi

  # Retired: the shared admin password (finding #5), the Gmail SMTP login
  for s in admin/password gmail; do
    check "retired secret $s removed" not sudo test -e "$SECRETS_DIR/$s"
  done
}

test_services() {
  section "Services"

  local u
  # Long-running services
  for u in plex tautulli sonarr radarr bazarr sabnzbd transmission \
    seerr audiobookshelf homepage-dashboard caddy homebridge drive-status-http; do
    check_service "$u.service"
  done
  if prowlarr_on; then check_service prowlarr.service; fi

  # Oneshots and timer jobs (services/notify.nix alerts on these)
  for u in "${ALERT_UNITS[@]}" media-fixup arr-rescan; do
    check_oneshot "$u.service"
  done
  # Setup oneshots stay active, so a switch doesn't re-run unchanged ones
  for u in "${SETUP_UNITS[@]}"; do
    check "$u stays active" systemctl is-active --quiet "$u.service"
  done

  # Timers
  for u in sabnzbd-resume radarr-auto-import restic-backups-local check-drive-status media-fixup arr-rescan; do
    check_service "$u.timer"
  done
}

test_ports() {
  section "Ports"

  check_port "$PLEX_PORT" t "plex"
  check_port "$TAUTULLI_PORT" t "tautulli"
  check_port "$SONARR_PORT" t "sonarr"
  check_port "$RADARR_PORT" t "radarr"
  check_port "$BAZARR_PORT" t "bazarr"
  if prowlarr_on; then check_port "$PROWLARR_PORT" t "prowlarr"; fi
  check_port "$SABNZBD_PORT" t "sabnzbd"
  check_port "$TRANSMISSION_PORT" t "transmission"
  check_port "$JELLYSEERR_PORT" t "jellyseerr"
  check_port "$AUDIOBOOKSHELF_PORT" t "audiobookshelf"
  check_port "$HOMEPAGE_PORT" t "homepage"
  check_port "$HOMEBRIDGE_PORT" t "homebridge"
  check_port 80 t "caddy-http"
  check_port 443 t "caddy-https"
  check_port "$CADDY_ADMIN_PORT" t "caddy-admin"
}

test_http() {
  section "HTTP Endpoints"

  check_http "http://localhost:$PLEX_PORT/identity" "200" "plex"
  check_http "http://localhost:$TAUTULLI_PORT" "200 302 303" "tautulli"
  check_http "http://localhost:$SONARR_PORT" "200 302" "sonarr"
  check_http "http://localhost:$RADARR_PORT" "200 302" "radarr"
  check_http "http://localhost:$BAZARR_PORT" "200 302" "bazarr"
  if prowlarr_on; then check_http "http://localhost:$PROWLARR_PORT" "200 302" "prowlarr"; fi
  check_http "http://localhost:$SABNZBD_PORT" "200 302 303" "sabnzbd"
  check_http "http://localhost:$TRANSMISSION_PORT" "401" "transmission"
  check_http "http://localhost:$JELLYSEERR_PORT/api/v1/settings/public" "200" "jellyseerr"
  check_http "http://localhost:$AUDIOBOOKSHELF_PORT/healthcheck" "200" "audiobookshelf"
  check_http "http://localhost:$HOMEPAGE_PORT" "200" "homepage"
  check_http "http://localhost:$HOMEBRIDGE_PORT/api/auth/settings" "200" "homebridge"
  check_http "http://localhost:$CADDY_ADMIN_PORT/config/" "200" "caddy-admin"
}

test_api_auth() {
  section "API Authentication"

  check_http "http://localhost:$RADARR_PORT/api/v3/system/status" "200" "radarr" -H @"$AUTH/radarr"
  check_http "http://localhost:$SONARR_PORT/api/v3/system/status" "200" "sonarr" -H @"$AUTH/sonarr"
  if prowlarr_on; then
    check_http "http://localhost:$PROWLARR_PORT/api/v1/system/status" "200" "prowlarr" -H @"$AUTH/prowlarr"
    fi
  check_http "http://localhost:$SABNZBD_PORT/api" "200" "sabnzbd" -d @"$AUTH/sabnzbd" -d "mode=version&output=json"
  check_http "http://localhost:$TAUTULLI_PORT/api/v2" "200" "tautulli" -d @"$AUTH/tautulli" -d "cmd=arnold"
  check_http "http://localhost:$BAZARR_PORT/api/system/status" "200" "bazarr" -H @"$AUTH/bazarr"
  check_http "http://localhost:$JELLYSEERR_PORT/api/v1/settings/main" "200" "jellyseerr" -H @"$AUTH/jellyseerr"
  check_http "http://localhost:$AUDIOBOOKSHELF_PORT/api/libraries" "200" "audiobookshelf" -H @"$AUTH/abs"
  check_http "http://localhost:$PLEX_PORT/identity" "200" "plex" -H @"$AUTH/plex"
  check_http "http://localhost:$TRANSMISSION_PORT/transmission/rpc" "409" "transmission" -K "$AUTH/transmission"

  # Without credentials every API refuses (catches auth being switched off).
  # Codes are each app's own: SABnzbd 403, Tautulli 400 "apikey is required".
  check_http "http://localhost:$RADARR_PORT/api/v3/system/status" "401" "radarr rejects anonymous"
  check_http "http://localhost:$SONARR_PORT/api/v3/system/status" "401" "sonarr rejects anonymous"
  check_http "http://localhost:$BAZARR_PORT/api/system/status" "401" "bazarr rejects anonymous"
  check_http "http://localhost:$SABNZBD_PORT/api?mode=queue&output=json" "403" "sabnzbd rejects anonymous"
  check_http "http://localhost:$TAUTULLI_PORT/api/v2?cmd=arnold" "400 401" "tautulli rejects anonymous"
  check_http "http://localhost:$JELLYSEERR_PORT/api/v1/settings/main" "401 403" "jellyseerr rejects anonymous"
  check_http "http://localhost:$AUDIOBOOKSHELF_PORT/api/libraries" "401" "audiobookshelf rejects anonymous"
  check_http "http://localhost:$PLEX_PORT/library/sections" "401" "plex rejects anonymous"
  check_http "http://localhost:$TRANSMISSION_PORT/transmission/rpc" "401" "transmission rejects anonymous"
  check_http "http://localhost:$HOMEBRIDGE_PORT/api/config-editor" "401" "homebridge rejects anonymous"

  # Same through Caddy, which is what LAN clients reach
  local svc path
  local routes=(radarr:/api/v3/system/status sonarr:/api/v3/system/status
    bazarr:/api/system/status "sabnzbd:/api?mode=queue&output=json" jellyseerr:/api/v1/settings/main
    audiobookshelf:/api/libraries plex:/library/sections transmission:/transmission/rpc
    homebridge:/api/config-editor)
  if prowlarr_on; then routes+=(prowlarr:/api/v1/system/status); fi
  for svc in "${routes[@]}"; do
    path=${svc#*:}
    svc=${svc%%:*}
    check_http "https://${svc}.${DOMAIN}${path}" "401 403" "${svc} via caddy rejects anonymous" \
      --resolve "${svc}.${DOMAIN}:443:127.0.0.1"
  done
}

test_integrations() {
  section "Integrations"

  local app category
  for app in radarr sonarr; do
    check_json "$app -> sabnzbd" 'any(.[]; .name | test("SABnzbd"))' "$app" downloadclient
    check_json "$app -> nzbgeek" 'any(.[]; .name | test("nzbgeek"; "i"))' "$app" indexer
    check_json "$app quality profiles" 'length > 0' "$app" qualityprofile
    check_json "$app download cleanup enabled" \
      '.[0].removeCompletedDownloads and .[0].removeFailedDownloads' "$app" downloadclient
  done
  # The disk rescan is weekly (arr-rescan.timer), not after each metadata refresh
  check_json "radarr rescans only on demand" '.rescanAfterRefresh == "afterManual"' radarr config/mediamanagement
  check_json "sonarr rescans only on demand" '.rescanAfterRefresh == "afterManual"' sonarr config/mediamanagement
  check_json "radarr root folder" '.[0].path | test("movies")' radarr rootfolder
  check_json "sonarr root folder" '.[0].path | test("tv")' sonarr rootfolder

  category=$(radarr downloadclient | jq -r '.[0].fields[] | select(.name == "movieCategory") | .value')
  check_eq "radarr sabnzbd category" "$category" movies
  category=$(sonarr downloadclient | jq -r '.[0].fields[] | select(.name == "tvCategory") | .value')
  check_eq "sonarr sabnzbd category" "$category" tv

  # Jellyseerr
  check_json "jellyseerr initialized (plex connected)" '.initialized' seerr settings/public
  check_json "jellyseerr -> radarr" '.[0].hostname == "localhost"' seerr settings/radarr
  check_json "jellyseerr -> sonarr" '.[0].hostname == "localhost"' seerr settings/sonarr
  check_json "jellyseerr radarr external url" ".[0].externalUrl | test(\"radarr.$DOMAIN\")" seerr settings/radarr
  check_json "jellyseerr sonarr external url" ".[0].externalUrl | test(\"sonarr.$DOMAIN\")" seerr settings/sonarr
  # Email disabled (replaced by pushover)
  check_json "jellyseerr email notifications disabled" '.enabled == false' seerr settings/notifications/email
  check_json "jellyseerr pushover notifications" '.enabled' seerr settings/notifications/pushover
  check_json "jellyseerr plex libraries enabled" '[.libraries[] | select(.enabled)] | length > 0' seerr settings/plex
  check_json "jellyseerr periodic plex scan" '.periodicScanning > 0' seerr settings/plex

  # Bazarr
  check_json "bazarr opensubtitles provider" '.general.enabled_providers | index("opensubtitlescom")' bazarr system/settings
  check_json "bazarr assrt provider" '.general.enabled_providers | index("assrt")' bazarr system/settings
  check_json "bazarr -> radarr/sonarr" '.data' bazarr system/health

  check_json "tautulli -> plex" '.response.result == "success"' tautulli get_server_info

  # Plex
  local sections prefs
  sections=$(plex library/sections)
  check "plex movies library" grep -q 'title="Movies"' <<< "$sections"
  check "plex tv library" grep -q 'title="TV Shows"' <<< "$sections"
  check "plex videos library" grep -q 'title="Videos"' <<< "$sections"
  prefs=$(plex :/prefs)
  # Reachability also needs the router's TCP 32400 forward
  check "plex remote access enabled" grep -q 'id="PublishServerOnPlexOnlineKey"[^>]*value="1"' <<< "$prefs"
  check "plex custom connections url" grep -q "customConnections.*plex\.$DOMAIN" <<< "$prefs"

  # Audiobookshelf
  local abs_lib
  abs_lib=$(abs libraries | jq -c '.libraries[0]')
  check_eq "audiobookshelf library name" "$(jq -r '.name' <<< "$abs_lib")" Audiobooks
  check_eq "audiobookshelf library path" "$(jq -r '.folders[0].fullPath' <<< "$abs_lib")" "$STORAGE_DIR/data/media/audiobooks"
}

test_storage() {
  section "Storage"

  check "$STORAGE_DIR mounted" mountpoint -q "$STORAGE_DIR"

  local dir
  for dir in "$STORAGE_DIR/data/media/movies" "$STORAGE_DIR/data/media/tv" \
    "$STORAGE_DIR/data/media/audiobooks" "$STORAGE_DIR/data/media/videos" \
    "$CACHE_DIR/data" "$CACHE_DIR/data/usenet/complete" "$CACHE_DIR/data/usenet/incomplete" \
    "$CACHE_DIR/data/torrents/complete" "$CACHE_DIR/data/torrents/incomplete" "$BACKUP_DIR"; do
    check "$dir exists" test -d "$dir"
  done

  check_eq "media dirs owned by media:media" \
    "$(stat -c "%U:%G" "$STORAGE_DIR/data/media/movies" 2>/dev/null)" media:media

  # Drive status (spindown monitor) served for homepage
  check_json "drive status JSON valid" '.device' http_get "http://localhost:$DRIVE_STATUS_PORT/status_sda.json"
}

test_downloads() {
  section "Downloads"

  local queue
  queue=$(sabnzbd "mode=queue&output=json")
  check_eq "sabnzbd queue active" "$(jq -r '.queue.paused' <<< "$queue")" false
  check_json "sabnzbd queue accessible" '.queue.status != null' echo "$queue"
  check_json "sabnzbd usenet server configured" '[.config.servers[] | select(.enable == 1)] | length > 0' \
    sabnzbd "mode=get_config&section=servers&output=json"
  check_json "sabnzbd categories (movies, tv)" '[.config.categories[].name] | index("movies") and index("tv")' \
    sabnzbd "mode=get_config&section=categories&output=json"

  # Transmission download-dir (needs a session id from a first request)
  local sid
  sid=$(curl -s --max-time 5 -K "$AUTH/transmission" "http://localhost:$TRANSMISSION_PORT/transmission/rpc" \
    | grep -oP 'X-Transmission-Session-Id: \K[^<]+' || true)
  check_eq "transmission download-dir" "$(http_get "http://localhost:$TRANSMISSION_PORT/transmission/rpc" \
    -K "$AUTH/transmission" -H "X-Transmission-Session-Id: $sid" \
    -d '{"method":"session-get","arguments":{"fields":["download-dir"]}}' \
    | jq -r '.arguments["download-dir"]')" "$STORAGE_DIR/data/media/videos"
}

test_caddy() {
  section "Caddy Routes"

  local svc code
  for svc in "${CADDY_HOSTS[@]}"; do
    code=$(http_code "https://${svc}.${DOMAIN}" --resolve "${svc}.${DOMAIN}:443:127.0.0.1")
    if [ "$code" != "502" ] && [ "$code" != "503" ] && [ "$code" != "000" ]; then
      pass "${svc}.${DOMAIN} (HTTP $code)"
    else
      fail "${svc}.${DOMAIN} (HTTP $code)"
    fi
  done
}

test_docker() {
  section "Docker"

  check "docker daemon running" sudo docker ps
  check "homebridge container running" grep -q homebridge <<< "$(sudo docker ps)"
  check "homebridge HAP port 51215" grep -q ":51215 " <<< "$(ss -tlnp)"
  # Avahi/mDNS for HomeKit discovery
  check "avahi-daemon running" systemctl is-active --quiet avahi-daemon
  check "mDNS port 5353" grep -q ":5353 " <<< "$(ss -ulnp)"
}

test_security() {
  section "Security"

  # Secrets root-only: nothing under the secrets dir owned by another user
  # or accessible to group/other
  check_eq "secrets root-only (700/600 root:root)" \
    "$(sudo find "$SECRETS_DIR" \( ! -user root -o ! -group root -o -perm /077 \) 2>/dev/null | wc -l)" 0
  check_eq "secrets dir 700 root:root" "$(sudo stat -c "%a %U:%G" "$SECRETS_DIR" 2>/dev/null)" "700 root:root"
  # Plaintext login passwords are recovery copies, never on the server
  check_eq "no plaintext login passwords on server" \
    "$(sudo find "$SECRETS_DIR/users" -name plaintext 2>/dev/null | wc -l)" 0
  # Backup credentials root-only
  check_eq "backup secrets root-only 600" \
    "$(sudo find "$SECRETS_DIR/restic" "$SECRETS_DIR/r2" -type f \( ! -user root -o -perm /077 \) 2>/dev/null | wc -l)" 0

  # Service state is private: a media-group daemon can't read files in other
  # services' state dirs (their configs hold tokens and passwords)
  local state_dirs="/var/lib/plex /var/lib/plexpy /var/lib/homebridge /var/lib/audiobookshelf /var/lib/jellyseerr /var/lib/transmission /var/lib/sabnzbd /var/lib/sonarr /var/lib/radarr /var/lib/bazarr"
  local u d readable
  for u in sabnzbd plex; do
    readable=$(for d in $state_dirs; do
      # find exits non-zero on "permission denied", which is the point
      [ "$d" = "/var/lib/$u" ] || sudo -u "$u" find "$d" -type f -readable 2>/dev/null || true
    done | wc -l)
    check_eq "$u can't read other services' state (readable files)" "$readable" 0
  done

  # Each web login has its own password (finding #5): none reused
  local dupes
  dupes=$(for u in "${PASSWORD_SERVICES[@]}"; do sudo sha256sum "$SECRETS_DIR/$u/password"; done \
    | awk '{print $1}' | sort | uniq -d | wc -l)
  check_eq "per-service web passwords (reused)" "$dupes" 0

  # Prowlarr stores a salted PBKDF2 hash (prowlarr-config sets it via the API)
  if prowlarr_on; then
    check_eq "prowlarr password hash salted (salted users)" \
      "$(sudo sqlite3 -readonly /var/lib/private/prowlarr/prowlarr.db \
        "select count(*) from Users where Salt is not null and Salt != '' and Iterations > 0;" 2>/dev/null || echo 0)" 1
  fi

  # Jellyseerr no longer keeps the old Gmail app password
  check_eq "jellyseerr stores no email password" \
    "$(sudo jq -r '.notifications.agents.email.options.authPass // ""' /var/lib/jellyseerr/config/settings.json 2>/dev/null)" ""

  # Homepage's Audiobookshelf key belongs to the read-only homepage user, not root
  check_eq "homepage audiobookshelf key user" "$(abs me | jq -r '.username + ":" + .type')" homepage:user

  # Sandboxing on services that handle untrusted input (services/hardening.nix)
  local unit
  for unit in bazarr sabnzbd audiobookshelf tautulli drive-status-http media-fixup plex seerr caddy; do
    check_eq "$unit sandboxed (NoNewPrivileges, ProtectProc)" \
      "$(systemctl show -p NoNewPrivileges -p ProtectProc --value "$unit" | xargs)" "yes invisible"
  done
  # ffmpeg on downloaded files: not root, and only CAP_CHOWN
  check_eq "media-fixup user" "$(systemctl show -p User --value media-fixup)" media-fixup
  check_eq "media-fixup capabilities" "$(systemctl show -p CapabilityBoundingSet --value media-fixup)" cap_chown

  # Jobs that don't need root run as dynamic users
  for unit in drive-status-http sabnzbd-resume radarr-auto-import; do
    check_eq "$unit runs as a dynamic user" "$(systemctl show -p DynamicUser --value "$unit")" yes
  done

  # Caddy can bind 80/443 and nothing else; Plex and seerr have no capabilities
  check_eq "caddy capabilities" "$(systemctl show -p CapabilityBoundingSet --value caddy)" cap_net_bind_service
  for unit in plex seerr; do
    check_eq "$unit has no capabilities" "$(systemctl show -p CapabilityBoundingSet --value "$unit")" ""
  done
  # Every Caddy site answers the LAN only
  check_eq "caddy sites LAN-only" \
    "$(grep -c 'not remote_ip private_ranges' /etc/caddy/caddy_config)" "${#CADDY_HOSTS[@]}"

  # The deployed commit is recorded (deploy.sh writes ~/deploy/.revision)
  check "deployed revision recorded ($REVISION)" test -n "$REVISION"

  # Legacy secrets file (admin password, WireGuard keys) is gone
  check "no legacy secrets/default.json on server" not sudo test -e "$SECRETS_DIR/default.json"

  # Homepage gets its keys via LoadCredential, not group access to secrets
  local hp_groups
  hp_groups=$(systemctl show -p Group -p SupplementaryGroups --value homepage-dashboard | tr '\n' ' ')
  check "homepage not in media/radarr groups ($hp_groups)" not grep -qwE 'media|radarr' <<< "$hp_groups"

  # Cloudflare token only in Caddy's environment: not in the generated config
  # or the admin API's, and the env file is root-only
  check "cloudflare token not in caddy config" no_match "$AUTH/cloudflare" /etc/caddy/caddy_config
  check "cloudflare token not in caddy admin api" \
    no_match "$AUTH/cloudflare" <<< "$(http_get "http://localhost:$CADDY_ADMIN_PORT/config/")"
  check_eq "caddy env file root-only" "$(sudo stat -c "%a %U:%G" /run/caddy-config/caddy.env 2>/dev/null)" "600 root:root"

  # SABnzbd: verifies usenet server certificates (3 = Strict); built-in
  # HTTPS off (Caddy terminates TLS); ini private
  check_json "sabnzbd usenet servers ssl_verify strict" 'all(.config.servers[]; .ssl_verify == 3)' \
    sabnzbd "mode=get_config&section=servers&output=json"
  check "sabnzbd https port 8090 closed" not grep -q ":8090 " <<< "$(ss -tln)"
  check_eq "sabnzbd.ini owner and mode" \
    "$(sudo stat -c "%U:%G %a" /var/lib/sabnzbd/sabnzbd.ini 2>/dev/null)" "sabnzbd:media 600"

  # Homebridge image pinned (not :latest)
  check "homebridge image pinned" grep -q '^homebridge/homebridge:[0-9-]*@sha256:' \
    <<< "$(sudo docker inspect homebridge --format '{{.Config.Image}}' 2>/dev/null)"

  # Homebridge UI not opened on the LAN (only reachable through Caddy)
  local fw_rules
  if fw_rules=$(sudo iptables -S nixos-fw 2>/dev/null && { sudo ip6tables -S nixos-fw 2>/dev/null || true; }); then
    check "homebridge ui port $HOMEBRIDGE_PORT closed in firewall" not grep -q -- "--dport $HOMEBRIDGE_PORT " <<< "$fw_rules"
  else
    fail "could not read nixos-fw firewall rules"
  fi

  # Everything behind Caddy, and Caddy's admin API, listen on loopback only
  local port exposed
  for port in "$HOMEPAGE_PORT" "$JELLYSEERR_PORT" "$BAZARR_PORT" "$RADARR_PORT" "$SABNZBD_PORT" \
    "$TAUTULLI_PORT" "$HOMEBRIDGE_PORT" "$SONARR_PORT" "$PROWLARR_PORT" "$CADDY_ADMIN_PORT"; do
    exposed=$(ss -tlnH "sport = :$port" | awk '{print $4}' | grep -vE '^(127\.0\.0\.1|\[::1\]):' || true)
    check_eq "port $port loopback-only (other listeners)" "$(tr '\n' ' ' <<< "$exposed" | xargs)" ""
  done

  # IPv6 disabled: sysctl set and no global IPv6 address on any interface
  check_eq "ipv6 disabled (disable_ipv6)" "$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null || echo 0)" 1
  check_eq "no global ipv6 addresses" "$(ip -6 -o addr show scope global 2>/dev/null | awk '{print $2": "$4}' | xargs)" ""

  # NetworkManager won't re-enable it: every active ethernet profile has
  # ipv6.method=disabled (set by hand, see "IPv6" in CLAUDE.md)
  local nm_auto
  nm_auto=$(nmcli -t -f UUID,TYPE con show --active 2>/dev/null | awk -F: '$2 == "802-3-ethernet" {print $1}' \
    | while read -r uuid; do [ "$(nmcli -g ipv6.method con show "$uuid")" = "disabled" ] || nmcli -g connection.id con show "$uuid"; done)
  check_eq "networkmanager ethernet profiles with ipv6 enabled" "$nm_auto" ""
}

test_backups() {
  section "Backups"

  # Latest snapshot in each repo is less than 48h old
  local repo latest age
  for repo in local r2; do
    latest=$(sudo "restic-$repo" snapshots --latest 1 --json 2>/dev/null | jq -r '.[-1].time // empty')
    if [ -z "$latest" ]; then
      fail "restic $repo: no snapshots"
      continue
    fi
    age=$(( ($(date +%s) - $(date -d "$latest" +%s)) / 3600 ))
    if [ "$age" -lt 48 ]; then
      pass "restic $repo latest snapshot ${age}h old"
    else
      fail "restic $repo latest snapshot ${age}h old (expected < 48h)"
    fi
  done

  check_oneshot "restic-backups-local.service"
  check_oneshot "restic-backups-r2.service"

  # A failed backup sends a Pushover alert (services/notify.nix)
  for repo in local r2; do
    check "restic $repo alerts on failure" grep -q notify-failure@ \
      <<< "$(systemctl show -p OnFailure --value "restic-backups-$repo.service")"
  done
}

# ─── Runner ────────────────────────────────────────────────────

CATEGORIES="secrets services ports http api_auth integrations downloads caddy docker storage security backups"

if [ $# -gt 0 ]; then
  CATEGORIES="$*"
fi

for cat in $CATEGORIES; do
  "test_$cat"
done

# ─── Summary ───────────────────────────────────────────────────
printf "\n\033[1m── Summary ──\033[0m\n"
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf "  \033[32m%d passed, 0 failed\033[0m\n" "$PASS_COUNT"
else
  printf "  \033[32m%d passed\033[0m, \033[31m%d failed\033[0m\n" "$PASS_COUNT" "$FAIL_COUNT"
fi

[ "$FAIL_COUNT" -eq 0 ]

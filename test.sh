#!/usr/bin/env bash
set -euo pipefail

# ─── Configuration ──────────────────────────────────────────────
SECRETS_DIR="/var/lib/secrets"
STORAGE_DIR="/mnt/storage"
CACHE_DIR="/mnt/cache"
BACKUP_DIR="/mnt/storage/backups"
DOMAIN="spudbox.online"

# ─── Counters & Helpers ────────────────────────────────────────
PASS_COUNT=0
FAIL_COUNT=0

pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf "  \033[32mPASS\033[0m  %s\n" "$1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf "  \033[31mFAIL\033[0m  %s\n" "$1"; }
section() { printf "\n\033[1m── %s ──\033[0m\n" "$1"; }

read_secret() { sudo cat "$SECRETS_DIR/$1" 2>/dev/null | tr -d '\n'; }

http_code() {
  local url="$1"; shift
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$@" "$url" 2>/dev/null) || true
  echo "${code:-000}"
}

http_get() {
  local url="$1"; shift
  curl -s --max-time 5 "$@" "$url" 2>/dev/null
}

check_secret() {
  local path="$1" label="$2"
  if sudo test -s "$SECRETS_DIR/$path"; then
    pass "$label"
  else
    fail "$label"
  fi
}

check_service() {
  local unit="$1"
  if systemctl is-active --quiet "$unit"; then
    pass "$unit"
  else
    fail "$unit"
  fi
}

check_oneshot() {
  local unit="$1"
  if systemctl is-failed --quiet "$unit"; then
    fail "$unit"
  else
    pass "$unit"
  fi
}

check_port() {
  local port="$1" proto="$2" label="$3"
  if ss -"${proto}lnp" | grep -q ":${port} "; then
    pass "$label :${port}/${proto}"
  else
    fail "$label :${port}/${proto}"
  fi
}

check_http() {
  local url="$1" expected="$2" label="$3"
  shift 3
  local code
  code=$(http_code "$url" "$@")
  if echo "$expected" | grep -qw "$code"; then
    pass "$label (HTTP $code)"
  else
    fail "$label (HTTP $code, expected $expected)"
  fi
}

# ─── Test Categories ───────────────────────────────────────────

test_secrets() {
  section "Secrets"

  # Deployed secrets
  check_secret "admin/username" "admin/username"
  check_secret "admin/password" "admin/password"
  check_secret "plex/username" "plex/username"
  check_secret "plex/password" "plex/password"
  check_secret "cloudflare/api-token" "cloudflare/api-token"
  check_secret "usenet/username" "usenet/username"
  check_secret "usenet/password" "usenet/password"
  check_secret "nzbgeek/api-key" "nzbgeek/api-key"
  check_secret "opensubtitles/username" "opensubtitles/username"
  check_secret "opensubtitles/password" "opensubtitles/password"
  check_secret "assrt/api-token" "assrt/api-token"
  check_secret "audiobookshelf/token-secret" "audiobookshelf/token-secret"
  check_secret "gmail/address" "gmail/address"
  check_secret "gmail/app-password" "gmail/app-password"
  check_secret "pushover/app-token" "pushover/app-token"
  check_secret "pushover/user-key" "pushover/user-key"
  check_secret "users/luds/hashed" "users/luds/hashed"
  check_secret "users/root/hashed" "users/root/hashed"
  check_secret "restic/password" "restic/password"
  check_secret "r2/s3-credentials.env" "r2/s3-credentials.env"

  # Runtime-generated secrets
  check_secret "plex/token" "plex/token"
  check_secret "radarr/api-key" "radarr/api-key"
  check_secret "sonarr/api-key" "sonarr/api-key"
  check_secret "bazarr/api-key" "bazarr/api-key"
  check_secret "prowlarr/api-key" "prowlarr/api-key"
  check_secret "sabnzbd/api-key" "sabnzbd/api-key"
  check_secret "sabnzbd/nzb-key" "sabnzbd/nzb-key"
  check_secret "tautulli/api-key" "tautulli/api-key"
  check_secret "jellyseerr/api-key" "jellyseerr/api-key"
  check_secret "audiobookshelf/apikey" "audiobookshelf/apikey"
}

test_services() {
  section "Services"

  # Long-running services
  check_service "plex.service"
  check_service "tautulli.service"
  check_service "sonarr.service"
  check_service "radarr.service"
  check_service "bazarr.service"
  check_service "prowlarr.service"
  check_service "sabnzbd.service"
  check_service "transmission.service"
  check_service "seerr.service"
  check_service "audiobookshelf.service"
  check_service "homepage-dashboard.service"
  check_service "caddy.service"
  check_service "homebridge.service"

  # Oneshot config services
  check_oneshot "plex-config.service"
  check_oneshot "tautulli-config.service"
  check_oneshot "radarr-config.service"
  check_oneshot "sonarr-config.service"
  check_oneshot "bazarr-config.service"
  check_oneshot "prowlarr-config.service"
  check_oneshot "jellyseerr-config.service"
  check_oneshot "sabnzbd-config.service"
  check_oneshot "audiobookshelf-config.service"
  check_oneshot "homebridge-config.service"
  check_oneshot "caddy-config.service"
  check_oneshot "create-dirs.service"

  # Timers
  check_service "sabnzbd-resume.timer"
  check_service "radarr-auto-import.timer"
  check_service "restic-backups-local.timer"
  check_service "check-drive-status.timer"
  check_service "drive-status-http.service"
}

test_ports() {
  section "Ports"

  check_port 32400 t "plex"
  check_port 8181 t "tautulli"
  check_port 8989 t "sonarr"
  check_port 7878 t "radarr"
  check_port 6767 t "bazarr"
  check_port 9696 t "prowlarr"
  check_port 8081 t "sabnzbd"
  check_port 9091 t "transmission"
  check_port 5055 t "jellyseerr"
  check_port 8000 t "audiobookshelf"
  check_port 3000 t "homepage"
  check_port 8581 t "homebridge"
  check_port 80 t "caddy-http"
  check_port 443 t "caddy-https"
  check_port 2019 t "caddy-admin"
}

test_http() {
  section "HTTP Endpoints"

  check_http "http://localhost:32400/identity" "200" "plex"
  check_http "http://localhost:8181" "200 302 303" "tautulli"
  check_http "http://localhost:8989" "200 302" "sonarr"
  check_http "http://localhost:7878" "200 302" "radarr"
  check_http "http://localhost:6767" "200 302" "bazarr"
  check_http "http://localhost:9696" "200 302" "prowlarr"
  check_http "http://localhost:8081" "200 302 303" "sabnzbd"
  check_http "http://localhost:9091" "401" "transmission"
  check_http "http://localhost:5055/api/v1/settings/public" "200" "jellyseerr"
  check_http "http://localhost:8000/healthcheck" "200" "audiobookshelf"
  check_http "http://localhost:3000" "200" "homepage"
  check_http "http://localhost:8581/api/auth/settings" "200" "homebridge"
  check_http "http://localhost:2019/config/" "200" "caddy-admin"
}

test_api_auth() {
  section "API Authentication"

  local RADARR_KEY SONARR_KEY PROWLARR_KEY SABNZBD_KEY TAUTULLI_KEY
  local BAZARR_KEY JELLYSEERR_KEY ABS_KEY PLEX_TOKEN
  local ADMIN_USER ADMIN_PASS

  RADARR_KEY=$(read_secret "radarr/api-key")
  SONARR_KEY=$(read_secret "sonarr/api-key")
  PROWLARR_KEY=$(read_secret "prowlarr/api-key")
  SABNZBD_KEY=$(read_secret "sabnzbd/api-key")
  TAUTULLI_KEY=$(read_secret "tautulli/api-key")
  BAZARR_KEY=$(read_secret "bazarr/api-key")
  JELLYSEERR_KEY=$(read_secret "jellyseerr/api-key")
  ABS_KEY=$(read_secret "audiobookshelf/apikey")
  PLEX_TOKEN=$(read_secret "plex/token")
  ADMIN_USER=$(read_secret "admin/username")
  ADMIN_PASS=$(read_secret "admin/password")

  check_http "http://localhost:7878/api/v3/system/status" "200" "radarr" \
    -H "X-Api-Key: $RADARR_KEY"

  check_http "http://localhost:8989/api/v3/system/status" "200" "sonarr" \
    -H "X-Api-Key: $SONARR_KEY"

  check_http "http://localhost:9696/api/v1/system/status" "200" "prowlarr" \
    -H "X-Api-Key: $PROWLARR_KEY"

  check_http "http://localhost:8081/api?mode=version&apikey=$SABNZBD_KEY&output=json" "200" "sabnzbd"

  check_http "http://localhost:8181/api/v2?apikey=$TAUTULLI_KEY&cmd=arnold" "200" "tautulli"

  check_http "http://localhost:6767/api/system/status" "200" "bazarr" \
    -H "X-API-KEY: $BAZARR_KEY"

  check_http "http://localhost:5055/api/v1/settings/main" "200" "jellyseerr" \
    -H "X-Api-Key: $JELLYSEERR_KEY"

  check_http "http://localhost:8000/api/libraries" "200" "audiobookshelf" \
    -H "Authorization: Bearer $ABS_KEY"

  check_http "http://localhost:32400/identity?X-Plex-Token=$PLEX_TOKEN" "200" "plex"

  check_http "http://localhost:9091/transmission/rpc" "409" "transmission" \
    -u "$ADMIN_USER:$ADMIN_PASS"
}

test_integrations() {
  section "Integrations"

  local RADARR_KEY SONARR_KEY JELLYSEERR_KEY TAUTULLI_KEY

  RADARR_KEY=$(read_secret "radarr/api-key")
  SONARR_KEY=$(read_secret "sonarr/api-key")
  JELLYSEERR_KEY=$(read_secret "jellyseerr/api-key")
  TAUTULLI_KEY=$(read_secret "tautulli/api-key")

  # Radarr integrations
  if http_get "http://localhost:7878/api/v3/downloadclient" -H "X-Api-Key: $RADARR_KEY" | jq -e '.[].name' | grep -q "SABnzbd"; then
    pass "radarr -> sabnzbd"
  else
    fail "radarr -> sabnzbd"
  fi

  if http_get "http://localhost:7878/api/v3/indexer" -H "X-Api-Key: $RADARR_KEY" | jq -e '.[].name' | grep -qi "NZBgeek"; then
    pass "radarr -> nzbgeek"
  else
    fail "radarr -> nzbgeek"
  fi

  if http_get "http://localhost:7878/api/v3/rootfolder" -H "X-Api-Key: $RADARR_KEY" | jq -e '.[0].path' | grep -q "movies"; then
    pass "radarr root folder"
  else
    fail "radarr root folder"
  fi

  # Sonarr integrations
  if http_get "http://localhost:8989/api/v3/downloadclient" -H "X-Api-Key: $SONARR_KEY" | jq -e '.[].name' | grep -q "SABnzbd"; then
    pass "sonarr -> sabnzbd"
  else
    fail "sonarr -> sabnzbd"
  fi

  if http_get "http://localhost:8989/api/v3/indexer" -H "X-Api-Key: $SONARR_KEY" | jq -e '.[].name' | grep -qi "NZBgeek"; then
    pass "sonarr -> nzbgeek"
  else
    fail "sonarr -> nzbgeek"
  fi

  if http_get "http://localhost:8989/api/v3/rootfolder" -H "X-Api-Key: $SONARR_KEY" | jq -e '.[0].path' | grep -q "tv"; then
    pass "sonarr root folder"
  else
    fail "sonarr root folder"
  fi

  # Jellyseerr integrations
  if http_get "http://localhost:5055/api/v1/settings/public" | jq -e '.initialized' | grep -q "true"; then
    pass "jellyseerr initialized (plex connected)"
  else
    fail "jellyseerr initialized (plex connected)"
  fi

  if http_get "http://localhost:5055/api/v1/settings/radarr" -H "X-Api-Key: $JELLYSEERR_KEY" | jq -e '.[0].hostname' | grep -q "localhost"; then
    pass "jellyseerr -> radarr"
  else
    fail "jellyseerr -> radarr"
  fi

  if http_get "http://localhost:5055/api/v1/settings/sonarr" -H "X-Api-Key: $JELLYSEERR_KEY" | jq -e '.[0].hostname' | grep -q "localhost"; then
    pass "jellyseerr -> sonarr"
  else
    fail "jellyseerr -> sonarr"
  fi

  if http_get "http://localhost:5055/api/v1/settings/radarr" -H "X-Api-Key: $JELLYSEERR_KEY" | jq -e '.[0].externalUrl' | grep -q "radarr.$DOMAIN"; then
    pass "jellyseerr radarr external url"
  else
    fail "jellyseerr radarr external url"
  fi

  if http_get "http://localhost:5055/api/v1/settings/sonarr" -H "X-Api-Key: $JELLYSEERR_KEY" | jq -e '.[0].externalUrl' | grep -q "sonarr.$DOMAIN"; then
    pass "jellyseerr sonarr external url"
  else
    fail "jellyseerr sonarr external url"
  fi

  # Radarr download cleanup flags
  local radarr_client
  radarr_client=$(http_get "http://localhost:7878/api/v3/downloadclient" -H "X-Api-Key: $RADARR_KEY")
  local radarr_rm_completed radarr_rm_failed radarr_category
  radarr_rm_completed=$(echo "$radarr_client" | jq '.[0].removeCompletedDownloads')
  radarr_rm_failed=$(echo "$radarr_client" | jq '.[0].removeFailedDownloads')
  if [ "$radarr_rm_completed" = "true" ] && [ "$radarr_rm_failed" = "true" ]; then
    pass "radarr download cleanup enabled"
  else
    fail "radarr download cleanup (completed=$radarr_rm_completed, failed=$radarr_rm_failed)"
  fi

  # Radarr SABnzbd category
  radarr_category=$(echo "$radarr_client" | jq -r '.[0].fields[] | select(.name == "movieCategory") | .value')
  if [ "$radarr_category" = "movies" ]; then
    pass "radarr sabnzbd category = movies"
  else
    fail "radarr sabnzbd category = $radarr_category (expected movies)"
  fi

  # Sonarr download cleanup flags
  local sonarr_client
  sonarr_client=$(http_get "http://localhost:8989/api/v3/downloadclient" -H "X-Api-Key: $SONARR_KEY")
  local sonarr_rm_completed sonarr_rm_failed sonarr_category
  sonarr_rm_completed=$(echo "$sonarr_client" | jq '.[0].removeCompletedDownloads')
  sonarr_rm_failed=$(echo "$sonarr_client" | jq '.[0].removeFailedDownloads')
  if [ "$sonarr_rm_completed" = "true" ] && [ "$sonarr_rm_failed" = "true" ]; then
    pass "sonarr download cleanup enabled"
  else
    fail "sonarr download cleanup (completed=$sonarr_rm_completed, failed=$sonarr_rm_failed)"
  fi

  # Sonarr SABnzbd category
  sonarr_category=$(echo "$sonarr_client" | jq -r '.[0].fields[] | select(.name == "tvCategory") | .value')
  if [ "$sonarr_category" = "tv" ]; then
    pass "sonarr sabnzbd category = tv"
  else
    fail "sonarr sabnzbd category = $sonarr_category (expected tv)"
  fi

  # Bazarr subtitle providers
  local BAZARR_KEY
  BAZARR_KEY=$(read_secret "bazarr/api-key")
  local bazarr_providers
  bazarr_providers=$(http_get "http://localhost:6767/api/system/settings" -H "X-API-KEY: $BAZARR_KEY" | jq -r '.general.enabled_providers // empty' 2>/dev/null)
  if echo "$bazarr_providers" | grep -q "opensubtitlescom"; then
    pass "bazarr opensubtitles provider"
  else
    fail "bazarr opensubtitles provider not enabled"
  fi
  if echo "$bazarr_providers" | grep -q "assrt"; then
    pass "bazarr assrt provider"
  else
    fail "bazarr assrt provider not enabled"
  fi

  # Tautulli -> Plex
  if http_get "http://localhost:8181/api/v2?apikey=$TAUTULLI_KEY&cmd=get_server_info" | jq -e '.response.result' | grep -q "success"; then
    pass "tautulli -> plex"
  else
    fail "tautulli -> plex"
  fi

  # Bazarr integrations
  local BAZARR_KEY
  BAZARR_KEY=$(read_secret "bazarr/api-key")

  if http_get "http://localhost:6767/api/system/health" -H "X-API-KEY: $BAZARR_KEY" | jq -e '.data' &>/dev/null; then
    pass "bazarr -> radarr/sonarr"
  else
    fail "bazarr -> radarr/sonarr"
  fi

  # Quality profiles
  if http_get "http://localhost:7878/api/v3/qualityprofile" -H "X-Api-Key: $RADARR_KEY" | jq -e 'length > 0' | grep -q "true"; then
    pass "radarr quality profiles"
  else
    fail "radarr quality profiles"
  fi

  if http_get "http://localhost:8989/api/v3/qualityprofile" -H "X-Api-Key: $SONARR_KEY" | jq -e 'length > 0' | grep -q "true"; then
    pass "sonarr quality profiles"
  else
    fail "sonarr quality profiles"
  fi

  # Plex libraries
  local PLEX_TOKEN
  PLEX_TOKEN=$(read_secret "plex/token")

  if http_get "http://localhost:32400/library/sections?X-Plex-Token=$PLEX_TOKEN" | grep -q 'title="Movies"'; then
    pass "plex movies library"
  else
    fail "plex movies library"
  fi

  if http_get "http://localhost:32400/library/sections?X-Plex-Token=$PLEX_TOKEN" | grep -q 'title="TV Shows"'; then
    pass "plex tv library"
  else
    fail "plex tv library"
  fi

  if http_get "http://localhost:32400/library/sections?X-Plex-Token=$PLEX_TOKEN" | grep -q 'title="Videos"'; then
    pass "plex videos library"
  else
    fail "plex videos library"
  fi

  # Audiobookshelf library
  local ABS_KEY
  ABS_KEY=$(read_secret "audiobookshelf/apikey")

  if http_get "http://localhost:8000/api/libraries" -H "Authorization: Bearer $ABS_KEY" | jq -e '.libraries[0].name' &>/dev/null; then
    pass "audiobookshelf library"
  else
    fail "audiobookshelf library"
  fi

  # Jellyseerr email notifications (disabled, replaced by pushover)
  if http_get "http://localhost:5055/api/v1/settings/notifications/email" -H "X-Api-Key: $JELLYSEERR_KEY" | jq -e '.enabled == false' | grep -q "true"; then
    pass "jellyseerr email notifications disabled"
  else
    fail "jellyseerr email notifications disabled"
  fi

  # Jellyseerr Pushover notifications
  if http_get "http://localhost:5055/api/v1/settings/notifications/pushover" -H "X-Api-Key: $JELLYSEERR_KEY" | jq -e '.enabled' | grep -q "true"; then
    pass "jellyseerr pushover notifications"
  else
    fail "jellyseerr pushover notifications"
  fi

  # Jellyseerr plex libraries enabled
  local plex_settings
  plex_settings=$(http_get "http://localhost:5055/api/v1/settings/plex" -H "X-Api-Key: $JELLYSEERR_KEY")
  local plex_libs_enabled
  plex_libs_enabled=$(echo "$plex_settings" | jq '[.libraries[] | select(.enabled == true)] | length')
  if [ "$plex_libs_enabled" -gt 0 ] 2>/dev/null; then
    pass "jellyseerr plex libraries enabled ($plex_libs_enabled)"
  else
    fail "jellyseerr no plex libraries enabled"
  fi

  # Jellyseerr periodic full scan enabled
  if echo "$plex_settings" | jq -e '.periodicScanning > 0' | grep -q "true"; then
    pass "jellyseerr periodic plex scan"
  else
    fail "jellyseerr periodic plex scan"
  fi

  # Plex remote access (reachability also needs the router's TCP 32400 forward)
  if http_get "http://localhost:32400/:/prefs?X-Plex-Token=$PLEX_TOKEN" | grep -q 'id="PublishServerOnPlexOnlineKey"[^>]*value="1"'; then
    pass "plex remote access enabled"
  else
    fail "plex remote access not enabled"
  fi

  # Plex custom connections URL
  if http_get "http://localhost:32400/:/prefs?X-Plex-Token=$PLEX_TOKEN" | grep -q 'customConnections.*plex\.'$DOMAIN; then
    pass "plex custom connections url"
  else
    fail "plex custom connections url not set"
  fi

  # Audiobookshelf library name and path
  local abs_lib
  abs_lib=$(http_get "http://localhost:8000/api/libraries" -H "Authorization: Bearer $ABS_KEY" | jq -r '.libraries[0]')
  local abs_name abs_path
  abs_name=$(echo "$abs_lib" | jq -r '.name')
  abs_path=$(echo "$abs_lib" | jq -r '.folders[0].fullPath')
  if [ "$abs_name" = "Audiobooks" ]; then
    pass "audiobookshelf library named Audiobooks"
  else
    fail "audiobookshelf library named $abs_name (expected Audiobooks)"
  fi
  if [ "$abs_path" = "/mnt/storage/data/media/audiobooks" ]; then
    pass "audiobookshelf library path correct"
  else
    fail "audiobookshelf library path $abs_path (expected /mnt/storage/data/media/audiobooks)"
  fi
}

test_storage() {
  section "Storage"

  # Mounts
  if mountpoint -q "$STORAGE_DIR" 2>/dev/null; then
    pass "$STORAGE_DIR mounted"
  else
    fail "$STORAGE_DIR mounted"
  fi

  # Key directories
  local dirs=(
    "$STORAGE_DIR/data/media/movies"
    "$STORAGE_DIR/data/media/tv"
    "$STORAGE_DIR/data/media/audiobooks"
    "$CACHE_DIR/data/usenet/complete"
    "$CACHE_DIR/data/torrents/complete"
  )
  for dir in "${dirs[@]}"; do
    if [ -d "$dir" ]; then
      pass "$dir exists"
    else
      fail "$dir exists"
    fi
  done

  # Videos dir (transmission download target, Plex Videos library)
  if [ -d "$STORAGE_DIR/data/media/videos" ]; then
    pass "$STORAGE_DIR/data/media/videos exists"
  else
    fail "$STORAGE_DIR/data/media/videos exists"
  fi

  # Incomplete dirs
  if [ -d "$CACHE_DIR/data/usenet/incomplete" ]; then
    pass "$CACHE_DIR/data/usenet/incomplete exists"
  else
    fail "$CACHE_DIR/data/usenet/incomplete exists"
  fi

  if [ -d "$CACHE_DIR/data/torrents/incomplete" ]; then
    pass "$CACHE_DIR/data/torrents/incomplete exists"
  else
    fail "$CACHE_DIR/data/torrents/incomplete exists"
  fi

  # Cache and backup dirs accessible
  if [ -d "$CACHE_DIR/data" ]; then
    pass "$CACHE_DIR accessible"
  else
    fail "$CACHE_DIR not accessible"
  fi

  if [ -d "$BACKUP_DIR" ]; then
    pass "$BACKUP_DIR accessible"
  else
    fail "$BACKUP_DIR not accessible"
  fi

  # Ownership
  local owner
  owner=$(stat -c "%U:%G" "$STORAGE_DIR/data/media/movies" 2>/dev/null || echo "unknown")
  if [ "$owner" = "media:media" ]; then
    pass "media dirs owned by media:media"
  else
    fail "media dirs owned by $owner (expected media:media)"
  fi
}

test_downloads() {
  section "Downloads"

  local SABNZBD_KEY
  SABNZBD_KEY=$(read_secret "sabnzbd/api-key")

  # SABnzbd not paused
  local paused
  paused=$(http_get "http://localhost:8081/api?mode=queue&apikey=$SABNZBD_KEY&output=json" | jq -r '.queue.paused')
  if [ "$paused" = "false" ]; then
    pass "sabnzbd queue active"
  else
    fail "sabnzbd queue is paused"
  fi

  # SABnzbd queue accessible
  local queue_status
  queue_status=$(http_get "http://localhost:8081/api?mode=queue&apikey=$SABNZBD_KEY&output=json" | jq -r '.queue.status')
  if [ -n "$queue_status" ] && [ "$queue_status" != "null" ]; then
    pass "sabnzbd queue accessible"
  else
    fail "sabnzbd queue accessible"
  fi

  # SABnzbd usenet server configured
  local server_count
  server_count=$(http_get "http://localhost:8081/api?mode=get_config&section=servers&apikey=$SABNZBD_KEY&output=json" | jq '[.config.servers[] | select(.enable == 1)] | length')
  if [ "$server_count" -gt 0 ]; then
    pass "sabnzbd usenet server configured ($server_count)"
  else
    fail "sabnzbd no usenet servers configured"
  fi

  # SABnzbd categories
  local sab_categories
  sab_categories=$(http_get "http://localhost:8081/api?mode=get_config&section=categories&apikey=$SABNZBD_KEY&output=json" | jq -r '[.config.categories[].name] | join(",")')
  local cat_ok=true
  for cat in movies tv; do
    if ! echo "$sab_categories" | grep -q "$cat"; then
      cat_ok=false
    fi
  done
  if [ "$cat_ok" = "true" ]; then
    pass "sabnzbd categories (movies, tv)"
  else
    fail "sabnzbd categories missing (got: $sab_categories)"
  fi

  # Transmission download-dir
  local ADMIN_USER ADMIN_PASS
  ADMIN_USER=$(read_secret "admin/username")
  ADMIN_PASS=$(read_secret "admin/password")
  local sid
  sid=$(curl -s --max-time 5 -u "$ADMIN_USER:$ADMIN_PASS" "http://localhost:9091/transmission/rpc" 2>/dev/null | grep -oP 'X-Transmission-Session-Id: \K[^<]+' || true)
  if [ -n "$sid" ]; then
    local download_dir
    download_dir=$(curl -s --max-time 5 -u "$ADMIN_USER:$ADMIN_PASS" \
      -H "X-Transmission-Session-Id: $sid" \
      -d '{"method":"session-get","arguments":{"fields":["download-dir"]}}' \
      "http://localhost:9091/transmission/rpc" | jq -r '.arguments["download-dir"]')
    if [ "$download_dir" = "/mnt/storage/data/media/videos" ]; then
      pass "transmission download-dir"
    else
      fail "transmission download-dir is $download_dir (expected /mnt/storage/data/media/videos)"
    fi
  else
    fail "transmission download-dir (could not get session)"
  fi
}

test_caddy() {
  section "Caddy Routes"

  local services="sonarr radarr bazarr prowlarr transmission sabnzbd plex tautulli jellyseerr homepage homebridge audiobookshelf"
  for svc in $services; do
    local code
    code=$(http_code "https://${svc}.${DOMAIN}" --insecure --resolve "${svc}.${DOMAIN}:443:127.0.0.1")
    if [ "$code" != "502" ] && [ "$code" != "503" ] && [ "$code" != "000" ]; then
      pass "${svc}.${DOMAIN} (HTTP $code)"
    else
      fail "${svc}.${DOMAIN} (HTTP $code)"
    fi
  done
}

test_docker() {
  section "Docker"

  # Drive status HTTP service
  if systemctl is-active --quiet drive-status-http; then
    pass "drive-status-http running"
  else
    fail "drive-status-http not running"
  fi

  # Drive status JSON endpoint
  local drive_json
  drive_json=$(http_get "http://localhost:9100/status_sda.json")
  if echo "$drive_json" | jq -e '.device' &>/dev/null; then
    pass "drive status JSON valid"
  else
    fail "drive status JSON invalid"
  fi

  if sudo docker ps &>/dev/null; then
    pass "docker daemon running"
  else
    fail "docker daemon running"
  fi

  if sudo docker ps | grep -q "homebridge"; then
    pass "homebridge container running"
  else
    fail "homebridge container running"
  fi

  # Homebridge HAP port listening
  if ss -tlnp | grep -q ":51215 "; then
    pass "homebridge HAP port 51215"
  else
    fail "homebridge HAP port 51215 not listening"
  fi

  # Avahi/mDNS running for HomeKit discovery
  if systemctl is-active --quiet avahi-daemon; then
    pass "avahi-daemon running"
  else
    fail "avahi-daemon not running"
  fi

  # mDNS port open
  if ss -ulnp | grep -q ":5353 "; then
    pass "mDNS port 5353"
  else
    fail "mDNS port 5353 not listening"
  fi
}

test_security() {
  section "Security"

  # Secrets root-only: nothing under /var/lib/secrets owned by another user
  # or accessible to group/other
  local loose_secrets
  loose_secrets=$(sudo find /var/lib/secrets \( ! -user root -o ! -group root -o -perm /077 \) 2>/dev/null | wc -l)
  if [ "$loose_secrets" -eq 0 ]; then
    pass "secrets root-only (700/600 root:root)"
  else
    fail "$loose_secrets secret paths not root-only"
  fi

  # Secrets dir itself 700
  local dir_perms
  dir_perms=$(sudo stat -c "%a %U:%G" /var/lib/secrets 2>/dev/null)
  if [ "$dir_perms" = "700 root:root" ]; then
    pass "secrets dir 700 root:root"
  else
    fail "secrets dir is $dir_perms (expected 700 root:root)"
  fi

  # Plaintext login passwords are recovery copies, never on the server
  local plaintext
  plaintext=$(sudo find /var/lib/secrets/users -name plaintext 2>/dev/null | wc -l)
  if [ "$plaintext" -eq 0 ]; then
    pass "no plaintext login passwords on server"
  else
    fail "$plaintext plaintext login password files on server"
  fi

  # Homepage gets its keys via LoadCredential, not group access to secrets
  local hp_groups
  hp_groups=$(systemctl show -p Group -p SupplementaryGroups --value homepage-dashboard | tr '\n' ' ')
  if ! grep -qwE 'media|radarr' <<< "$hp_groups"; then
    pass "homepage not in media/radarr groups"
  else
    fail "homepage groups: $hp_groups"
  fi

  # Caddy admin bound to localhost
  if sudo grep -q 'admin localhost' /etc/caddy/Caddyfile 2>/dev/null; then
    pass "caddy admin localhost-only"
  else
    fail "caddy admin not bound to localhost"
  fi

  # Caddy config file permissions
  local caddy_perms caddy_owner
  caddy_perms=$(stat -c "%a" /etc/caddy/Caddyfile 2>/dev/null)
  caddy_owner=$(stat -c "%U:%G" /etc/caddy/Caddyfile 2>/dev/null)
  if [ "$caddy_perms" = "640" ] && [ "$caddy_owner" = "caddy:caddy" ]; then
    pass "caddyfile permissions 640 caddy:caddy"
  else
    fail "caddyfile permissions $caddy_perms $caddy_owner (expected 640 caddy:caddy)"
  fi

  # SABnzbd verifies usenet server certificates (3 = Strict)
  local SABNZBD_KEY unverified
  SABNZBD_KEY=$(read_secret "sabnzbd/api-key")
  unverified=$(http_get "http://localhost:8081/api?mode=get_config&section=servers&apikey=$SABNZBD_KEY&output=json" | jq '[.config.servers[] | select(.ssl_verify != 3)] | length')
  if [ "$unverified" = "0" ]; then
    pass "sabnzbd usenet servers ssl_verify strict"
  else
    fail "sabnzbd usenet servers without strict ssl_verify: $unverified"
  fi

  # SABnzbd built-in HTTPS disabled (Caddy terminates TLS)
  if ss -tln | grep -q ":8090 "; then
    fail "sabnzbd https port 8090 listening"
  else
    pass "sabnzbd https port 8090 closed"
  fi

  # Homebridge image pinned (not :latest)
  if sudo docker inspect homebridge --format '{{.Config.Image}}' 2>/dev/null | grep -q '^homebridge/homebridge:[0-9-]*@sha256:'; then
    pass "homebridge image pinned"
  else
    fail "homebridge image not pinned"
  fi

  # Homebridge UI not opened on the LAN (only reachable through Caddy)
  local fw_rules
  if fw_rules=$(sudo iptables -S nixos-fw 2>/dev/null && { sudo ip6tables -S nixos-fw 2>/dev/null || true; }); then
    if grep -q -- "--dport 8581 " <<< "$fw_rules"; then
      fail "homebridge ui port 8581 open in firewall"
    else
      pass "homebridge ui port 8581 closed in firewall"
    fi
  else
    fail "could not read nixos-fw firewall rules"
  fi

  # Web UIs behind Caddy listen on loopback only (homepage, seerr, bazarr,
  # radarr, sabnzbd, tautulli, homebridge, sonarr, prowlarr)
  local port exposed
  for port in 3000 5055 6767 7878 8081 8181 8581 8989 9696; do
    exposed=$(ss -tlnH "sport = :$port" | awk '{print $4}' | grep -vE '^(127\.0\.0\.1|\[::1\]):' || true)
    if [ -z "$exposed" ]; then
      pass "port $port loopback-only"
    else
      fail "port $port listening on $(echo "$exposed" | tr '\n' ' ')"
    fi
  done

  # IPv6 disabled: sysctl set and no global IPv6 address on any interface
  local v6_off v6_global
  v6_off=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null || echo 0)
  v6_global=$(ip -6 -o addr show scope global 2>/dev/null | awk '{print $2": "$4}')
  if [ "$v6_off" = "1" ] && [ -z "$v6_global" ]; then
    pass "ipv6 disabled"
  else
    fail "ipv6 not disabled (disable_ipv6=$v6_off) $(echo "$v6_global" | tr '\n' ' ')"
  fi

  # NetworkManager won't re-enable it: every active ethernet profile has
  # ipv6.method=disabled (set by hand, see "IPv6" in CLAUDE.md)
  local nm_auto
  nm_auto=$(nmcli -t -f UUID,TYPE con show --active 2>/dev/null | awk -F: '$2 == "802-3-ethernet" {print $1}' \
    | while read -r uuid; do [ "$(nmcli -g ipv6.method con show "$uuid")" = "disabled" ] || nmcli -g connection.id con show "$uuid"; done)
  if [ -z "$nm_auto" ]; then
    pass "networkmanager ethernet profiles ipv6 disabled"
  else
    fail "networkmanager profile with ipv6 enabled: $nm_auto"
  fi

  # SABnzbd ini ownership
  local sab_owner
  sab_owner=$(stat -c "%U:%G" /var/lib/sabnzbd/sabnzbd.ini 2>/dev/null)
  if [ "$sab_owner" = "sabnzbd:sabnzbd" ]; then
    pass "sabnzbd.ini owned by sabnzbd:sabnzbd"
  else
    fail "sabnzbd.ini owned by $sab_owner (expected sabnzbd:sabnzbd)"
  fi

  # Backup credentials root-only
  local bad_backup_secrets
  bad_backup_secrets=$(sudo find /var/lib/secrets/restic /var/lib/secrets/r2 -type f \( ! -user root -o -perm /077 \) 2>/dev/null | wc -l)
  if [ "$bad_backup_secrets" -eq 0 ]; then
    pass "backup secrets root-only 600"
  else
    fail "$bad_backup_secrets backup secret files not root-only 600"
  fi
}

test_backups() {
  section "Backups"

  # Latest snapshot in each repo is less than 48h old
  local repo latest age
  for repo in local r2; do
    latest=$(sudo restic-$repo snapshots --latest 1 --json 2>/dev/null | jq -r '.[-1].time // empty')
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

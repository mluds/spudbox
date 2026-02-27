#!/usr/bin/env bash
set -euo pipefail

# ─── Configuration ──────────────────────────────────────────────
SECRETS_DIR="/var/lib/secrets"
STORAGE_DIR="/mnt/storage"
CACHE_DIR="/mnt/cache"
BACKUP_DIR="/mnt/backup"
DOMAIN="spudbox.win"

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
  check_secret "wireguard/server/private-key" "wireguard/server/private-key"
  check_secret "wireguard/server/public-key" "wireguard/server/public-key"
  check_secret "wireguard/clients/mikes-iphone/private-key" "wireguard/clients/mikes-iphone/private-key"
  check_secret "wireguard/clients/mikes-iphone/public-key" "wireguard/clients/mikes-iphone/public-key"
  check_secret "wireguard/clients/mikes-pc/private-key" "wireguard/clients/mikes-pc/private-key"
  check_secret "wireguard/clients/mikes-pc/public-key" "wireguard/clients/mikes-pc/public-key"
  check_secret "users/luds/hashed" "users/luds/hashed"
  check_secret "users/root/hashed" "users/root/hashed"

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
  check_service "jellyseerr.service"
  check_service "audiobookshelf.service"
  check_service "homepage-dashboard.service"
  check_service "ttyd.service"
  check_service "caddy.service"
  check_service "homebridge.service"
  check_service "wg-quick-wg0.service"

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
  check_service "autorestic-backup.timer"
  check_service "check-drive-status.timer"
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
  check_port 7681 t "ttyd"
  check_port 8581 t "homebridge"
  check_port 80 t "caddy-http"
  check_port 443 t "caddy-https"
  check_port 2019 t "caddy-admin"
  check_port 51820 u "wireguard"
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
  check_http "http://localhost:7681" "200" "ttyd"
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

  # Radarr import lists
  if http_get "http://localhost:7878/api/v3/importlist" -H "X-Api-Key: $RADARR_KEY" | jq -e '.[].name' | grep -qi "letterboxd"; then
    pass "radarr letterboxd import list"
  else
    fail "radarr letterboxd import list"
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

  # Audiobookshelf library
  local ABS_KEY
  ABS_KEY=$(read_secret "audiobookshelf/apikey")

  if http_get "http://localhost:8000/api/libraries" -H "Authorization: Bearer $ABS_KEY" | jq -e '.libraries[0].name' &>/dev/null; then
    pass "audiobookshelf library"
  else
    fail "audiobookshelf library"
  fi

  # Jellyseerr email notifications
  if http_get "http://localhost:5055/api/v1/settings/notifications/email" -H "X-Api-Key: $JELLYSEERR_KEY" | jq -e '.enabled' | grep -q "true"; then
    pass "jellyseerr email notifications"
  else
    fail "jellyseerr email notifications"
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

  # Ownership
  local owner
  owner=$(stat -c "%U:%G" "$STORAGE_DIR/data/media/movies" 2>/dev/null || echo "unknown")
  if [ "$owner" = "media:media" ]; then
    pass "media dirs owned by media:media"
  else
    fail "media dirs owned by $owner (expected media:media)"
  fi
}

test_wireguard() {
  section "WireGuard"

  # Interface up
  if ip link show wg0 &>/dev/null; then
    pass "wg0 interface exists"
  else
    fail "wg0 interface exists"
  fi

  # Peers configured
  local peer_count
  peer_count=$(sudo wg show wg0 2>/dev/null | grep -c "^peer:" || echo "0")
  if [ "$peer_count" -eq 2 ]; then
    pass "2 peers configured"
  else
    fail "$peer_count peers configured (expected 2)"
  fi

  # Config files
  if sudo test -f /etc/wireguard/wg0.conf; then
    pass "wg0.conf exists"
  else
    fail "wg0.conf exists"
  fi

  if sudo test -f /etc/wireguard/clients/mikes-iphone/client.conf && sudo test -f /etc/wireguard/clients/mikes-pc/client.conf; then
    pass "client configs exist"
  else
    fail "client configs exist"
  fi

  # IP forwarding
  local fwd
  fwd=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "0")
  if [ "$fwd" = "1" ]; then
    pass "IP forwarding enabled"
  else
    fail "IP forwarding disabled"
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
}

test_caddy() {
  section "Caddy Routes"

  local services="sonarr radarr bazarr prowlarr transmission sabnzbd plex tautulli jellyseerr homepage homebridge audiobookshelf ttyd"
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
}

# ─── Runner ────────────────────────────────────────────────────

CATEGORIES="secrets services ports http api_auth integrations downloads caddy docker storage wireguard"

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

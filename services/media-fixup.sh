# Makes newly imported video files play on every Plex client (the Apple TV in
# particular). For each new file under MEDIA_DIRS:
#   - Dolby Vision profile 5 has no HDR10 fallback, so non-DV players show
#     green/purple or fail: re-encode to HDR10 on the Intel GPU (libplacebo
#     applies the DV reshaping, hevc_vaapi encodes Main10).
#   - "Hybrid" Dolby Vision profile 8 (an RPU grafted from another source) can
#     stall the Apple TV at buffering forever: strip the DV layer losslessly,
#     leaving the HDR10 base untouched.
#   - SRT tracks carrying <font size=...> tags render tiny in Plex: strip them.
# Each rewrite is verified (duration, stream count, tags) before it replaces
# the original. Afterwards Sonarr/Radarr rescan and Plex refreshes the folder.
#
# Usage: media-fixup            # files changed since the previous run
#        media-fixup FILE...    # just these files

umask 077
STAMP=$STATE_DIR/last-run
# Bookkeeping (the run's start stamp, API keys for curl) lives in the state
# dir on the boot disk: touching the media pool on every 15-minute run woke
# the HDD each time. Scratch space for rewriting a video is on the pool (so
# the result is moved into place, not copied), made only when one needs it.
RUN=$(mktemp -d "$STATE_DIR/run.XXXX")
trap 'if [ -s "$RUN/scratch" ]; then rm -rf "$(cat "$RUN/scratch")"; fi; rm -rf "$RUN"' EXIT

# scratch: print the pool scratch dir, creating it on first use
scratch() {
  local dir=$WORK_DIR/run.$$
  if [ ! -s "$RUN/scratch" ]; then
    mkdir -p "$dir"
    echo "$dir" > "$RUN/scratch"
  fi
  echo "$dir"
}

probe() { ffprobe -v error "$@" 2>/dev/null; }
duration() { probe -show_entries format=duration -of csv=p=0 "$1" | cut -d. -f1; }
stream_count() { probe -show_entries stream=index -of csv=p=0 "$1" | wc -l; }
stream_tags() { probe -show_entries stream=codec_type:stream_tags=language,title -of csv=p=0 "$1"; }
dv_profile() { probe -select_streams v:0 -show_entries stream_side_data=dv_profile -of default=nw=1:nk=1 "$1" | grep -m1 . || true; }
video_transfer() { probe -select_streams v:0 -show_entries stream=color_transfer -of csv=p=0 "$1"; }

# secret NAME: a secret such as plex/token. The unit gets them as
# credentials (plex-token); a manual `sudo media-fixup` reads secretsDir.
secret() {
  if [ -n "${CREDENTIALS_DIRECTORY:-}" ]; then
    cat "$CREDENTIALS_DIRECTORY/${1//\//-}"
  else
    read-secret "$1"
  fi
}

# same_duration A B: durations within a second of each other.
same_duration() {
  local a b
  a=$(duration "$1")
  b=$(duration "$2")
  [ -n "$a" ] && [ -n "$b" ] && [ $((a > b ? a - b : b - a)) -le 1 ]
}

# same_media A B: same duration and the same number of streams.
same_media() {
  same_duration "$1" "$2" && [ "$(stream_count "$1")" = "$(stream_count "$2")" ]
}

# hdr10_name BASENAME: the release name with its Dolby Vision tag swapped for HDR10.
hdr10_name() {
  local n
  n=$(sed -E 's/[.](DV|DoVi)[.](HDR)/.\2/I; s/[.](DV|DoVi)[.]/.HDR10./I; s/[.]DV-/.HDR10-/I;
              s/Dolby[.]Vision[.]HDR10/HDR10/I; s/Dolby[.]Vision/HDR10/I; s/[.]MP4[.]/./I' <<< "$1")
  [ "$n" = "$1" ] && n=$(sed -E 's/[.](H[.]?265|x265|HEVC)/.HDR10.\1/I' <<< "$1")
  [ "$n" = "$1" ] && n="$1.HDR10"
  echo "$n"
}

# replace ORIG NEW: put NEW in ORIG's place as <hdr10 name>.mkv, rename sidecar
# subtitles to match, delete ORIG. Sets FILE to the new path.
replace() {
  local orig=$1 new=$2 dir base newbase s
  dir=$(dirname "$orig")
  base=$(basename "${orig%.*}")
  newbase=$(hdr10_name "$base")
  chmod --reference="$orig" "$new" # before chown: then it's no longer ours
  chown --reference="$orig" "$new"
  mv -f "$new" "$dir/$newbase.mkv"
  [ "$dir/$newbase.mkv" = "$orig" ] || rm -f "$orig"
  if [ "$newbase" != "$base" ]; then
    for s in "$dir/$base".*srt; do
      [ -e "$s" ] && mv "$s" "$dir/$newbase${s#"$dir/$base"}"
    done
  fi
  FILE=$dir/$newbase.mkv
}

convert_dv5() {
  local tmp out
  tmp=$(scratch)
  out=$tmp/convert.mkv
  say "Dolby Vision profile 5: re-encoding to HDR10 on the GPU"
  ffmpeg -hide_banner -nostdin -y -v error \
    -init_hw_device vaapi=va:/dev/dri/renderD128 -init_hw_device vulkan=vk@va -filter_hw_device vk \
    -i "$FILE" -map 0:v:0 -map '0:a?' -map '0:s?' -map_metadata 0 \
    -vf 'hwupload,libplacebo=apply_dolbyvision=1:colorspace=bt2020nc:color_primaries=bt2020:color_trc=smpte2084:range=tv:format=p010le,hwdownload,format=p010le,hwupload=derive_device=vaapi' \
    -c:v hevc_vaapi -profile:v main10 -rc_mode CQP -qp 19 -c:a copy -c:s srt "$out"
  if ! same_duration "$FILE" "$out" || [ "$(video_transfer "$out")" != smpte2084 ] \
    || [ -n "$(dv_profile "$out")" ]; then
    say "Verification failed, leaving the file unchanged"
    return 1
  fi
  replace "$FILE" "$out"
}

strip_dv() {
  local tmp out
  tmp=$(scratch)
  out=$tmp/strip.mkv
  say "Hybrid Dolby Vision: stripping the DV layer (lossless)"
  ffmpeg -hide_banner -nostdin -y -v error -i "$FILE" -map 0 -c copy -bsf:v dovi_rpu=strip=1 "$out"
  if ! same_media "$FILE" "$out" || [ -n "$(dv_profile "$out")" ]; then
    say "Verification failed, leaving the file unchanged"
    return 1
  fi
  replace "$FILE" "$out"
}

# fix_subs: strip <font> tags from FILE's SRT tracks (other subtitle formats
# are copied untouched). Also clears the default flag when every subtitle
# track has it (an mp4 quirk that makes Plex switch subtitles on by itself).
fix_subs() {
  local tmp
  tmp=$(scratch)
  local n i k found=0 ndef=0 d t a b
  local -a codecs sample=() extract=() inputs=() maps=() meta=()
  mapfile -t codecs < <(probe -select_streams s -show_entries stream=codec_name -of csv=p=0 "$FILE")
  n=${#codecs[@]}
  [ "$n" -gt 0 ] || return 1

  # Cheap check first: the tags appear on every line, so 10 minutes is enough.
  for ((i = 0; i < n; i++)); do
    [ "${codecs[$i]}" = subrip ] && sample+=(-map "0:s:$i" -c copy -f srt "$tmp/sample$i.srt")
  done
  if [ ${#sample[@]} -gt 0 ]; then
    ffmpeg -v error -nostdin -t 600 -i "$FILE" "${sample[@]}" || true
    cat "$tmp"/sample*.srt 2>/dev/null | grep -q '<font' && found=1
    rm -f "$tmp"/sample*.srt
  fi
  for ((i = 0; i < n; i++)); do
    probe -select_streams "s:$i" -show_entries stream_disposition=default -of csv=p=0 "$FILE" | grep -q 1 \
      && ndef=$((ndef + 1))
  done
  [ "$found" = 1 ] || { [ "$ndef" -eq "$n" ] && [ "$n" -gt 1 ]; } || return 1

  say "Cleaning subtitle tracks"
  for ((i = 0; i < n; i++)); do
    [ "${codecs[$i]}" = subrip ] && extract+=(-map "0:s:$i" -c copy -f srt "$tmp/$i.srt")
  done
  [ ${#extract[@]} -eq 0 ] || ffmpeg -v error -nostdin -i "$FILE" "${extract[@]}"
  k=0
  for ((i = 0; i < n; i++)); do
    if [ "${codecs[$i]}" = subrip ]; then
      sed -E -i 's#</?font[^>]*>##g' "$tmp/$i.srt"
      k=$((k + 1))
      inputs+=(-i "$tmp/$i.srt")
      maps+=(-map "$k:0")
    else
      maps+=(-map "0:s:$i")
    fi
    d=$(probe -select_streams "s:$i" -show_entries stream_disposition=default,forced -of default=nw=1 "$FILE" \
      | grep '=1$' | sed -E 's/^DISPOSITION://I; s/=1$//' | paste -sd+ -)
    [ "$ndef" -eq "$n" ] && d=$(sed -E 's/\+?default//; s/^\+//' <<< "$d")
    meta+=("-map_metadata:s:s:$i" "0:s:s:$i" "-disposition:s:$i" "${d:-0}")
  done
  # Any per-stream -map_metadata turns off ffmpeg's default per-stream copy,
  # so carry video/audio/attachment metadata over explicitly.
  for t in v a t; do
    a=$(probe -select_streams "$t" -show_entries stream=index -of csv=p=0 "$FILE" | wc -l)
    for ((i = 0; i < a; i++)); do meta+=("-map_metadata:s:$t:$i" "0:s:$t:$i"); done
  done
  ffmpeg -v error -nostdin -y -i "$FILE" "${inputs[@]}" -map 0:v -map '0:a?' "${maps[@]}" -map '0:t?' \
    -map_metadata 0 "${meta[@]}" -c copy "$tmp/subs.mkv"
  a=$(stream_tags "$FILE")
  b=$(stream_tags "$tmp/subs.mkv")
  if ! same_media "$FILE" "$tmp/subs.mkv" || [ "$a" != "$b" ]; then
    say "Verification failed, leaving subtitles unchanged"
    return 1
  fi
  chmod --reference="$FILE" "$tmp/subs.mkv"
  chown --reference="$FILE" "$tmp/subs.mkv"
  mv -f "$tmp/subs.mkv" "$FILE"
}

# rescan: have Sonarr/Radarr pick up the new file and Plex refresh its folder.
# Keys go to curl through header files, never on its command line.
rescan() {
  local dir id
  dir=$(dirname "$FILE")
  if [[ $FILE == "$TV_DIR"/* ]]; then
    printf 'X-Api-Key: %s\n' "$(secret sonarr/api-key)" > "$RUN/arr-key"
    id=$(curl -sf -H @"$RUN/arr-key" "http://localhost:$SONARR_PORT/api/v3/series" \
      | jq --arg f "$FILE" '[.[] | select(.path as $p | $f | startswith($p + "/"))][0].id // empty') || true
    [ -z "$id" ] || curl -sf -o /dev/null -H @"$RUN/arr-key" -H "Content-Type: application/json" \
      -d "{\"name\":\"RescanSeries\",\"seriesId\":$id}" "http://localhost:$SONARR_PORT/api/v3/command" || true
  else
    printf 'X-Api-Key: %s\n' "$(secret radarr/api-key)" > "$RUN/arr-key"
    id=$(curl -sf -H @"$RUN/arr-key" "http://localhost:$RADARR_PORT/api/v3/movie" \
      | jq --arg d "$dir" '[.[] | select(.path == $d)][0].id // empty') || true
    [ -z "$id" ] || curl -sf -o /dev/null -H @"$RUN/arr-key" -H "Content-Type: application/json" \
      -d "{\"name\":\"RescanMovie\",\"movieId\":$id}" "http://localhost:$RADARR_PORT/api/v3/command" || true
  fi
  printf 'X-Plex-Token: %s\n' "$(secret plex/token)" > "$RUN/plex-key"
  curl -sf -H @"$RUN/plex-key" "http://localhost:$PLEX_PORT/library/sections" \
    | xmlstarlet sel -t -v '//Directory/@key' -n \
    | while read -r s; do
      curl -sf -o /dev/null -G -H @"$RUN/plex-key" "http://localhost:$PLEX_PORT/library/sections/$s/refresh" \
        --data-urlencode "path=$dir" || true
    done
  rm -f "$RUN/arr-key" "$RUN/plex-key"
}

process() {
  local profile changed=0
  FILE=$1
  [ -f "$FILE" ] || return 0
  echo "$FILE" > "$RUN/current" # printed only once there's something to do
  profile=$(dv_profile "$FILE")
  if [ "$profile" = 5 ]; then
    convert_dv5 && changed=1
  elif [ "$profile" = 8 ] && [[ ${FILE,,} == *hybrid* ]]; then
    strip_dv && changed=1
  fi
  if [[ ${FILE,,} == *.mkv ]] && fix_subs; then
    changed=1
  fi
  [ "$changed" = 0 ] || rescan
}

# say MESSAGE: log an action, preceded by the file name the first time.
say() {
  if [ -s "$RUN/current" ]; then
    cat "$RUN/current"
    : > "$RUN/current"
  fi
  echo "  $*"
}

if [ $# -gt 0 ]; then
  for f in "$@"; do process "$f" || echo "  Failed: $f"; done
  exit 0
fi

if [ ! -e "$STAMP" ]; then
  touch "$STAMP"
  echo "First run: baseline set; only files added from now on are checked"
  exit 0
fi

# Files that land while this run is busy are picked up by the next one.
touch "$RUN/started"
read -ra dirs <<< "$MEDIA_DIRS"
find "${dirs[@]}" -type f \( -iname '*.mkv' -o -iname '*.mp4' -o -iname '*.m4v' \) -newer "$STAMP" -print0 \
  | while IFS= read -r -d '' f; do
    process "$f" || echo "  Failed: $f"
  done
mv "$RUN/started" "$STAMP"

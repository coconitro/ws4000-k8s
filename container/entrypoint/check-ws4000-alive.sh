#!/bin/bash
# Verify WS4000v4.exe is running and the simulator display is updating.
#
# Exit codes:
#   0 — healthy (process running; display changing or within stale grace)
#   1 — WS4000v4.exe not running
#   2 — display frozen (process running but frame unchanged past threshold)
set -euo pipefail

export DISPLAY="${DISPLAY:-:99}"

FREEZE_ENABLED="${WS4000_FREEZE_DETECTION_ENABLED:-1}"
STALE_THRESHOLD="${WS4000_FREEZE_STALE_THRESHOLD_SECONDS:-300}"
GRACE_PERIOD="${WS4000_FREEZE_GRACE_PERIOD_SECONDS:-120}"
RESOLUTION="${RESOLUTION:-800x600}"
SAMPLE_REGION="${WS4000_FREEZE_SAMPLE_REGION:-}"

HASH_FILE="/tmp/ws4000-frame-hash"
STALE_SINCE_FILE="/tmp/ws4000-stale-since"
SIM_STARTED_FILE="/tmp/ws4000-sim-started-at"

if ! pgrep -f 'WS4000v4\.exe' >/dev/null 2>&1; then
  echo "WS4000v4.exe not running" >&2
  exit 1
fi

if [ "$FREEZE_ENABLED" != "1" ]; then
  exit 0
fi

now="$(date +%s)"
if [ -f "$SIM_STARTED_FILE" ]; then
  sim_started="$(cat "$SIM_STARTED_FILE")"
  if [ $((now - sim_started)) -lt "$GRACE_PERIOD" ]; then
    exit 0
  fi
fi

resolve_crop() {
  local screen_w screen_h

  if [ -n "$SAMPLE_REGION" ]; then
    if [[ "$SAMPLE_REGION" =~ ^([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+)$ ]]; then
      CROP_W="${BASH_REMATCH[1]}"
      CROP_H="${BASH_REMATCH[2]}"
      CROP_X="${BASH_REMATCH[3]}"
      CROP_Y="${BASH_REMATCH[4]}"
      return 0
    fi
    echo "WARNING: invalid WS4000_FREEZE_SAMPLE_REGION=$SAMPLE_REGION; using center crop" >&2
  fi

  IFS=x read -r screen_w screen_h <<< "$RESOLUTION"
  CROP_W=$((screen_w / 2))
  CROP_H=$((screen_h / 2))
  CROP_X=$(((screen_w - CROP_W) / 2))
  CROP_Y=$(((screen_h - CROP_H) / 2))
}

capture_frame_hash() {
  local display_num="${DISPLAY#:}"
  resolve_crop
  ffmpeg -hide_banner -loglevel error \
    -f x11grab -video_size "$RESOLUTION" -i ":${display_num}" \
    -vf "crop=${CROP_W}:${CROP_H}:${CROP_X}:${CROP_Y}" \
    -frames:v 1 -f rawvideo - 2>/dev/null | md5sum | awk '{print $1}'
}

current_hash="$(capture_frame_hash)" || {
  echo "WARNING: failed to capture display frame; skipping freeze check" >&2
  exit 0
}

if [ -z "$current_hash" ]; then
  echo "WARNING: empty frame hash; skipping freeze check" >&2
  exit 0
fi

if [ ! -f "$HASH_FILE" ]; then
  echo "$current_hash" >"$HASH_FILE"
  rm -f "$STALE_SINCE_FILE"
  exit 0
fi

previous_hash="$(cat "$HASH_FILE")"
if [ "$current_hash" != "$previous_hash" ]; then
  echo "$current_hash" >"$HASH_FILE"
  rm -f "$STALE_SINCE_FILE"
  exit 0
fi

if [ ! -f "$STALE_SINCE_FILE" ]; then
  echo "$now" >"$STALE_SINCE_FILE"
  exit 0
fi

stale_since="$(cat "$STALE_SINCE_FILE")"
stale_seconds=$((now - stale_since))
if [ "$stale_seconds" -ge "$STALE_THRESHOLD" ]; then
  if [ "${WS4000_FREEZE_SOFT_RECOVERY_ENABLED:-1}" = "1" ] && [ ! -f /tmp/ws4000-soft-recovery-attempted ]; then
    echo "WS4000 display frozen for ${stale_seconds}s; attempting soft recovery" >&2
    if /usr/local/bin/recover-ws4000-sim.sh; then
      touch /tmp/ws4000-soft-recovery-attempted
      exit 0
    fi
    echo "WARNING: soft recovery failed" >&2
  fi
  echo "WS4000 display frozen for ${stale_seconds}s (threshold ${STALE_THRESHOLD}s)" >&2
  exit 2
fi

exit 0

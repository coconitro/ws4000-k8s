#!/bin/bash
# Verify the Kick stream is healthy: local ffmpeg process plus optional remote live check.
#
# Exit codes:
#   0 — healthy
#   1 — ffmpeg not running (local ingest pipeline down)
#   2 — Kick channel not live (remote check failed)
#   3 — unable to query Kick API (transient; does not trigger restart)
set -euo pipefail

CHANNEL_SLUG="${KICK_CHANNEL_SLUG:-}"
API_TOKEN="${KICK_API_ACCESS_TOKEN:-}"
RESTART_ON_FAIL="${KICK_HEALTH_CHECK_RESTART_ON_FAIL:-1}"

check_ffmpeg_running() {
  if pgrep -f '[f]fmpeg' >/dev/null 2>&1; then
    return 0
  fi
  echo "Kick health check: ffmpeg not running" >&2
  return 1
}

# Kick sometimes closes RTMPS while local ffmpeg keeps encoding into a
# half-closed socket (CLOSE_WAIT on :443). That looks "healthy" to pgrep
# but Kick shows offline — force a reconnect in that case.
check_rtmp_socket() {
  local close_wait established
  close_wait="$(awk 'NR>1 && $4=="08" && $3 ~ /:01BB$/ {c++} END{print c+0}' /proc/net/tcp 2>/dev/null || echo 0)"
  established="$(awk 'NR>1 && $4=="01" && $3 ~ /:01BB$/ {c++} END{print c+0}' /proc/net/tcp 2>/dev/null || echo 0)"
  if [ "$close_wait" -gt 0 ] && [ "$established" -eq 0 ]; then
    echo "Kick health check: RTMP socket in CLOSE_WAIT (Kick hung up)" >&2
    return 1
  fi
  return 0
}

fetch_kick_channel_json() {
  local slug="$1"
  local body http_code tmp

  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' RETURN

  if [ -n "$API_TOKEN" ]; then
    http_code="$(curl -sS -o "$tmp" -w "%{http_code}" \
      -H "Authorization: Bearer ${API_TOKEN}" \
      -H "Accept: application/json" \
      "https://api.kick.com/public/v1/channels?slug=${slug}" 2>/dev/null)" || http_code="000"
    if [ "$http_code" = "200" ]; then
      cat "$tmp"
      return 0
    fi
    echo "WARNING: Kick official API returned HTTP ${http_code}; trying public channel API" >&2
  fi

  http_code="$(curl -sS -o "$tmp" -w "%{http_code}" \
    -H "Accept: application/json" \
    -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36" \
    "https://kick.com/api/v2/channels/${slug}" 2>/dev/null)" || http_code="000"

  if [ "$http_code" != "200" ]; then
    echo "Kick health check: channel API HTTP ${http_code} for slug=${slug}" >&2
    return 1
  fi

  cat "$tmp"
}

kick_channel_is_live() {
  local body="$1"

  if echo "$body" | grep -qE '"is_live"[[:space:]]*:[[:space:]]*true'; then
    return 0
  fi

  if echo "$body" | grep -qE '"livestream"[[:space:]]*:[[:space:]]*\{'; then
    return 0
  fi

  return 1
}

restart_ffmpeg_if_enabled() {
  if [ "$RESTART_ON_FAIL" != "1" ]; then
    return 0
  fi
  echo "Kick health check: restarting ffmpeg ingest" >&2
  pkill -TERM -f '[f]fmpeg' 2>/dev/null || true
}

check_ffmpeg_running || exit 1

if ! check_rtmp_socket; then
  restart_ffmpeg_if_enabled
  exit 2
fi

if [ -z "$CHANNEL_SLUG" ]; then
  echo "Kick health check: ffmpeg running (remote check skipped — set KICK_CHANNEL_SLUG for live verification)" >&2
  exit 0
fi

body="$(fetch_kick_channel_json "$CHANNEL_SLUG")" || exit 3

if kick_channel_is_live "$body"; then
  echo "Kick health check: channel ${CHANNEL_SLUG} is live" >&2
  exit 0
fi

echo "Kick health check: channel ${CHANNEL_SLUG} is not live on Kick" >&2
restart_ffmpeg_if_enabled
exit 2

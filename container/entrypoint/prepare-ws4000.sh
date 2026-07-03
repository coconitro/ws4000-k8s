#!/bin/bash
# Ensure locale files and Wine C: mapping exist (Linux case + profile path target).
set -e

WINEPREFIX="${WINEPREFIX:-/wineprefix}"
WS4000_DIR="${WS4000_DIR:-/app/WS4000v4}"

mkdir -p "${WINEPREFIX}/drive_c"
ln -sfn "$WS4000_DIR" "${WINEPREFIX}/drive_c/WS4000v4_win"

cd "$WS4000_DIR"
if [ -f config.w4k ] && [ ! -f Config.w4k ]; then cp -f config.w4k Config.w4k; fi

if [ ! -f profile.dat ] || [ ! -f Config.w4k ]; then
  echo "ERROR: missing profile.dat or Config.w4k in $WS4000_DIR"
  ls -la "$WS4000_DIR" || true
  exit 1
fi

echo "WS4000 config: profile.dat + Config.w4k OK, C:\\WS4000v4_win -> $WS4000_DIR"

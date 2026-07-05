#!/bin/bash
# Soft recovery: re-click Simulation -> Run Simulation in the WS4000 UI.
set -euo pipefail

export DISPLAY="${DISPLAY:-:99}"

WS4000_CLICK_DELAY="${WS4000_CLICK_DELAY:-5}"
SIM_MENU_X="${WS4000_SIM_MENU_X:-96}"
SIM_MENU_Y="${WS4000_SIM_MENU_Y:-29}"
RUN_SIM_X="${WS4000_RUN_SIM_X:-114}"
RUN_SIM_Y="${WS4000_RUN_SIM_Y:-52}"
RESOLUTION="${RESOLUTION:-800x600}"

if ! command -v xdotool >/dev/null 2>&1; then
  echo "ERROR: xdotool not available for soft recovery" >&2
  exit 1
fi

echo "Soft recovery: clicking Simulation -> Run Simulation"
xdotool mousemove --sync "$SIM_MENU_X" "$SIM_MENU_Y"
xdotool click 1
sleep "$WS4000_CLICK_DELAY"
xdotool mousemove --sync "$RUN_SIM_X" "$RUN_SIM_Y"
xdotool click 1
sleep 1

IFS=x read -r screen_w screen_h <<< "$RESOLUTION"
xdotool mousemove --sync $((screen_w + 100)) $((screen_h + 100))

STATE_DIR="${WS4000_STATE_DIR:-/tmp/ws4000-state}"
mkdir -p "$STATE_DIR"
rm -f "${STATE_DIR}/frame-hash" "${STATE_DIR}/stale-since" 2>/dev/null || true
date +%s >"${STATE_DIR}/sim-started-at"
echo "Soft recovery complete"

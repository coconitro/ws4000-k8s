#!/bin/bash
# Shared helpers for detecting / tearing down the WS4000 Wine process tree.
#
# Wine launches the sim as:
#   wine64 explorer /desktop=ws4000,WxH WS4000v4.exe
# After WS4000v4.exe dies, that explorer parent often stays alive with
# "WS4000v4.exe" still in its cmdline. A naive `pgrep -f WS4000v4\.exe`
# then reports the sim as running (black virtual desktop) and freeze
# detection never sees a process-exit. Match the real sim only.

ws4000_sim_pids() {
  ps -eo pid=,args= 2>/dev/null | awk '
    tolower($0) ~ /ws4000v4\.exe/ \
      && $0 !~ /explorer/ \
      && $0 !~ /check-ws4000/ \
      && $0 !~ /healthcheck/ \
      && $0 !~ /ws4000-process/ \
      && $0 !~ /recover-ws4000/ \
      && $0 !~ /awk/ {
        print $1
      }
  '
}

ws4000_is_running() {
  [ -n "$(ws4000_sim_pids)" ]
}

# Tear down the Wine virtual desktop so the X11 root wallpaper is visible
# to the stream (explorer /desktop covers the entire display otherwise).
ws4000_teardown_wine_desktop() {
  local display="${DISPLAY:-:99}"
  echo "Tearing down Wine virtual desktop on ${display}"

  # Kill any remaining sim processes first.
  local pid
  for pid in $(ws4000_sim_pids); do
    kill "$pid" 2>/dev/null || true
  done

  # explorer /desktop=... keeps a black fullscreen window after the sim exits.
  pkill -f 'explorer.*/desktop=ws4000' 2>/dev/null || true
  pkill -f 'explorer\.exe.*/desktop=ws4000' 2>/dev/null || true

  if command -v wineserver >/dev/null 2>&1; then
    wineserver -k 2>/dev/null || true
  elif [ -x /opt/wine-ge/bin/wineserver ]; then
    /opt/wine-ge/bin/wineserver -k 2>/dev/null || true
  fi

  sleep 1
}

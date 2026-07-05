#!/bin/bash
set +e

export DISPLAY=:99
RESOLUTION=${RESOLUTION:-800x600}
MUSIC_DIR=${MUSIC_DIR:-/music}
PLAYLIST=${PLAYLIST:-${MUSIC_DIR}/ws4000-all.xspf}
export TZ="${TZ:-America/Los_Angeles}"

mkdir -p /tmp/pulse/run /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix 2>/dev/null || true
export XDG_RUNTIME_DIR=/tmp/pulse/run
if ! pulseaudio --start --exit-idle-time=-1 2>/tmp/pulse-start.log; then
  echo "WARNING: pulseaudio --start failed, trying foreground daemon"
  cat /tmp/pulse-start.log 2>/dev/null || true
  pulseaudio --daemonize=false --exit-idle-time=-1 --disallow-exit --disable-shm &
  sleep 1
fi
echo "=== PulseAudio ==="
pulseaudio --check && echo "PulseAudio running at ${XDG_RUNTIME_DIR}/pulse/native" || echo "WARNING: PulseAudio not running"

DISPLAY_NUM="${DISPLAY#:}"
X_SOCKET="/tmp/.X11-unix/X${DISPLAY_NUM}"
if [ ! -S "$X_SOCKET" ]; then
  echo "ERROR: X display socket missing: $X_SOCKET (entrypoint should start Xorg or Xvfb)" >&2
  exit 1
fi
if [ -f "/tmp/Xorg.${DISPLAY_NUM}.log" ]; then
  echo "=== Xorg log (last 15 lines) ==="
  tail -15 "/tmp/Xorg.${DISPLAY_NUM}.log" 2>/dev/null || true
fi
# Solid black root unless a background image is configured.
if { [ -z "${X11_BACKGROUND:-}" ] || [ ! -f "$X11_BACKGROUND" ]; } && [ -f /app/WS4000v4/ws4000-background.jpg ]; then
  X11_BACKGROUND=/app/WS4000v4/ws4000-background.jpg
fi
set_x11_background() {
  if [ -n "${X11_BACKGROUND:-}" ] && [ -f "$X11_BACKGROUND" ]; then
    echo "Setting X11 background: $X11_BACKGROUND"
    pkill -x feh 2>/dev/null || true
    feh --bg-fill "$X11_BACKGROUND" >/tmp/feh.log 2>&1 || {
      echo "WARNING: feh failed; falling back to black"
      xsetroot -solid black 2>/dev/null || true
    }
  else
    xsetroot -solid black 2>/dev/null || true
  fi
}
set_x11_background
echo "=== X11 socket ==="
ls -la /tmp/.X11-unix/ 2>/dev/null || true

export WINEPREFIX=/wineprefix
export WINEARCH=win64
export WINEESYNC=1
export WINEFSYNC=1
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-d3d8=n;d3d9=n;d3d11=n;dxgi=n}"
export PATH="/opt/wine-ge/bin:${PATH}"
export WINELOADER=/opt/wine-ge/bin/wine64

echo "=== System timezone ==="
echo "TZ=${TZ}"
date
readlink -f /etc/localtime 2>/dev/null || true

echo "=== Wine version ==="
/opt/wine-ge/bin/wine64 --version || true

configure-wine-timezone.sh || echo "WARNING: failed to configure Wine timezone"

WS4000_DIR=/app/WS4000v4
prepare-ws4000.sh || { echo "ERROR: WS4000 config preparation failed"; exit 1; }

sync_profile_to_export() {
  [ -d /config-export ] || return 0
  [ -f /app/WS4000v4/profile.dat ] || return 0
  mkdir -p /config-export
  cp -f /app/WS4000v4/profile.dat /config-export/profile.dat
}

sync_profile_to_export

cd "$WS4000_DIR" || { echo "ERROR: $WS4000_DIR not found"; exit 1; }
echo "=== WS4000 work dir ==="
pwd
ls -la profile.dat Config.w4k WS4000v4.exe 2>/dev/null || true
ls -la /wineprefix/drive_c/windows/system32/d3d8.dll 2>/dev/null || true

GPU_DEVICE="${WS4000_GPU_DEVICE:-/dev/dri/renderD128}"
if [ -f /tmp/ws4000-zink-fallback ]; then
  export WS4000_USE_XORG=0
  export WS4000_USE_ZINK=1
  echo "=== Xorg unavailable — using Zink fallback on render node ==="
fi
if [ "${WS4000_USE_GPU:-0}" = "1" ]; then
  echo "=== WS4000 GPU rendering enabled ==="
  if [ ! -e "$GPU_DEVICE" ]; then
    echo "ERROR: WS4000_USE_GPU=1 but $GPU_DEVICE not found"
    ls -la /dev/dri/ 2>/dev/null || true
    exit 1
  fi
  export LIBVA_DRIVER_NAME="${LIBVA_DRIVER_NAME:-radeonsi}"
  if [ -z "${VK_ICD_FILENAMES:-}" ] && [ -f /usr/share/vulkan/icd.d/radeon_icd.x86_64.json ]; then
    export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.x86_64.json
  fi
  # WS4000 uses OpenGL (GLFW). With Xorg+amdgpu use native DRI3; Zink only for Xvfb fallback.
  if [ "${WS4000_USE_XORG:-0}" = "1" ]; then
    unset MESA_LOADER_DRIVER_OVERRIDE
    echo "OpenGL via Xorg amdgpu DRI3 (Zink disabled)"
  elif [ "${WS4000_USE_ZINK:-0}" = "1" ]; then
    export MESA_LOADER_DRIVER_OVERRIDE=zink
    export LIBGL_ALWAYS_SOFTWARE=0
    echo "OpenGL via Zink: MESA_LOADER_DRIVER_OVERRIDE=zink VK_ICD_FILENAMES=${VK_ICD_FILENAMES:-default}"
  fi
  echo "GPU device: $GPU_DEVICE LIBVA_DRIVER_NAME=${LIBVA_DRIVER_NAME} VK_ICD_FILENAMES=${VK_ICD_FILENAMES:-default}"
  ls -la /dev/dri/ 2>/dev/null || true
else
  echo "=== WS4000 GPU rendering disabled (set WS4000_USE_GPU=1 + mount /dev/dri for hardware D3D8) ==="
fi

echo "WINEDLLOVERRIDES=${WINEDLLOVERRIDES}"

# Launch directly from the install dir so WS4000 can resolve profile.dat / Config.w4k.
# cmd /c breaks "executing directory" detection and leaves the default locale path empty.
WINEDEBUG=-all /opt/wine-ge/bin/wine64 explorer /desktop=ws4000,${RESOLUTION} \
  WS4000v4.exe > /tmp/wine.log 2>&1 &

WS4000_STARTUP_DELAY="${WS4000_STARTUP_DELAY:-15}"
WS4000_CLICK_DELAY="${WS4000_CLICK_DELAY:-5}"
SIM_MENU_X="${WS4000_SIM_MENU_X:-96}"
SIM_MENU_Y="${WS4000_SIM_MENU_Y:-29}"
RUN_SIM_X="${WS4000_RUN_SIM_X:-114}"
RUN_SIM_Y="${WS4000_RUN_SIM_Y:-52}"

echo "=== Waiting ${WS4000_STARTUP_DELAY}s for WS4000 UI ==="
sleep "$WS4000_STARTUP_DELAY"

if command -v xdotool >/dev/null 2>&1; then
  echo "=== Click Simulation -> Run Simulation ==="
  xdotool mousemove --sync "$SIM_MENU_X" "$SIM_MENU_Y"
  xdotool click 1
  sleep "$WS4000_CLICK_DELAY"
  xdotool mousemove --sync "$RUN_SIM_X" "$RUN_SIM_Y"
  xdotool click 1
  sleep 1
  IFS=x read -r SCREEN_W SCREEN_H <<< "${RESOLUTION}"
  xdotool mousemove --sync $((SCREEN_W + 100)) $((SCREEN_H + 100))
  echo "Mouse moved off screen"
  mkdir -p "${WS4000_STATE_DIR:-/tmp/ws4000-state}"
  date +%s >"${WS4000_STATE_DIR:-/tmp/ws4000-state}/sim-started-at"
else
  echo "WARNING: xdotool not installed; skipping Simulation menu clicks"
fi

echo "=== WS4000 launch log ==="
cat /tmp/wine.log || true

# --- Background music via VLC (optional; WS4000 can use its own audio when disabled) ---
export PULSE_SERVER="${PULSE_SERVER:-unix:${XDG_RUNTIME_DIR}/pulse/native}"

resolve_playlist() {
  if [ -n "$PLAYLIST" ] && [ -f "$PLAYLIST" ]; then
    echo "$PLAYLIST"
    return 0
  fi
  local candidate
  for candidate in \
    "${MUSIC_DIR}/ws4000-all.xspf" \
    "${MUSIC_DIR}/music.xspf" \
    "${MUSIC_DIR}/music.m3u" \
    "${MUSIC_DIR}"/*.xspf \
    "${MUSIC_DIR}"/*.m3u; do
    if [ -f "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

if [ "${VLC_ENABLED:-1}" = "1" ]; then
  echo "=== Music ==="
  ls -la "$MUSIC_DIR" 2>/dev/null || echo "WARNING: music dir missing: $MUSIC_DIR"

  PLAYLIST_FILE="$(resolve_playlist)" || PLAYLIST_FILE=""
  if [ -z "$PLAYLIST_FILE" ]; then
    echo "WARNING: no playlist found (set PLAYLIST or add music.xspf / music.m3u under $MUSIC_DIR)"
  elif [ ! -s "$PLAYLIST_FILE" ]; then
    echo "WARNING: playlist is empty: $PLAYLIST_FILE"
  else
    VLC_NORM_MAX_LEVEL="${VLC_NORM_MAX_LEVEL:-0.85}"
    echo "Playing (shuffle + loop, volume normalize): $PLAYLIST_FILE"
    cvlc --aout=pulse --loop --random --no-video \
      --audio-filter=normvol --norm-max-level="$VLC_NORM_MAX_LEVEL" \
      "$PLAYLIST_FILE" > /tmp/vlc.log 2>&1 &
    sleep 2
    if pgrep -x vlc >/dev/null 2>&1; then
      echo "VLC running"
    else
      echo "WARNING: VLC exited; see /tmp/vlc.log"
      tail -20 /tmp/vlc.log 2>/dev/null || true
    fi
  fi
else
  echo "VLC disabled — using WS4000 audio (music still mounted at $MUSIC_DIR)"
fi

if [ -d /config-export ]; then
  (
    while true; do
      sync_profile_to_export
      sleep "${PROFILE_SYNC_INTERVAL:-15}"
    done
  ) &
fi

if [ -n "${VNC_PASSWORD:-}" ]; then
  mkdir -p /tmp/.vnc
  x11vnc -storepasswd "$VNC_PASSWORD" /tmp/.vnc/passwd
  x11vnc -display :99 -forever -shared -rfbauth /tmp/.vnc/passwd -listen 0.0.0.0 -rfbport 5900 > /tmp/x11vnc.log 2>&1 &
else
  x11vnc -display :99 -forever -shared -nopw -listen 0.0.0.0 -rfbport 5900 > /tmp/x11vnc.log 2>&1 &
fi
sleep 1
if pgrep -f x11vnc >/dev/null 2>&1; then
  echo "x11vnc running on port 5900"
else
  echo "WARNING: x11vnc not listening on 5900; see /tmp/x11vnc.log"
  cat /tmp/x11vnc.log 2>/dev/null || true
fi

# Keep the container alive only while WS4000 is running and the display is updating.
# When the sim exits or freezes, exit non-zero so kubelet restarts the pod.
WATCH_INTERVAL="${WS4000_WATCH_INTERVAL:-30}"
echo "Watching WS4000v4.exe (interval ${WATCH_INTERVAL}s, freeze detection enabled=${WS4000_FREEZE_DETECTION_ENABLED:-1})"
while true; do
  check_result=0
  /usr/local/bin/check-ws4000-alive.sh || check_result=$?

  if [ "$check_result" -eq 1 ]; then
    echo "ERROR: WS4000v4.exe exited" >&2
    set_x11_background
    tail -30 /tmp/wine.log 2>/dev/null || true
    exit 1
  fi

  if [ "$check_result" -eq 2 ]; then
    echo "ERROR: WS4000 display frozen after soft recovery" >&2
    tail -30 /tmp/wine.log 2>/dev/null || true
    set_x11_background
    exit 1
  fi

  rm -f "${WS4000_STATE_DIR:-/tmp/ws4000-state}/soft-recovery-attempted" 2>/dev/null || true
  sleep "$WATCH_INTERVAL"
done

#!/bin/bash
# Start GPU-backed Xorg (or Xvfb fallback), then hand off to start.sh as wineuser.
set -euo pipefail

export DISPLAY="${DISPLAY:-:99}"
RESOLUTION="${RESOLUTION:-800x600}"
IFS=x read -r SCREEN_W SCREEN_H <<< "${RESOLUTION}"
DISPLAY_NUM="${DISPLAY#:}"
X_SOCKET="/tmp/.X11-unix/X${DISPLAY_NUM}"
XORG_LOG="/tmp/Xorg.${DISPLAY_NUM}.log"

mkdir -p /tmp/.X11-unix /tmp/pulse/run
chmod 1777 /tmp/.X11-unix
chown wineuser:wineuser /tmp/pulse/run

# runuser drops pod supplementalGroups (render/video); setpriv preserves them for wineuser.
wineuser_groups() {
  local groups="1000"
  local g
  for g in $(id -G); do
    [ "$g" = "0" ] && continue
    [ "$g" = "1000" ] && continue
    groups="${groups},${g}"
  done
  echo "${groups}"
}

run_as_wineuser() {
  setpriv --reuid=1000 --regid=1000 --groups="$(wineuser_groups)" -- "$@"
}

start_xvfb() {
  echo "=== Starting Xvfb on ${DISPLAY} (${RESOLUTION}) as wineuser ==="
  run_as_wineuser env DISPLAY="$DISPLAY" Xvfb "${DISPLAY}" -screen 0 "${RESOLUTION}x24" &
  for _ in $(seq 1 20); do
    [ -S "$X_SOCKET" ] && return 0
    sleep 1
  done
  echo "ERROR: Xvfb failed to create ${X_SOCKET}" >&2
  return 1
}

write_xorg_conf() {
  local bus_id_line=""
  if command -v lspci >/dev/null 2>&1; then
    local pci_addr bus_hex bus_dec dev fn
    pci_addr="$(lspci -D -d 1002: 2>/dev/null | head -1 | awk '{print $1}')"
    if [ -n "$pci_addr" ]; then
      bus_hex="$(echo "$pci_addr" | awk -F: '{print $2}')"
      dev="$(echo "$pci_addr" | awk -F'[:.]' '{print $(NF-1)}')"
      fn="$(echo "$pci_addr" | awk -F'[:.]' '{print $NF}')"
      bus_dec=$((16#$bus_hex))
      bus_id_line="    BusID \"PCI:${bus_dec}:${dev}:${fn}\""
      echo "Detected AMD GPU at ${pci_addr} -> PCI:${bus_dec}:${dev}:${fn}"
    fi
  fi

  cat > /etc/X11/ws4000-headless.conf <<EOF
Section "ServerFlags"
    Option "AllowEmptyInput" "true"
    Option "DontVTSwitch" "true"
    Option "AutoAddGPU" "true"
EndSection

Section "ServerLayout"
    Identifier "Layout0"
    Screen 0 "Screen0"
EndSection

Section "Device"
    Identifier "Device0"
    Driver "amdgpu"
${bus_id_line}
    Option "TearFree" "false"
EndSection

Section "Monitor"
    Identifier "Monitor0"
EndSection

Section "Screen"
    Identifier "Screen0"
    Device "Device0"
    Monitor "Monitor0"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Virtual ${SCREEN_W} ${SCREEN_H}
    EndSubSection
EndSection
EOF
}

start_xorg() {
  echo "=== Starting Xorg amdgpu on ${DISPLAY} (${RESOLUTION}) ==="
  ls -la /dev/dri/ 2>/dev/null || true
  write_xorg_conf
  cat /etc/X11/ws4000-headless.conf

  XORG_VT="${WS4000_XORG_VT:-8}"
  if [ -e "/dev/tty${XORG_VT}" ]; then
    chmod 666 "/dev/tty${XORG_VT}" 2>/dev/null || true
    chvt "${XORG_VT}" 2>/dev/null || true
  fi

  Xorg "${DISPLAY}" \
    -config /etc/X11/ws4000-headless.conf \
    -noreset -novtswitch -sharevts -ac \
    -logfile "$XORG_LOG" \
    -nolisten tcp \
    "vt${XORG_VT}" &

  for i in $(seq 1 30); do
    if [ -S "$X_SOCKET" ]; then
      echo "Xorg ready on ${DISPLAY} (${i}s)"
      return 0
    fi
    if [ "$i" -eq 30 ]; then
      echo "ERROR: Xorg failed to create ${X_SOCKET}" >&2
      tail -40 "$XORG_LOG" 2>/dev/null || true
      return 1
    fi
    sleep 1
  done
}

fix_display_permissions() {
  chmod 1777 /tmp/.X11-unix
  if [ -S "$X_SOCKET" ]; then
    chmod 777 "$X_SOCKET" 2>/dev/null || true
  fi
  if command -v xhost >/dev/null 2>&1 && [ -S "$X_SOCKET" ]; then
    DISPLAY="$DISPLAY" xhost +si:localuser:wineuser 2>/dev/null || true
    DISPLAY="$DISPLAY" xhost +local: 2>/dev/null || true
  fi
  echo "=== X11 socket permissions ==="
  ls -la /tmp/.X11-unix/ 2>/dev/null || true
}

if [ "${WS4000_USE_GPU:-0}" = "1" ] && [ "${WS4000_USE_XORG:-1}" = "1" ]; then
  if [ ! -e "${WS4000_GPU_DEVICE:-/dev/dri/renderD128}" ]; then
    echo "ERROR: WS4000_USE_GPU=1 but ${WS4000_GPU_DEVICE:-/dev/dri/renderD128} missing" >&2
    ls -la /dev/dri/ 2>/dev/null || true
    exit 1
  fi
  if ! start_xorg; then
    echo "WARNING: Xorg failed — falling back to Xvfb + Zink (Vulkan render node)" >&2
    touch /tmp/ws4000-zink-fallback
    start_xvfb
  fi
else
  start_xvfb
fi

fix_display_permissions

mkdir -p /tmp/ws4000-state
chown wineuser:wineuser /tmp/ws4000-state
chmod 700 /tmp/ws4000-state

exec setpriv --reuid=1000 --regid=1000 --groups="$(wineuser_groups)" -- \
  env HOME=/home/wineuser XDG_RUNTIME_DIR=/tmp/pulse/run /start.sh

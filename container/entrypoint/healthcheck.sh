#!/bin/bash
# Exit 0 when WS4000 is running and the display is updating; used by Kubernetes liveness probes.
set -euo pipefail

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

exec setpriv --reuid=1000 --regid=1000 --groups="$(wineuser_groups)" -- \
  env HOME=/home/wineuser XDG_RUNTIME_DIR=/tmp/pulse/run DISPLAY="${DISPLAY:-:99}" \
  /usr/local/bin/check-ws4000-alive.sh

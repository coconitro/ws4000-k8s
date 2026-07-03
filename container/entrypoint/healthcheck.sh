#!/bin/bash
# Exit 0 when WS4000v4.exe is running; used by Kubernetes liveness/readiness probes.
set -euo pipefail

if pgrep -f 'WS4000v4\.exe' >/dev/null 2>&1; then
  exit 0
fi

echo "WS4000v4.exe not running" >&2
exit 1

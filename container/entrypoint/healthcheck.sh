#!/bin/bash
# Exit 0 when WS4000 is running and the display is updating; used by Kubernetes liveness probes.
set -euo pipefail

/usr/local/bin/check-ws4000-alive.sh

#!/bin/bash
# Unit test for ws4000_sim_pids matching (no Wine required).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
. "${ROOT}/container/entrypoint/ws4000-process.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok - $*"; }

# Override ps for deterministic fixtures.
ps() {
  cat <<'EOF'
  101 /opt/wine-ge/bin/wine64 explorer /desktop=ws4000,800x600 WS4000v4.exe
  202 /opt/wine-ge/bin/wine64-preloader WS4000v4.exe
  303 /usr/bin/bash /usr/local/bin/check-ws4000-alive.sh
  404 /usr/bin/feh --bg-fill /config/ws4000-background.jpg
EOF
}

pids="$(ws4000_sim_pids | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
[ "$pids" = "202" ] || fail "expected only real sim pid 202, got '$pids'"
pass "ignores explorer /desktop parent and check script"

ws4000_is_running || fail "expected ws4000_is_running=true with sim pid present"
pass "ws4000_is_running true when sim alive"

ps() {
  cat <<'EOF'
  101 /opt/wine-ge/bin/wine64 explorer /desktop=ws4000,800x600 WS4000v4.exe
  303 /usr/bin/bash /usr/local/bin/check-ws4000-alive.sh
EOF
}

if ws4000_is_running; then
  fail "explorer-only should count as sim dead"
fi
pass "explorer-only cmdline does not count as running"

echo "All ws4000-process tests passed"

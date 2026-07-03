#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC=""
DEST=""
FROM_CLUSTER=0

usage() {
  cat <<EOF
Seed WS4000 config files onto a host path or NFS mount.

Usage: $0 --dest PATH [--src DIR] [--from-cluster]

  --dest PATH   Destination directory (e.g. NFS apps/ws4000-config)
  --src DIR     Source directory (default: assets/ws4000)
  --from-cluster  Export profile.dat from running pod first

Copies: profile.dat, Config.w4k, ws4000-logo.png, ws4000-background.jpg
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dest) DEST="$2"; shift 2 ;;
    --src) SRC="$2"; shift 2 ;;
    --from-cluster) FROM_CLUSTER=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [ -z "$DEST" ]; then
  echo "ERROR: --dest is required" >&2
  usage
  exit 1
fi

SRC="${SRC:-${ROOT}/assets/ws4000}"

if [ "$FROM_CLUSTER" = "1" ]; then
  "${ROOT}/build/export-profile.sh"
fi

mkdir -p "$DEST"

copy_if_present() {
  local name="$1"
  if [ -f "${SRC}/${name}" ]; then
    cp -f "${SRC}/${name}" "${DEST}/${name}"
    echo "copied ${name}"
  fi
}

if [ ! -f "${SRC}/profile.dat" ]; then
  echo "ERROR: ${SRC}/profile.dat not found" >&2
  exit 1
fi

copy_if_present profile.dat

if [ -f "${SRC}/Config.w4k" ]; then
  cp -f "${SRC}/Config.w4k" "${DEST}/Config.w4k"
  echo "copied Config.w4k"
elif [ -f "${SRC}/config.w4k" ]; then
  cp -f "${SRC}/config.w4k" "${DEST}/Config.w4k"
  echo "copied config.w4k -> Config.w4k"
else
  echo "ERROR: Config.w4k not found in ${SRC}" >&2
  exit 1
fi

copy_if_present ws4000-logo.png
copy_if_present ws4000-background.jpg

echo "Config volume seeded at ${DEST}:"
ls -la "$DEST"

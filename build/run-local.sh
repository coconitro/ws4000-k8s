#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

GITHUB_USER="${GITHUB_USER:-coconitro}"
IMAGE_REPO="${IMAGE_REPO:-ghcr.io/${GITHUB_USER}/ws4000}"
IMAGE_TAG="${IMAGE_TAG:-local}"
CONTAINER_NAME="${CONTAINER_NAME:-ws4000-test}"
NOVNC_NAME="${NOVNC_NAME:-ws4000-novnc}"
NETWORK_NAME="${NETWORK_NAME:-ws4000-net}"
MUSIC_MOUNT="${MUSIC_MOUNT:-}"
VLC_ENABLED="${VLC_ENABLED:-1}"
CONFIG_MOUNT="${CONFIG_MOUNT:-}"

"${ROOT}/build/download-ws4000.sh"

echo "=== Building image (linux/amd64): ${IMAGE_REPO}:${IMAGE_TAG} ==="
docker buildx build --platform linux/amd64 -t "${IMAGE_REPO}:${IMAGE_TAG}" . --load

echo "=== Stopping old containers if they exist ==="
docker rm -f "$CONTAINER_NAME" "$NOVNC_NAME" 2>/dev/null || true

docker network create "$NETWORK_NAME" 2>/dev/null || true

RUN_ARGS=(
  -d
  --name "$CONTAINER_NAME"
  --network "$NETWORK_NAME"
  --platform linux/amd64
  --shm-size=2g
  -e "VLC_ENABLED=${VLC_ENABLED}"
)

if [ -n "$MUSIC_MOUNT" ]; then
  RUN_ARGS+=(-v "${MUSIC_MOUNT}:/music:ro")
fi

if [ -n "$CONFIG_MOUNT" ]; then
  RUN_ARGS+=(-v "${CONFIG_MOUNT}:/config:ro")
  RUN_ARGS+=(-e "X11_BACKGROUND=/config/ws4000-background.jpg")
  RUN_ARGS+=(-e "STREAM_LOGO=/config/ws4000-logo.png")
fi

echo "=== Running ws4000 container ==="
docker run "${RUN_ARGS[@]}" "${IMAGE_REPO}:${IMAGE_TAG}"

echo "=== Running noVNC sidecar ==="
docker run -d \
  --name "$NOVNC_NAME" \
  --network "$NETWORK_NAME" \
  -p 6080:6080 \
  gotget/novnc \
  --vnc "${CONTAINER_NAME}:5900"

echo "=== Containers started ==="
echo "Web VNC: http://localhost:6080/vnc.html"
echo "Logs:    docker logs -f $CONTAINER_NAME"
echo "Stop:    docker rm -f $CONTAINER_NAME $NOVNC_NAME"
if [ -z "$MUSIC_MOUNT" ]; then
  echo ""
  echo "Tip: MUSIC_MOUNT=/path/to/music $0"
fi

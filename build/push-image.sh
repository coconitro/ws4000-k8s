#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

GITHUB_USER="${GITHUB_USER:-coconitro}"
IMAGE_REPO="${IMAGE_REPO:-ghcr.io/${GITHUB_USER}/ws4000}"
TAG="${1:-$(date +%Y%m%d-%H%M%S)}"

"${ROOT}/build/download-ws4000.sh"

if [ -z "${GITHUB_TOKEN:-}" ] && command -v gh >/dev/null 2>&1; then
  GITHUB_TOKEN="$(gh auth token 2>/dev/null || true)"
fi
if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "ERROR: set GITHUB_TOKEN or run 'gh auth login'" >&2
  exit 1
fi

echo "Logging into GHCR..."
echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$GITHUB_USER" --password-stdin

echo "Building + pushing linux/amd64 image: ${IMAGE_REPO}:${TAG}"
docker buildx build --platform linux/amd64 \
  --push \
  --build-arg WS4000_BUST="$(date +%s)" \
  -t "${IMAGE_REPO}:${TAG}" \
  -t "${IMAGE_REPO}:latest" \
  .

if [ "${UPDATE_VALUES_TAG:-0}" = "1" ]; then
  VALUES_FILE="deploy/helm/ws4000/values.yaml"
  if sed --version 2>/dev/null | grep -q GNU; then
    sed -i "0,/^  tag: /s/^  tag: .*/  tag: ${TAG}/" "$VALUES_FILE"
  else
    sed -i '' "0,/^  tag: /s/^  tag: .*/  tag: ${TAG}/" "$VALUES_FILE"
  fi
fi

echo "Build & push complete."
echo "Image: ${IMAGE_REPO}:${TAG}"
echo ""
echo "Deploy:"
echo "  helm upgrade --install ws4000 oci://ghcr.io/${GITHUB_USER}/ws4000 -f my-values.yaml"

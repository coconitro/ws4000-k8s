#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CHART_DIR="${CHART_DIR:-deploy/helm/ws4000}"
GITHUB_USER="${GITHUB_USER:-coconitro}"
REGISTRY="${HELM_OCI_REGISTRY:-oci://ghcr.io/${GITHUB_USER}}"
DIST_DIR="${DIST_DIR:-dist/charts}"
VERSION_OVERRIDE="${1:-}"

chart_version() {
  if [ -n "$VERSION_OVERRIDE" ]; then
    echo "$VERSION_OVERRIDE"
    return
  fi
  grep '^version:' "$CHART_DIR/Chart.yaml" | awk '{print $2}' | tr -d '"'
}

CHART_NAME=$(grep '^name:' "$CHART_DIR/Chart.yaml" | awk '{print $2}' | tr -d '"')
VERSION="$(chart_version)"

echo "=== Linting chart ${CHART_NAME} ${VERSION} ==="
helm lint "$CHART_DIR"

mkdir -p "$DIST_DIR"
echo "=== Packaging chart ==="
helm package "$CHART_DIR" -d "$DIST_DIR"

PACKAGE="${DIST_DIR}/${CHART_NAME}-${VERSION}.tgz"
if [ ! -f "$PACKAGE" ]; then
  echo "ERROR: expected package not found: $PACKAGE"
  exit 1
fi

if [ -z "${GITHUB_TOKEN:-}" ] && command -v gh >/dev/null 2>&1; then
  GITHUB_TOKEN="$(gh auth token 2>/dev/null || true)"
fi
if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "ERROR: set GITHUB_TOKEN or run 'gh auth login'" >&2
  exit 1
fi

echo "=== Logging into GHCR ==="
echo "$GITHUB_TOKEN" | helm registry login ghcr.io -u "$GITHUB_USER" --password-stdin

echo "=== Pushing ${PACKAGE} to ${REGISTRY} ==="
helm push "$PACKAGE" "$REGISTRY"

echo ""
echo "Chart published: ${REGISTRY}/${CHART_NAME}:${VERSION}"
echo ""
echo "Install:"
echo "  helm install ws4000 oci://ghcr.io/${GITHUB_USER}/${CHART_NAME} \\"
echo "    --version ${VERSION} -f my-values.yaml"

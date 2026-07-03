#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-${ROOT}/assets/ws4000/profile.dat}"
MODE="${MODE:-auto}"
NAMESPACE="${NAMESPACE:-ws4000}"
DEPLOYMENT="${DEPLOYMENT:-ws4000}"
CONTAINER_NAME="${CONTAINER_NAME:-ws4000-test}"
INGRESS_HOST="${INGRESS_HOST:-ws4000.example.com}"
INGRESS_USER="${INGRESS_USER:-admin}"
INGRESS_PASSWORD="${INGRESS_PASSWORD:-}"
REMOTE_PATH="/app/WS4000v4/profile.dat"

usage() {
  cat <<EOF
Export profile.dat from a running ws4000 container to a local file.

Usage: $0

Environment:
  MODE            auto | k8s-cp | k8s-http | docker-cp  (default: auto)
  OUT             Output path (default: assets/ws4000/profile.dat)
  NAMESPACE       Kubernetes namespace (default: ws4000)
  DEPLOYMENT      Kubernetes deployment name (default: ws4000)
  CONTAINER_NAME  Docker container name (default: ws4000-test)
  INGRESS_HOST    Host for k8s-http mode (default: ws4000.example.com)
  INGRESS_USER    Basic auth user for k8s-http (default: admin)
  INGRESS_PASSWORD Basic auth password for k8s-http

Examples:
  $0
  MODE=k8s-http INGRESS_PASSWORD=secret $0
  MODE=docker-cp CONTAINER_NAME=ws4000-test $0
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

backup_existing() {
  if [[ -f "$OUT" ]]; then
    local bak="${OUT}.bak.$(date +%Y%m%d%H%M%S)"
    cp -f "$OUT" "$bak"
    echo "Backed up existing file to $bak"
  fi
}

export_k8s_cp() {
  local pod
  pod="$(kubectl -n "$NAMESPACE" get pods -l "app.kubernetes.io/name=ws4000" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [[ -z "$pod" ]]; then
    pod="$(kubectl -n "$NAMESPACE" get pods -l "app.kubernetes.io/instance=$DEPLOYMENT" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  fi
  if [[ -z "$pod" ]]; then
    echo "ERROR: no ws4000 pod found in namespace $NAMESPACE" >&2
    exit 1
  fi
  echo "Copying from pod $NAMESPACE/$pod (container ws4000)..."
  mkdir -p "$(dirname "$OUT")"
  backup_existing
  kubectl -n "$NAMESPACE" cp "${pod}:${REMOTE_PATH}" "$OUT" -c ws4000
}

export_k8s_http() {
  if [[ -z "$INGRESS_PASSWORD" ]]; then
    echo "ERROR: INGRESS_PASSWORD required for k8s-http mode" >&2
    exit 1
  fi
  echo "Downloading from http://${INGRESS_HOST}/export/profile.dat ..."
  mkdir -p "$(dirname "$OUT")"
  backup_existing
  curl -fsSL -u "${INGRESS_USER}:${INGRESS_PASSWORD}" \
    "http://${INGRESS_HOST}/export/profile.dat" -o "$OUT"
}

export_docker_cp() {
  if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    echo "ERROR: docker container '$CONTAINER_NAME' not running" >&2
    exit 1
  fi
  echo "Copying from docker container $CONTAINER_NAME..."
  mkdir -p "$(dirname "$OUT")"
  backup_existing
  docker cp "${CONTAINER_NAME}:${REMOTE_PATH}" "$OUT"
}

detect_mode() {
  if kubectl -n "$NAMESPACE" get pods -l "app.kubernetes.io/name=ws4000" -o name 2>/dev/null | grep -q .; then
    echo "k8s-cp"
  elif docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER_NAME"; then
    echo "docker-cp"
  else
    echo "ERROR: could not detect target (no k8s pod or docker container)" >&2
    exit 1
  fi
}

if [[ "$MODE" == "auto" ]]; then
  MODE="$(detect_mode)"
  echo "Auto-detected mode: $MODE"
fi

case "$MODE" in
  k8s-cp) export_k8s_cp ;;
  k8s-http) export_k8s_http ;;
  docker-cp) export_docker_cp ;;
  *)
    echo "ERROR: unknown MODE=$MODE" >&2
    usage
    exit 1
    ;;
esac

echo "Exported profile.dat to $OUT"
echo "Next: review changes, then rebuild with ./build/push-image.sh and redeploy."

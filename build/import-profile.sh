#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${SRC:-${ROOT}/assets/ws4000/profile.dat}"
MODE="${MODE:-auto}"
NAMESPACE="${NAMESPACE:-ws4000}"
DEPLOYMENT="${DEPLOYMENT:-ws4000}"
CONTAINER_NAME="${CONTAINER_NAME:-ws4000-test}"
REMOTE_PATH="/app/WS4000v4/profile.dat"

usage() {
  cat <<EOF
Import a local profile.dat into a running ws4000 container.

Usage: $0

Environment:
  MODE            auto | k8s | docker  (default: auto)
  SRC             Source file (default: assets/ws4000/profile.dat)
  NAMESPACE       Kubernetes namespace (default: ws4000)
  DEPLOYMENT      Kubernetes deployment name (default: ws4000)
  CONTAINER_NAME  Docker container name (default: ws4000-test)

Note: restart the pod/container after import so WS4000 reloads the profile.

Examples:
  $0
  SRC=/path/to/profile.dat MODE=docker CONTAINER_NAME=ws4000-test $0
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -f "$SRC" ]]; then
  echo "ERROR: source file not found: $SRC" >&2
  exit 1
fi

import_k8s() {
  local pod
  pod="$(kubectl -n "$NAMESPACE" get pods -l "app.kubernetes.io/name=ws4000" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [[ -z "$pod" ]]; then
    pod="$(kubectl -n "$NAMESPACE" get pods -l "app.kubernetes.io/instance=$DEPLOYMENT" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  fi
  if [[ -z "$pod" ]]; then
    echo "ERROR: no ws4000 pod found in namespace $NAMESPACE" >&2
    exit 1
  fi
  echo "Copying to pod $NAMESPACE/$pod (container ws4000)..."
  kubectl -n "$NAMESPACE" cp "$SRC" "${pod}:${REMOTE_PATH}" -c ws4000
  echo "Restarting deployment/$DEPLOYMENT to reload profile..."
  kubectl -n "$NAMESPACE" rollout restart "deployment/${DEPLOYMENT}"
  kubectl -n "$NAMESPACE" rollout status "deployment/${DEPLOYMENT}" --timeout=180s
}

import_docker() {
  if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    echo "ERROR: docker container '$CONTAINER_NAME' not running" >&2
    exit 1
  fi
  echo "Copying to docker container $CONTAINER_NAME..."
  docker cp "$SRC" "${CONTAINER_NAME}:${REMOTE_PATH}"
  echo "Restarting container $CONTAINER_NAME..."
  docker restart "$CONTAINER_NAME" >/dev/null
}

detect_mode() {
  if kubectl -n "$NAMESPACE" get pods -l "app.kubernetes.io/name=ws4000" -o name 2>/dev/null | grep -q .; then
    echo "k8s"
  elif docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER_NAME"; then
    echo "docker"
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
  k8s) import_k8s ;;
  docker) import_docker ;;
  *)
    echo "ERROR: unknown MODE=$MODE" >&2
    usage
    exit 1
    ;;
esac

echo "Imported $SRC into running ws4000."

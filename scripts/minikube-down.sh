#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${MINIKUBE_PROFILE:-minikube}"
TUNNEL_PID_FILE="$ROOT_DIR/.minikube-tunnel.pid"

if [[ -f "$TUNNEL_PID_FILE" ]]; then
  TUNNEL_PID="$(cat "$TUNNEL_PID_FILE")"
  if [[ -n "$TUNNEL_PID" ]] && kill -0 "$TUNNEL_PID" 2>/dev/null; then
    echo "Stopping minikube tunnel pid=${TUNNEL_PID}"
    sudo kill "$TUNNEL_PID" 2>/dev/null || kill "$TUNNEL_PID" 2>/dev/null || true
  fi
  rm -f "$TUNNEL_PID_FILE"
fi

minikube -p "$PROFILE" stop

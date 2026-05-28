#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PROFILE="${MINIKUBE_PROFILE:-minikube}"
DRIVER="${MINIKUBE_DRIVER:-docker}"
APP_NAMESPACE="${APP_NAMESPACE:-taskmanager}"
APP_HOST="${APP_HOST:-taskmanager.test}"
ARGOCD_HOST="${ARGOCD_HOST:-argocd.test}"
TUNNEL_PID_FILE="$ROOT_DIR/.minikube-tunnel.pid"
TUNNEL_LOG_FILE="$ROOT_DIR/.minikube-tunnel.log"

ensure_hosts() {
  local ip="$1"

  echo "Updating /etc/hosts: ${APP_HOST}, ${ARGOCD_HOST} -> ${ip}"
  sudo sed -i.bak "/[[:space:]]${APP_HOST}$/d; /[[:space:]]${ARGOCD_HOST}$/d" /etc/hosts
  printf "%s %s %s\n" "$ip" "$APP_HOST" "$ARGOCD_HOST" | sudo tee -a /etc/hosts >/dev/null
}

ensure_ycr_pull_secret() {
  kubectl apply -f "$ROOT_DIR/k8s/namespace.yaml"

  local token="${YC_IAM_TOKEN:-}"
  if [[ -z "$token" ]] && command -v yc >/dev/null 2>&1; then
    token="$(yc iam create-token 2>/dev/null || true)"
  fi

  if [[ -z "$token" ]]; then
    echo "YCR pull secret was not created."
    echo "Set YC_IAM_TOKEN or install/configure yc, then create ycr-pull-secret from MINIKUBE_README.md."
    return
  fi

  kubectl -n "$APP_NAMESPACE" create secret docker-registry ycr-pull-secret \
    --docker-server=cr.yandex \
    --docker-username=iam \
    --docker-password="$token" \
    --dry-run=client -o yaml | kubectl apply -f -
}

ensure_tunnel_for_macos_docker() {
  if [[ "$(uname -s)" != "Darwin" || "$DRIVER" != "docker" ]]; then
    return
  fi

  if pgrep -f "minikube tunnel.*${PROFILE}" >/dev/null 2>&1 || pgrep -f "minikube tunnel" >/dev/null 2>&1; then
    echo "minikube tunnel is already running."
    return
  fi

  echo "Starting minikube tunnel in background for macOS Docker driver."
  echo "sudo may ask for your password because ports 80/443 need privileged routes."
  sudo -v
  nohup minikube -p "$PROFILE" tunnel > "$TUNNEL_LOG_FILE" 2>&1 &
  echo "$!" > "$TUNNEL_PID_FILE"
  echo "Tunnel log: $TUNNEL_LOG_FILE"
}

echo "Starting minikube profile=${PROFILE} driver=${DRIVER}"
minikube -p "$PROFILE" start --driver="$DRIVER"

minikube -p "$PROFILE" addons enable metrics-server
minikube -p "$PROFILE" addons enable ingress

echo "Waiting for ingress-nginx controller..."
kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=180s

if [[ "$(uname -s)" == "Darwin" && "$DRIVER" == "docker" ]]; then
  ensure_hosts "127.0.0.1"
else
  ensure_hosts "$(minikube -p "$PROFILE" ip)"
fi

ensure_ycr_pull_secret

echo "Installing/updating Argo CD..."
kubectl apply -f "$ROOT_DIR/argocd/namespace.yaml"
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl -n argocd rollout status deployment/argocd-server --timeout=240s
kubectl apply -f "$ROOT_DIR/argocd/project.yaml"
kubectl apply -f "$ROOT_DIR/argocd/application-taskmanager.yaml"
kubectl apply -f "$ROOT_DIR/argocd/argocd-ingress.yaml"

ensure_tunnel_for_macos_docker

echo
echo "Done."
echo "Application: http://${APP_HOST}"
echo "Argo CD UI:  https://${ARGOCD_HOST}"
echo
echo "Argo CD initial admin password:"
echo "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"

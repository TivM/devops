#!/usr/bin/env bash
set -euo pipefail

APP_NAMESPACE="${APP_NAMESPACE:-taskmanager}"
MON_NAMESPACE="${MON_NAMESPACE:-monitoring}"
APP_SERVICE="${APP_SERVICE:-client}"
GRAFANA_SERVICE="${GRAFANA_SERVICE:-kube-prometheus-stack-grafana}"
APP_LOCAL_PORT="${APP_LOCAL_PORT:-8080}"
GRAFANA_LOCAL_PORT="${GRAFANA_LOCAL_PORT:-3000}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="$ROOT_DIR/.port-forward-pids"
LOG_DIR="$ROOT_DIR/.port-forward-logs"
mkdir -p "$LOG_DIR"

if [[ -f "$PID_FILE" ]]; then
  echo "Port-forward процессы уже запущены (файл $PID_FILE существует)."
  echo "Если нужно перезапустить, выполни: bash scripts/stop-port-forwards.sh"
  exit 1
fi

echo "Запускаю port-forward для приложения на http://localhost:${APP_LOCAL_PORT} ..."
nohup kubectl -n "$APP_NAMESPACE" port-forward "svc/${APP_SERVICE}" "${APP_LOCAL_PORT}:80" \
  > "$LOG_DIR/app-port-forward.log" 2>&1 &
APP_PID=$!

echo "Запускаю port-forward для Grafana на http://localhost:${GRAFANA_LOCAL_PORT} ..."
nohup kubectl -n "$MON_NAMESPACE" port-forward "svc/${GRAFANA_SERVICE}" "${GRAFANA_LOCAL_PORT}:80" \
  > "$LOG_DIR/grafana-port-forward.log" 2>&1 &
GRAFANA_PID=$!

sleep 2

if ! kill -0 "$APP_PID" 2>/dev/null; then
  echo "Не удалось поднять port-forward для приложения. См. $LOG_DIR/app-port-forward.log"
  exit 1
fi

if ! kill -0 "$GRAFANA_PID" 2>/dev/null; then
  echo "Не удалось поднять port-forward для Grafana. См. $LOG_DIR/grafana-port-forward.log"
  kill "$APP_PID" 2>/dev/null || true
  exit 1
fi

cat > "$PID_FILE" <<EOF
APP_PID=$APP_PID
GRAFANA_PID=$GRAFANA_PID
EOF

echo
echo "Готово:"
echo "- Приложение: http://localhost:${APP_LOCAL_PORT}"
echo "- Grafana:    http://localhost:${GRAFANA_LOCAL_PORT}"
echo
echo "Логи:"
echo "- $LOG_DIR/app-port-forward.log"
echo "- $LOG_DIR/grafana-port-forward.log"
echo
echo "Остановить всё: bash scripts/stop-port-forwards.sh"

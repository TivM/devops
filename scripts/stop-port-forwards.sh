#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="$ROOT_DIR/.port-forward-pids"

if [[ ! -f "$PID_FILE" ]]; then
  echo "Файл $PID_FILE не найден, активных port-forward процессов не обнаружено."
  exit 0
fi

# shellcheck disable=SC1090
source "$PID_FILE"

stop_pid() {
  local pid="$1"
  local name="$2"
  if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    echo "Остановлен $name (pid=$pid)."
  else
    echo "$name уже не запущен."
  fi
}

stop_pid "${APP_PID:-}" "port-forward приложения"
stop_pid "${GRAFANA_PID:-}" "port-forward Grafana"

rm -f "$PID_FILE"
echo "Готово. Все port-forward процессы остановлены."

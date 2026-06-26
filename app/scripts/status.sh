#!/bin/sh
set -eu

APP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PID_FILE="$APP_DIR/runtime/app.pid"
LOG_FILE="$APP_DIR/runtime/app.log"
PORT="${PORT:-4321}"

if [ -f "$PID_FILE" ]; then
  PID="$(cat "$PID_FILE")"
  if kill -0 "$PID" >/dev/null 2>&1; then
    echo "状态：运行中"
    echo "PID：$PID"
    echo "地址：http://127.0.0.1:$PORT"
    echo "日志：$LOG_FILE"
    exit 0
  fi
fi

echo "状态：未运行"
echo "日志：$LOG_FILE"

#!/bin/sh
set -eu

APP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
RUNTIME_DIR="$APP_DIR/runtime"
PID_FILE="$RUNTIME_DIR/app.pid"
LOG_FILE="$RUNTIME_DIR/app.log"
PORT="${PORT:-4321}"

mkdir -p "$RUNTIME_DIR"

if command -v lsof >/dev/null 2>&1; then
  EXISTING_PID="$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | head -n 1 || true)"
  if [ -n "$EXISTING_PID" ] && [ ! -f "$PID_FILE" ]; then
    echo "端口 $PORT 已被占用，PID=$EXISTING_PID。请先停止占用进程，或改用其他 PORT。"
    exit 1
  fi
fi

if [ -f "$PID_FILE" ]; then
  PID="$(cat "$PID_FILE")"
  if kill -0 "$PID" >/dev/null 2>&1; then
    echo "出口成章 app 已在运行，PID=$PID"
    exit 0
  else
    rm -f "$PID_FILE"
  fi
fi

cd "$APP_DIR"
nohup env PORT="$PORT" npm start >> "$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"
sleep 1

PID="$(cat "$PID_FILE")"
if kill -0 "$PID" >/dev/null 2>&1; then
  echo "出口成章 app 已启动，PID=$PID，地址：http://127.0.0.1:$PORT，日志：$LOG_FILE"
else
  echo "启动失败，请检查日志：$LOG_FILE"
  exit 1
fi

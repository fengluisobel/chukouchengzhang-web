#!/bin/sh
set -eu

APP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PID_FILE="$APP_DIR/runtime/app.pid"

if [ ! -f "$PID_FILE" ]; then
  echo "出口成章 app 当前未记录运行 PID"
  exit 0
fi

PID="$(cat "$PID_FILE")"
if kill -0 "$PID" >/dev/null 2>&1; then
  kill "$PID"
  rm -f "$PID_FILE"
  echo "出口成章 app 已停止，PID=$PID"
else
  rm -f "$PID_FILE"
  echo "PID 文件已清理，进程不存在"
fi

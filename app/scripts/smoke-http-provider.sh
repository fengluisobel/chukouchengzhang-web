#!/bin/sh
set -eu

APP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
RUNTIME_DIR="$APP_DIR/runtime"
UPSTREAM_LOG="$RUNTIME_DIR/http-provider-demo.log"
UPSTREAM_PID_FILE="$RUNTIME_DIR/http-provider-demo.pid"
APP_PORT="${APP_PORT:-4322}"
UPSTREAM_PORT="${UPSTREAM_PORT:-8000}"
APP_PID_FILE="$RUNTIME_DIR/app.pid"

mkdir -p "$RUNTIME_DIR"

cleanup() {
  if [ -f "$APP_PID_FILE" ]; then
    PORT="$APP_PORT" bash "$APP_DIR/scripts/stop.sh" >/dev/null 2>&1 || true
  fi
  if [ -f "$UPSTREAM_PID_FILE" ]; then
    PID="$(cat "$UPSTREAM_PID_FILE")"
    kill "$PID" >/dev/null 2>&1 || true
    rm -f "$UPSTREAM_PID_FILE"
  fi
}

trap cleanup EXIT INT TERM

cd "$APP_DIR"
nohup env PORT="$UPSTREAM_PORT" node examples/http-provider-demo.js >> "$UPSTREAM_LOG" 2>&1 &
echo $! > "$UPSTREAM_PID_FILE"
sleep 1

CKCZ_PROVIDER=http \
CKCZ_HTTP_BASE_URL="http://127.0.0.1:$UPSTREAM_PORT" \
PORT="$APP_PORT" \
bash "$APP_DIR/scripts/start.sh"

sleep 1
curl -s "http://127.0.0.1:$APP_PORT/api/health"
printf '\n'
curl -s -X POST "http://127.0.0.1:$APP_PORT/api/transcripts/create" \
  -H 'Content-Type: application/json' \
  -d '{"rawText":"这是一次 smoke test，请验证 http provider 链路。","scene":"idea","mode":"concise","inputSource":"text"}'
printf '\n'

echo "HTTP provider smoke test 完成。"

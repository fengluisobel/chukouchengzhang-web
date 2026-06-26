#!/usr/bin/env bash
set -euo pipefail

IOS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_ROOT="$(cd "$IOS_ROOT/.." && pwd)"
APP_ROOT="$PROJECT_ROOT/app"
PORT="${PORT:-4321}"
WAIT_SECONDS=20
ACTION="${1:-status}"

usage() {
  cat <<'EOF'
用法：
  # 先进入 ios-app/ 目录
  bash scripts/handoff-backend.sh start
  bash scripts/handoff-backend.sh status
  bash scripts/handoff-backend.sh stop
  bash scripts/handoff-backend.sh smoke
  bash scripts/handoff-backend.sh smoke-flow
  bash scripts/handoff-backend.sh test
  bash scripts/handoff-backend.sh verify

说明：
- 这个脚本给 Mac 交接场景用，统一从 ios-app 目录侧操作同级 app/ 后端。
- 要求目录结构是：
  - ios-app/
  - app/
- start：启动后端并等待 /api/health 通过
- status：查看后端运行状态
- stop：停止后端
- smoke：先确保后端在跑，再做 /api/provider/status、/api/bootstrap、/api/health、/api/reports/daily 非侵入烟测，并顺手校验报告页关键字段
- smoke-flow：启动一个临时隔离 store 的 app 实例，串行验证 health / provider-status / bootstrap / transcribe / transcripts-create / transcripts-list / train-evaluate / training-list / ideas-archive / ideas-list / reports-daily，并额外校验 iOS 客户端依赖字段，不污染正式 data/store.json
- test：直接从 ios-app 目录侧触发同级 app/ 的 npm test
- verify：先跑 npm test，再跑上述 smoke-flow；也就是不只校验 transcribe/create/train/archive/report 写链路，还会顺手回读 transcripts/training/ideas 列表与 bootstrap / reports-daily 契约；适合 Mac 首编前做一轮后端接口契约总自检
EOF
}

if [[ "$ACTION" == "-h" || "$ACTION" == "--help" || "$ACTION" == "help" ]]; then
  usage
  exit 0
fi

if [[ ! -d "$APP_ROOT" || ! -f "$APP_ROOT/package.json" ]]; then
  echo "没找到同级 app/ 后端目录：$APP_ROOT" >&2
  echo "请确认你拿的是完整 Mac 交接包，而不只是 ios-app。" >&2
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "没找到 npm。请先在 Mac 上安装 Node.js 22+。" >&2
  exit 1
fi

wait_for_health() {
  local base_url="http://127.0.0.1:$PORT"
  local deadline=$((SECONDS + WAIT_SECONDS))
  while (( SECONDS < deadline )); do
    if curl -fsS "$base_url/api/health" >/dev/null 2>&1; then
      echo "后端已就绪：$base_url"
      return 0
    fi
    sleep 1
  done

  echo "后端启动后仍未在 ${WAIT_SECONDS}s 内通过健康检查：$base_url/api/health" >&2
  echo "可先看日志：$APP_ROOT/runtime/app.log" >&2
  return 1
}

case "$ACTION" in
  start)
    (
      cd "$APP_ROOT"
      PORT="$PORT" bash scripts/start.sh
    )
    wait_for_health
    ;;
  status)
    (
      cd "$APP_ROOT"
      PORT="$PORT" bash scripts/status.sh
    )
    ;;
  stop)
    (
      cd "$APP_ROOT"
      PORT="$PORT" bash scripts/stop.sh
    )
    ;;
  smoke)
    (
      cd "$APP_ROOT"
      PORT="$PORT" bash scripts/status.sh
    )
    if ! curl -fsS "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1; then
      echo "检测到后端尚未启动，先尝试拉起..."
      (
        cd "$APP_ROOT"
        PORT="$PORT" bash scripts/start.sh
      )
      wait_for_health
    fi
    PORT="$PORT" bash "$IOS_ROOT/scripts/smoke-backend.sh" "http://127.0.0.1:$PORT"
    ;;
  smoke-flow)
    (
      cd "$APP_ROOT"
      bash scripts/smoke-api-flow.sh
    )
    ;;
  test)
    (
      cd "$APP_ROOT"
      npm test
    )
    ;;
  verify)
    (
      cd "$APP_ROOT"
      npm run verify
    )
    ;;
  *)
    echo "未知动作：$ACTION" >&2
    usage >&2
    exit 1
    ;;
esac

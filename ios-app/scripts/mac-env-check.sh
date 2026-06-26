#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_ROOT="$(cd "$ROOT/.." && pwd)"
APP_ROOT="$PROJECT_ROOT/app"
LOG_FILE="$ROOT/build/mac-env-check.log"
STRICT=0

usage() {
  cat <<'EOF'
用法：
  bash scripts/mac-env-check.sh
  bash scripts/mac-env-check.sh --strict

说明：
- 只在 macOS 上执行，用来在真正点开 Xcode 前先查环境是否齐。
- 会把检查结果同时写到 build/mac-env-check.log。
- 默认：缺失关键依赖时报错；非关键风险只给 WARN。
- --strict：把 WARN 也视为失败，适合正式接手前做更严格预检。
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict)
      STRICT=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "未知参数：$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

mkdir -p "$(dirname "$LOG_FILE")"
: > "$LOG_FILE"

log() {
  echo "$*" | tee -a "$LOG_FILE"
}

ok() {
  log "[OK] $*"
}

note() {
  log "[NOTE] $*"
}

warn() {
  log "[WARN] $*"
  WARN_COUNT=$((WARN_COUNT + 1))
}

fail() {
  log "[FAIL] $*"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

WARN_COUNT=0
FAIL_COUNT=0

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "scripts/mac-env-check.sh 只给 macOS 用；当前系统不是 macOS。" >&2
  exit 1
fi

log "== Mac 首编环境预检 =="
log "时间：$(date '+%Y-%m-%d %H:%M:%S %Z')"
log "工程：$ROOT"
log "日志：$LOG_FILE"
log

if [[ -f "$ROOT/ChuKouChengZhang.xcodeproj/project.pbxproj" ]]; then
  ok "已找到 Xcode 工程"
else
  fail "缺少 Xcode 工程：$ROOT/ChuKouChengZhang.xcodeproj/project.pbxproj"
fi

if command -v xcode-select >/dev/null 2>&1; then
  developer_dir="$(xcode-select -p 2>/dev/null || echo '(未选中开发者目录)')"
  ok "xcode-select 可用：$developer_dir"
  if [[ "$developer_dir" == "/Library/Developer/CommandLineTools" ]]; then
    warn "当前 xcode-select 指向 CommandLineTools；iOS Simulator / xcodebuild 可能拿不到完整 Xcode SDK。若已安装完整 Xcode，请先执行 sudo xcode-select -s /Applications/Xcode.app/Contents/Developer 再继续。"
  fi
else
  fail "缺少 xcode-select；请先安装 Xcode / Command Line Tools。"
fi

if command -v xcodebuild >/dev/null 2>&1; then
  if xcodebuild_version="$(xcodebuild -version 2>&1)"; then
    ok "xcodebuild 可用"
    while IFS= read -r line; do
      log "    $line"
    done <<< "$xcodebuild_version"
  else
    fail "xcodebuild 存在但当前不可用；请先打开一次 Xcode 完成初始化/同意 license，或执行 sudo xcodebuild -runFirstLaunch。"
    while IFS= read -r line; do
      log "    $line"
    done <<< "$xcodebuild_version"
  fi
else
  fail "缺少 xcodebuild；请先安装 Xcode，并运行 xcode-select。"
fi

if command -v xcrun >/dev/null 2>&1; then
  if iphonesimulator_sdk_path="$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null)"; then
    if [[ -d "$iphonesimulator_sdk_path" ]]; then
      ok "iPhone Simulator SDK 可用：$iphonesimulator_sdk_path"
    else
      fail "xcrun 已返回 iPhone Simulator SDK 路径，但目录不存在：$iphonesimulator_sdk_path"
    fi
  else
    fail "当前拿不到 iPhone Simulator SDK；请先打开一次完整 Xcode，确认 Simulator Runtime 已安装，并检查 xcode-select 是否指向完整 Xcode Developer 目录。"
  fi

  if simctl_text="$(xcrun simctl list devices available 2>/dev/null)"; then
    available_count="$(printf '%s\n' "$simctl_text" | grep -E '\((Booted|Shutdown|Creating)\)$' | wc -l | tr -d ' ')"
    iphone_count="$(printf '%s\n' "$simctl_text" | grep -E '^[[:space:]]*iPhone .+ \([0-9A-F-]+\) \((Booted|Shutdown|Creating)\)$' | wc -l | tr -d ' ')"
    if [[ "$available_count" =~ ^[0-9]+$ ]] && (( available_count > 0 )); then
      ok "已发现可用模拟器设备：$available_count 台"
      if [[ "$iphone_count" =~ ^[0-9]+$ ]] && (( iphone_count > 0 )); then
        ok "已发现可用 iPhone Simulator：$iphone_count 台"
      else
        warn "当前没发现可用 iPhone Simulator；就算有别的平台模拟器，scripts/xcodebuild-smoke.sh 也可能只能回退 generic destination。请先在 Xcode 里补装至少一套 iPhone Simulator Runtime。"
      fi
    else
      warn "xcrun simctl 可用，但当前没发现 available 模拟器设备；首次打开 Xcode 后可再试。"
    fi
  else
    warn "xcrun simctl 调用失败；若 Xcode 刚装好，先打开一次 Xcode 让 Simulator Runtime 安装完成。"
  fi
else
  fail "缺少 xcrun；无法列出模拟器，也无法确认 iPhone Simulator SDK。"
fi

if command -v python3 >/dev/null 2>&1; then
  ok "python3 可用：$(python3 --version 2>&1)"
else
  fail "缺少 python3；scripts/configure-signing.sh 依赖它修改 project.pbxproj / Info.plist。"
fi

if command -v plutil >/dev/null 2>&1; then
  if plutil -lint "$ROOT/Config/Info.plist" >/dev/null 2>&1; then
    ok "Info.plist 可被 plutil 正常解析"
  else
    fail "Info.plist 解析失败：$ROOT/Config/Info.plist"
  fi
else
  warn "缺少 plutil；无法在命令行预检 Info.plist。"
fi

if command -v curl >/dev/null 2>&1; then
  ok "curl 可用"
else
  fail "缺少 curl；后端 smoke / verify 与联调脚本都依赖它。"
fi

if [[ -d "$APP_ROOT" && -f "$APP_ROOT/package.json" ]]; then
  log
  log "== 同级 app/ 后端依赖 =="
  if command -v node >/dev/null 2>&1; then
    node_version="$(node -v 2>/dev/null || true)"
    ok "node 可用：$node_version"
    node_major="$(printf '%s' "$node_version" | sed -E 's/^v([0-9]+).*/\1/')"
    if [[ "$node_major" =~ ^[0-9]+$ ]] && (( node_major < 22 )); then
      warn "Node 版本低于 22：$node_version；完整后端 verify 可能失败。"
    fi
  else
    fail "检测到同级 app/，但缺少 node；无法在 Mac 上直接跑后端 verify。"
  fi

  if command -v npm >/dev/null 2>&1; then
    ok "npm 可用：$(npm -v 2>/dev/null || true)"
  else
    fail "检测到同级 app/，但缺少 npm；无法跑 handoff-backend.sh verify。"
  fi
else
  log
  log "== 同级 app/ 后端依赖 =="
  note "当前未检测到同级 app/；本次按 iOS-only 编译 / Mock 路径预检，这不是阻断项。若你要跑完整录音 → 转写 → 优化 → 训练闭环，再把同级 app/ 一起带到 Mac。"
fi

log
if (( FAIL_COUNT > 0 )); then
  log "环境预检失败：FAIL=$FAIL_COUNT WARN=$WARN_COUNT"
  log "先处理 FAIL，再继续 scripts/mac-first-run.sh / xcodebuild 会更省时间。"
  exit 1
fi

if (( STRICT == 1 && WARN_COUNT > 0 )); then
  log "环境预检严格模式失败：FAIL=$FAIL_COUNT WARN=$WARN_COUNT"
  log "因为传了 --strict，当前 WARN 也被视为阻断项。"
  exit 1
fi

log "环境预检通过：FAIL=$FAIL_COUNT WARN=$WARN_COUNT"
log "下一步建议：继续跑 bash scripts/mac-first-run.sh（或先单独跑 bash scripts/xcodebuild-smoke.sh）。"

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_ROOT="$(cd "$ROOT/.." && pwd)"
APP_ROOT="$PROJECT_ROOT/app"
BACKEND_SCRIPT="$ROOT/scripts/handoff-backend.sh"
SIGNING_SCRIPT="$ROOT/scripts/configure-signing.sh"
ENV_CHECK_SCRIPT="$ROOT/scripts/mac-env-check.sh"
XCODEBUILD_SCRIPT="$ROOT/scripts/xcodebuild-smoke.sh"
CHECK_SCRIPT="$ROOT/scripts/check-ios-project.sh"
PROJECT_FILE="$ROOT/ChuKouChengZhang.xcodeproj"

TEAM_ID=""
BUNDLE_ID=""
RELEASE_BASE_URL=""
DESTINATION=""
BACKEND_CHECK="auto"
STRICT_ENV_CHECK=0
SKIP_XCODEBUILD=0
SKIP_SIGNING=0

usage() {
  cat <<'EOF'
用法：
  bash scripts/mac-first-run.sh
  bash scripts/mac-first-run.sh --team TEAMID --bundle-id com.yourname.chukouchengzhang
  bash scripts/mac-first-run.sh --team TEAMID --bundle-id com.yourname.chukouchengzhang --backend-check verify
  bash scripts/mac-first-run.sh --strict-env-check --skip-backend --skip-xcodebuild

它会在 Mac 上按顺序做这些事：
1. 先跑 macOS 环境预检（Xcode / xcrun / python3 / Node 等）
2. 静态校验 iOS 工程结构
3. 若同级 app/ 存在，则从 ios-app 目录侧做一次后端总自检（默认 verify = npm test + smoke-flow；除校验 transcribe/create/train/archive/report 写链路外，还会顺手回读 transcripts/training/ideas 列表与 bootstrap/reports-daily 契约，且不污染正式 store）
4. 若你传了 --team / --bundle-id / --release-base-url，则一把写入工程配置
5. 跑一次 xcodebuild 模拟器编译烟测（并产出 .xcresult 结果包）

常用参数：
  --team TEAMID                  写入 DEVELOPMENT_TEAM
  --bundle-id BUNDLE_ID          写入 PRODUCT_BUNDLE_IDENTIFIER
  --release-base-url URL         写入 Info.plist 的 CKCZReleaseBaseURL
  --backend-check smoke          只跑 provider/status + bootstrap + health + reports/daily 轻量烟测，并顺手校验报告页关键字段
  --backend-check smoke-flow     跑 transcribe/create/train/archive/report 全链路烟测，并校验 iOS 依赖字段
  --backend-check test           只跑同级 app/ 的 npm test
  --backend-check verify         先跑 npm test，再跑 smoke-flow；除写链路外，还会回读 transcripts/training/ideas 与 bootstrap/reports-daily，并顺手校验 iOS 依赖字段
  --backend-check auto           默认；若检测到同级 app/ 就跑 verify，否则自动跳过后端检查，方便只带 ios-app 做首编/Mock
  --backend-check skip           显式跳过后端检查（等价于 --skip-backend）
  --skip-backend                 跳过同级 app/ 后端检查
  --strict-env-check             把 mac-env-check.sh 的 WARN 也视为阻断项
  --destination DEST             透传给 scripts/xcodebuild-smoke.sh 的 --destination
  --skip-signing                 跳过写入 Team / Bundle Identifier
  --skip-xcodebuild              跳过命令行编译烟测
  -h, --help                     显示帮助
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --team)
      TEAM_ID="${2:-}"
      shift 2
      ;;
    --bundle-id)
      BUNDLE_ID="${2:-}"
      shift 2
      ;;
    --release-base-url)
      RELEASE_BASE_URL="${2:-}"
      shift 2
      ;;
    --backend-check)
      BACKEND_CHECK="${2:-}"
      shift 2
      ;;
    --skip-backend)
      BACKEND_CHECK="skip"
      shift
      ;;
    --strict-env-check)
      STRICT_ENV_CHECK=1
      shift
      ;;
    --destination)
      DESTINATION="${2:-}"
      shift 2
      ;;
    --skip-signing)
      SKIP_SIGNING=1
      shift
      ;;
    --skip-xcodebuild)
      SKIP_XCODEBUILD=1
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

case "$BACKEND_CHECK" in
  auto|smoke|smoke-flow|test|verify|skip)
    ;;
  *)
    echo "不支持的 --backend-check：$BACKEND_CHECK" >&2
    echo "可选值：auto / smoke / smoke-flow / test / verify / skip" >&2
    usage >&2
    exit 1
    ;;
esac

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "scripts/mac-first-run.sh 只给 macOS 首编接手用；当前系统不是 macOS。" >&2
  exit 1
fi

if [[ ! -f "$PROJECT_FILE/project.pbxproj" ]]; then
  echo "缺少 Xcode 工程：$PROJECT_FILE" >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "没找到 xcodebuild。请先安装 Xcode，并完成 xcode-select。" >&2
  exit 1
fi

echo "== [1/5] Mac 环境预检 =="
env_check_args=()
if [[ $STRICT_ENV_CHECK -eq 1 ]]; then
  env_check_args+=(--strict)
fi
bash "$ENV_CHECK_SCRIPT" "${env_check_args[@]}"

echo
echo "== [2/5] 静态校验 iOS 工程 =="
bash "$CHECK_SCRIPT"

echo
if [[ "$BACKEND_CHECK" != "skip" ]]; then
  if [[ ! -x "$BACKEND_SCRIPT" && ! -f "$BACKEND_SCRIPT" ]]; then
    echo "== [3/5] 后端联调检查 =="
    echo "未找到 $BACKEND_SCRIPT，跳过。"
  elif [[ -d "$APP_ROOT" && -f "$APP_ROOT/package.json" ]]; then
    backend_action="$BACKEND_CHECK"
    if [[ "$backend_action" == "auto" ]]; then
      backend_action="verify"
    fi

    echo "== [3/5] 后端联调检查 ($backend_action) =="
    if bash "$BACKEND_SCRIPT" "$backend_action"; then
      :
    else
      echo
      echo "后端检查失败。先修同级 app/ 后端，再继续 Xcode 首编会更省时间。" >&2
      exit 1
    fi
  elif [[ "$BACKEND_CHECK" == "auto" ]]; then
    echo "== [3/5] 后端联调检查 =="
    echo "未检测到同级 app/ 后端目录，自动跳过后端检查；本次仅继续 iOS 工程首编 / Mock 路径。"
    echo "如果你想跑完整远端闭环，请改用完整 Mac 交接包，或把同级 app/ 一起带到 Mac。"
  else
    echo "== [3/5] 后端联调检查 =="
    echo "你显式要求了 --backend-check $BACKEND_CHECK，但当前未检测到同级 app/ 后端目录：$APP_ROOT" >&2
    echo "请把同级 app/ 一起带到 Mac，或改用 --backend-check auto / --skip-backend。" >&2
    exit 1
  fi
else
  echo "== [3/5] 后端联调检查 =="
  echo "已按参数要求跳过。"
fi

echo
if [[ $SKIP_SIGNING -eq 0 ]]; then
  if [[ -n "$TEAM_ID" || -n "$BUNDLE_ID" || -n "$RELEASE_BASE_URL" ]]; then
    echo "== [4/5] 写入签名与可选正式服配置 =="
    signing_args=()
    [[ -n "$TEAM_ID" ]] && signing_args+=(--team "$TEAM_ID")
    [[ -n "$BUNDLE_ID" ]] && signing_args+=(--bundle-id "$BUNDLE_ID")
    [[ -n "$RELEASE_BASE_URL" ]] && signing_args+=(--release-base-url "$RELEASE_BASE_URL")
    bash "$SIGNING_SCRIPT" "${signing_args[@]}"
  else
    echo "== [4/5] 写入签名与可选正式服配置 =="
    echo "未传 --team / --bundle-id / --release-base-url，本步只展示当前配置："
    bash "$SIGNING_SCRIPT" --show
    echo "如需一把写入，可重跑："
    echo "  bash scripts/mac-first-run.sh --team 你的TEAMID --bundle-id 你的.bundle.id"
  fi
else
  echo "== [4/5] 写入签名与可选正式服配置 =="
  echo "已按参数要求跳过。"
fi

echo
if [[ $SKIP_XCODEBUILD -eq 0 ]]; then
  echo "== [5/5] xcodebuild 模拟器编译烟测 =="
  xcodebuild_args=()
  [[ -n "$DESTINATION" ]] && xcodebuild_args+=(--destination "$DESTINATION")
  bash "$XCODEBUILD_SCRIPT" "${xcodebuild_args[@]}"
else
  echo "== [5/5] xcodebuild 模拟器编译烟测 =="
  echo "已按参数要求跳过。"
fi

echo
cat <<'EOF'
Mac 首编预热流程完成。建议下一步：
1. 打开 Xcode 工程：ChuKouChengZhang.xcodeproj
2. 先跑模拟器确认首页 / 设置 / 录音页都能打开
3. 如果 xcodebuild 失败，优先查看 build/mac-env-check.log、build/xcodebuild-smoke.log、build/xcodebuild-smoke.xcresult
4. 如果要真机联调本地后端，先跑 bash scripts/resolve-local-ip.sh
5. 真机再测一轮：录音 → 转写 → 优化 → 训练 → 归档
EOF

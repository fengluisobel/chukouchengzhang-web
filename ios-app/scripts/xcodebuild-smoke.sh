#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/ChuKouChengZhang.xcodeproj"
SCHEME="ChuKouChengZhang"
CONFIGURATION="Debug"
DESTINATION=""
DESTINATION_SOURCE="auto"
DERIVED_DATA="$ROOT/build/DerivedData"
LOG_FILE="$ROOT/build/xcodebuild-smoke.log"
RESULT_BUNDLE="$ROOT/build/xcodebuild-smoke.xcresult"
DO_CLEAN=1

usage() {
  cat <<'EOF'
用法：
  bash scripts/xcodebuild-smoke.sh
  bash scripts/xcodebuild-smoke.sh --destination 'platform=iOS Simulator,name=iPhone 16'
  bash scripts/xcodebuild-smoke.sh --result-bundle build/custom-smoke.xcresult
  bash scripts/xcodebuild-smoke.sh --skip-clean

默认行为：
- 先跑 scripts/check-ios-project.sh
- 若未显式传 --destination，则优先自动挑一台可用 iPhone Simulator；挑不到时回退到 generic/platform=iOS Simulator
- 用 xcodebuild 对 ChuKouChengZhang 做一次 Debug 模拟器编译烟测
- 构建日志输出到 build/xcodebuild-smoke.log
- 构建结果包输出到 build/xcodebuild-smoke.xcresult
EOF
}

pick_default_destination() {
  if ! command -v xcrun >/dev/null 2>&1; then
    return 1
  fi

  local line=""
  line="$({ xcrun simctl list devices available 2>/dev/null || true; } | grep -E '^[[:space:]]*iPhone .+ \([0-9A-F-]+\) \((Booted|Shutdown|Creating)\)$' | head -n 1)"
  if [[ -z "$line" ]]; then
    return 1
  fi

  local name=""
  local udid=""
  name="$(printf '%s\n' "$line" | sed -E 's/^[[:space:]]*(iPhone .+) \([0-9A-F-]+\) \((Booted|Shutdown|Creating)\)$/\1/')"
  udid="$(printf '%s\n' "$line" | sed -E 's/^[[:space:]]*iPhone .+ \(([0-9A-F-]+)\) \((Booted|Shutdown|Creating)\)$/\1/')"

  if [[ -z "$name" || -z "$udid" || "$name" == "$line" || "$udid" == "$line" ]]; then
    return 1
  fi

  DESTINATION="platform=iOS Simulator,id=$udid"
  DESTINATION_SOURCE="auto:$name"
  return 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --destination)
      DESTINATION="${2:-}"
      DESTINATION_SOURCE="manual"
      shift 2
      ;;
    --configuration)
      CONFIGURATION="${2:-}"
      shift 2
      ;;
    --derived-data)
      DERIVED_DATA="${2:-}"
      shift 2
      ;;
    --result-bundle)
      RESULT_BUNDLE="${2:-}"
      shift 2
      ;;
    --skip-clean)
      DO_CLEAN=0
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

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "这个脚本要在 macOS 上执行；当前系统不是 macOS。" >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "没找到 xcodebuild。请先安装 Xcode，并在终端里完成 xcode-select。" >&2
  exit 1
fi

mkdir -p "$(dirname "$LOG_FILE")"
rm -rf "$RESULT_BUNDLE"

bash "$ROOT/scripts/check-ios-project.sh"

if [[ -z "$DESTINATION" ]]; then
  if pick_default_destination; then
    :
  else
    DESTINATION="generic/platform=iOS Simulator"
    DESTINATION_SOURCE="fallback:generic"
  fi
fi

cat <<EOF | tee "$LOG_FILE"
project: $PROJECT
scheme: $SCHEME
configuration: $CONFIGURATION
destination: $DESTINATION
destinationSource: $DESTINATION_SOURCE
derivedData: $DERIVED_DATA
log: $LOG_FILE
resultBundle: $RESULT_BUNDLE
EOF
echo | tee -a "$LOG_FILE"

if [[ $DO_CLEAN -eq 1 ]]; then
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA" \
    clean | tee -a "$LOG_FILE"
fi

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$RESULT_BUNDLE" \
  build | tee -a "$LOG_FILE"

echo

echo "xcodebuild 烟测完成。"
echo "日志：$LOG_FILE"
echo "结果包：$RESULT_BUNDLE"
echo "如果这里失败，优先带上这两个产物排障；如果这里通过，再去 Xcode 里跑模拟器 / 真机，心里会踏实很多。"

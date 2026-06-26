#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_FILE="$ROOT/ChuKouChengZhang.xcodeproj/project.pbxproj"
SCHEME_FILE="$ROOT/ChuKouChengZhang.xcodeproj/xcshareddata/xcschemes/ChuKouChengZhang.xcscheme"
INFO_PLIST="$ROOT/Config/Info.plist"

required=(
  "$PROJECT_FILE"
  "$SCHEME_FILE"
  "$INFO_PLIST"
  "$ROOT/ChuKouChengZhang/ChuKouChengZhangApp.swift"
  "$ROOT/ChuKouChengZhang/ViewModels/AppViewModel.swift"
  "$ROOT/ChuKouChengZhang/Services/APIClient.swift"
  "$ROOT/ChuKouChengZhang/Resources/Assets.xcassets/Contents.json"
  "$ROOT/ChuKouChengZhang/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json"
  "$ROOT/README.md"
  "$ROOT/STATUS.md"
  "$ROOT/Mac-首编手册.md"
  "$ROOT/Mac-编译失败排障.md"
  "$ROOT/Mac-环境安装清单.md"
  "$ROOT/scripts/configure-signing.sh"
  "$ROOT/scripts/mac-env-check.sh"
  "$ROOT/scripts/mac-first-run.sh"
  "$ROOT/scripts/xcodebuild-smoke.sh"
  "$ROOT/scripts/resolve-local-ip.sh"
  "$ROOT/scripts/package-ios-app.sh"
  "$ROOT/scripts/package-mac-handoff.sh"
  "$ROOT/scripts/handoff-backend.sh"
  "$ROOT/scripts/smoke-backend.sh"
)

fail=0
warn=0

check_file() {
  local f="$1"
  if [[ -f "$f" ]]; then
    echo "[OK] $f"
  else
    echo "[MISSING] $f"
    fail=1
  fi
}

check_contains() {
  local file="$1"
  local needle="$2"
  local label="$3"
  if grep -Fq "$needle" "$file"; then
    echo "[OK] $label"
  else
    echo "[MISSING] $label"
    fail=1
  fi
}

check_regex() {
  local file="$1"
  local regex="$2"
  local label="$3"
  if grep -Eq "$regex" "$file"; then
    echo "[OK] $label"
  else
    echo "[MISSING] $label"
    fail=1
  fi
}

warn_if_contains() {
  local file="$1"
  local needle="$2"
  local label="$3"
  if grep -Fq "$needle" "$file"; then
    echo "[WARN] $label"
    warn=1
  fi
}

for f in "${required[@]}"; do
  check_file "$f"
done

echo
if [[ $fail -ne 0 ]]; then
  echo "工程不完整：请先补齐缺失文件。"
  exit 1
fi

echo "== 静态校验 Xcode 工程接线 =="
while IFS= read -r swift_file; do
  name="$(basename "$swift_file")"
  check_contains "$PROJECT_FILE" "/* $name */" "project.pbxproj 已引用 $name"
  check_contains "$PROJECT_FILE" "/* $name in Sources */" "$name 已加入 Sources Build Phase"
done < <(find "$ROOT/ChuKouChengZhang" -type f -name '*.swift' | sort)

while IFS= read -r referenced_name; do
  [[ -z "$referenced_name" ]] && continue
  if find "$ROOT/ChuKouChengZhang" -type f -name "$referenced_name" | grep -q .; then
    echo "[OK] Sources 引用文件存在：$referenced_name"
  else
    echo "[MISSING] Sources 引用的文件不存在：$referenced_name"
    fail=1
  fi
done < <(
  grep -oE '/\* [^*]+ in Sources \*/' "$PROJECT_FILE" \
    | sed -E 's#^/\* (.*) in Sources \*/$#\1#' \
    | sort -u
)

check_contains "$PROJECT_FILE" 'INFOPLIST_FILE = Config/Info.plist;' 'Build Settings 已指向 Config/Info.plist'
check_regex "$PROJECT_FILE" 'PRODUCT_BUNDLE_IDENTIFIER = "?[A-Za-z0-9.-]+"?;' '工程里存在非空 Bundle Identifier（允许改成 Mac 上自己的唯一标识）'
check_contains "$PROJECT_FILE" 'SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";' '同时支持真机与模拟器平台'
check_contains "$PROJECT_FILE" 'IPHONEOS_DEPLOYMENT_TARGET = 16.0;' 'Deployment Target = iOS 16.0'
check_contains "$PROJECT_FILE" 'Assets.xcassets in Resources' 'Assets.xcassets 已加入 Resources Build Phase'
warn_if_contains "$PROJECT_FILE" 'DEVELOPMENT_TEAM = "";' 'DEVELOPMENT_TEAM 仍为空；到 Mac 后需先跑 bash scripts/configure-signing.sh 或进 Xcode 选 Team'

echo
printf '== 校验共享 xcscheme 关键项 ==\n'
check_contains "$SCHEME_FILE" 'BlueprintName = "ChuKouChengZhang"' '共享 xcscheme 的 BlueprintName 正确'
check_contains "$SCHEME_FILE" 'BuildableName = "ChuKouChengZhang.app"' '共享 xcscheme 的 BuildableName 正确'

scheme_target_id="$(grep -oE 'BlueprintIdentifier = "[A-F0-9]+"' "$SCHEME_FILE" | head -n1 | sed -E 's#.*"([A-F0-9]+)"#\1#')"
if [[ -n "$scheme_target_id" ]]; then
  check_contains "$PROJECT_FILE" "$scheme_target_id /* ChuKouChengZhang */" '共享 xcscheme 指向的 Target 仍存在于 project.pbxproj'
else
  echo '[MISSING] 共享 xcscheme 未解析出 BlueprintIdentifier'
  fail=1
fi

echo
printf '== 校验 Info.plist 关键项 ==\n'
check_contains "$INFO_PLIST" '<key>CFBundleDisplayName</key>' 'Info.plist 包含 CFBundleDisplayName'
check_contains "$INFO_PLIST" '<key>NSMicrophoneUsageDescription</key>' 'Info.plist 包含麦克风权限文案'
check_contains "$INFO_PLIST" '<key>NSLocalNetworkUsageDescription</key>' 'Info.plist 包含局域网访问权限文案'
check_contains "$INFO_PLIST" '<key>NSAppTransportSecurity</key>' 'Info.plist 包含开发期 ATS 配置'
check_contains "$INFO_PLIST" '<key>CKCZReleaseBaseURL</key>' 'Info.plist 预留正式服地址键'

echo
if [[ $fail -ne 0 ]]; then
  echo "工程静态校验失败：至少有一处 Xcode 工程引用或配置不完整。"
  exit 1
fi

echo "工程结构与静态接线校验通过。下一步："
echo "1. 只想先编译 / Mock：把整个 ios-app 目录拿到 Mac"
echo "2. 想跑完整远端闭环：优先执行 bash scripts/package-mac-handoff.sh，连同同级 app/ 一起打包带走"
echo "3. 在 Mac 上优先跑 bash scripts/mac-env-check.sh，再跑 bash scripts/mac-first-run.sh（可选带 --team / --bundle-id）"
echo "4. 若你想拆开执行，也可以先跑 bash scripts/handoff-backend.sh verify（或按需 smoke / smoke-flow / test）"
echo "5. 再用 Xcode 打开 ChuKouChengZhang.xcodeproj"
echo "6. 真机联调前，可先跑 bash scripts/resolve-local-ip.sh 算出局域网地址"

if [[ $warn -ne 0 ]]; then
  echo
  echo "提示：上面有 WARN，不一定阻断编译，但建议在 Mac 首编前先处理。"
fi

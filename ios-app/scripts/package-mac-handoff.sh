#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_ROOT="$(cd "$ROOT/.." && pwd)"
BACKEND_ROOT="$PROJECT_ROOT/app"
DIST_DIR="$ROOT/dist"
STAMP="$(date +%Y%m%d-%H%M%S)"
RUN_BACKEND_TEST=1
INCLUDE_BACKEND=auto

mkdir -p "$DIST_DIR"

usage() {
  cat <<'EOF'
用法：
  bash scripts/package-mac-handoff.sh
  bash scripts/package-mac-handoff.sh --ios-only
  bash scripts/package-mac-handoff.sh --skip-backend-test

说明：
- 默认会把 ios-app 打进一个 Mac 交接包。
- 如果检测到同级 app/ 后端目录，也会一并打进去，方便在 Mac 上直接联调完整闭环。
- `--ios-only` 产物会额外带上 `-ios-only` 文件名前缀，避免和完整 handoff 包混淆。
- 会自动排除 node_modules / .venv / runtime 日志 / .env 等本地或敏感文件。
- 默认会先对 app/ 运行一次 npm run verify，确认 iOS 依赖的后端 API 契约还没坏。
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ios-only)
      INCLUDE_BACKEND=no
      shift
      ;;
    --skip-backend-test)
      RUN_BACKEND_TEST=0
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

if [[ "$INCLUDE_BACKEND" == "no" ]]; then
  BUNDLE_PREFIX="chukouchengzhang-mac-handoff-ios-only"
else
  BUNDLE_PREFIX="chukouchengzhang-mac-handoff"
fi
BUNDLE_NAME="$BUNDLE_PREFIX-$STAMP"
STAGE_ROOT="$(mktemp -d "$DIST_DIR/.handoff-stage-$STAMP-XXXX")"
BUNDLE_DIR="$STAGE_ROOT/$BUNDLE_NAME"
TAR_ARCHIVE="$DIST_DIR/$BUNDLE_NAME.tar.gz"
ZIP_ARCHIVE="$DIST_DIR/$BUNDLE_NAME.zip"

cleanup() {
  rm -rf "$STAGE_ROOT"
}
trap cleanup EXIT

mkdir -p "$DIST_DIR"
mkdir -p "$BUNDLE_DIR"

copy_tree() {
  local src="$1"
  local dest="$2"
  shift 2
  mkdir -p "$dest"
  tar -C "$src" "$@" -cf - . | tar -C "$dest" -xf -
}

bash "$ROOT/scripts/check-ios-project.sh"

copy_tree "$ROOT" "$BUNDLE_DIR/ios-app" \
  --exclude='./dist' \
  --exclude='./build' \
  --exclude='./DerivedData' \
  --exclude='./*.xcuserstate' \
  --exclude='./xcuserdata' \
  --exclude='./**/*.xcuserstate' \
  --exclude='./**/xcuserdata' \
  --exclude='./*.bak-*' \
  --exclude='./.DS_Store'

for required_entry in \
  "STATUS.md" \
  "README.md" \
  "Mac-环境安装清单.md" \
  "Mac-首编手册.md" \
  "Mac-编译失败排障.md" \
  "scripts/check-ios-project.sh" \
  "scripts/mac-env-check.sh" \
  "scripts/mac-first-run.sh" \
  "scripts/configure-signing.sh" \
  "scripts/handoff-backend.sh" \
  "scripts/smoke-backend.sh" \
  "scripts/package-ios-app.sh" \
  "scripts/package-mac-handoff.sh" \
  "scripts/xcodebuild-smoke.sh" \
  "scripts/resolve-local-ip.sh" \
  "Config/Info.plist" \
  "ChuKouChengZhang.xcodeproj/project.pbxproj" \
  "ChuKouChengZhang.xcodeproj/xcshareddata/xcschemes/ChuKouChengZhang.xcscheme"
  do
  if [[ ! -f "$BUNDLE_DIR/ios-app/$required_entry" ]]; then
    echo "打包失败：ios-app/$required_entry 未进入 Mac 交接包，请先检查 copy/exclude 逻辑。" >&2
    exit 1
  fi
done

backend_included=no
if [[ "$INCLUDE_BACKEND" != "no" && -f "$BACKEND_ROOT/package.json" ]]; then
  if [[ $RUN_BACKEND_TEST -eq 1 ]]; then
    (
      cd "$BACKEND_ROOT"
      npm run verify
    )
  fi

  copy_tree "$BACKEND_ROOT" "$BUNDLE_DIR/app" \
    --exclude='./node_modules' \
    --exclude='./.venv' \
    --exclude='./runtime' \
    --exclude='./.env' \
    --exclude='./.env.local' \
    --exclude='./.DS_Store'

  for required_backend_entry in \
    "package.json" \
    ".env.example" \
    "README.md" \
    "config/llm-profiles.example.json" \
    "src/server.js" \
    "src/load-env.js" \
    "scripts/start.sh" \
    "scripts/status.sh" \
    "scripts/stop.sh" \
    "scripts/smoke-api-flow.sh" \
    "scripts/smoke-http-provider.sh" \
    "scripts/setup-local-stt.sh" \
    "scripts/faster_whisper_transcribe.py" \
    "scripts/faster_whisper_warmup.py"
  do
    if [[ ! -f "$BUNDLE_DIR/app/$required_backend_entry" ]]; then
      echo "打包失败：app/$required_backend_entry 未进入 Mac 交接包，请先检查 copy/exclude 逻辑。" >&2
      exit 1
    fi
  done

  backend_included=yes
fi

cat > "$BUNDLE_DIR/HANDOFF-README.md" <<EOF
# 出口成章｜Mac 交接包说明

打包时间：$(date '+%Y-%m-%d %H:%M:%S %Z')

## 里面有什么
- ios-app/：可直接用 Xcode 打开的 iPhone 客户端工程
- app/：Node 后端（$( [[ "$backend_included" == "yes" ]] && echo '已包含' || echo '本包未包含' )）

## 最短接手路径

### 只想先编译 / 看 UI / 跑 Mock
1. 先进入 \`ios-app/\` 目录：
   - cd ios-app
2. 最省事的做法是先跑环境预检，再跑一键首编：
   - bash scripts/mac-env-check.sh
   - 如需把 WARN 也当阻断项，可改跑：bash scripts/mac-env-check.sh --strict
   - 如果提示“当前没发现可用 iPhone Simulator”，先在 Xcode 里补装至少一套 iPhone Simulator Runtime，再继续首编
   - bash scripts/mac-first-run.sh --team 你的TEAMID --bundle-id 你的.bundle.id
   - 如果这个包里没带同级 app/，脚本会自动跳过后端检查，只继续 iOS 首编 / Mock 路径
3. 如果你想拆开执行：
   - bash scripts/check-ios-project.sh
   - bash scripts/configure-signing.sh --team 你的TEAMID --bundle-id 你的.bundle.id
   - bash scripts/xcodebuild-smoke.sh
4. 如果 xcodebuild 失败，优先看：
   - build/mac-env-check.log
   - build/xcodebuild-smoke.log
   - build/xcodebuild-smoke.xcresult
5. 然后回 Xcode 里跑模拟器或真机

### 想跑完整“录音 → 转写 → 优化 → 训练”闭环
EOF

if [[ "$backend_included" == "yes" ]]; then
  cat >> "$BUNDLE_DIR/HANDOFF-README.md" <<'EOF'
1. 先进入 `ios-app/` 目录：
   - cd ios-app
2. 最省事的做法是先跑环境预检，再直接跑首编脚本：
   - bash scripts/mac-env-check.sh
   - 如需把 WARN 也当阻断项，可改跑：bash scripts/mac-env-check.sh --strict
   - 如果提示“当前没发现可用 iPhone Simulator”，先在 Xcode 里补装至少一套 iPhone Simulator Runtime，再继续首编
   - bash scripts/mac-first-run.sh --team 你的TEAMID --bundle-id 你的.bundle.id
   它会先做环境预检与静态校验，再从 `ios-app/` 目录侧跑一次同级 `app/` 后端 verify（`npm test + smoke-flow`；除 `transcribe/create/train/archive/report` 写链路外，还会回读 `transcripts/training/ideas` 列表与 `bootstrap/reports-daily` 契约，并顺手校验 iOS 依赖字段），最后再做 `xcodebuild` 模拟器烟测并产出 `.xcresult` 结果包。
3. 如果你更想拆开执行，推荐顺序是：
   - bash scripts/handoff-backend.sh verify
   - bash scripts/handoff-backend.sh start
   - bash scripts/handoff-backend.sh smoke
   其中 verify = npm test + smoke-flow；除 `transcribe/create/train/archive/report` 写链路外，还会回读 `transcripts/training/ideas` 列表与 `bootstrap/reports-daily` 契约，并顺手校验 iOS 依赖字段；smoke 会轻量检查 provider/status、bootstrap、health、reports/daily 与报告页关键字段。
4. 如果你更想直接进 `app/` 目录，也可以：
   - cd ../app
   - bash scripts/start.sh
5. 如果要真机联调，先算出 Mac 的局域网地址：
   - bash scripts/resolve-local-ip.sh
6. 在 iOS App 设置页中：
   - 模拟器填 http://127.0.0.1:4321
   - 真机填上一步输出的 http://局域网IP:4321
EOF
else
  cat >> "$BUNDLE_DIR/HANDOFF-README.md" <<'EOF'
本包当前只含 ios-app。若要完整闭环，请把项目同级 app/ 后端目录也一起带到 Mac，或重新在原环境先进入 `ios-app/` 再执行：
- bash scripts/package-mac-handoff.sh
EOF
fi

cat >> "$BUNDLE_DIR/HANDOFF-README.md" <<'EOF'

## 重点说明
- 只拿 ios-app 也能完成编译、Mock 演示、基础真机安装。
- 要跑真实转写 / 优化 / 训练闭环，还需要同级 app/ 后端。
- 这个交接包默认不会带 .env / .env.local / node_modules / .venv / runtime 日志，避免把本地缓存和敏感配置一并塞过去。
- app/scripts/*.sh 现已改成相对路径解析；只要保留 ios-app/ 与 app/ 的相对关系，拿到任意 Mac 目录也能直接跑。
- 如首编失败，优先回看 `build/mac-env-check.log`、`build/xcodebuild-smoke.log`、`build/xcodebuild-smoke.xcresult`。
EOF

if [[ ! -s "$BUNDLE_DIR/HANDOFF-README.md" ]]; then
  echo "打包失败：HANDOFF-README.md 未生成或为空，无法作为完整 Mac 交接包交付。" >&2
  exit 1
fi

tar -C "$STAGE_ROOT" -czf "$TAR_ARCHIVE" "$BUNDLE_NAME"

require_tar_entry() {
  local entry="$1"
  if ! tar -tzf "$TAR_ARCHIVE" "$entry" >/dev/null 2>&1; then
    echo "打包失败：最终 Mac 交接包缺少 $entry，请先检查打包流程。" >&2
    exit 1
  fi
}

require_zip_entry() {
  local entry="$1"
  python3 - "$ZIP_ARCHIVE" "$entry" <<'PY'
import sys
import zipfile

archive, entry = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(archive) as zf:
    if entry not in zf.namelist():
        print(f"打包失败：最终 Mac 交接包 ZIP 缺少 {entry}，请先检查打包流程。", file=sys.stderr)
        sys.exit(1)
PY
}

for required_tar_entry in \
  "$BUNDLE_NAME/HANDOFF-README.md" \
  "$BUNDLE_NAME/ios-app/STATUS.md" \
  "$BUNDLE_NAME/ios-app/README.md" \
  "$BUNDLE_NAME/ios-app/Mac-环境安装清单.md" \
  "$BUNDLE_NAME/ios-app/Mac-首编手册.md" \
  "$BUNDLE_NAME/ios-app/Mac-编译失败排障.md" \
  "$BUNDLE_NAME/ios-app/scripts/check-ios-project.sh" \
  "$BUNDLE_NAME/ios-app/scripts/mac-env-check.sh" \
  "$BUNDLE_NAME/ios-app/scripts/mac-first-run.sh" \
  "$BUNDLE_NAME/ios-app/scripts/configure-signing.sh" \
  "$BUNDLE_NAME/ios-app/scripts/handoff-backend.sh" \
  "$BUNDLE_NAME/ios-app/scripts/smoke-backend.sh" \
  "$BUNDLE_NAME/ios-app/scripts/package-ios-app.sh" \
  "$BUNDLE_NAME/ios-app/scripts/package-mac-handoff.sh" \
  "$BUNDLE_NAME/ios-app/scripts/xcodebuild-smoke.sh" \
  "$BUNDLE_NAME/ios-app/scripts/resolve-local-ip.sh" \
  "$BUNDLE_NAME/ios-app/Config/Info.plist" \
  "$BUNDLE_NAME/ios-app/ChuKouChengZhang.xcodeproj/project.pbxproj" \
  "$BUNDLE_NAME/ios-app/ChuKouChengZhang.xcodeproj/xcshareddata/xcschemes/ChuKouChengZhang.xcscheme"
do
  require_tar_entry "$required_tar_entry"
done

if [[ "$backend_included" == "yes" ]]; then
  require_tar_entry "$BUNDLE_NAME/app/package.json"
  require_tar_entry "$BUNDLE_NAME/app/.env.example"
  require_tar_entry "$BUNDLE_NAME/app/config/llm-profiles.example.json"
  require_tar_entry "$BUNDLE_NAME/app/README.md"
  require_tar_entry "$BUNDLE_NAME/app/src/server.js"
  require_tar_entry "$BUNDLE_NAME/app/src/load-env.js"
  require_tar_entry "$BUNDLE_NAME/app/scripts/start.sh"
  require_tar_entry "$BUNDLE_NAME/app/scripts/status.sh"
  require_tar_entry "$BUNDLE_NAME/app/scripts/stop.sh"
  require_tar_entry "$BUNDLE_NAME/app/scripts/smoke-api-flow.sh"
  require_tar_entry "$BUNDLE_NAME/app/scripts/smoke-http-provider.sh"
  require_tar_entry "$BUNDLE_NAME/app/scripts/setup-local-stt.sh"
  require_tar_entry "$BUNDLE_NAME/app/scripts/faster_whisper_transcribe.py"
  require_tar_entry "$BUNDLE_NAME/app/scripts/faster_whisper_warmup.py"
fi

if command -v zip >/dev/null 2>&1; then
  (
    cd "$STAGE_ROOT"
    zip -qr "$ZIP_ARCHIVE" "$BUNDLE_NAME"
  )

  for required_zip_entry in \
    "$BUNDLE_NAME/HANDOFF-README.md" \
    "$BUNDLE_NAME/ios-app/STATUS.md" \
    "$BUNDLE_NAME/ios-app/README.md" \
    "$BUNDLE_NAME/ios-app/Mac-环境安装清单.md" \
    "$BUNDLE_NAME/ios-app/Mac-首编手册.md" \
    "$BUNDLE_NAME/ios-app/Mac-编译失败排障.md" \
    "$BUNDLE_NAME/ios-app/scripts/check-ios-project.sh" \
    "$BUNDLE_NAME/ios-app/scripts/mac-env-check.sh" \
    "$BUNDLE_NAME/ios-app/scripts/mac-first-run.sh" \
    "$BUNDLE_NAME/ios-app/scripts/configure-signing.sh" \
    "$BUNDLE_NAME/ios-app/scripts/handoff-backend.sh" \
    "$BUNDLE_NAME/ios-app/scripts/smoke-backend.sh" \
    "$BUNDLE_NAME/ios-app/scripts/package-ios-app.sh" \
    "$BUNDLE_NAME/ios-app/scripts/package-mac-handoff.sh" \
    "$BUNDLE_NAME/ios-app/scripts/xcodebuild-smoke.sh" \
    "$BUNDLE_NAME/ios-app/scripts/resolve-local-ip.sh" \
    "$BUNDLE_NAME/ios-app/Config/Info.plist" \
    "$BUNDLE_NAME/ios-app/ChuKouChengZhang.xcodeproj/project.pbxproj" \
    "$BUNDLE_NAME/ios-app/ChuKouChengZhang.xcodeproj/xcshareddata/xcschemes/ChuKouChengZhang.xcscheme"
  do
    require_zip_entry "$required_zip_entry"
  done

  if [[ "$backend_included" == "yes" ]]; then
    require_zip_entry "$BUNDLE_NAME/app/package.json"
    require_zip_entry "$BUNDLE_NAME/app/.env.example"
    require_zip_entry "$BUNDLE_NAME/app/config/llm-profiles.example.json"
    require_zip_entry "$BUNDLE_NAME/app/README.md"
    require_zip_entry "$BUNDLE_NAME/app/src/server.js"
    require_zip_entry "$BUNDLE_NAME/app/src/load-env.js"
    require_zip_entry "$BUNDLE_NAME/app/scripts/start.sh"
    require_zip_entry "$BUNDLE_NAME/app/scripts/status.sh"
    require_zip_entry "$BUNDLE_NAME/app/scripts/stop.sh"
    require_zip_entry "$BUNDLE_NAME/app/scripts/smoke-api-flow.sh"
    require_zip_entry "$BUNDLE_NAME/app/scripts/smoke-http-provider.sh"
    require_zip_entry "$BUNDLE_NAME/app/scripts/setup-local-stt.sh"
    require_zip_entry "$BUNDLE_NAME/app/scripts/faster_whisper_transcribe.py"
    require_zip_entry "$BUNDLE_NAME/app/scripts/faster_whisper_warmup.py"
  fi
fi

if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$TAR_ARCHIVE" > "$TAR_ARCHIVE.sha256"
  if [[ -f "$ZIP_ARCHIVE" ]]; then
    sha256sum "$ZIP_ARCHIVE" > "$ZIP_ARCHIVE.sha256"
  fi
fi

echo "HANDOFF TAR: $TAR_ARCHIVE"
if [[ -f "$ZIP_ARCHIVE" ]]; then
  echo "HANDOFF ZIP: $ZIP_ARCHIVE"
fi
if [[ -f "$TAR_ARCHIVE.sha256" ]]; then
  echo "SHA256: $TAR_ARCHIVE.sha256"
fi
if [[ -f "$ZIP_ARCHIVE.sha256" ]]; then
  echo "SHA256: $ZIP_ARCHIVE.sha256"
fi

echo
echo "交接包已生成。拿到 Mac 后，先看包内 HANDOFF-README.md。"
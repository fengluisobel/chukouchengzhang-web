#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT/dist"
STAMP="$(date +%Y%m%d-%H%M%S)"
TAR_ARCHIVE="$OUT_DIR/chukouchengzhang-ios-app-$STAMP.tar.gz"
ZIP_ARCHIVE="$OUT_DIR/chukouchengzhang-ios-app-$STAMP.zip"

mkdir -p "$OUT_DIR"

bash "$ROOT/scripts/check-ios-project.sh"

tar \
  --exclude='dist' \
  --exclude='build' \
  --exclude='DerivedData' \
  --exclude='*.xcuserstate' \
  --exclude='xcuserdata' \
  --exclude='.DS_Store' \
  -czf "$TAR_ARCHIVE" \
  -C "$ROOT" \
  .

require_tar_entry() {
  local entry="$1"
  if ! tar -tzf "$TAR_ARCHIVE" "$entry" >/dev/null 2>&1; then
    echo "打包失败：iOS-only 归档缺少 $entry，请先检查 package-ios-app.sh 的 exclude 逻辑。" >&2
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
        print(f"打包失败：iOS-only ZIP 归档缺少 {entry}，请先检查 package-ios-app.sh 的打包逻辑。", file=sys.stderr)
        sys.exit(1)
PY
}

for required_entry in \
  "./STATUS.md" \
  "./README.md" \
  "./Mac-环境安装清单.md" \
  "./Mac-首编手册.md" \
  "./Mac-编译失败排障.md" \
  "./scripts/mac-env-check.sh" \
  "./scripts/mac-first-run.sh" \
  "./scripts/check-ios-project.sh" \
  "./scripts/configure-signing.sh" \
  "./scripts/handoff-backend.sh" \
  "./scripts/smoke-backend.sh" \
  "./scripts/package-ios-app.sh" \
  "./scripts/package-mac-handoff.sh" \
  "./scripts/resolve-local-ip.sh" \
  "./scripts/xcodebuild-smoke.sh" \
  "./Config/Info.plist" \
  "./ChuKouChengZhang.xcodeproj/project.pbxproj" \
  "./ChuKouChengZhang.xcodeproj/xcshareddata/xcschemes/ChuKouChengZhang.xcscheme"
  do
  require_tar_entry "$required_entry"
done

if command -v zip >/dev/null 2>&1; then
  (
    cd "$ROOT"
    zip -qr "$ZIP_ARCHIVE" . -x 'dist/*' -x 'build/*' -x 'DerivedData/*' -x '*.xcuserstate' -x 'xcuserdata/*' -x '*.DS_Store'
  )

  for required_entry in \
    "STATUS.md" \
    "README.md" \
    "Mac-环境安装清单.md" \
    "Mac-首编手册.md" \
    "Mac-编译失败排障.md" \
    "scripts/mac-env-check.sh" \
    "scripts/mac-first-run.sh" \
    "scripts/check-ios-project.sh" \
    "scripts/configure-signing.sh" \
    "scripts/handoff-backend.sh" \
    "scripts/smoke-backend.sh" \
    "scripts/package-ios-app.sh" \
    "scripts/package-mac-handoff.sh" \
    "scripts/resolve-local-ip.sh" \
    "scripts/xcodebuild-smoke.sh" \
    "Config/Info.plist" \
    "ChuKouChengZhang.xcodeproj/project.pbxproj" \
    "ChuKouChengZhang.xcodeproj/xcshareddata/xcschemes/ChuKouChengZhang.xcscheme"
    do
    require_zip_entry "$required_entry"
  done
fi

if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$TAR_ARCHIVE" > "$TAR_ARCHIVE.sha256"
  if [[ -f "$ZIP_ARCHIVE" ]]; then
    sha256sum "$ZIP_ARCHIVE" > "$ZIP_ARCHIVE.sha256"
  fi
fi

echo "TAR: $TAR_ARCHIVE"
if [[ -f "$ZIP_ARCHIVE" ]]; then
  echo "ZIP: $ZIP_ARCHIVE"
fi
if [[ -f "$TAR_ARCHIVE.sha256" ]]; then
  echo "SHA256: $TAR_ARCHIVE.sha256"
fi
if [[ -f "$ZIP_ARCHIVE.sha256" ]]; then
  echo "SHA256: $ZIP_ARCHIVE.sha256"
fi
echo "说明：这个归档只包含 ios-app。若要把同级 app/ 后端也一起打成 Mac 交接包，请改用 bash scripts/package-mac-handoff.sh"

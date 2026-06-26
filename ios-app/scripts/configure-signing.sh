#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_FILE="$ROOT/ChuKouChengZhang.xcodeproj/project.pbxproj"
INFO_PLIST="$ROOT/Config/Info.plist"

usage() {
  cat <<'EOF'
用法：
  bash scripts/configure-signing.sh --team TEAMID --bundle-id com.yourname.chukouchengzhang
  bash scripts/configure-signing.sh --team TEAMID --bundle-id com.yourname.chukouchengzhang --release-base-url https://api.example.com
  bash scripts/configure-signing.sh --show

说明：
- 用来在 Mac 上一次性把 Team / Bundle Identifier / 可选正式服地址写进工程。
- 会先自动备份：
  - ChuKouChengZhang.xcodeproj/project.pbxproj.bak-时间戳
  - Config/Info.plist.bak-时间戳
EOF
}

show_current() {
  python3 - "$PROJECT_FILE" "$INFO_PLIST" <<'PY'
import pathlib
import plistlib
import re
import sys

project = pathlib.Path(sys.argv[1]).read_text(encoding='utf-8')
plist_path = pathlib.Path(sys.argv[2])
plist = plistlib.loads(plist_path.read_bytes())

team_match = re.search(r'DEVELOPMENT_TEAM = "([^"]*)";', project)
bundle_match = re.search(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);', project)
release_url = plist.get('CKCZReleaseBaseURL', '')

print(f"当前 Team: {team_match.group(1) if team_match else '(未找到)'}")
print(f"当前 Bundle Identifier: {bundle_match.group(1).strip() if bundle_match else '(未找到)'}")
print(f"当前 CKCZReleaseBaseURL: {release_url or '(空)'}")
PY
}

TEAM_ID=""
BUNDLE_ID=""
RELEASE_BASE_URL=""
SHOW_ONLY=0

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
    --show)
      SHOW_ONLY=1
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

if [[ ! -f "$PROJECT_FILE" ]]; then
  echo "缺少工程文件：$PROJECT_FILE" >&2
  exit 1
fi

if [[ ! -f "$INFO_PLIST" ]]; then
  echo "缺少 Info.plist：$INFO_PLIST" >&2
  exit 1
fi

if [[ $SHOW_ONLY -eq 1 ]]; then
  show_current
  exit 0
fi

if [[ -z "$TEAM_ID" && -z "$BUNDLE_ID" && -z "$RELEASE_BASE_URL" ]]; then
  usage >&2
  echo >&2
  show_current >&2
  exit 1
fi

if [[ -n "$BUNDLE_ID" ]]; then
  if [[ ! "$BUNDLE_ID" =~ ^[A-Za-z0-9.-]+$ ]]; then
    echo "Bundle Identifier 格式不合法：$BUNDLE_ID" >&2
    exit 1
  fi
fi

if [[ -n "$RELEASE_BASE_URL" ]]; then
  if [[ ! "$RELEASE_BASE_URL" =~ ^https?:// ]]; then
    echo "--release-base-url 必须以 http:// 或 https:// 开头。" >&2
    exit 1
  fi
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
cp "$PROJECT_FILE" "$PROJECT_FILE.bak-$STAMP"
cp "$INFO_PLIST" "$INFO_PLIST.bak-$STAMP"

python3 - "$PROJECT_FILE" "$TEAM_ID" "$BUNDLE_ID" "$INFO_PLIST" "$RELEASE_BASE_URL" <<'PY'
import pathlib
import plistlib
import re
import sys

project_path = pathlib.Path(sys.argv[1])
team_id = sys.argv[2]
bundle_id = sys.argv[3]
plist_path = pathlib.Path(sys.argv[4])
release_base_url = sys.argv[5]

text = project_path.read_text(encoding='utf-8')

if team_id:
  text, count = re.subn(r'DEVELOPMENT_TEAM = "[^"]*";', f'DEVELOPMENT_TEAM = "{team_id}";', text)
  if count == 0:
    raise SystemExit('没有找到 DEVELOPMENT_TEAM，可手动检查 project.pbxproj')

if bundle_id:
  text, count = re.subn(r'PRODUCT_BUNDLE_IDENTIFIER = [^;]+;', f'PRODUCT_BUNDLE_IDENTIFIER = {bundle_id};', text)
  if count == 0:
    raise SystemExit('没有找到 PRODUCT_BUNDLE_IDENTIFIER，可手动检查 project.pbxproj')

project_path.write_text(text, encoding='utf-8')

if release_base_url:
  plist = plistlib.loads(plist_path.read_bytes())
  plist['CKCZReleaseBaseURL'] = release_base_url
  plist_path.write_bytes(plistlib.dumps(plist, fmt=plistlib.FMT_XML))
PY

echo "已更新工程配置。"
show_current

echo
if [[ -n "$TEAM_ID" ]]; then
  echo "下一步建议：在 Mac 上执行 xcodebuild 烟测"
  echo "  bash scripts/xcodebuild-smoke.sh"
else
  echo "下一步建议：进 Xcode 检查 Signing & Capabilities 是否已就绪。"
fi

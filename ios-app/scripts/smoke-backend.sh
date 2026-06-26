#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-http://127.0.0.1:4321}"

assert_provider_contract() {
  local payload="$1"
  python3 - "$payload" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
if not isinstance(payload, dict):
    raise SystemExit("provider/status 返回不是 JSON 对象")

required = ["ok", "provider", "checkedAt"]
missing = [key for key in required if key not in payload]
if missing:
    raise SystemExit(f"provider/status 返回缺少关键字段: {', '.join(missing)}")
PY
}

assert_bootstrap_contract() {
  local payload="$1"
  python3 - "$payload" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
if not isinstance(payload, dict):
    raise SystemExit("bootstrap 返回不是 JSON 对象")

required = ["providerStatus", "transcripts", "ideas", "report"]
missing = [key for key in required if key not in payload]
if missing:
    raise SystemExit(f"bootstrap 返回缺少顶层字段: {', '.join(missing)}")

provider_status = payload.get("providerStatus")
if not isinstance(provider_status, dict):
    raise SystemExit("bootstrap.providerStatus 返回不是 JSON 对象")

provider_required = ["ok", "provider", "checkedAt"]
provider_missing = [key for key in provider_required if key not in provider_status]
if provider_missing:
    raise SystemExit(f"bootstrap.providerStatus 返回缺少关键字段: {', '.join(provider_missing)}")

transcripts = payload.get("transcripts")
if not isinstance(transcripts, list):
    raise SystemExit("bootstrap.transcripts 返回不是 JSON 数组")

ideas = payload.get("ideas")
if not isinstance(ideas, list):
    raise SystemExit("bootstrap.ideas 返回不是 JSON 数组")

report = payload.get("report")
if not isinstance(report, dict):
    raise SystemExit("bootstrap.report 返回不是 JSON 对象")

report_required = [
    "totalWords",
    "transcribeCount",
    "trainingCount",
    "polishCount",
    "catchphraseCount",
    "speechInputCount",
    "bestSentence",
]
report_missing = [key for key in report_required if key not in report]
if report_missing:
    raise SystemExit(f"bootstrap.report 返回缺少关键字段: {', '.join(report_missing)}")
PY
}

assert_health_contract() {
  local payload="$1"
  python3 - "$payload" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
if not isinstance(payload, dict):
    raise SystemExit("health 返回不是 JSON 对象")

required = ["ok", "service", "provider"]
missing = [key for key in required if key not in payload]
if missing:
    raise SystemExit(f"health 返回缺少关键字段: {', '.join(missing)}")
PY
}

assert_daily_report_contract() {
  local payload="$1"
  python3 - "$payload" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
if not isinstance(payload, dict):
    raise SystemExit("reports/daily 返回不是 JSON 对象")

required = [
    "totalWords",
    "transcribeCount",
    "trainingCount",
    "polishCount",
    "catchphraseCount",
    "speechInputCount",
    "bestSentence",
]
missing = [key for key in required if key not in payload]
if missing:
    raise SystemExit(f"reports/daily 返回缺少关键字段: {', '.join(missing)}")
PY
}

echo "[1/4] provider status => $BASE_URL/api/provider/status"
provider_json="$(curl -fsSL "$BASE_URL/api/provider/status")"
printf '%s\n' "$provider_json" | sed -n '1,120p'
assert_provider_contract "$provider_json"
echo "[OK] provider/status 已包含 ok / provider / checkedAt"

echo
echo "[2/4] bootstrap => $BASE_URL/api/bootstrap"
bootstrap_json="$(curl -fsSL "$BASE_URL/api/bootstrap")"
printf '%s\n' "$bootstrap_json" | sed -n '1,160p'
assert_bootstrap_contract "$bootstrap_json"
echo "[OK] bootstrap 已包含 providerStatus / transcripts / ideas / report，且 report 关键字段齐全"

echo
echo "[3/4] health => $BASE_URL/api/health"
health_json="$(curl -fsSL "$BASE_URL/api/health")"
printf '%s\n' "$health_json" | sed -n '1,80p'
assert_health_contract "$health_json"
echo "[OK] health 已包含 ok / service / provider"

echo
echo "[4/4] daily report => $BASE_URL/api/reports/daily"
daily_report_json="$(curl -fsSL "$BASE_URL/api/reports/daily")"
printf '%s\n' "$daily_report_json" | sed -n '1,120p'
assert_daily_report_contract "$daily_report_json"
echo "[OK] reports/daily 已包含 totalWords / transcribeCount / trainingCount / polishCount / catchphraseCount / speechInputCount / bestSentence"

echo
echo "后端烟测通过。模拟器可直接填 $BASE_URL；若要真机联调，再跑 bash scripts/resolve-local-ip.sh 取局域网地址。"

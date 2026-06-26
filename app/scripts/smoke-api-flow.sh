#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ckcz-smoke-flow.XXXXXX")"
DATA_FILE="$TMP_DIR/store.json"
LOG_FILE="$TMP_DIR/app.log"
PORT="${PORT:-$(node -e "const net=require('node:net'); const server=net.createServer(); server.listen(0,'127.0.0.1',()=>{const port=server.address().port; server.close(()=>process.stdout.write(String(port)));});")}"
BASE_URL="http://127.0.0.1:$PORT"
SERVER_PID=""

if curl -fsS "$BASE_URL/api/health" >/dev/null 2>&1; then
  echo "端口 $PORT 已有服务在跑。为避免把 smoke-flow 请求打到现有实例，本脚本拒绝继续。" >&2
  echo "请直接执行 bash app/scripts/smoke-api-flow.sh（使用随机空闲端口），或显式换一个未占用的 PORT。" >&2
  exit 1
fi

usage() {
  cat <<'EOF'
用法：
  bash app/scripts/smoke-api-flow.sh
  PORT=4521 bash app/scripts/smoke-api-flow.sh

说明：
- 该脚本会用临时 store 启动一个隔离的 app 实例，不污染现有 data/store.json。
- 会串行验证：health → provider/status → bootstrap → transcribe → transcripts/create → transcripts(list) → train/evaluate → training(list) → ideas/archive → ideas(list) → reports/daily。
- 适合在 Mac 上拿到交接包后，先确认后端 API 契约主链路仍然是通的。
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

cleanup() {
  if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" >/dev/null 2>&1; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

wait_for_health() {
  local deadline=$((SECONDS + 20))
  while (( SECONDS < deadline )); do
    if curl -fsS "$BASE_URL/api/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  echo "隔离 smoke server 未在 20s 内就绪：$BASE_URL/api/health" >&2
  echo "日志：$LOG_FILE" >&2
  exit 1
}

json_get() {
  local expr="$1"
  node -e "const fs=require('node:fs'); const input=fs.readFileSync(0,'utf8'); const data=JSON.parse(input); const value=(function(){ return ${expr}; })(); if (value === undefined || value === null) process.exit(3); if (typeof value === 'object') process.stdout.write(JSON.stringify(value)); else process.stdout.write(String(value));"
}

request_json() {
  local method="$1"
  local path="$2"
  local body="${3:-}"

  if [[ -n "$body" ]]; then
    curl -fsS -X "$method" "$BASE_URL$path" \
      -H 'Content-Type: application/json' \
      --data "$body"
  else
    curl -fsS -X "$method" "$BASE_URL$path"
  fi
}

cd "$APP_DIR"
env PORT="$PORT" CKCZ_DATA_FILE="$DATA_FILE" node src/server.js > "$LOG_FILE" 2>&1 &
SERVER_PID="$!"
wait_for_health

echo "[1/11] health => $BASE_URL/api/health"
health_json="$(request_json GET /api/health)"
printf '%s\n' "$health_json"
provider_name="$(printf '%s' "$health_json" | json_get 'data.provider')"

printf '\n[2/11] provider status => %s/api/provider/status\n' "$BASE_URL"
provider_json="$(request_json GET /api/provider/status)"
printf '%s\n' "$provider_json"
provider_ok="$(printf '%s' "$provider_json" | json_get 'data.ok')"
provider_checked_at="$(printf '%s' "$provider_json" | json_get 'data.checkedAt')"
provider_status_provider="$(printf '%s' "$provider_json" | json_get 'data.provider')"
if [[ "$provider_ok" != "true" ]]; then
  echo "provider/status 未返回 ok=true" >&2
  exit 1
fi
if [[ -z "$provider_checked_at" ]]; then
  echo "provider/status 返回缺少 checkedAt。" >&2
  exit 1
fi
if [[ -z "$provider_status_provider" ]]; then
  echo "provider/status 返回缺少 provider。" >&2
  exit 1
fi

printf '\n[3/11] bootstrap => %s/api/bootstrap\n' "$BASE_URL"
bootstrap_before="$(request_json GET /api/bootstrap)"
printf '%s\n' "$bootstrap_before"
bootstrap_before_provider_ok="$(printf '%s' "$bootstrap_before" | json_get 'data.providerStatus.ok')"
bootstrap_before_provider_name="$(printf '%s' "$bootstrap_before" | json_get 'data.providerStatus.provider')"
bootstrap_before_provider_checked_at="$(printf '%s' "$bootstrap_before" | json_get 'data.providerStatus.checkedAt')"
bootstrap_before_transcripts="$(printf '%s' "$bootstrap_before" | json_get 'data.transcripts.length')"
bootstrap_before_ideas="$(printf '%s' "$bootstrap_before" | json_get 'data.ideas.length')"
bootstrap_before_report_transcribe="$(printf '%s' "$bootstrap_before" | json_get 'data.report.transcribeCount')"
bootstrap_before_report_speech="$(printf '%s' "$bootstrap_before" | json_get 'data.report.speechInputCount')"
if [[ "$bootstrap_before_provider_ok" != "true" || -z "$bootstrap_before_provider_name" || -z "$bootstrap_before_provider_checked_at" ]]; then
  echo "bootstrap.providerStatus 契约异常：ok=$bootstrap_before_provider_ok provider=$bootstrap_before_provider_name checkedAt=$bootstrap_before_provider_checked_at" >&2
  exit 1
fi
if [[ "$bootstrap_before_transcripts" != "0" || "$bootstrap_before_ideas" != "0" || "$bootstrap_before_report_transcribe" != "0" || "$bootstrap_before_report_speech" != "0" ]]; then
  echo "bootstrap(before) 初始计数异常：transcripts=$bootstrap_before_transcripts ideas=$bootstrap_before_ideas transcribeCount=$bootstrap_before_report_transcribe speechInputCount=$bootstrap_before_report_speech" >&2
  exit 1
fi

transcribe_body='{"rawText":"这段语音转写主要用于验证 iOS 训练页依赖的 transcribe 返回结构。","scene":"interview","inputSource":"speech","captureMeta":{"durationSeconds":4.2,"source":"smoke-api-flow"}}'
printf '\n[4/11] transcribe => %s/api/transcribe\n' "$BASE_URL"
transcribe_json="$(request_json POST /api/transcribe "$transcribe_body")"
printf '%s\n' "$transcribe_json"
transcribe_text="$(printf '%s' "$transcribe_json" | json_get 'data.text')"
transcribe_language="$(printf '%s' "$transcribe_json" | json_get 'data.language')"
transcribe_scene="$(printf '%s' "$transcribe_json" | json_get 'data.scene')"
transcribe_input_source="$(printf '%s' "$transcribe_json" | json_get 'data.inputSource')"
transcribe_provider="$(printf '%s' "$transcribe_json" | json_get 'data.provider')"
transcribe_duration="$(printf '%s' "$transcribe_json" | json_get 'data.duration')"
transcribe_capture_source="$(printf '%s' "$transcribe_json" | json_get 'data.captureMeta.source')"
transcribe_segments_json="$(printf '%s' "$transcribe_json" | json_get 'data.segments')"
if [[ -z "$transcribe_text" || -z "$transcribe_language" || -z "$transcribe_provider" || -z "$transcribe_duration" ]]; then
  echo "transcribe 返回缺少 iOS 端依赖的关键字段。" >&2
  exit 1
fi
if [[ "$transcribe_scene" != "interview" || "$transcribe_input_source" != "speech" ]]; then
  echo "transcribe 返回的 scene/inputSource 异常：scene=$transcribe_scene inputSource=$transcribe_input_source" >&2
  exit 1
fi
if [[ "$transcribe_capture_source" != "smoke-api-flow" || "$transcribe_segments_json" != "[]" ]]; then
  echo "transcribe 返回的 captureMeta/segments 异常：source=$transcribe_capture_source segments=$transcribe_segments_json" >&2
  exit 1
fi

create_body='{"rawText":"今天我想把出口成章做成一个拿到 Mac 就能尽快编译、联调并开始真机验证的 iOS App。","scene":"idea","mode":"concise","inputSource":"text","captureMeta":{"capturedBy":"smoke-api-flow","platform":"isolated-temp-store"}}'
printf '\n[5/11] create transcript => %s/api/transcripts/create\n' "$BASE_URL"
create_json="$(request_json POST /api/transcripts/create "$create_body")"
printf '%s\n' "$create_json"
transcript_id="$(printf '%s' "$create_json" | json_get 'data.id')"
polished_text="$(printf '%s' "$create_json" | json_get 'data.polishedText')"
summary_title="$(printf '%s' "$create_json" | json_get 'data.summaryTitle')"
next_action="$(printf '%s' "$create_json" | json_get 'data.nextAction')"
transcript_provider="$(printf '%s' "$create_json" | json_get 'data.provider')"
transcript_input_source="$(printf '%s' "$create_json" | json_get 'data.inputSource')"
transcript_issue_count="$(printf '%s' "$create_json" | json_get 'data.issues.length')"
transcript_tag_count="$(printf '%s' "$create_json" | json_get 'data.suggestedTags.length')"
transcript_word_count="$(printf '%s' "$create_json" | json_get 'data.stats.wordCount')"
if [[ -z "$transcript_id" || -z "$polished_text" || -z "$summary_title" || -z "$next_action" || -z "$transcript_provider" ]]; then
  echo "transcripts/create 返回缺少 iOS 端依赖的关键字段。" >&2
  exit 1
fi
if [[ "$transcript_input_source" != "text" ]]; then
  echo "transcripts/create 的 inputSource 异常：$transcript_input_source" >&2
  exit 1
fi
if [[ "$transcript_issue_count" -lt 1 || "$transcript_tag_count" -lt 1 || "$transcript_word_count" -lt 1 ]]; then
  echo "transcripts/create 返回字段不完整：issues=$transcript_issue_count tags=$transcript_tag_count wordCount=$transcript_word_count" >&2
  exit 1
fi

printf '\n[6/11] transcripts list => %s/api/transcripts\n' "$BASE_URL"
transcripts_json="$(request_json GET /api/transcripts)"
printf '%s\n' "$transcripts_json"
transcripts_count="$(printf '%s' "$transcripts_json" | json_get 'data.length')"
transcripts_first_id="$(printf '%s' "$transcripts_json" | json_get 'data[0].id')"
transcripts_first_created_at="$(printf '%s' "$transcripts_json" | json_get 'data[0].createdAt')"
transcripts_first_scene="$(printf '%s' "$transcripts_json" | json_get 'data[0].scene')"
transcripts_first_mode="$(printf '%s' "$transcripts_json" | json_get 'data[0].mode')"
transcripts_first_raw_text="$(printf '%s' "$transcripts_json" | json_get 'data[0].rawText')"
transcripts_first_polished_text="$(printf '%s' "$transcripts_json" | json_get 'data[0].polishedText')"
transcripts_first_issues_count="$(printf '%s' "$transcripts_json" | json_get 'data[0].issues.length')"
transcripts_first_input_source="$(printf '%s' "$transcripts_json" | json_get 'data[0].inputSource')"
transcripts_first_summary_title="$(printf '%s' "$transcripts_json" | json_get 'data[0].summaryTitle')"
transcripts_first_tags_count="$(printf '%s' "$transcripts_json" | json_get 'data[0].suggestedTags.length')"
transcripts_first_next_action="$(printf '%s' "$transcripts_json" | json_get 'data[0].nextAction')"
transcripts_first_provider="$(printf '%s' "$transcripts_json" | json_get 'data[0].provider')"
if [[ "$transcripts_count" != "1" ]]; then
  echo "transcripts 列表返回条数异常：count=$transcripts_count" >&2
  exit 1
fi
if [[ -z "$transcripts_first_id" || -z "$transcripts_first_created_at" || -z "$transcripts_first_scene" || -z "$transcripts_first_mode" || -z "$transcripts_first_raw_text" || -z "$transcripts_first_polished_text" ]]; then
  echo "transcripts 列表返回缺少 TranscriptDTO 必需字段。" >&2
  exit 1
fi
if [[ -z "$transcripts_first_summary_title" || -z "$transcripts_first_next_action" || -z "$transcripts_first_provider" ]]; then
  echo "transcripts 列表返回缺少 iOS 结果页依赖字段。" >&2
  exit 1
fi
if [[ "$transcripts_first_id" != "$transcript_id" || "$transcripts_first_input_source" != "text" || "$transcripts_first_issues_count" -lt 1 || "$transcripts_first_tags_count" -lt 1 ]]; then
  echo "transcripts 列表返回的 id/inputSource/issues/tags 异常：id=$transcripts_first_id inputSource=$transcripts_first_input_source issues=$transcripts_first_issues_count tags=$transcripts_first_tags_count" >&2
  exit 1
fi

train_body="$(cat <<EOF
{"transcriptId":"$transcript_id","attemptText":"这个 App 会先在 Mac 上完成编译和签名，再跑后端闭环与真机录音验证。","round":1}
EOF
)"
printf '\n[7/11] training evaluate => %s/api/train/evaluate\n' "$BASE_URL"
train_json="$(request_json POST /api/train/evaluate "$train_body")"
printf '%s\n' "$train_json"
training_score="$(printf '%s' "$train_json" | json_get 'data.clarityScore')"
training_feedback="$(printf '%s' "$train_json" | json_get 'data.feedback')"
training_round="$(printf '%s' "$train_json" | json_get 'data.round')"
if [[ -z "$training_score" || -z "$training_feedback" ]]; then
  echo "train/evaluate 返回缺少 iOS 端依赖字段。" >&2
  exit 1
fi
if [[ "$training_round" != "1" ]]; then
  echo "train/evaluate round 异常：$training_round" >&2
  exit 1
fi

printf '\n[8/11] training list => %s/api/training?transcriptId=%s\n' "$BASE_URL" "$transcript_id"
training_list_json="$(request_json GET "/api/training?transcriptId=$transcript_id")"
printf '%s\n' "$training_list_json"
training_list_count="$(printf '%s' "$training_list_json" | json_get 'data.length')"
training_list_id="$(printf '%s' "$training_list_json" | json_get 'data[0].id')"
training_list_transcript_id="$(printf '%s' "$training_list_json" | json_get 'data[0].transcriptId')"
training_list_round="$(printf '%s' "$training_list_json" | json_get 'data[0].round')"
training_list_text="$(printf '%s' "$training_list_json" | json_get 'data[0].text')"
training_list_clarity="$(printf '%s' "$training_list_json" | json_get 'data[0].clarityScore')"
training_list_structure="$(printf '%s' "$training_list_json" | json_get 'data[0].structureScore')"
training_list_polish="$(printf '%s' "$training_list_json" | json_get 'data[0].polishScore')"
training_list_feedback="$(printf '%s' "$training_list_json" | json_get 'data[0].feedback')"
if [[ "$training_list_count" != "1" ]]; then
  echo "training 列表返回条数异常：count=$training_list_count" >&2
  exit 1
fi
if [[ -z "$training_list_id" || -z "$training_list_text" || -z "$training_list_feedback" || -z "$training_list_clarity" || -z "$training_list_structure" || -z "$training_list_polish" ]]; then
  echo "training 列表返回缺少 iOS 训练页依赖字段。" >&2
  exit 1
fi
if [[ "$training_list_transcript_id" != "$transcript_id" || "$training_list_round" != "1" ]]; then
  echo "training 列表返回的 transcriptId/round 异常：transcriptId=$training_list_transcript_id round=$training_list_round" >&2
  exit 1
fi

archive_body="$(cat <<EOF
{"transcriptId":"$transcript_id"}
EOF
)"
printf '\n[9/11] archive idea => %s/api/ideas/archive\n' "$BASE_URL"
archive_json="$(request_json POST /api/ideas/archive "$archive_body")"
printf '%s\n' "$archive_json"
archive_transcript_id="$(printf '%s' "$archive_json" | json_get 'data.transcriptId')"
if [[ "$archive_transcript_id" != "$transcript_id" ]]; then
  echo "ideas/archive 返回的 transcriptId 与刚创建的不一致。" >&2
  exit 1
fi

printf '\n[10/11] ideas list => %s/api/ideas\n' "$BASE_URL"
ideas_json="$(request_json GET /api/ideas)"
printf '%s\n' "$ideas_json"
ideas_count="$(printf '%s' "$ideas_json" | json_get 'data.length')"
idea_id="$(printf '%s' "$ideas_json" | json_get 'data[0].id')"
idea_transcript_id="$(printf '%s' "$ideas_json" | json_get 'data[0].transcriptId')"
idea_title="$(printf '%s' "$ideas_json" | json_get 'data[0].title')"
idea_raw_input="$(printf '%s' "$ideas_json" | json_get 'data[0].rawInput')"
idea_normalized_text="$(printf '%s' "$ideas_json" | json_get 'data[0].normalizedText')"
idea_category="$(printf '%s' "$ideas_json" | json_get 'data[0].category')"
idea_tags_count="$(printf '%s' "$ideas_json" | json_get 'data[0].tags.length')"
idea_next_action="$(printf '%s' "$ideas_json" | json_get 'data[0].nextAction')"
idea_status="$(printf '%s' "$ideas_json" | json_get 'data[0].status')"
idea_created_at="$(printf '%s' "$ideas_json" | json_get 'data[0].createdAt')"
if [[ "$ideas_count" != "1" ]]; then
  echo "ideas 列表返回条数异常：count=$ideas_count" >&2
  exit 1
fi
if [[ -z "$idea_id" || -z "$idea_title" || -z "$idea_raw_input" || -z "$idea_normalized_text" || -z "$idea_category" || -z "$idea_next_action" || -z "$idea_status" || -z "$idea_created_at" ]]; then
  echo "ideas 列表返回缺少 iOS 灵感库依赖字段。" >&2
  exit 1
fi
if [[ "$idea_transcript_id" != "$transcript_id" || "$idea_tags_count" -lt 1 ]]; then
  echo "ideas 列表返回的 transcriptId/tags 异常：transcriptId=$idea_transcript_id tags=$idea_tags_count" >&2
  exit 1
fi

printf '\n[11/11] report + bootstrap(after)\n'
report_json="$(request_json GET /api/reports/daily)"
printf '%s\n' "$report_json"
report_total_words="$(printf '%s' "$report_json" | json_get 'data.totalWords')"
report_transcribe_count="$(printf '%s' "$report_json" | json_get 'data.transcribeCount')"
report_training_count="$(printf '%s' "$report_json" | json_get 'data.trainingCount')"
report_polish_count="$(printf '%s' "$report_json" | json_get 'data.polishCount')"
report_catchphrase_count="$(printf '%s' "$report_json" | json_get 'data.catchphraseCount')"
report_speech_input_count="$(printf '%s' "$report_json" | json_get 'data.speechInputCount')"
report_best_sentence="$(printf '%s' "$report_json" | json_get 'data.bestSentence')"
bootstrap_after="$(request_json GET /api/bootstrap)"
printf '%s\n' "$bootstrap_after"
bootstrap_after_provider_ok="$(printf '%s' "$bootstrap_after" | json_get 'data.providerStatus.ok')"
bootstrap_after_provider_name="$(printf '%s' "$bootstrap_after" | json_get 'data.providerStatus.provider')"
bootstrap_after_provider_checked_at="$(printf '%s' "$bootstrap_after" | json_get 'data.providerStatus.checkedAt')"
bootstrap_transcripts="$(printf '%s' "$bootstrap_after" | json_get 'data.transcripts.length')"
bootstrap_ideas="$(printf '%s' "$bootstrap_after" | json_get 'data.ideas.length')"
bootstrap_after_transcript_id="$(printf '%s' "$bootstrap_after" | json_get 'data.transcripts[0].id')"
bootstrap_after_summary_title="$(printf '%s' "$bootstrap_after" | json_get 'data.transcripts[0].summaryTitle')"
bootstrap_after_provider="$(printf '%s' "$bootstrap_after" | json_get 'data.transcripts[0].provider')"
bootstrap_after_idea_id="$(printf '%s' "$bootstrap_after" | json_get 'data.ideas[0].id')"
bootstrap_after_idea_title="$(printf '%s' "$bootstrap_after" | json_get 'data.ideas[0].title')"
bootstrap_after_idea_next_action="$(printf '%s' "$bootstrap_after" | json_get 'data.ideas[0].nextAction')"
bootstrap_after_report_total_words="$(printf '%s' "$bootstrap_after" | json_get 'data.report.totalWords')"
bootstrap_after_report_transcribe="$(printf '%s' "$bootstrap_after" | json_get 'data.report.transcribeCount')"
bootstrap_after_report_training="$(printf '%s' "$bootstrap_after" | json_get 'data.report.trainingCount')"
bootstrap_after_report_polish="$(printf '%s' "$bootstrap_after" | json_get 'data.report.polishCount')"
bootstrap_after_report_catchphrase="$(printf '%s' "$bootstrap_after" | json_get 'data.report.catchphraseCount')"
bootstrap_after_report_speech="$(printf '%s' "$bootstrap_after" | json_get 'data.report.speechInputCount')"
bootstrap_after_report_best_sentence="$(printf '%s' "$bootstrap_after" | json_get 'data.report.bestSentence')"

if [[ -z "$report_total_words" || "$report_transcribe_count" != "1" || "$report_training_count" != "1" || -z "$report_polish_count" || -z "$report_catchphrase_count" || "$report_speech_input_count" != "0" ]]; then
  echo "reports/daily 契约异常：totalWords=$report_total_words transcribe=$report_transcribe_count training=$report_training_count polish=$report_polish_count catchphrase=$report_catchphrase_count speechInputCount=$report_speech_input_count" >&2
  exit 1
fi
if [[ -z "$report_best_sentence" ]]; then
  echo "reports/daily 缺少 bestSentence。" >&2
  exit 1
fi

if [[ "$bootstrap_after_provider_ok" != "true" || -z "$bootstrap_after_provider_name" || -z "$bootstrap_after_provider_checked_at" || "$bootstrap_transcripts" != "1" || "$bootstrap_ideas" != "1" ]]; then
  echo "bootstrap(after) 顶层状态异常：providerOk=$bootstrap_after_provider_ok provider=$bootstrap_after_provider_name checkedAt=$bootstrap_after_provider_checked_at transcripts=$bootstrap_transcripts ideas=$bootstrap_ideas" >&2
  exit 1
fi
if [[ "$bootstrap_after_transcript_id" != "$transcript_id" || -z "$bootstrap_after_summary_title" || -z "$bootstrap_after_provider" ]]; then
  echo "bootstrap(after) transcript 聚合结果异常：id=$bootstrap_after_transcript_id summaryTitle=$bootstrap_after_summary_title provider=$bootstrap_after_provider" >&2
  exit 1
fi
if [[ "$bootstrap_after_idea_id" != "$idea_id" || -z "$bootstrap_after_idea_title" || -z "$bootstrap_after_idea_next_action" ]]; then
  echo "bootstrap(after) idea 聚合结果异常：id=$bootstrap_after_idea_id title=$bootstrap_after_idea_title nextAction=$bootstrap_after_idea_next_action" >&2
  exit 1
fi
if [[ -z "$bootstrap_after_report_total_words" || "$bootstrap_after_report_transcribe" != "1" || "$bootstrap_after_report_training" != "1" || -z "$bootstrap_after_report_polish" || -z "$bootstrap_after_report_catchphrase" || "$bootstrap_after_report_speech" != "0" || -z "$bootstrap_after_report_best_sentence" ]]; then
  echo "bootstrap(after) report 聚合结果异常：totalWords=$bootstrap_after_report_total_words transcribe=$bootstrap_after_report_transcribe training=$bootstrap_after_report_training polish=$bootstrap_after_report_polish catchphrase=$bootstrap_after_report_catchphrase speechInputCount=$bootstrap_after_report_speech bestSentence=$bootstrap_after_report_best_sentence" >&2
  exit 1
fi

echo
echo "隔离后端全流程烟测通过。"
echo "provider=$provider_name transcriptId=$transcript_id clarityScore=$training_score"
echo "临时日志：$LOG_FILE（脚本退出后会自动清理）"

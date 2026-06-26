#!/usr/bin/env bash
set -euo pipefail

PORT="${CKCZ_PORT:-4321}"
FORMAT="plain"

usage() {
  cat <<'EOF'
用法：
  bash scripts/resolve-local-ip.sh
  bash scripts/resolve-local-ip.sh --port 4321
  bash scripts/resolve-local-ip.sh --format json

说明：
- 输出当前机器上可供 iPhone 真机联调填写的候选局域网地址。
- 模拟器仍然优先用 http://127.0.0.1:4321
- 真机不要填 127.0.0.1，要填这里输出的 http://局域网IP:端口
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)
      PORT="${2:-}"
      shift 2
      ;;
    --format)
      FORMAT="${2:-}"
      shift 2
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

if [[ ! "$PORT" =~ ^[0-9]+$ ]]; then
  echo "端口必须是数字：$PORT" >&2
  exit 1
fi

collect_ips() {
  if command -v ip >/dev/null 2>&1; then
    ip -4 addr show up scope global | awk '/inet / {print $2}' | cut -d/ -f1
    return
  fi

  if [[ "$(uname -s)" == "Darwin" ]]; then
    for iface in en0 en1 en2 bridge100; do
      if command -v ipconfig >/dev/null 2>&1; then
        ipconfig getifaddr "$iface" 2>/dev/null || true
      fi
    done
    return
  fi

  if command -v hostname >/dev/null 2>&1; then
    hostname -I 2>/dev/null | tr ' ' '\n'
    return
  fi
}

mapfile -t ips < <(collect_ips | sed '/^$/d' | awk '!seen[$0]++')

if [[ ${#ips[@]} -eq 0 ]]; then
  echo "没有找到可用的非回环 IPv4 地址。请确认当前机器已连上局域网。" >&2
  exit 1
fi

case "$FORMAT" in
  plain)
    echo "模拟器： http://127.0.0.1:$PORT"
    echo "真机候选："
    for ip in "${ips[@]}"; do
      echo "- http://$ip:$PORT"
    done
    ;;
  json)
    printf '{\n  "simulator": "http://127.0.0.1:%s",\n  "deviceCandidates": [\n' "$PORT"
    for i in "${!ips[@]}"; do
      suffix=','
      if [[ $i -eq $((${#ips[@]} - 1)) ]]; then
        suffix=''
      fi
      printf '    "http://%s:%s"%s\n' "${ips[$i]}" "$PORT" "$suffix"
    done
    printf '  ]\n}\n'
    ;;
  *)
    echo "不支持的 format：$FORMAT" >&2
    exit 1
    ;;
esac
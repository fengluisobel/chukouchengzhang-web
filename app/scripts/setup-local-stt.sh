#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VENV_DIR="$ROOT_DIR/.venv"
PYTHON_BIN=${PYTHON_BIN:-python3}
MODE=${MODE:-auto}
WARMUP=${WARMUP:-1}
WARMUP_SCRIPT="$ROOT_DIR/scripts/faster_whisper_warmup.py"

run_warmup() {
  if [ "$WARMUP" != "1" ]; then
    return 0
  fi
  echo "开始预热 faster-whisper 模型（首次可能较慢）..."
  "$1" "$WARMUP_SCRIPT"
}

install_with_user_site() {
  "$PYTHON_BIN" -m pip install --user --break-system-packages --upgrade pip
  "$PYTHON_BIN" -m pip install --user --break-system-packages -r "$ROOT_DIR/requirements-local-stt.txt"
  run_warmup "$PYTHON_BIN"
  echo "本地 STT 环境已安装（user-site 模式）。"
  echo "建议写入 $ROOT_DIR/.env.local："
  echo "CKCZ_STT_PYTHON=$PYTHON_BIN"
}

install_with_venv() {
  if [ ! -d "$VENV_DIR" ]; then
    "$PYTHON_BIN" -m venv "$VENV_DIR"
  fi

  "$VENV_DIR/bin/python" -m pip install --upgrade pip
  "$VENV_DIR/bin/pip" install -r "$ROOT_DIR/requirements-local-stt.txt"
  run_warmup "$VENV_DIR/bin/python"
  echo "本地 STT 环境已安装（venv 模式）。"
  echo "建议写入 $ROOT_DIR/.env.local："
  echo "CKCZ_STT_PYTHON=$VENV_DIR/bin/python"
}

if [ "$MODE" = "user" ]; then
  install_with_user_site
  exit 0
fi

if [ "$MODE" = "venv" ]; then
  install_with_venv
  exit 0
fi

if "$PYTHON_BIN" -m venv "$VENV_DIR" >/dev/null 2>&1; then
  install_with_venv
else
  echo "检测到当前环境不可用 python venv，自动回退到 user-site 安装。"
  install_with_user_site
fi

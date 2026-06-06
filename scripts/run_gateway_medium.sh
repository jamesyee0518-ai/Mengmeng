#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export LMSTUDIO_ENABLED="${LMSTUDIO_ENABLED:-1}"
export LMSTUDIO_BASE_URL="${LMSTUDIO_BASE_URL:-http://127.0.0.1:1234/v1}"
export LMSTUDIO_MODEL="${LMSTUDIO_MODEL:-qwen3-vl-8b-instruct}"
export LMSTUDIO_TIMEOUT="${LMSTUDIO_TIMEOUT:-60}"
export WHISPER_MODEL="${WHISPER_MODEL:-/Users/jamesyee/Models/whisper/ggml-medium.bin}"

cd "$ROOT_DIR"
python3 ai_gateway/main.py

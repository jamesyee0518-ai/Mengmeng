#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# LLM：MiniMax 开放平台（M3 同时支持文本与图像输入，聊天/视觉共用一个模型）
# 换回本地 LM Studio 时：BASE_URL=http://127.0.0.1:1234/v1、CHAT_PATH=/chat/completions、
# MODEL=qwen3-vl-8b-instruct、API_KEY 留空
export LMSTUDIO_ENABLED="${LMSTUDIO_ENABLED:-1}"
export LMSTUDIO_BASE_URL="${LMSTUDIO_BASE_URL:-https://api.minimaxi.com/v1}"
export LMSTUDIO_CHAT_PATH="${LMSTUDIO_CHAT_PATH:-/text/chatcompletion_v2}"
export LMSTUDIO_MODEL="${LMSTUDIO_MODEL:-MiniMax-M3}"
# 密钥不入库：从 scripts/local.env（git 忽略）读取 LMSTUDIO_API_KEY
if [ -z "${LMSTUDIO_API_KEY:-}" ] && [ -f "$ROOT_DIR/scripts/local.env" ]; then
  . "$ROOT_DIR/scripts/local.env"
fi
export LMSTUDIO_API_KEY="${LMSTUDIO_API_KEY:?请在 scripts/local.env 设置 LMSTUDIO_API_KEY}"
export LMSTUDIO_TEMPERATURE="${LMSTUDIO_TEMPERATURE:-1.0}"
export LMSTUDIO_MAX_TOKENS="${LMSTUDIO_MAX_TOKENS:-2048}"
export LMSTUDIO_TIMEOUT="${LMSTUDIO_TIMEOUT:-60}"
export LMSTUDIO_NO_THINK="${LMSTUDIO_NO_THINK:-0}"
export WHISPER_MODEL="${WHISPER_MODEL:-$ROOT_DIR/Models/whisper/ggml-medium.bin}"

# 语音引擎：Ubuntu 服务器 mengmeng_speech（FunASR STT + edge-tts TTS）
# 服务器不可达时 STT 自动回退本机 whisper；TTS 由手机端回退系统合成
export STT_ENGINE="${STT_ENGINE:-funasr_http}"
export SPEECH_BASE_URL="${SPEECH_BASE_URL:-http://192.168.11.10:8801}"
export SPEECH_TIMEOUT="${SPEECH_TIMEOUT:-90}"

cd "$ROOT_DIR"
python3 ai_gateway/main.py

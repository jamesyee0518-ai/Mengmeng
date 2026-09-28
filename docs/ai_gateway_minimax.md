# AI Gateway 模型切换记录：MiniMax M3

> 日期：2026-09-28。`ai_gateway/main.py` 的模型客户端本就是 OpenAI 兼容协议，本次将其指向 MiniMax 开放平台并补齐云端必需的能力。

## 当前配置（scripts/run_gateway_medium.sh）

| 环境变量 | 值 | 说明 |
|---|---|---|
| LMSTUDIO_BASE_URL | `https://api.minimaxi.com/v1` | MiniMax 开放平台 |
| LMSTUDIO_CHAT_PATH | `/text/chatcompletion_v2` | 推理/正文分离（content 干净无 `<think>`） |
| LMSTUDIO_MODEL | `MiniMax-M3` | 文本+图像同模型，聊天/视觉共用 |
| LMSTUDIO_API_KEY | sk-cp-…（脚本内） | 本地脚本明文，项目非 git 仓库 |
| LMSTUDIO_TEMPERATURE | 1.0 | M 系列官方推荐值 |
| LMSTUDIO_MAX_TOKENS | 2048 | 推理模型需要余量，96 会把 token 烧在思考上 |
| LMSTUDIO_TIMEOUT | 60 | 推理模型比本地模型慢 |

换回本地 LM Studio：`BASE_URL=http://127.0.0.1:1234/v1`、`CHAT_PATH=/chat/completions`、`MODEL=qwen3-vl-8b-instruct`、`API_KEY` 留空。可用模型：MiniMax-M3 / M2.7(-highspeed) / M2.5 / M2.1 / M2。

## main.py 代码改动

1. 新增 `LMSTUDIO_API_KEY`、`LMSTUDIO_CHAT_PATH` 配置；`_post/_get` 携带 `Authorization: Bearer`。
2. 聊天/视觉两处调用改为可配置路径（MiniMax 用 chatcompletion_v2）。
3. `gateway_health()` 的 LLM 探测改用客户端 `_get("/models")`（带鉴权）——原裸请求在 MiniMax 下必 401，会导致 /health 不健康、手机端禁止语音唤醒。
4. `_extract_model_text` 先剥离 `<think>...</think>`（推理模型走 OpenAI 标准路径时的兜底）。
5. 修复 run 脚本 Whisper 模型路径错误（原指向不存在的 `/Users/jamesyee/Models/...`，改为 `$ROOT_DIR/Models/whisper/ggml-medium.bin`）。

## 实测（2026-09-28）

- `/health`：ok=true，llm=MiniMax-M3 reachable，stt ok。
- `/chat`：M3 按 persona 回复（"嗨~我是萌萌…"），无 fallback。
- `/vision`：M3 正确识别测试图颜色（image_url 输入）。
- M3 经 chatcompletion_v2 的响应：`content` 为最终答案，`reasoning_content` 为思考过程（客户端已有取 content 优先、reasoning 兜底的逻辑）。

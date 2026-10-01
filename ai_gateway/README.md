# Pocket Companion AI Gateway

这是第一阶段的最小 AI Gateway 骨架，用 Python 标准库实现，便于在没有安装 FastAPI 依赖时也能运行。

## 运行

```bash
python3 main.py
```

默认地址：

```text
http://192.168.1.111:8787
```

Gateway 默认监听 `0.0.0.0:8787`，同一局域网手机可通过 `http://192.168.1.111:8787` 访问。

## 接口

- `GET /health`
- `GET /model/health`
- `POST /chat`
- `POST /event`

## 接入 MiniMax（当前统一模型入口）

从项目根目录启动：

```bash
scripts/run_gateway_medium.sh
```

启动脚本目前将文字、看图及事件的模型请求统一交给 MiniMax。脚本配置为 `https://api.minimaxi.com/v1`、`/text/chatcompletion_v2`、`MiniMax-M3`；这些是仓库配置值，模型可用性以实际服务响应为准。

密钥通过环境变量 `LMSTUDIO_API_KEY` 或被 Git 忽略的 `scripts/local.env` 提供。代码中的 `LmStudioClient`、`LMSTUDIO_*` 和响应中的 `model_provider=lmstudio` 是历史兼容命名，并不表示当前仍调用本地 LM Studio。不要仅凭这个字段判断实际模型服务。

`/chat` 与 `/chat/vision` 均支持可选的 `context`（`session_id`、`persona`、成对的 `history`）。网关校验后，把历史放入同一模型请求的 `messages`；没有另设多轮模型入口。图片历史只保留问答文本。

直接执行 `python3 main.py` 不会自动加载上述启动脚本的 MiniMax 配置；正式联调请使用统一脚本或显式提供同等环境变量。

验证模型连接：

```bash
curl http://127.0.0.1:8787/model/health
```

从手机同一局域网验证 Gateway：

```bash
curl http://192.168.1.111:8787/health
```

验证聊天：

```bash
curl -X POST http://127.0.0.1:8787/chat \
  -H 'content-type: application/json' \
  -d '{"text":"我今天有点累","settings":{"allow_speech_output":true}}'
```

如果 MiniMax 请求失败或返回内容无法使用，Gateway 会自动退回本地规则回复，App 不会中断。

后续阶段可将该服务替换为 FastAPI，并保留相同响应结构。

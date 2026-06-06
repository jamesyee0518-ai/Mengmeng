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

## 接入 LM Studio

先在 LM Studio 中启动本地服务，并加载一个模型。然后用下面的方式启动 Gateway：

```bash
LMSTUDIO_ENABLED=1 \
AI_GATEWAY_HOST=0.0.0.0 \
AI_GATEWAY_PORT=8787 \
LMSTUDIO_BASE_URL=http://127.0.0.1:1234/v1 \
LMSTUDIO_MODEL=qwen3-vl-8b-instruct \
python3 main.py
```

可选环境变量：

```text
LMSTUDIO_TIMEOUT=12
LMSTUDIO_TEMPERATURE=0.2
LMSTUDIO_MAX_TOKENS=96
```

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

如果 LM Studio 未启动、模型未加载或返回格式不稳定，Gateway 会自动退回本地规则回复，App 不会中断。

后续阶段可将该服务替换为 FastAPI，并保留相同响应结构。

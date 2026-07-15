# 本地 AI 聊天 Bot 开发文档

> 文档版本：V1.1  
> 适用项目：本地 AI 聊天 Bot / AI 工作台 / Agent 控制台  
> 核心能力：本地 LLM 聊天、TTS/STT 语音交互、生图/视频生成、文本处理、文件分析、Codex / Claude Code / Hermes 调用  
> 推荐部署环境：macOS Apple Silicon，高内存本地机器优先，例如 MacBook Pro M 系列 64GB/128GB 以上内存  
> V1.1 更新重点：补充 Apple Silicon 统一内存并发控制、显存锁、Hermes 持久化任务流、Claude Code 沙箱隔离、RAG 布局解析、多流前端体验

---

## 1. 项目概述

### 1.1 项目定位

本项目旨在设计并开发一个本地优先的 AI 聊天 Bot。该 Bot 不只是传统问答机器人，而是一个统一的本地 AI 工作台入口，能够通过自然语言对话调度多个本地或云端 AI 能力，包括：

- 本地 LLM 聊天；
- TTS 文本转语音；
- STT 语音转文本；
- ComfyUI 生图 / 视频生成；
- 文本总结、翻译、改写、结构化；
- 文件上传、解析与问答；
- 调用 Codex 执行代码分析与修改；
- 调用 Claude Code 执行代码库理解、重构与文档生成；
- 调用 Hermes 执行自动化任务、定时任务、报告生成和本地 Agent 工作流。

最终目标是形成一个可长期扩展的个人 AI 控制台。

---

### 1.2 核心价值

本项目解决的问题不是单一模型能力，而是统一调度能力：

1. 用户不需要分别打开 Ollama、ComfyUI、Codex、Claude Code、Hermes、TTS 工具；
2. 所有能力通过一个聊天入口完成；
3. Bot 根据用户意图自动选择合适工具；
4. 关键操作具备权限控制、日志记录、人工确认与回滚能力；
5. 本地优先，保护隐私，降低云端模型调用成本；
6. 支持后续产品化为桌面端、Web 端、移动端 AI 助手。

---

### 1.3 典型使用场景

| 场景 | 用户输入示例 | 系统行为 |
|---|---|---|
| 本地聊天 | “解释一下 JEP 架构” | 调用本地 LLM 回答 |
| 语音对话 | 用户语音提问 | STT 转文字，LLM 回答，TTS 朗读 |
| 生图 | “生成一个按摩品牌 Logo” | 优化 prompt，调用 ComfyUI 工作流 |
| 文本处理 | “把这段话改成商务风格” | 调用文本处理模板和 LLM |
| 文件分析 | “总结这个 PDF” | 解析文件，分块，检索，回答 |
| 代码分析 | “分析 Apos 项目架构” | 调用 Codex / Claude Code 只读分析 |
| 代码修改 | “修复这个 Flutter 报错” | 进入受控代码修改流程 |
| 自动任务 | “每天早上生成 A 股盘前简报” | 调用 Hermes 创建定时任务 |
| 报告生成 | “生成今日 A 股收盘复盘” | Hermes 执行数据采集与报告输出 |

---

## 2. 总体架构设计

### 2.1 架构原则

系统设计遵循以下原则：

1. **本地优先**：优先调用本地 LLM、本地 TTS、本地 ComfyUI；
2. **工具隔离**：Codex、Claude Code、Hermes 不直接暴露给聊天模型，而是通过 Tool Gateway 受控调用；
3. **权限最小化**：默认只读，涉及文件修改、命令执行、安装依赖、Git 操作时必须确认；
4. **可插拔 Provider**：LLM、TTS、STT、Image、Agent 均通过 Provider 抽象；
5. **任务异步化**：生图、视频、代码任务、Hermes 自动任务均使用队列；
6. **可追踪**：所有工具调用、文件修改、生成任务都要记录日志；
7. **可回滚**：代码修改类任务必须保留 diff、变更文件和执行记录；
8. **本地资源互斥**：在 Apple Silicon 统一内存环境下，LLM、MLX Server、ComfyUI、TTS/VLM 等高负载任务必须通过本地资源锁和队列统一调度，避免同时抢占 GPU/Unified Memory 导致闪退、卡死或系统 swap 激增。

---

### 2.2 总体架构图

```text
用户
 │
 ├─ Web / Desktop / Mobile 聊天界面
 │
 ├─ 文字输入
 ├─ 语音输入
 ├─ 文件上传
 │
 ▼
Bot Backend / Orchestrator
 │
 ├─ Intent Router          意图识别
 ├─ Session Manager        会话管理
 ├─ Memory Manager         记忆管理
 ├─ Model Router           模型路由
 ├─ Tool Gateway           工具网关
 ├─ Task Queue             异步任务队列
 ├─ Permission Manager     权限控制
 ├─ Resource Scheduler      本地资源调度 / 显存锁
 └─ Audit Logger           审计日志
 │
 ├──────────────┬──────────────┬──────────────┬──────────────┐
 ▼              ▼              ▼              ▼              ▼
Local LLM       TTS/STT        ComfyUI         Code Agents     Hermes
Ollama/MLX      Kokoro/Piper   Image/Video     Codex/Claude    Task Agent
LM Studio       Whisper        Workflows       Code            Scheduler
 │              │              │              │              │
 ▼              ▼              ▼              ▼              ▼
聊天回答        语音输入输出     图片/视频结果    代码分析/修改    自动化报告
```

---

### 2.3 系统分层

```text
Presentation Layer
 ├─ Web Chat UI
 ├─ Desktop Client
 └─ Mobile Client

Application Layer
 ├─ Chat Service
 ├─ Intent Router
 ├─ Orchestrator
 ├─ Workflow Service
 └─ Permission Service

Tool Gateway Layer
 ├─ LLM Provider Adapter
 ├─ TTS Provider Adapter
 ├─ STT Provider Adapter
 ├─ ComfyUI Adapter
 ├─ Codex Adapter
 ├─ Claude Code Adapter
 └─ Hermes Adapter

Infrastructure Layer
 ├─ PostgreSQL
 ├─ Redis
 ├─ Qdrant / pgvector
 ├─ Local File Storage
 ├─ Log System
 └─ Scheduler
```

---

## 3. 技术选型

### 3.1 推荐技术栈

| 模块 | 推荐技术 | 说明 |
|---|---|---|
| 前端 Web | Next.js + React | 快速实现 ChatGPT 类界面 |
| 桌面端 | Flutter / Tauri | 后续产品化 |
| 后端 API | FastAPI | Python 生态适合 AI 工具集成 |
| 实时通信 | WebSocket / SSE | 支持流式输出 |
| 数据库 | PostgreSQL | 业务数据、会话、任务记录 |
| 缓存队列 | Redis | 任务队列、状态缓存 |
| 任务队列 | RQ / Celery / Dramatiq | 异步任务执行 |
| 向量库 | Qdrant / pgvector | RAG 文件问答 |
| 文件解析 | PyMuPDF、pdfplumber、python-docx、openpyxl | 文档处理 |
| 本地 LLM | Ollama / MLX / LM Studio | 本地模型服务 |
| TTS | Kokoro / Piper / ChatTTS / Fish Speech | 文本转语音 |
| STT | faster-whisper / whisper.cpp / FunASR | 语音转文本 |
| 生图 | ComfyUI | 图片/视频生成工作流 |
| 代码 Agent | Codex CLI / Claude Code | 项目分析与修改 |
| 自动任务 | Hermes | 定时任务与本地 Agent 编排 |

---

### 3.2 MVP 推荐组合

第一版建议选择如下组合：

```text
前端：Next.js Web Chat
后端：FastAPI
LLM：Ollama + MLX Server
TTS：Kokoro 或 Piper
STT：faster-whisper
生图：ComfyUI API
代码 Agent：Codex CLI 先接入，Claude Code 后接入
自动任务：Hermes Adapter 后接入
数据库：PostgreSQL
队列：Redis + RQ
文件存储：本地 storage 目录
```

---

## 4. 核心功能模块

## 4.1 Chat Service 聊天服务

### 4.1.1 功能说明

Chat Service 是系统核心入口，负责：

- 创建会话；
- 保存消息；
- 维护上下文；
- 调用 Intent Router；
- 流式返回模型输出；
- 记录工具调用；
- 绑定文件、图片、音频和任务结果。

---

### 4.1.2 聊天消息类型

| 类型 | 说明 |
|---|---|
| text | 普通文本 |
| image | 图片结果 |
| audio | 音频结果 |
| file | 文件附件 |
| tool_call | 工具调用记录 |
| task_status | 异步任务状态 |
| code_diff | 代码变更 diff |
| markdown | Markdown 文档 |
| html | HTML 报告 |

---

### 4.1.3 聊天流程

```text
用户输入
 ↓
保存 user message
 ↓
Intent Router 判断任务类型
 ↓
Model Router 或 Tool Gateway 选择执行器
 ↓
执行任务
 ↓
流式返回结果
 ↓
保存 assistant message
 ↓
必要时触发 TTS / 文件生成 / 图片展示
```

---

## 4.2 Intent Router 意图识别模块

### 4.2.1 功能说明

Intent Router 负责判断用户请求属于哪类任务。

### 4.2.2 意图分类

| intent | 说明 | 默认执行器 |
|---|---|---|
| chat | 普通聊天 | Local LLM |
| text_process | 文本处理 | Local LLM + Prompt Template |
| tts | 文本转语音 | TTS Service |
| stt | 语音转文本 | STT Service |
| image_generate | 文生图 | ComfyUI |
| image_edit | 图生图 / 图片编辑 | ComfyUI |
| video_generate | 视频生成 | ComfyUI |
| file_analyze | 文件分析 | Document Service + RAG |
| code_analyze | 代码分析 | Codex / Claude Code |
| code_modify | 代码修改 | Codex / Claude Code，需确认 |
| hermes_task | Hermes 自动任务 | Hermes Adapter |
| scheduled_task | 定时任务 | Scheduler / Hermes |
| web_research | 网络检索 | Web Agent / Hermes |

---

### 4.2.3 意图识别规则示例

```yaml
intent_rules:
  image_generate:
    keywords:
      - 生成图片
      - 生图
      - logo
      - 海报
      - 图片
      - 视觉设计

  code_analyze:
    keywords:
      - 分析项目
      - review code
      - 审查代码
      - 代码结构
      - 架构分析

  code_modify:
    keywords:
      - 修改代码
      - 修复 bug
      - 增加功能
      - 重构
      - apply patch

  hermes_task:
    keywords:
      - Hermes
      - 定时任务
      - 盘前简报
      - 午盘热点
      - 收盘复盘
      - 自动报告

  tts:
    keywords:
      - 读出来
      - 朗读
      - 转语音
      - 播放
```

---

## 4.3 Model Router 模型路由模块

### 4.3.1 功能说明

Model Router 根据任务类型、上下文长度、速度要求、隐私要求和内存状态选择合适模型。

---

### 4.3.2 推荐模型路由

```yaml
model_routing:
  chat:
    provider: ollama
    model: qwen3.6:27b-mlx-bf16
    temperature: 0.5

  coding:
    provider: ollama
    model: qwen3.6:27b-coding-bf16
    temperature: 0.2

  summarize:
    provider: ollama
    model: gemma4:31b
    temperature: 0.3

  prompt_optimize:
    provider: ollama
    model: qwen3.6:27b-mlx-bf16
    temperature: 0.6

  long_context:
    provider: mlx
    model: long-context-model
    temperature: 0.3

  fallback_fast:
    provider: ollama
    model: small-fast-model
    temperature: 0.4
```

---

### 4.3.3 内存压力路由

当本地机器内存或 swap 压力较高时，自动降级模型。

```text
正常：qwen3.6:27b-mlx-bf16
内存压力中等：gemma4:31b 或更小模型
内存压力高：small-fast-model
复杂任务：提示用户是否切换云端模型
```



### 4.3.4 Apple Silicon 统一内存并发策略

在 Mac Apple Silicon 上，Ollama、MLX Server、ComfyUI、Whisper、VLM 文档解析等任务都会共享 Unified Memory，并可能同时占用 GPU / Neural Engine / CPU 资源。若系统不做调度，常见风险包括：

```text
- LLM 推理过程中同时启动 ComfyUI，导致模型被迫换入 swap；
- ComfyUI 视频生成时继续接收 LLM 长上下文请求，导致显存/统一内存被打满；
- MLX Server 与 Ollama 同时常驻大模型，空闲模型仍占用大量内存；
- TTS/STT/VLM 与图像生成并发运行，造成短时内存峰值超过阈值；
- 前端表现为请求卡死、图片任务失败、模型响应突然变慢或后端进程退出。
```

因此 Model Router 不能只按“任务类型”选模型，还必须感知当前本地资源状态。

推荐引入 `Resource Scheduler` 和 `VRAM/Unified Memory Mutex`：

| 资源等级 | 典型任务 | 并发策略 |
|---|---|---|
| low | 短文本摘要、小模型聊天、短 TTS | 可并发 |
| medium | 27B LLM 推理、Whisper 长音频、PDF 解析 | 限流并发 |
| high | ComfyUI SDXL/Flux 生图、大模型长上下文 | 独占 GPU 锁 |
| exclusive | Wan 视频生成、VLM 图表解析、大规模代码 Agent | 独占 GPU 锁 + 任务队列 |

推荐路由规则：

```yaml
resource_policy:
  locks:
    unified_memory_gpu_lock:
      owner: null
      ttl_seconds: 1800
      renewable: true

  tasks:
    llm_chat:
      resource_level: medium
      require_gpu_lock: false
      pause_when_exclusive_running: true

    comfyui_image:
      resource_level: high
      require_gpu_lock: true
      queue_policy: fifo

    comfyui_video:
      resource_level: exclusive
      require_gpu_lock: true
      unload_llm_before_start: true

    vlm_document_parse:
      resource_level: exclusive
      require_gpu_lock: true
      run_during_idle: true
```

当 ComfyUI 执行高显存任务时：

```text
1. Resource Scheduler 获取 unified_memory_gpu_lock；
2. Model Router 暂停新的本地 LLM 长推理任务；
3. 若已有 LLM 常驻模型占用过高，触发 ollama keep_alive=0 或调用卸载策略；
4. 生图/视频任务完成后释放锁；
5. 队列中等待的 LLM 请求继续执行。
```

当 LLM 正在执行长上下文任务时：

```text
1. ComfyUI 新任务进入 queued 状态；
2. 前端提示“等待本地显存资源”；
3. 若用户强制启动 ComfyUI，需要确认是否中断/降级当前 LLM 推理；
4. 任务调度器记录中断原因和资源占用快照。
```

资源状态采集建议：

```text
- macOS memory_pressure；
- vm_stat；
- ps / Activity Monitor 进程内存；
- Ollama / MLX / ComfyUI 进程 RSS；
- swap 使用量；
- 当前任务队列中的 high/exclusive 任务数量；
- 模型是否常驻、上次访问时间、keep_alive 策略。
```

注意：macOS 统一内存调优应采用保守策略。可在部署文档中预留系统参数优化项，例如 `sudo sysctl iogpu.wired_limit_mb=XXXX`，但该参数是否可用、推荐值和风险取决于 macOS 版本、硬件型号和当前系统负载。开发文档中只应将其列为“可选高级调优项”，默认部署不应强制修改内核参数。

---

## 4.4 TTS 文本转语音模块

### 4.4.1 功能说明

TTS Service 将 Bot 输出文本转换为语音，可支持中英文朗读、分段播放、流式播放。

---

### 4.4.2 推荐实现策略

| 阶段 | 推荐方案 |
|---|---|
| MVP | Piper / Kokoro |
| 中文体验增强 | ChatTTS / Fish Speech |
| 实时语音助手 | 流式 TTS |
| 商业化 | 可选云端 TTS 作为 fallback |

---

### 4.4.3 TTS 流程

```text
LLM 流式输出
 ↓
句子切分
 ↓
TTS 任务队列
 ↓
生成音频片段
 ↓
前端按顺序播放
```

---

### 4.4.4 TTS 接口

```http
POST /api/tts
```

请求：

```json
{
  "text": "你好，我是你的本地 AI 助手。",
  "voice": "zh_female_01",
  "speed": 1.0,
  "format": "mp3",
  "stream": true
}
```

返回：

```json
{
  "audio_url": "/storage/audio/tts_20260606_001.mp3",
  "duration": 5.2
}
```

---

## 4.5 STT 语音转文本模块

### 4.5.1 功能说明

STT Service 将用户录音转换为文本，再交给 Chat Service 处理。

---

### 4.5.2 推荐流程

```text
前端录音
 ↓
上传 wav / webm
 ↓
STT Service 转写
 ↓
返回文本
 ↓
进入普通聊天流程
```

---

### 4.5.3 STT 接口

```http
POST /api/stt/transcribe
```

请求：

```text
multipart/form-data
- audio_file
- language: zh/en/auto
```

返回：

```json
{
  "text": "帮我分析这个项目的架构。",
  "language": "zh",
  "duration": 4.8
}
```

---

## 4.6 ComfyUI 生图 / 视频模块

### 4.6.1 功能说明

Image Service 调用 ComfyUI API 执行图片或视频生成工作流。

---

### 4.6.2 支持能力

| 能力 | 说明 |
|---|---|
| 文生图 | 根据文本生成图片 |
| 图生图 | 基于上传图片生成新图 |
| Logo 生成 | 品牌 Logo、图标设计 |
| 海报生成 | 宣传图、活动图 |
| 商品图生成 | 电商商品图 |
| 局部重绘 | 基于 mask 编辑图片 |
| 视频生成 | 调用 Wan / I2V / T2V workflow |

---

### 4.6.3 工作流模板管理

```text
workflows/
 ├─ text_to_image_sdxl.json
 ├─ flux_logo.json
 ├─ product_image.json
 ├─ image_to_image.json
 ├─ inpainting.json
 ├─ wan_i2v_video.json
 └─ poster_design.json
```

---

### 4.6.4 生图流程

```text
用户输入生图需求
 ↓
Intent Router 判断 image_generate
 ↓
LLM 优化 prompt
 ↓
选择 workflow 模板
 ↓
填充 prompt、size、seed、steps 等参数
 ↓
提交 ComfyUI /prompt
 ↓
轮询任务状态
 ↓
返回图片 / 视频 URL
```

---

### 4.6.5 生图接口

```http
POST /api/image/generate
```

请求：

```json
{
  "prompt": "A clean premium logo for Ease&Joy...",
  "workflow": "flux_logo",
  "size": "1024x1024",
  "steps": 30,
  "seed": -1
}
```

返回：

```json
{
  "task_id": "img_20260606_001",
  "status": "queued"
}
```

查询：

```http
GET /api/image/tasks/{task_id}
```

返回：

```json
{
  "task_id": "img_20260606_001",
  "status": "completed",
  "outputs": [
    "/storage/images/logo_001.png"
  ]
}
```

---

## 4.7 文本处理模块

### 4.7.1 功能说明

Text Processor 用于处理高频文本任务，避免所有任务都通过自由聊天方式完成。

---

### 4.7.2 支持任务

| 任务 | 说明 |
|---|---|
| summarize | 总结 |
| translate | 翻译 |
| rewrite | 改写 |
| expand | 扩写 |
| polish | 润色 |
| markdown_generate | 生成 Markdown |
| json_extract | 提取 JSON |
| contract_review | 合同审查 |
| project_plan | 项目规划 |
| prompt_optimize | Prompt 优化 |

---

### 4.7.3 模板目录

```text
prompts/text/
 ├─ summarize.md
 ├─ translate.md
 ├─ rewrite_business.md
 ├─ polish.md
 ├─ markdown_generate.md
 ├─ contract_review.md
 ├─ project_plan.md
 └─ prompt_optimizer.md
```

---

## 4.8 文件分析与知识库模块

### 4.8.1 功能说明

Document Service 支持用户上传文件，并基于文件内容进行总结、问答、提取表格和生成文档。

---

### 4.8.2 支持文件类型

| 文件类型 | 处理方式 |
|---|---|
| PDF | Marker / Unstructured / PyMuPDF / pdfplumber |
| Word | python-docx / Unstructured |
| Excel | openpyxl / pandas |
| Markdown | 直接解析 |
| TXT | 直接解析 |
| 图片 | OCR / VLM |
| 代码目录 | ripgrep / tree-sitter |

---

### 4.8.3 文件处理流程

```text
文件上传
 ↓
保存原始文件
 ↓
布局解析：标题、段落、表格、图片、页码
 ↓
转换为结构化 Markdown
 ↓
语义切片 chunk
 ↓
生成 embedding
 ↓
写入向量库
 ↓
用户提问
 ↓
检索相关 chunk
 ↓
LLM 生成答案
```



### 4.8.4 RAG 文档解析增强策略

传统按字符数硬切片适合简单 TXT 或 Markdown，但对 PDF、扫描件、合同、财务报表、技术白皮书等文档效果较差。推荐采用“布局解析 → Markdown 化 → 语义切片 → 向量化”的流程。

推荐解析策略：

| 文档类型 | 推荐处理方式 |
|---|---|
| 普通 PDF | Marker / Unstructured 转 Markdown，再做标题级切片 |
| 表格型 PDF | 表格抽取后保留为 Markdown Table 或 JSON |
| 扫描 PDF | OCR + 版面恢复 |
| 图表较多文档 | OCR + VLM 图表说明 |
| 合同 / 法务文档 | 按章节、条款、款项层级切片 |
| 技术文档 | 按标题、代码块、表格、流程图分块 |
| 代码仓库 | tree-sitter / ripgrep / 目录结构索引 |

切片原则：

```text
- 优先按标题层级切片，而不是固定字符数；
- 保留 chunk 的章节路径，例如：第 5 章 > 5.3 > 5.3.1；
- 表格不要拆散，应整体保存，并生成表格摘要；
- 图片、流程图、架构图应生成可检索的 caption；
- 每个 chunk 保存 page_no、heading_path、source_file、block_type；
- 检索时同时使用 embedding 相似度、关键词匹配和章节路径加权。
```

在高配置 Mac 上，可增加本地轻量 VLM 作为“文档视觉解析辅助器”：

```text
PDF 页面截图 / 图片 / 图表
 ↓
本地 VLM 生成图表说明、流程解释、关键字段
 ↓
与 OCR / Markdown 文本合并
 ↓
进入向量库
```

注意：VLM 文档解析属于 high/exclusive 资源任务，应纳入 Resource Scheduler，避免与 ComfyUI 视频生成或大模型长上下文推理同时运行。

---

## 4.9 Codex Adapter

### 4.9.1 功能说明

Codex Adapter 负责让 Bot 调用 Codex CLI 执行代码项目分析、修改、测试和文档生成任务。

---

### 4.9.2 使用场景

| 场景 | 示例 |
|---|---|
| 项目分析 | “分析 Apos 项目结构” |
| Bug 修复 | “修复 checkout 页面报错” |
| 文档生成 | “基于代码生成接口文档” |
| 测试修复 | “运行测试并修复失败项” |
| Git 辅助 | “生成 commit message” |

---

### 4.9.3 Codex 调用接口

```http
POST /api/tools/codex/run
```

请求：

```json
{
  "project_path": "/Users/jamesyee/projects/Apos",
  "task": "分析当前项目结构，只输出分析报告，不修改文件。",
  "mode": "read_only",
  "timeout_seconds": 600
}
```

返回：

```json
{
  "task_id": "codex_20260606_001",
  "status": "running"
}
```

---

### 4.9.4 Codex 执行模式

| 模式 | 说明 | 是否需要确认 |
|---|---|---|
| read_only | 只读分析 | 否 |
| patch_plan | 生成修改计划和 diff | 否 |
| apply_patch | 修改文件 | 是 |
| run_tests | 执行测试 | 是 |
| commit | 创建 commit | 是 |
| push | 推送远程仓库 | 默认禁止 |

---

## 4.10 Claude Code Adapter

### 4.10.1 功能说明

Claude Code Adapter 负责调用 Claude Code 执行复杂代码库理解、架构分析、多文件重构和工程文档生成。

---

### 4.10.2 使用场景

| 场景 | 示例 |
|---|---|
| 大型代码库理解 | “分析财务系统权限模块” |
| 多文件重构 | “把当前项目改造成多租户架构” |
| 技术文档生成 | “生成模块开发文档” |
| PR Review | “审查这次改动的风险” |
| Git 工作流 | “总结本次变更并生成提交说明” |

---

### 4.10.3 Claude Code 调用接口

```http
POST /api/tools/claude-code/run
```

请求：

```json
{
  "project_path": "/Users/jamesyee/projects/Apos",
  "task": "审查权限模块，给出重构方案，不要修改代码。",
  "permission_mode": "ask",
  "timeout_seconds": 900
}
```

返回：

```json
{
  "task_id": "claude_20260606_001",
  "status": "running"
}
```

---

### 4.10.4 Claude Code 推荐权限

| 操作 | 默认策略 |
|---|---|
| 读取项目文件 | allow |
| 修改项目文件 | ask |
| 执行测试 | ask |
| 安装依赖 | ask |
| 删除文件 | deny |
| 读取密钥文件 | deny |
| git push | deny |
| 修改系统配置 | deny |



### 4.10.5 Claude Code 环境隔离要求

Claude Code 具备自主读取代码、执行测试、安装依赖、生成和修改多文件代码的能力。仅限制项目路径不足以保证安全，特别是在 L3-L4 权限等级下，必须增加运行环境隔离。

推荐隔离等级：

| 任务等级 | 任务类型 | 推荐隔离方式 |
|---|---|---|
| L1 | 只读分析、生成文档 | 宿主机只读挂载项目目录 |
| L2 | 生成 patch、不实际写入 | 临时 workspace + diff 输出 |
| L3 | 修改代码、运行测试 | Docker 容器 / 独立 workspace / venv / pnpm workspace |
| L4 | 安装依赖、数据库迁移、构建发布 | Docker 容器或专用沙箱，必须人工确认 |
| L5 | 删除文件、系统配置、git push | 默认禁止，除非用户手动切换专家模式 |

代码任务执行建议：

```text
1. 复制项目到 isolated_workspace；
2. 初始化独立 venv / node_modules / package cache；
3. Claude Code 在隔离目录内执行；
4. 执行完成后生成 diff；
5. 用户确认后再将 patch 应用回真实项目；
6. 所有命令、文件变更、测试结果写入 code_task 和 audit log。
```

对于 Flutter / Node / Python / .NET 项目，不建议让 Agent 修改全局依赖环境。应优先使用：

```text
- Python: venv / uv / pipx isolated env；
- Node: pnpm workspace / npm ci --prefix isolated_workspace；
- Flutter: 独立项目副本 + flutter pub get；
- .NET: 独立工作目录 + dotnet restore；
- Docker: 挂载只读源码，输出 patch 到 /patches。
```

---

## 4.11 Hermes Adapter

### 4.11.1 功能说明

Hermes Adapter 负责让聊天 Bot 调用 Hermes 执行自动化任务、定时任务、报告生成、本地 Agent 工作流。

---

### 4.11.2 使用场景

| 场景 | 说明 |
|---|---|
| A 股盘前简报 | 每天开盘前生成市场报告 |
| 午盘热点跟踪 | 中午跟踪板块和个股热点 |
| 收盘复盘 | 收盘后生成复盘报告 |
| 定时任务管理 | 新增、暂停、恢复任务 |
| Markdown / HTML 报告 | 自动生成结构化报告 |
| 邮件 / Webhook 推送 | 把结果发送到指定渠道 |
| 长流程 Agent | 复杂搜索、整理、输出任务 |

---

### 4.11.3 Hermes 任务接口

```http
POST /api/tools/hermes/run
```

请求：

```json
{
  "task_type": "stock_morning_report",
  "task": "生成今日 A 股盘前简报，输出 Markdown 和 HTML。",
  "delivery": {
    "markdown": true,
    "html": true,
    "email": false,
    "webhook": false
  }
}
```

返回：

```json
{
  "task_id": "hermes_20260606_001",
  "status": "running"
}
```

---

### 4.11.4 Hermes 定时任务接口

```http
POST /api/tools/hermes/tasks
```

请求：

```json
{
  "name": "A股盘前简报",
  "schedule": "每天 08:45",
  "prompt_template": "ashare_morning_report.md",
  "enabled": true
}
```



### 4.11.5 Hermes 长周期任务持久化要求

Hermes 负责 A 股盘前、午盘、收盘复盘、网页报告、邮件推送、Webhook 推送等长周期 Agent 工作流。这类任务通常包含：

```text
- 多源网络检索；
- 行情与新闻数据对齐；
- 多轮 LLM 总结和结构化；
- Markdown / HTML 报告生成；
- 文件输出、邮件发送或 Webhook 推送；
- 失败重试与人工补偿。
```

因此 Hermes Adapter 不应依赖 FastAPI `BackgroundTasks` 或简单线程。FastAPI 重启、进程崩溃或服务部署更新时，后台线程中的 Agent 状态会丢失。

推荐使用持久化任务流：

| 方案 | 适合阶段 | 特点 |
|---|---|---|
| Celery + Redis | MVP / 中期 | 成熟、简单、易接入 Python 生态 |
| Celery + Redis + PostgreSQL Result Backend | 中期 | 结果可追踪，适合任务审计 |
| Temporal | 长期 / 企业级 | 工作流状态持久化、重试、补偿、可观测性强 |
| Dramatiq / RQ | 轻量版本 | 简单任务队列，复杂工作流能力弱 |

推荐任务模型：

```text
Hermes Task
 ├─ task_id
 ├─ task_type
 ├─ schedule_id
 ├─ current_step
 ├─ input_snapshot
 ├─ intermediate_artifacts
 ├─ output_files
 ├─ retry_count
 ├─ error_message
 └─ resume_token
```

Hermes 执行流程应支持断点恢复：

```text
1. 创建任务记录，状态 pending；
2. 入队，状态 queued；
3. Worker 获取任务，状态 running；
4. 每完成一个步骤写入 current_step 和中间结果；
5. 失败时根据 retry_policy 重试；
6. 超过重试次数进入 failed，可人工重新执行；
7. 完成后写入 Markdown / HTML / JSON 输出，状态 completed。
```

---

## 5. Tool Gateway 工具网关设计

### 5.1 设计目标

Tool Gateway 是连接聊天 Bot 与外部工具的安全边界。

其职责包括：

- 统一工具调用接口；
- 检查权限；
- 控制工作目录；
- 管理任务状态；
- 记录工具日志；
- 收集工具输出；
- 处理超时和异常；
- 将结果返回 Chat Service。

---

### 5.2 工具类型

| 工具 | 类型 | 是否异步 | 风险等级 |
|---|---|---|---|
| Local LLM | 推理 | 否/可流式 | 低 |
| TTS | 音频生成 | 是 | 低 |
| STT | 音频识别 | 是 | 低 |
| ComfyUI | 图片/视频生成 | 是 | 中 |
| Codex | 代码 Agent | 是 | 高 |
| Claude Code | 代码 Agent | 是 | 高 |
| Hermes | 自动化 Agent | 是 | 中/高 |
| File Parser | 文件解析 | 是 | 中 |

---

### 5.3 工具调用生命周期

```text
创建 tool_call 记录
 ↓
权限检查
 ↓
创建 task
 ↓
放入队列
 ↓
Worker 执行
 ↓
实时写入日志
 ↓
更新状态
 ↓
返回结果
 ↓
保存到聊天上下文
```



### 5.4 本地资源锁与任务调度

Tool Gateway 需要统一控制高资源任务，避免多个 Provider 直接竞争 Apple Silicon Unified Memory。

核心组件：

```text
Resource Scheduler
 ├─ Memory Monitor
 ├─ GPU/Unified Memory Mutex
 ├─ Model Residency Manager
 ├─ Queue Prioritizer
 ├─ Kill / Cancel Controller
 └─ Resource Audit Logger
```

推荐锁类型：

| 锁名称 | 用途 | 典型持有者 |
|---|---|---|
| gpu_mutex | 高显存/GPU 独占任务 | ComfyUI、VLM、视频生成 |
| llm_mutex | 长上下文 LLM 独占推理 | Ollama / MLX |
| code_workspace_lock | 防止同一项目被多个 Agent 同时改写 | Codex / Claude Code |
| file_index_lock | 防止同一文件重复解析入库 | Document Service |
| hermes_schedule_lock | 防止定时任务重复执行 | Hermes Worker |

资源调度伪代码：

```python
def submit_task(task):
    resource = classify_resource(task)
    if resource.requires_exclusive_gpu:
        if gpu_mutex.is_locked():
            queue.push(task, reason="waiting_for_gpu")
            return queued_response(task)
        gpu_mutex.acquire(task.id, ttl=task.timeout)

    if memory_monitor.swap_ratio > 0.6:
        task = downgrade_or_queue(task)

    try:
        return run_task(task)
    finally:
        release_owned_locks(task.id)
```

前端必须可见资源等待原因：

```text
状态：queued
原因：ComfyUI 正在执行视频生成，占用本地 GPU/Unified Memory
预计动作：当前任务完成后自动执行，或用户手动取消/强制切换云端模型
```

---

## 6. 权限与安全设计

### 6.1 权限分级

| 等级 | 名称 | 能力 | 默认策略 |
|---|---|---|---|
| L0 | Chat Only | 普通聊天，不调用工具 | 允许 |
| L1 | Read Only | 只读文件、只读代码分析 | 允许 |
| L2 | Generate Only | 生成图片、音频、文档 | 允许 |
| L3 | Modify Files | 修改项目文件 | 需要确认 |
| L4 | Execute Commands | 执行测试、构建、脚本 | 需要确认 |
| L5 | System / Git Push | 安装依赖、删除文件、推送代码 | 默认禁止 |

---

### 6.2 高危操作清单

以下操作默认禁止或必须强确认：

```text
rm -rf
chmod / chown
sudo
ssh / scp
curl | bash
读取 .env / secret / key 文件
git push
修改系统配置
删除数据库
清空目录
安装全局依赖
```

---

### 6.3 工作目录沙箱

代码类任务必须绑定 project_path，只能在指定项目目录中执行。

```text
允许：/Users/jamesyee/projects/Apos
禁止：/Users/jamesyee
禁止：/Users/jamesyee/.ssh
禁止：/Users/jamesyee/.config
禁止：/etc
```

---

### 6.4 人工确认机制

涉及以下行为时必须弹出确认：

- 修改文件；
- 执行 shell 命令；
- 安装依赖；
- 运行迁移脚本；
- 创建 Git commit；
- 调用外部 API；
- 发送邮件；
- 创建或修改定时任务；
- 删除文件或任务。

---

## 7. 数据库设计

### 7.1 chat_session

```sql
CREATE TABLE chat_session (
    id BIGSERIAL PRIMARY KEY,
    title VARCHAR(255),
    user_id BIGINT,
    default_model VARCHAR(100),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

---

### 7.2 chat_message

```sql
CREATE TABLE chat_message (
    id BIGSERIAL PRIMARY KEY,
    session_id BIGINT NOT NULL,
    role VARCHAR(20) NOT NULL,
    content TEXT,
    content_type VARCHAR(50) DEFAULT 'text',
    model VARCHAR(100),
    metadata JSONB,
    created_at TIMESTAMP DEFAULT NOW()
);
```

---

### 7.3 tool_call

```sql
CREATE TABLE tool_call (
    id BIGSERIAL PRIMARY KEY,
    session_id BIGINT,
    message_id BIGINT,
    tool_name VARCHAR(100),
    status VARCHAR(30),
    input JSONB,
    output JSONB,
    error_message TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

---

### 7.4 generation_task

```sql
CREATE TABLE generation_task (
    id BIGSERIAL PRIMARY KEY,
    task_type VARCHAR(50),
    provider VARCHAR(100),
    status VARCHAR(30),
    input JSONB,
    output JSONB,
    log_path TEXT,
    error_message TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

---

### 7.5 workflow_template

```sql
CREATE TABLE workflow_template (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(100),
    type VARCHAR(50),
    json_path TEXT,
    input_schema JSONB,
    default_params JSONB,
    required_models JSONB,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

---

### 7.6 file_asset

```sql
CREATE TABLE file_asset (
    id BIGSERIAL PRIMARY KEY,
    session_id BIGINT,
    original_name VARCHAR(255),
    file_path TEXT,
    file_type VARCHAR(50),
    mime_type VARCHAR(100),
    size_bytes BIGINT,
    parse_status VARCHAR(30),
    metadata JSONB,
    created_at TIMESTAMP DEFAULT NOW()
);
```

---

### 7.7 code_task

```sql
CREATE TABLE code_task (
    id BIGSERIAL PRIMARY KEY,
    provider VARCHAR(50),
    project_path TEXT,
    task TEXT,
    mode VARCHAR(50),
    status VARCHAR(30),
    diff_path TEXT,
    log_path TEXT,
    result JSONB,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

---

### 7.8 permission_audit

```sql
CREATE TABLE permission_audit (
    id BIGSERIAL PRIMARY KEY,
    tool_call_id BIGINT,
    action VARCHAR(100),
    risk_level VARCHAR(20),
    decision VARCHAR(20),
    reason TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);
```

---

## 8. API 设计

### 8.1 聊天接口

```http
POST /api/chat
```

请求：

```json
{
  "session_id": 1,
  "message": "帮我分析 Apos 项目结构",
  "stream": true,
  "attachments": []
}
```

返回：

```json
{
  "message_id": 1001,
  "status": "streaming"
}
```

---

### 8.2 会话列表

```http
GET /api/chat/sessions
```

---

### 8.3 文件上传

```http
POST /api/files/upload
```

---

### 8.4 工具任务状态

```http
GET /api/tasks/{task_id}
```

---

### 8.5 代码任务执行

```http
POST /api/tools/code/run
```

请求：

```json
{
  "provider": "codex",
  "project_path": "/Users/jamesyee/projects/Apos",
  "task": "分析项目结构，不修改文件",
  "mode": "read_only"
}
```

---

### 8.6 工具确认接口

```http
POST /api/permissions/confirm
```

请求：

```json
{
  "tool_call_id": 123,
  "decision": "approved",
  "reason": "允许修改 checkout 模块文件"
}
```

---

## 9. 前端页面设计

### 9.1 页面结构

```text
首页 / Chat 页面
 ├─ 左侧会话列表
 ├─ 中间聊天区
 │   ├─ 文本消息
 │   ├─ 图片结果
 │   ├─ 音频播放器
 │   ├─ 文件卡片
 │   ├─ 代码 diff 卡片
 │   └─ 工具执行状态卡片
 ├─ 右侧工具面板
 │   ├─ 当前模型
 │   ├─ 当前工具
 │   ├─ 任务队列
 │   ├─ 权限确认
 │   └─ 系统状态
 └─ 底部输入区
     ├─ 文本输入
     ├─ 语音输入
     ├─ 文件上传
     ├─ 模型选择
     └─ 发送按钮
```

---

### 9.2 工具执行状态卡片

```text
工具：Claude Code
任务：审查权限模块
状态：运行中
工作目录：/Users/jamesyee/projects/FMS
耗时：02:31
日志：查看
操作：停止任务
```

---

### 9.3 权限确认卡片

```text
Claude Code 请求执行以下操作：

操作：修改文件
文件：lib/features/checkout/presentation/checkout_page.dart
风险等级：L3

[查看 diff] [允许] [拒绝]
```

---

### 9.4 生图结果卡片

```text
任务：Logo 生成
Workflow：flux_logo
状态：完成

[图片预览]
[下载] [重新生成] [用作图生图输入] [生成设计说明]
```



### 9.5 多流 Multi-Stream 卡片联动

用户的一句话可能触发多个异步任务。例如：

```text
“分析这段代码，并帮我读出来。”
```

系统实际会产生：

```text
1. LLM / Claude Code 文本分析流；
2. TTS 分句合成音频流；
3. 音频播放器播放流；
4. 代码引用 / diff 展示卡片；
5. 工具执行状态卡片。
```

前端需要支持多个流并行展示，而不是只显示单一文本消息。

推荐 UI 结构：

```text
Message Group
 ├─ Text Stream Card
 │   ├─ 流式文本
 │   ├─ 当前句子高亮
 │   └─ 引用 / 代码块 / diff
 ├─ TTS Audio Card
 │   ├─ 分句生成状态
 │   ├─ 当前播放句子
 │   ├─ 播放 / 暂停 / 跳句
 │   └─ 语速 / 声音选择
 ├─ Tool Status Card
 │   ├─ Claude Code / Codex / Hermes 状态
 │   ├─ 日志
 │   └─ 停止任务
 └─ Artifact Card
     ├─ 图片
     ├─ Markdown 文件
     ├─ HTML 报告
     └─ 代码 patch
```

TTS 联动策略：

```text
LLM 流式输出
 ↓
按句子切分
 ↓
句子进入 TTS 队列
 ↓
TTS 返回 audio segment
 ↓
播放器顺序播放
 ↓
前端高亮当前正在朗读的句子
```

前端数据结构建议：

```json
{
  "message_group_id": "mg_001",
  "streams": [
    {"type": "text", "status": "streaming"},
    {"type": "tts", "status": "generating"},
    {"type": "tool", "tool": "claude_code", "status": "running"}
  ],
  "active_sentence_index": 3
}
```

---

## 10. Prompt 与系统指令设计

### 10.1 Orchestrator System Prompt

```text
你是一个本地 AI 工作台的任务编排器。

你可以根据用户意图调用以下工具：
1. 本地 LLM：用于聊天、写作、总结、翻译、推理；
2. TTS：用于将文本转为语音；
3. STT：用于将语音转为文本；
4. ComfyUI：用于生成图片或视频；
5. Codex：用于代码分析、修改、测试；
6. Claude Code：用于大型代码库分析、重构、文档生成；
7. Hermes：用于定时任务、自动报告、本地 Agent 工作流；
8. Document Service：用于文件解析和知识库问答。

你必须先判断用户意图，再选择合适工具。
涉及文件修改、命令执行、发送邮件、创建定时任务、删除文件、Git 操作时，必须请求用户确认。
如果缺少实时数据，必须说明数据缺失，不得编造。
默认使用中文回答，除非用户明确要求英文。
```

---

### 10.2 生图 Prompt 优化模板

```text
请将用户的图像生成需求转换为适合 ComfyUI 的英文 prompt。
要求：
1. 保留用户明确要求的主体、风格、颜色、用途；
2. 增强构图、材质、光影、质感描述；
3. 避免色情、暴力、违法内容；
4. 输出 positive prompt 和 negative prompt；
5. 如果是 Logo，强调 minimal、clean、premium、vector-like、brand identity。
```

---

### 10.3 代码任务 Prompt 模板

```text
你正在指定项目目录中执行代码任务。

任务要求：
- 先分析项目结构；
- 不要读取密钥文件；
- 不要修改用户未授权的文件；
- 不要执行危险命令；
- 如果需要修改文件，先输出修改计划；
- 如果需要执行测试，先说明测试命令；
- 输出结果需包含：发现的问题、修改建议、涉及文件、风险点、下一步建议。
```

---

## 11. 任务队列设计

### 11.1 需要异步化的任务

| 任务 | 原因 |
|---|---|
| TTS 长文本 | 生成耗时 |
| STT 长音频 | 转写耗时 |
| ComfyUI 生图 | GPU/内存占用，耗时不确定 |
| 视频生成 | 长耗时 |
| 文件解析 | 大文件处理 |
| Codex / Claude Code | 多步骤执行 |
| Hermes 自动任务 | 需要后台执行 |

---

### 11.2 任务状态

```text
pending
queued
running
waiting_confirmation
completed
failed
cancelled
timeout
```



### 11.3 持久化任务流要求

所有高价值、长耗时、可失败重试的任务都必须进入持久化任务队列，不允许只使用 FastAPI `BackgroundTasks`。

必须持久化的任务：

```text
- Hermes 定时报告；
- ComfyUI 生图 / 视频；
- Claude Code / Codex 多步骤代码任务；
- 大文档解析与向量化；
- 长音频 STT；
- 长文本 TTS；
- 邮件、Webhook、报告投递。
```

任务表必须保存：

```text
- 当前步骤；
- 输入快照；
- 中间产物；
- 输出文件；
- 错误信息；
- 重试次数；
- 是否可恢复；
- 锁占用记录；
- 执行 worker。
```

推荐实现：

```text
MVP：Celery + Redis + PostgreSQL task table
增强：Celery + Redis + result backend + Flower 监控
长期：Temporal + PostgreSQL，实现可恢复工作流和补偿事务
```

---

## 12. 日志与审计

### 12.1 日志类型

| 日志 | 说明 |
|---|---|
| chat_log | 聊天日志 |
| tool_log | 工具调用日志 |
| permission_log | 权限确认日志 |
| code_diff_log | 代码修改 diff |
| task_log | 后台任务日志 |
| error_log | 错误日志 |
| system_log | 系统状态日志 |

---

### 12.2 审计要求

每次工具调用需要记录：

```text
- 用户输入
- 触发意图
- 调用工具
- 输入参数
- 权限级别
- 是否经过确认
- 执行结果
- 错误信息
- 输出文件
- 耗时
```

---

## 13. 部署方案

### 13.1 本地部署拓扑

```text
Mac 本机
 ├─ Frontend: Next.js
 ├─ Backend: FastAPI
 ├─ Redis
 ├─ PostgreSQL
 ├─ Ollama
 ├─ MLX Server
 ├─ ComfyUI
 ├─ TTS Service
 ├─ STT Service
 ├─ Codex CLI
 ├─ Claude Code
 └─ Hermes
```

---

### 13.2 推荐端口

| 服务 | 端口 |
|---|---|
| Frontend | 3000 |
| Backend API | 8000 |
| PostgreSQL | 5432 |
| Redis | 6379 |
| Ollama | 11434 |
| ComfyUI | 8188 |
| TTS Service | 8020 |
| STT Service | 8030 |
| Hermes Adapter | 8040 |

---

### 13.3 环境变量

```env
APP_ENV=local
DATABASE_URL=postgresql://user:password@localhost:5432/local_ai_bot
REDIS_URL=redis://localhost:6379/0
OLLAMA_BASE_URL=http://localhost:11434
COMFYUI_BASE_URL=http://localhost:8188
TTS_BASE_URL=http://localhost:8020
STT_BASE_URL=http://localhost:8030
STORAGE_DIR=/Users/jamesyee/ai-bot-storage
CODE_WORKSPACE_ROOT=/Users/jamesyee/projects
ENABLE_CODE_AGENT=true
ENABLE_HERMES=true
```



### 13.4 Apple Silicon 部署与内存调优建议

本项目在高内存 Mac 上运行时，应将“稳定性”优先于“极限并发”。部署脚本应包含本地资源检查和保守默认值。

推荐初始化检查：

```bash
# 查看内存压力
memory_pressure

# 查看虚拟内存和 swap
vm_stat
sysctl vm.swapusage

# 查看关键进程
ps aux | grep -E "ollama|mlx|comfy|python|node"
```

推荐默认策略：

```text
- Ollama / MLX 大模型默认不永久常驻；
- ComfyUI 视频生成时暂停本地 LLM 长推理；
- 每次 high/exclusive 任务启动前记录内存快照；
- swap 超过阈值时自动降级模型或排队；
- 前端显示“本地资源等待”而不是让请求无响应；
- 所有可选系统参数调优必须由用户手动确认。
```

可选高级调优项：

```bash
# 示例：提高 macOS iogpu wired limit。具体值必须结合机器内存和 macOS 版本测试，不建议默认执行。
sudo sysctl iogpu.wired_limit_mb=XXXX
```

注意：该类内核参数属于高级调优项。开发文档和安装脚本只应给出说明和检测能力，不应在默认安装流程中自动修改。建议先通过资源锁、模型卸载、任务队列和并发限制解决稳定性问题，再考虑系统参数调优。

---

## 14. 目录结构

```text
local-ai-bot/
 ├─ backend/
 │   ├─ app/
 │   │   ├─ main.py
 │   │   ├─ api/
 │   │   │   ├─ chat.py
 │   │   │   ├─ tts.py
 │   │   │   ├─ stt.py
 │   │   │   ├─ image.py
 │   │   │   ├─ files.py
 │   │   │   ├─ tools.py
 │   │   │   └─ permissions.py
 │   │   ├─ core/
 │   │   │   ├─ config.py
 │   │   │   ├─ intent_router.py
 │   │   │   ├─ model_router.py
 │   │   │   ├─ memory.py
 │   │   │   ├─ security.py
 │   │   │   └─ logging.py
 │   │   ├─ providers/
 │   │   │   ├─ ollama_provider.py
 │   │   │   ├─ mlx_provider.py
 │   │   │   ├─ lmstudio_provider.py
 │   │   │   ├─ comfyui_provider.py
 │   │   │   ├─ tts_provider.py
 │   │   │   ├─ stt_provider.py
 │   │   │   ├─ codex_provider.py
 │   │   │   ├─ claude_code_provider.py
 │   │   │   └─ hermes_provider.py
 │   │   ├─ services/
 │   │   │   ├─ chat_service.py
 │   │   │   ├─ tts_service.py
 │   │   │   ├─ stt_service.py
 │   │   │   ├─ image_service.py
 │   │   │   ├─ document_service.py
 │   │   │   ├─ code_agent_service.py
 │   │   │   ├─ hermes_service.py
 │   │   │   └─ permission_service.py
 │   │   ├─ models/
 │   │   ├─ schemas/
 │   │   └─ workers/
 │   ├─ workflows/
 │   ├─ prompts/
 │   │   ├─ system/
 │   │   ├─ text/
 │   │   ├─ image/
 │   │   ├─ code/
 │   │   └─ hermes/
 │   ├─ storage/
 │   ├─ requirements.txt
 │   └─ Dockerfile
 │
 ├─ frontend/
 │   ├─ app/
 │   ├─ components/
 │   ├─ lib/
 │   ├─ hooks/
 │   ├─ stores/
 │   └─ package.json
 │
 ├─ docs/
 │   ├─ architecture.md
 │   ├─ api.md
 │   ├─ deployment.md
 │   └─ security.md
 │
 ├─ docker-compose.yml
 ├─ README.md
 └─ .env.example
```

---

## 15. 开发阶段规划

## 阶段 1：基础聊天 MVP

### 目标

跑通本地 LLM 聊天、流式输出和会话保存。

### 任务清单

- 初始化 FastAPI 项目；
- 初始化 Next.js 前端；
- 接入 Ollama Provider；
- 实现 Chat API；
- 实现 SSE / WebSocket 流式输出；
- 建立 chat_session、chat_message 表；
- 实现基础会话列表；
- 支持模型选择。

### 验收标准

```text
用户可以在网页中输入问题，系统调用本地 LLM 流式回答，并保存会话记录。
```

---

## 阶段 2：TTS / STT 语音能力

### 目标

让 Bot 可以听和说。

### 任务清单

- 接入 Piper / Kokoro；
- 实现 TTS API；
- 实现前端音频播放；
- 支持回答后自动朗读；
- 接入 faster-whisper；
- 实现语音上传与转写；
- 前端增加录音按钮。

### 验收标准

```text
用户可以语音输入，系统转写为文本并回答；用户可以点击朗读，让 Bot 用语音播放回答。
```

---

## 阶段 3：ComfyUI 生图能力

### 目标

让 Bot 可以通过聊天生成图片。

### 任务清单

- 实现 ComfyUI Provider；
- 接入 /prompt API；
- 实现任务状态轮询；
- 建立 workflow_template 表；
- 支持 workflow JSON 模板；
- 实现 prompt 优化模板；
- 前端展示图片生成进度；
- 前端展示图片结果卡片。

### 验收标准

```text
用户输入生图需求，系统自动优化 prompt，调用 ComfyUI，返回生成图片。
```

---

## 阶段 4：文件分析与 RAG

### 目标

支持上传文档并基于内容问答。

### 任务清单

- 文件上传接口；
- PDF / Word / Markdown / Excel 解析；
- 文本清洗与切片；
- Embedding 生成；
- 接入 Qdrant 或 pgvector；
- 实现文件问答流程；
- 前端展示文件卡片。

### 验收标准

```text
用户上传 PDF 或 Markdown 文件后，可以让 Bot 总结、提取重点、基于文件回答问题。
```

---

## 阶段 5：Codex / Claude Code 接入

### 目标

让 Bot 可以受控调用代码 Agent。

### 任务清单

- 实现 Codex Adapter；
- 实现 Claude Code Adapter；
- 建立 code_task 表；
- 实现只读分析模式；
- 实现 patch plan 模式；
- 实现权限确认卡片；
- 实现 diff 展示；
- 实现任务日志查看；
- 禁止高危命令。

### 验收标准

```text
用户可以要求 Bot 分析指定项目代码；涉及修改时，系统必须先展示计划或 diff，并等待用户确认。
```

---

## 阶段 6：Hermes 接入

### 目标

让 Bot 调用 Hermes 执行自动化任务和定时任务。

### 任务清单

- 实现 Hermes Adapter；
- 支持立即执行 Hermes 任务；
- 支持查询 Hermes 任务列表；
- 支持创建 / 暂停 / 恢复定时任务；
- 支持 A 股报告模板；
- 支持 Markdown / HTML 报告输出；
- 支持邮件 / Webhook 推送配置。

### 验收标准

```text
用户可以通过聊天创建和管理 Hermes 任务，例如 A 股盘前简报、午盘热点跟踪、收盘复盘。
```

---

## 阶段 7：权限、安全、日志完善

### 目标

形成可长期使用的本地 AI 工作台。

### 任务清单

- 完善权限分级；
- 增加用户确认机制；
- 增加工具调用审计；
- 增加任务超时机制；
- 增加错误恢复机制；
- 增加日志查看页面；
- 增加系统状态监控；
- 增加模型内存压力提示；
- 增加备份和恢复机制。

---

## 16. MVP 版本范围

第一版建议严格控制范围：

```text
必须完成：
1. Web 聊天界面；
2. 本地 LLM 调用；
3. 流式输出；
4. 会话保存；
5. TTS 朗读；
6. ComfyUI 文生图；
7. 基础文件上传和总结。

暂缓完成：
1. Claude Code 深度接入；
2. Hermes 完整任务管理；
3. 视频生成；
4. 多用户系统；
5. 云端 fallback；
6. 移动端客户端。
```

---

## 17. 风险与注意事项

### 17.1 技术风险

| 风险 | 说明 | 应对 |
|---|---|---|
| 本地模型延迟高 | 大模型推理慢 | 增加模型路由和小模型 fallback |
| 内存压力 | ComfyUI + LLM 同时运行可能占用过高 | 任务排队、内存监控、模型卸载 |
| Codex / Claude Code 权限风险 | 可能修改或删除文件 | 默认只读、确认机制、沙箱目录 |
| 生图任务耗时 | 视频生成可能非常慢 | 异步队列和状态展示 |
| 文件解析不稳定 | PDF / Excel 格式复杂 | 多解析器 fallback |
| Hermes 调用复杂 | Hermes 本身已有任务系统 | 先做最小 Adapter，不直接重写 Hermes |

---

### 17.2 产品风险

| 风险 | 说明 | 应对 |
|---|---|---|
| 功能过多 | MVP 容易失控 | 严格按阶段开发 |
| 用户操作复杂 | 工具太多导致界面混乱 | Intent 自动路由 + 工具状态卡片 |
| 任务不可控 | Agent 执行结果不稳定 | 增加日志、确认、回滚 |
| 安全感不足 | 用户担心 Bot 乱改代码 | 明确展示每次操作和权限 |

---

## 18. 推荐实现顺序

```text
第 1 步：FastAPI + Next.js + Ollama 聊天
第 2 步：接入流式输出和会话保存
第 3 步：接入 TTS 朗读
第 4 步：接入 ComfyUI 文生图
第 5 步：接入文件上传和总结
第 6 步：接入 Codex 只读分析
第 7 步：接入 Claude Code 复杂分析
第 8 步：增加代码修改确认机制
第 9 步：接入 Hermes 立即任务
第 10 步：接入 Hermes 定时任务
第 11 步：完善权限、日志和任务中心
```

---

## 19. 最终产品形态

最终系统应形成如下能力：

```text
一个本地 AI 工作台：

- 可以聊天；
- 可以说话；
- 可以听语音；
- 可以生成图片；
- 可以生成视频；
- 可以处理文档；
- 可以分析代码；
- 可以受控修改代码；
- 可以调用 Hermes 执行自动任务；
- 可以作为 A 股简报、项目开发、文档生成、图像创作、代码工程的统一入口。
```

---

## 20. 给 Codex / Claude Code / Hermes 的执行建议

### 20.1 给 Codex 的建议

Codex 适合执行：

```text
- 后端 FastAPI 项目初始化；
- API 接口实现；
- Provider Adapter 编写；
- 单元测试；
- 小范围代码修改；
- README 和部署脚本生成。
```

### 20.2 给 Claude Code 的建议

Claude Code 适合执行：

```text
- 架构审查；
- 多模块重构；
- 前后端联动修改；
- 权限系统设计；
- 大型代码库文档生成；
- 复杂 bug 定位。
```

### 20.3 给 Hermes 的建议

Hermes 适合执行：

```text
- A 股定时报告；
- 每日开发日报；
- 自动搜索并整理资料；
- 生成 Markdown / HTML 报告；
- 调度本地 LLM 完成周期性任务；
- 通过邮件或 Webhook 推送结果。
```

---

## 21. 结论

本项目建议定位为：

> 本地 AI 工作台 + 聊天式 Agent 控制台。

它的核心不是单一聊天能力，而是通过统一的聊天入口，安全、可控、可审计地调度本地 LLM、TTS/STT、ComfyUI、Codex、Claude Code 和 Hermes。

第一阶段先完成“聊天 + TTS + 生图 + 文件总结”的 MVP，第二阶段接入 Codex / Claude Code，第三阶段接入 Hermes 和自动任务。这样既能快速得到可用产品，又能为后续复杂 Agent 工作流留出架构空间。

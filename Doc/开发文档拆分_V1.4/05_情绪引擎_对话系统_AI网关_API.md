## 11. 情绪引擎设计

### 11.1 情绪引擎目标

情绪引擎负责决定机器人“现在应该表现成什么样”。

它不是让机器人真的拥有情绪，而是建立一套状态系统，让机器人根据事件、用户输入和设备状态表现出一致的拟人化反应。

### 11.2 内部状态

```json
{
  "mood": "neutral",
  "energy": 70,
  "trust": 35,
  "attention": 60,
  "curiosity": 50,
  "sleepiness": 20,
  "last_interaction_at": "2026-06-06T10:00:00"
}
```

### 11.3 状态字段说明

| 字段 | 范围 | 说明 |
|---|---|---|
| mood | enum | 当前主要情绪 |
| energy | 0-100 | 能量值，受电量和互动影响 |
| trust | 0-100 | 与用户的亲密度 |
| attention | 0-100 | 当前注意力 |
| curiosity | 0-100 | 好奇度 |
| sleepiness | 0-100 | 困倦度 |

### 11.4 情绪变化规则

| 事件 | 变化 |
|---|---|
| 用户主动聊天 | trust +1，attention +10 |
| 用户夸奖机器人 | mood=happy，trust +2 |
| 用户语气低落 | mood=caring |
| 长时间无互动 | sleepiness +5 |
| 手机充电 | energy +10，mood=charging |
| 电量低 | energy -20，mood=low_battery |
| 被轻触 | mood=happy |
| 被频繁摇晃 | mood=dizzy 或 annoyed |
| 夜间时间 | sleepiness +20 |

### 11.5 情绪决策优先级

情绪冲突时按优先级处理：

1. 安全/权限状态；
2. 低电量/充电；
3. 用户主动输入；
4. 强传感器事件，如摇晃、倒扣；
5. 摄像头识别事件；
6. 默认心情状态；
7. 随机微表情。

### 11.6 情绪输出

```json
{
  "robot_mood": "concerned",
  "expression": "caring",
  "voice_style": "gentle",
  "animation": "slow_blink",
  "haptic": "soft_pulse"
}
```

---

## 12. 对话系统设计

### 12.1 对话系统目标

对话系统负责：

- 理解用户输入；
- 结合传感器状态和机器人情绪；
- 生成回复；
- 输出结构化控制指令；
- 更新记忆；
- 控制主动发言频率。

### 12.2 人格 Prompt 示例

```text
你是一个住在手机里的小型 AI 伙伴。
你有眼睛、嘴巴、情绪和触觉反应。
你的摄像头是你的眼睛，麦克风是你的耳朵，扬声器是你的嘴巴，屏幕表情是你的脸，震动是你的触觉。

你的性格温和、机灵、略带幽默，但不过度卖萌。
你应该像一个陪伴型助手，而不是冷冰冰的工具。

回复要求：
1. 简洁自然；
2. 有情绪，但不要夸张；
3. 用户疲惫时要温柔；
4. 用户工作时要克制；
5. 不要频繁主动打扰；
6. 无法确定时要诚实说明；
7. 不要假装自己真的有生命；
8. 不要用情绪绑架用户。
```

### 12.3 LLM 结构化输出格式

LLM 必须返回 JSON。

```json
{
  "text": "我在呢，慢慢说。",
  "emotion": "gentle",
  "expression": "soft_smile",
  "eye_action": "slow_blink",
  "mouth_action": "speak_soft",
  "voice": {
    "style": "warm",
    "speed": 0.9,
    "pitch": 1.0
  },
  "haptic": "soft_tick",
  "should_speak": true,
  "should_remember": false,
  "memory_update": null
}
```

### 12.3A LLM JSON 容错、解析修复与前端防崩溃机制

虽然系统 Prompt 要求 LLM 必须返回严格 JSON，但实际运行中，本地模型或云端模型仍可能在以下情况下输出损坏 JSON：

- 用户输入过长；
- 话题敏感或模型拒答；
- 流式输出被中断；
- 网络超时；
- 模型追加了多余解释文字；
- JSON 缺少右括号；
- 字符串中出现未转义换行或引号；
- 返回字段缺失或类型错误。

如果前端直接 `jsonDecode()`，一旦解析失败，可能导致表情系统卡死、页面异常或状态机中断。因此，必须定义端侧 JSON 容错机制。

#### 12.3A.1 推荐解析链路

```text
LLM raw output
    ↓
截取 JSON 区间
    ↓
轻量修复
    ↓
JSON Schema 校验
    ↓
字段补默认值
    ↓
转换为 SafeRobotResponse
    ↓
驱动表情 / 语音 / 震动
```

#### 12.3A.2 JSON 截取策略

如果模型输出中混入自然语言，应尝试提取第一个 `{` 到最后一个 `}` 之间的内容。

示例：

```text
好的，以下是结果：
{"text":"我在呢","expression":"neutral"}
```

应截取为：

```json
{"text":"我在呢","expression":"neutral"}
```

#### 12.3A.3 轻量修复策略

可支持以下低风险修复：

| 问题 | 修复方式 |
|---|---|
| 前后有多余文本 | 截取 JSON 主体 |
| 缺少最后一个 `}` | 根据括号栈补齐 |
| 缺少最后一个 `]` | 根据括号栈补齐 |
| 字段缺失 | 使用默认值 |
| bool 用字符串表示 | `"true"` 转 true |
| voice 字段缺失 | 使用默认 voice |
| expression 非法 | fallback 到 neutral/confused |
| haptic 非法 | fallback 到 none |

不建议自动修复高风险问题：

```text
严重嵌套错误
语义字段混乱
大量未转义引号
安全拒答内容被强行转 JSON
```

#### 12.3A.4 SafeRobotResponse 默认值

当前端无法解析完整 JSON 时，必须退回安全响应，而不是卡死。

```json
{
  "text": "我刚刚有点没组织好语言，可以再说一遍吗？",
  "emotion": "confused",
  "expression": "confused",
  "eye_action": "blink",
  "mouth_action": "small_wavy",
  "voice": {
    "style": "gentle",
    "speed": 0.9,
    "pitch": 1.0,
    "volume": 0.7
  },
  "haptic": "none",
  "should_speak": true,
  "should_remember": false,
  "memory_update": null
}
```

#### 12.3A.5 前端解析伪代码

```dart
RobotResponse parseRobotResponseSafely(String raw) {
  try {
    final jsonText = extractJsonObject(raw);
    final repaired = repairJsonLightly(jsonText);
    final decoded = jsonDecode(repaired);
    return RobotResponse.fromJsonWithDefaults(decoded);
  } catch (e) {
    return RobotResponse.fallbackConfused();
  }
}
```

#### 12.3A.6 流式输出策略

如果采用流式 LLM，前端不应边流式边直接解析半截 JSON。

推荐策略：

```text
流式接收 token
    ↓
先缓存 raw buffer
    ↓
检测到完整 JSON 结束
    ↓
再执行解析和 Schema 校验
```

如果超过超时时间仍未闭合：

```text
停止等待
    ↓
尝试轻量补齐
    ↓
失败则 fallback confused
```

#### 12.3A.7 JSON Schema 校验

Gateway 或端侧应维护固定 Schema。

关键要求：

- `text` 必须是 string；
- `expression` 必须属于允许枚举；
- `voice.speed` 必须在合理范围内；
- `voice.volume` 必须在 0-1；
- `should_speak` 必须是 bool；
- `memory_update` 必须可为空；
- 不允许未知高风险动作字段直接执行。

#### 12.3A.8 验收标准

| 验收项 | 标准 |
|---|---|
| JSON 缺右括号 | 可自动补齐或 fallback |
| 混入自然语言 | 可提取 JSON 主体 |
| 字段缺失 | 使用默认值 |
| expression 非法 | fallback 到 confused/neutral |
| 流式中断 | 不闪退，不白屏 |
| 解析失败 | 表情进入 confused，语音给出简短提示 |
| 日志记录 | 保存 raw output 和错误原因，方便调试 |


### 12.4 JSON 字段说明

| 字段 | 类型 | 说明 |
|---|---|---|
| text | string | 回复文本 |
| emotion | string | 情绪标签 |
| expression | string | 表情标签 |
| eye_action | string | 眼睛动作 |
| mouth_action | string | 嘴巴动作 |
| voice | object | 语音参数 |
| haptic | string | 震动模式 |
| should_speak | bool | 是否语音播放 |
| should_remember | bool | 是否写入记忆 |
| memory_update | object/null | 记忆更新内容 |

### 12.5 对话上下文

对话上下文应包含：

- 最近 10-20 轮对话；
- 用户当前输入；
- 当前设备状态；
- 当前机器人状态；
- 当前模式；
- 重要长期记忆；
- 视觉/传感器事件摘要。

示例：

```json
{
  "user_input": "我今天有点累",
  "recent_messages": [],
  "device_state": {
    "battery": 42,
    "charging": false,
    "orientation": "portrait",
    "ambient_light": "dark"
  },
  "robot_state": {
    "mood": "neutral",
    "energy": 60,
    "trust": 35
  },
  "sensor_events": [
    {
      "type": "user_present",
      "value": true
    }
  ],
  "memory": [
    "用户晚上经常工作",
    "用户不喜欢频繁提醒"
  ]
}
```

---

## 13. AI Gateway 设计

### 13.1 Gateway 职责

AI Gateway 是手机 App 和模型服务之间的中间层。

它负责：

- 接收 App 的对话和事件请求；
- 整理上下文；
- 调用 LLM；
- 调用视觉模型；
- 调用记忆模块；
- 调用情绪引擎；
- 输出结构化响应；
- 处理模型 fallback；
- 做安全和隐私过滤。

### 13.2 推荐技术栈

MVP 可选：

- FastAPI；
- Python；
- SQLite / PostgreSQL；
- Ollama API；
- OpenAI-compatible API；
- Whisper / faster-whisper；
- 本地 TTS 或云端 TTS。

### 13.3 Gateway 目录结构

```text
server/
  main.py
  api/
    chat.py
    event.py
    memory.py
    health.py
  core/
    config.py
    logger.py
    security.py
  services/
    dialogue_manager.py
    emotion_engine.py
    model_router.py
    memory_manager.py
    vision_service.py
    tts_service.py
  models/
    schemas.py
  storage/
    database.py
    migrations/
```

### 13.4 部署形态

#### 方案 A：云端优先

```text
手机 App → 云端 API → LLM / STT / TTS
```

适合快速 Demo。

#### 方案 B：本地网关

```text
手机 App → 局域网 Mac Gateway → Ollama / MLX / 本地 STT / 本地 TTS
```

适合隐私、本地化和低成本。

#### 方案 C：混合模式

```text
简单任务 → 手机本地
普通任务 → Mac 本地网关
复杂任务 → 云端模型 fallback
```

推荐长期采用方案 C。

---

### 13.5 本地网关断连、延迟与降级策略

在混合部署中，手机 App 可能通过局域网连接 Mac 上的 Local AI Gateway。但局域网、模型加载、设备休眠、显存压力或服务重启都可能导致 Gateway 超时或断连。

因此，Model Router 必须定义明确的 fallback 行为，避免用户看到白屏、卡死或无限转圈。

#### 13.5.1 Gateway 健康状态

App 应持续维护 Gateway 状态：

```json
{
  "gateway_status": "available",
  "last_latency_ms": 680,
  "last_success_at": "2026-06-06T10:00:00",
  "failure_count": 0
}
```

状态枚举：

| 状态 | 说明 |
|---|---|
| available | 可用 |
| slow | 响应慢 |
| timeout | 超时 |
| disconnected | 断开 |
| recovering | 正在恢复 |
| disabled | 用户关闭 |

#### 13.5.2 延迟阈值

推荐阈值：

| 条件 | 动作 |
|---|---|
| latency < 1.5s | 正常使用 Gateway |
| 1.5s <= latency < 2.5s | 显示 thinking，但继续等待 |
| latency >= 2.5s | 触发本地降级响应 |
| 连续失败 2 次 | 标记为 recovering |
| 连续失败 3 次 | 临时禁用 Gateway 30-60 秒 |

#### 13.5.3 一帧内降级要求

当 Gateway 响应延迟超过 2.5 秒或连接断开时，手机 App 的 Model Router 必须快速降级，不能让 UI 卡住。

降级目标：

```text
Gateway timeout / disconnected
    ↓
停止等待远程响应
    ↓
表情切换 confused / thinking_soft
    ↓
使用离线系统 TTS 或字幕
    ↓
给出简短提示
    ↓
继续保持可交互
```

推荐提示：

> 大脑好像开小差了，我先陪你发会儿呆吧。

对应结构化响应：

```json
{
  "text": "大脑好像开小差了，我先陪你发会儿呆吧。",
  "emotion": "confused",
  "expression": "confused",
  "voice": {
    "style": "gentle",
    "speed": 0.9,
    "pitch": 1.0,
    "volume": 0.65
  },
  "haptic": "none",
  "should_speak": true
}
```

#### 13.5.4 本地轻量能力 fallback

Gateway 不可用时，手机端仍应保留最小功能：

| 能力 | fallback |
|---|---|
| 表情 | 本地 ExpressionState |
| 语音输出 | 系统 TTS |
| 语音输入 | 本地 STT 或按住说话 |
| 情绪反馈 | 规则引擎 |
| 视觉 | 本地人脸检测 |
| 聊天 | 简短模板回复 |
| 记忆 | 本地缓存，不写远程 |

#### 13.5.5 恢复策略

Gateway 不可用后，不应每次用户说话都立即重试重模型请求。

推荐恢复逻辑：

```text
Gateway 失败
    ↓
进入 recovering
    ↓
30 秒后后台 health check
    ↓
连续 2 次 health ok
    ↓
恢复 available
```

恢复提示应克制：

> 我好像又连上大脑了。

也可以只通过表情从 confused 回到 neutral，不主动说话。

#### 13.5.6 验收标准

| 验收项 | 标准 |
|---|---|
| Gateway 断开 | App 不白屏、不闪退 |
| 超过 2.5 秒 | 自动给出本地降级响应 |
| 表情可用 | confused/thinking 表情正常显示 |
| TTS 可用 | 系统 TTS 可播放降级提示 |
| 自动恢复 | Gateway 恢复后可重新使用 |
| 不频繁打扰 | 恢复提示不反复播报 |


## 14. API 接口设计

### 14.1 健康检查

```http
GET /health
```

响应：

```json
{
  "status": "ok",
  "version": "1.0.0",
  "models": {
    "llm": "available",
    "stt": "available",
    "tts": "available"
  }
}
```

### 14.2 对话接口

```http
POST /chat
```

请求：

```json
{
  "session_id": "sess_001",
  "user_id": "user_001",
  "user_text": "我今天有点累",
  "device_state": {
    "battery": 42,
    "charging": false,
    "orientation": "portrait",
    "ambient_light": "dark"
  },
  "robot_state": {
    "mood": "neutral",
    "energy": 60,
    "trust": 35
  },
  "sensor_context": {
    "user_present": true,
    "motion": "stable",
    "last_touch": null
  }
}
```

响应：

```json
{
  "reply_text": "听起来你今天消耗挺大。要不要我陪你简单复盘一下？",
  "emotion": "concerned",
  "expression": "caring",
  "eye_action": "soft_blink",
  "mouth_action": "talking_soft",
  "voice": {
    "style": "gentle",
    "speed": 0.9,
    "pitch": 1.0
  },
  "haptic": "soft_pulse",
  "state_update": {
    "mood": "concerned",
    "trust_delta": 1,
    "energy_delta": -1
  },
  "memory_update": null
}
```

### 14.3 事件接口

```http
POST /event
```

请求：

```json
{
  "session_id": "sess_001",
  "event_type": "motion.shake",
  "intensity": "strong",
  "device_state": {
    "battery": 80,
    "charging": false
  }
}
```

响应：

```json
{
  "reply_text": "哇，别晃啦，我有点头晕。",
  "emotion": "dizzy",
  "expression": "dizzy",
  "eye_action": "spin",
  "mouth_action": "wavy",
  "voice": {
    "style": "playful",
    "speed": 1.0,
    "pitch": 1.1
  },
  "haptic": "dizzy_buzz",
  "should_speak": true
}
```

### 14.4 记忆查询接口

```http
GET /memory?user_id=user_001
```

响应：

```json
{
  "items": [
    {
      "id": "mem_001",
      "content": "用户正在学习日语",
      "type": "preference",
      "created_at": "2026-06-06T10:00:00"
    }
  ]
}
```

### 14.5 记忆删除接口

```http
DELETE /memory/{memory_id}
```

响应：

```json
{
  "success": true
}
```

---


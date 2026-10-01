# Robot 侧 EnterpriseAI 对接评审与需求清单

> 日期：2026-09-30  
> 评审对象：[Robot 接入 EnterpriseAI 网关开发设计 V1.0](/Users/jamesyee/Desktop/AIG/EnterpriseAI/docs/robot-gateway-integration-development-v1.md)  
> 对接方：EnterpriseAI 网关、Robot 服务端、Android APK、语音服务。  
> 本文是独立评审意见与契约建议，不修改原设计，不表示双方已确认或完成开发。

## 1. 评审结论

**总体架构方向认可，建议有条件通过架构评审，但先不要冻结接口和排期。** 原稿关于设备身份、资源授权、幂等、持久回合、取消、记忆隔离，以及本地云台控制的边界较完整，应保留。

需要修正的重点是 Robot 基线与过渡实施范围。现有 APK 是同步 HTTP、客户端短期历史、M4A 录音、客户端逐段合成播放的实现；它并不支持设备 Token、托管会话、202 回合、SSE 或受认证媒体下载。旧 APK 无法仅修改 baseUrl 就透明接入新协议。

建议将“过渡兼容接入”和“新版回合协议接入”分别定义交付边界。首个试点可不开放长期记忆和企业工具，但不能把现有视觉、人设、停止、完整播报等功能在迁移中静默退化。

本次核对了 Robot 工作区实际代码及已有部署记录；原稿关于 EnterpriseAI 内部 C# 实现的描述作为设计方提供的依据，本次未独立完成该仓库的代码审计。

## 2. 应补入原稿的 Robot 实际基线

| 项目 | 已核实的 Robot 实现 | 对原稿的修订建议 |
|---|---|---|
| 客户端 | Flutter/Dart + Android Kotlin，主要联调设备为华为 P30 Pro | 不再将技术栈标为待确认；多平台目录不代表同等能力 |
| Robot 后端 | Python 标准库 `HTTPServer`，同步阻塞请求 | 过渡适配不能继续依赖进程内全局状态或让所有设备串行等待 |
| 部署 | 网关在语音服务器 `~/video_dub_pipeline/services/mengmeng_gateway/`，本机 8787；语音服务本机 8801 | 已不依赖 Mac；不要设计回到 Mac 的自动回退 |
| 手机入口 | `https://aipipeline.hiqer.top/mengmeng/gw` | 过渡期保留入口，通过明确版本/设备灰度切换 |
| 模型 | 统一调用 MiniMax，当前配置 MiniMax-M3 | `LmStudioClient`/`model_provider=lmstudio` 是历史命名，不代表本地模型 |
| 唤醒 | Sherpa 本地 KWS；异常时 STT 备用识别 | 唤醒不等于一次问答回合，需独立处理备用转写 |
| 新唤醒词 | 小易、你好小易、小易小易均映射 `mengmeng`；原词保留 | “小易”是 Robot 唤醒别名，不是 EnterpriseAI 小易应用身份 |
| 称呼 | 萌萌、小远当前称呼为“权哥”；群群老师有独立规则 | 新 Profile 初始化需保持，不能沿用“老板”或“大大” |
| KWS 音频 | 16kHz、单声道 PCM16，在本地模型使用 | 不要与上传音频格式混淆 |
| 上传录音 | MediaRecorder：MPEG-4 容器、AAC、配置 16kHz/单声道/64kbps；`.m4a` 文件 | 原稿 WAV 是目标格式，不是旧 APK 现状；实际参数仍需解码校验 |
| STT 接口 | `POST /stt`，原始二进制，`x-audio-format: m4a` | 不是 multipart，也不是 `?format=m4a` 的 APK 接口 |
| TTS 接口 | `POST /tts` JSON，返回 MP3 字节 | 当前不存在 audioId/音频下载 URL 协议 |
| 播报 | 客户端按最多 300 个 Unicode 字符分段，等待真实播放完成；支持系统 TTS 回退 | 新版不能在服务端完成或估算时长到期后提前恢复收音 |
| 口型 | `isSpeaking` 驱动周期动画 | 原稿“振幅驱动”是新增开发项，不是现有能力 |
| 对话历史 | 手机内存最近 6 轮、总长 12,000、单条 2,000；按代码字符长度计 | 不应直接迁移为默认永久会话或双重拼历史 |
| 记忆/情绪 | Python 进程内共享对象；重启丢失，没有可靠主体隔离 | 不自动导入旧记忆；进程全局 STT 恢复与调试状态也需隔离 |
| 认证和流 | 当前请求无设备 Bearer；客户端不具备 SSE/持久回合处理 | 即使过渡阶段，也需要最小 APK 升级或明确限定的内部试验方案 |
| 表情 | 15 个 RobotExpression，无 `sad` | 不能直接按原稿五表情集合冻结能力契约 |

代码依据见第 9 节。最新一次新增唤醒词版本记录为 154 项 Flutter 测试通过；这些测试不等于已通过 EnterpriseAI 对接验收。

## 3. 契约冻结前必须处理的问题

以下 P0 表示“不解决会阻碍对接或破坏既有行为”，不是对整个项目的安全严重等级。

### P0-01 过渡兼容不是零 APK 改造

**对应原稿：3.2、4.3、16.2、19.2。**

原稿要求设备认证，又保留现有 APK 协议；当前 APK 不发送认证头、稳定 clientTurnId 或幂等键。旧响应解析器只认识顶层 snake_case RobotResponse，收到 `{success,data}` 或 202 时不会进入新状态机，可能生成错误的默认回复。

**Robot 要求：**

- 明确支持的最低 APK 版本。过渡版至少加入设备身份、安全凭据存储、统一认证传输、稳定请求 ID 和错误分类。
- `/chat` 等兼容接口仍返回旧格式的最终响应；新回合端点另由专用客户端处理，禁止把 202 包装成回答成功。
- 认证必须覆盖 chat、STT、TTS、图片、记忆、媒体与 SSE，不能只改 AiGatewayClient：目前语音组件分别自行创建 HttpClient。
- 不允许服务端通过客户端自报 persona/session_id 推断用户身份；不以所有旧 APK 共用一个企业用户作为正式迁移方案。
- 非幂等旧 APK 仅可受限内测，不能承诺网络重试不会重复执行或计费。

**验收：**旧兼容 DTO 正确解析；新版能处理 202；所有受控入口要求有效身份；重试一次语音问题只有一个业务回合。

### P0-02 明确 M4A 到 WAV 的转换责任

**对应原稿：8.3、11.2、21.3。**

现有上传是 AAC/M4A，本地 KWS 才是 PCM16。把上传直接标为 WAV 会造成解码失败。

**Robot 建议：**过渡接入接受真实 M4A，由受控适配层校验、转成约定的 WAV；新版 APK 是否直接产生 WAV 另列音频采集改造。能力配置应返回接受的 MIME/容器/编码/采样率/声道，而不只给大小与时长。

**验收：**真实手机 M4A 与标准 WAV 分别通过；伪造扩展名被拒绝；超过 30 秒或大小上限明确报错；录音时间不被错误计入“回合处理超时”。

### P0-03 新协议缺少唤醒备用转写和唤醒确认的完整入口

**对应原稿：9.1、11.2、14.1。**

原稿认可 STT 唤醒回退，但公开协议仅有“音频输入创建问答 turn”。当前备用检测需要先识别短音频，再在手机匹配唤醒词；未命中时不应该调用 LLM、创建对话消息或生成 TTS。现有 `/event` 还承担 `wake` 问候，目标事件列表没有明确对应项。

**Robot 要求：**

- 冻结受认证、限流、可关闭的“仅转写”能力，可采用独立接口或明确的 transcription operation；不得为它创建普通问答回合。
- 标明 `purpose=wake_detection`、保存策略、最大采样时长和频率、无语音结果；只计真实 STT 用量，不计 LLM 问答。
- 明确唤醒成功后的确认声/问候由本地预设还是受控服务产生；不让“叫小易”变成业务问题进入历史。
- 纯转写不能依赖已建立的业务 session，否则存在“先唤醒才能建会话、先建会话才能备用唤醒”的循环；仍必须绑定有效设备身份。
- 新协议关闭备用 STT 时，APK明确停用该回退并提供本地提示，不能无限重试或静默上传环境音。

**验收：**未命中只发生受控转写；命中三个“小易”别名均进入 mengmeng Profile，不进入 EnterpriseAI 小易应用；离线本地唤醒仍可给出本地反馈。

### P0-04 保证完整播报，明确 TTS 主责方

**对应原稿：9.2、11.3、11.5、13.1、19.4。**

原稿首期单 segment、分句放第三阶段；但现有语音服务器存在前 600 字限制，Robot 已通过客户端 300 字分段避免丢尾。若新服务将完整长回复直接交给该 Worker，可能重新引入截断。`maxReplyChars=300` 的生成建议不能作为可靠的防截断机制。

**Robot 要求：**

- 过渡版由客户端负责 TTS，或由新回合服务负责 TTS，二选一；禁止收到 audioId 后 APK 又按 text 重跑 `/tts`。
- 首期可以不做流式，但必须支持完整长文本：服务端内部安全分段并产出完整音频，或协议首期允许有序多个 segment。
- 禁止静默截取文本。若限制回复长度，需明确摘要/拒绝策略及展示文本与朗读文本的对应关系。
- 规定 `segmentIndex` 或等价顺序、稳定 segmentId、是否最后一段、每段实际朗读文本；去重不只按 SSE seq，还要防止快照与事件重复播放同一片段。
- 补齐“仅重试 TTS/重新生成过期音频”的契约：复用既有回答和冻结语音配置，不再次调用 LLM；采用独立 operationId 和计量。
- 系统 TTS 是否允许回退由有效策略与本地用户开关共同决定；关闭播报、取消或解绑后不得回退发声。

**验收：**超过 600 字、含换行和 emoji 的回答完整播放；下载/合成重试不增加模型消息；取消后迟到音频不播放；TTS 失败可保留文本并退出等待。

### P0-05 表情和状态结构必须按实际能力协商

**对应原稿：7.2、7.3、11.4、16.2、21.3。**

当前支持：`neutral, happy, listening, thinking, speaking, confused, caring, sleepy, dizzy, annoyed, charging, low_battery, sleeping, surprised, focus`。Dart 枚举中 `lowBattery` 对应线上 `low_battery`。`sad` 目前会被旧解析器降为 confused。

**Robot 要求：**

- 至少保留当前常用 `caring/confused`，默认不发送 APK 未声明的 sad；若需 sad→caring 等映射，必须显式版本化，不能宣称语义完全相同。
- 旧响应还包含 eye_action、mouth_action、haptic、voice、robot_state、should_speak；逐项标明保留、适配默认值或废弃，不直接丢字段。
- 操作阶段由 APK 主责，但“speaking”状态不能永久遮盖回答的 caring/happy 情绪；区分本地工作阶段与情绪表现两个维度。
- 未知表情降为 neutral 是合理目标，但需更新/适配旧端默认 confused 的行为。
- 表情词不能进入实际朗读文本；振幅口型另列开发项，首期保留现有动画亦可。

**验收：**“羞涩微笑”转换为 caring 动画且不朗读；未知值安全降级；文本、表情与本地播报状态无相互覆盖。

### P0-06 服务端历史接管不应默认恢复旧会话或纳入未交付回复

**对应原稿：1.2、8.2、10.3、13.2。**

当前客户端在新唤醒/会话、切人设、关闭、切后台等路径清理短期历史；仅将完整交付的有效非规则问答写入历史。原稿改为持久历史并支持恢复，是行为变化。

**Robot 要求：**

- 服务端唯一组织历史，旧 context 不逐轮再注入；持久映射键应含已认证身份、设备、绑定代次、人设及旧 session_id。
- 区分“可恢复记录”和“默认自动续聊”。建议首版仍默认新唤醒创建新逻辑会话，继续旧会话须显式选择或产品确认。
- 明确后台、隐私、人设切换和主人换绑分别是暂停、关闭还是新会话；不要仅依赖一个通用 close 行为。
- 生成结果可以留作审计，但“未展示、未播放、取消或只播一部分”的回答是否注入后续上下文必须有策略，不能仅依据 turn.completed。
- 回执缺失不能永久阻塞后续问答，也不能直接推定用户已听完。首期可排除未确认交付的助手内容，并通过客户端已交付水位补充；策略需双方冻结。

**验收：**迁移后六轮不重复；取消回答不被下一轮当作用户已知事实；重新唤醒/换人设符合约定；重启不自动重播旧语音。

### P0-07 生成完成不代表设备空闲，取消优先级需要修正

**对应原稿：9.4、10、14.2、15.2。**

原稿正确区分生成和播放，但终态释放活动槽位后，设备可能还在播放；此时自动事件可能创建新回合。原稿又把“用户主动输入”排在“用户显式取消”之前，容易造成竞态。

**Robot 要求：**

- 服务器生成锁与 APK 麦克风/播放占用分开。生成终态可以释放槽位，但不能据此触发新的自动问候。
- 主动事件采用本地空闲许可/短期可用状态并二次校验；取消、隐私、撤销与生命周期停止优先于新输入，最后才是自动事件。
- 本地必须先停播和失效旧 generation，再异步请求取消；本地恢复不能等待取消 HTTP 成功。
- cancelled 请求与 completed 响应竞争时，APK 已失效的回合始终不能复活。
- 保留 VoiceMode（关闭/唤醒/连续）与阶段分离；无语音、短暂断网不能一律跳 Idle 并关闭用户希望保持的唤醒。

**验收：**生成完成但仍播报时收到 presence 不抢答；取消与新输入同时发生不播放旧音频；重复取消、离线取消均能立即停本地资源。

### P0-08 新接口没有完整承接本地隐私与能力开关

**对应原稿：7.3、9.1、13、18。**

现有 settings 包含 allow_speech_input/output、allow_vision、allow_memory、privacy_mode、keep_awake。目标 turns 仅有 output.speech，且 Profile 决定记忆，缺少用户主动收紧权限的契约。

**Robot 要求：**用户开关可以减少服务器已授权能力，不能扩大权限。冻结会话或回合级“禁用记忆读写/检索”“禁用图像上传”“关闭输出”的表达；keep_awake 仍是本地设置。

隐私开启时 APK停止采集、取消当前输出、丢弃迟到结果。服务端对已接受数据的取消、保留、删除范围需要清楚反馈；隐私开关不是自动删除所有历史的替代接口。用户重新联网后不得自动补发隐私开启前的未发送录音。

**验收：**不记忆模式不读写长期记忆；无视觉授权不上传图片；隐私中没有后台转写、媒体预取或自动重播。

## 4. 应补齐的 P1 契约

| ID | 对应原稿 | Robot 要求 | 验收重点 |
|---|---|---|---|
| P1-01 | 6.4、15.1 | 忙碌错误返回有权访问的 activeTurnId、状态查询入口、重试建议；细分设备忙/会话忙 | APK 无需猜测冲突回合，也不能看到他人回合 |
| P1-02 | 9.3、18.1 | 明确全部代理的 SSE 支持和 polling 后备路径；提供事件保留期、重连间隔与快照一致性规则 | 现有 mengmeng_proxy 使用 `requests` 并读取完整 `resp.content`，不能直接用于 SSE；需流式代理或新路径 |
| P1-03 | 18.2、18.4 | 协商 deadline 起点、排队/上传/生成/下载/播放预算；返回 deadlineAt 和可诊断 stage | 25 秒预算不包含用户思考、录音和实际播放；阶段超时可区分 |
| P1-04 | 7、18 | 补设备可用的健康/能力诊断契约，区分离线、未绑定、认证失效、模型/语音不可用 | 错误进入右上角提示中心，不播报内部堆栈或铺满主屏 |
| P1-05 | 8.4、9.4 | 指定媒体过期后的再合成 API、回执补传期限及终态后追加回执规则 | 不重跑 LLM，不因回执失败阻止下一轮 |
| P1-06 | 4.3 | 对刷新响应丢失给出确定恢复流程；评估设备绑定的短期幂等刷新结果回取 | 移动网切换不应频繁被迫重新扫码；是否支持回取须保持轮换/重放安全 |
| P1-07 | 12、19 | 图文可不进入首个试点，但明确关闭提示和旧视觉路由的授权兼容计划 | 不能把现有“看一下”静默退成普通文本；不能保留匿名旁路 |
| P1-08 | 13.1 | 提供稳定 personaKey→profileId 映射、配置版本；称呼与音色独立于唤醒别名 | 小易别名仍是萌萌人设；“权哥”称呼保持；切人设不串历史 |
| P1-09 | 11.3、13.1 | 允许本地降低音量与静音；区分媒体生成策略和设备播放音量 | profile不能强制覆盖用户静音，系统TTS回退遵守同一策略 |
| P1-10 | 6、8、9 | 交付 OpenAPI、JSON Schema、真实脱敏样例和可运行 mock | 可用同一组 fixture 自动校验双方 DTO，不靠文字描述推测字段 |

原稿对未知上游结果、计费去重、设备撤销及媒体授权已有较充分设计，本次建议保留，不把外部供应商不支持的 exactly-once 包装成承诺。

## 5. 现有接口映射要求

所有旧路径均相对于 `/mengmeng/gw`；新路径相对于 `/api/v1/robot`。下表用于补全原稿 16.2。

| 旧接口 | 实际输入/输出 | 目标映射和注意事项 |
|---|---|---|
| GET /health | gateway/stt/llm/tts 状态对象 | 兼容旧健康结构；新版健康协议单独约定 |
| POST /chat | text、persona、settings、context；返回顶层 RobotResponse | 认证后的 session 映射 + text turn；兼容层等待最终文本，不把 202 原样交给旧解析器 |
| POST /chat/vision | 上述字段 + image_base64、mime_type | 私有 image media + 同一 turn 的文本/图像；图片处理与模型费用统一治理 |
| POST /vision | image_base64、prompt、persona、settings | 映射受控图文回合或明确退役，不留模型直连旁路 |
| POST /stt | 原始 M4A，x-audio-format；返回 ok/text/raw_text/normalized_text/flags/error | 区分问答音频与仅转写；备用唤醒不建普通 turn |
| POST /tts | text/style/persona/speed；返回 MP3 | 兼容版单独合成；新协议改为已有回合音频下载，不重复合成 |
| POST /event | type、persona、settings、source、intensity 等；同步 RobotResponse | tap/wake/shake/charging/low_battery/person_seen/person_left 等逐项映射；固定反馈可本地化 |
| POST /memory/query | keyword → items | 原表不自动迁移；新 API 默认隔离并按开关禁用 |
| POST /memory/delete | 可选 id；旧版无 id 表示全部删除 | 不直接映射为跨作用域删除；明确用户可见范围和确认流程 |
| GET /state | 全局表现状态 | 改为设备/会话作用域或移回本地，不复用当前全局对象 |
| /diagnostics、/debug/* | 联调信息 | 禁止作为新设备凭据可随意访问的公共调试面 |

### 旧响应兼容样例

```json
{
  "text": "权哥，我在呢。",
  "emotion": "caring",
  "expression": "caring",
  "eye_action": "slow_blink",
  "mouth_action": "soft_smile",
  "voice": {"style":"female","speed":0.95,"pitch":1.12,"volume":0.75},
  "haptic": "none",
  "should_speak": true,
  "should_remember": false,
  "memory_update": null,
  "model_provider": "enterpriseai"
}
```

这是面向兼容层的最小示例，不是要求 EnterpriseAI 内部继续使用 snake_case；RobotState 等可选字段应另附完整 schema。规范化错误不能被伪装成模型正常回答。

### 新版回合结果建议补充

以下字段仅为待冻结建议，不代表原协议已经支持：

- `result.segments[].segmentIndex`、`isLast`、`spokenText`：明确顺序与实际朗读范围。
- `result.deliveryPolicy.systemTtsFallbackAllowed`：在本地开关仍允许的前提下使用。
- 错误扩展中的 `activeTurnId/statusUrl/retryAfterMs`：帮助冲突恢复。
- 配置中的 `personaKey`、`acceptedAudioFormats`、`wakeTranscriptionPolicy`、`historyResumePolicy`。
- 明确 transcript 的标准化与过滤结果，便于唤醒 matcher 和本地诊断判断，不要求暴露供应商内部数据。

## 6. Robot 承担的改造范围

| 工作包 | Robot 侧交付 | EnterpriseAI 必须提供的依赖 |
|---|---|---|
| RBT-01 统一网络层 | 所有 HTTP/媒体/SSE 共用认证、刷新、错误分类；安全存储 | 激活/刷新/撤销契约与试点环境 |
| RBT-02 会话客户端 | server session/profile 映射、持久 clientTurnId、恢复与关闭策略 | 明确会话主库、幂等和历史导入边界 |
| RBT-03 回合协调 | 保留本地 generation 与 VoiceMode；处理202、SSE/快照和冲突 | 完整回合 schema、错误码、终态和取消行为 |
| RBT-04 音频交付 | M4A上传或新采集器、受认证下载、有序播放、回执去重 | 媒体格式、完整音频、TTS重试/过期恢复、授权策略 |
| RBT-05 表情适配 | 新旧字段映射、能力集合、表情与操作状态分层 | 冻结表达 schema 和 Profile 配置 |
| RBT-06 本地行为 | 唤醒/备用STT开关、隐私即时停止、事件去抖、硬件仍本地 | 仅转写能力、事件映射、有效策略反馈 |
| RBT-07 兼容服务 | 替换直接模型调用、持久身份/session映射、旧协议转换 | 用户委托凭证、托管会话接口、费用主责与最小权限 |
| RBT-08 真机验收 | 断网/4G切换/后台/长播报/取消/设备撤销联调记录 | 可注入故障的测试环境、trace查询、双方fixture |

不建议直接把现有 Python 全局内存对象扩充为企业回合数据库。过渡服务可以保留，但持久映射、认证和 SSE 代理需要独立设计；新增并发必须先解决全局情绪、记忆和最近转写串用户的问题。

## 7. 建议联调顺序与增量验收

### 阶段 A 契约补齐

先解决 P0-01 至 P0-08，提供一组设备凭据、三个人设映射、媒体样例、成功/错误/取消/重放 fixture。此阶段不改变正式手机的模型路径。

### 阶段 B 最小受控接入

升级少量试点 APK 的认证与错误处理，保持现有语音服务可用；只迁移受控文本对话，验证身份、单会话历史、称呼、表情和费用归属。明确唯一 TTS 主责方。不支持的功能清楚标记，不能匿名绕回旧服务。

### 阶段 C 新版回合和音频

接入媒体、turn、查询/事件、取消和播放回执；保持本地 KWS 与云台闭环不变。逐步迁移视觉、人设管理和记忆，不把 VAD/全双工重构捆绑成企业接入前置条件。

| 用例 | 原稿验收之外应增加的内容 |
|---|---|
| ROBOT-01 | 真实 M4A 经适配成功，不能把 KWS PCM 误认为上传文件 |
| ROBOT-02 | 小易/你好小易/小易小易均选中 mengmeng；纯唤醒不创建业务用户消息 |
| ROBOT-03 | KWS异常时仅转写受控回退；未命中不调用LLM；隐私开启立即停采集 |
| ROBOT-04 | 旧 RobotResponse 和新信封/202 使用不同解析路径，不发生默认错误对白 |
| ROBOT-05 | caring动画不降为confused，表情词不朗读；未知表情按协商规则降级 |
| ROBOT-06 | 超600字回答播完尾部；快照和SSE并行恢复不重复片段 |
| ROBOT-07 | turn.completed后仍播放时，自动事件不插话；playback回执丢失不阻止监听 |
| ROBOT-08 | 取消与新输入竞争、退出后台、切人设后，旧音频/表情不复活 |
| ROBOT-09 | 服务端生成但未交付的回答不被默认为用户已知；六轮历史不重复 |
| ROBOT-10 | Wi-Fi/4G切换后刷新凭据、续订、下载恢复，不重复推理 |
| ROBOT-11 | 网关不可达仍有本地唤醒反馈，错误只进入提示中心，禁止无限重试播报 |
| ROBOT-12 | 视觉关闭时“看一下”明确不可用；开启后问题和图片共同进入受控模型路径 |
| ROBOT-13 | 关闭长期记忆仍可进行约定的短期多轮；关闭语音不触发系统TTS回退 |
| ROBOT-14 | 现有frp/WebUI入口SSE无整包缓冲，或经验证的轮询后备可完成回合 |

154项现有Flutter测试和13项Python测试可作为Robot回归基础；新协议的身份、幂等、媒体授权、SSE、持久恢复和计量需要新增独立契约与集成测试，不能用现有数量代替。

## 8. 请 EnterpriseAI 侧回复的冻结项

1. 首期选择“兼容适配”还是“新版turn端点”，最低APK版本及每阶段功能边界是什么？
2. M4A是否由适配层接受并转换？谁交付实际格式能力配置？
3. 仅转写的备用唤醒能力和本地唤醒问候如何落地？
4. 长回复首期如何保证完整，谁唯一负责TTS，音频过期/失败重试接口是什么？
5. 是否接受Robot实际表情集合、personaKey和“权哥”称呼基线？
6. 会话默认恢复还是默认新建？未交付/部分交付回答如何进入历史？
7. 本地播放占用、自动事件许可、取消与新输入优先级如何对齐？
8. 本地隐私和功能开关如何收紧服务端策略？关闭记忆是否同时禁止检索与写入？
9. 最终公网路径、SSE代理、认证下载和轮询后备由谁负责？
10. 提供哪个试点租户、设备绑定入口、Profile、OpenAPI/schema、测试fixture及可诊断环境？

以上回复完成后，可以按第6节工作包拆任务；在此之前不建议承诺“改地址即可接入”或固定工期。

## 9. Robot 侧证据索引

- [旧 HTTP 客户端与路径](../pocket_companion/lib/core/network/ai_gateway_client.dart)
- [旧 HTTP 传输层](../pocket_companion/lib/core/network/robot_http_transport_io.dart)
- [旧响应与字段解析](../pocket_companion/lib/features/chat/robot_response.dart)
- [短期历史和交付后记忆](../pocket_companion/lib/features/chat/conversation_coordinator.dart)
- [本地语音模式与资源协调](../pocket_companion/lib/features/voice/voice_wake_controller.dart)
- [STT备用唤醒](../pocket_companion/lib/features/voice/stt_wake_detector.dart)
- [现有上传格式与STT请求](../pocket_companion/lib/features/voice/speech_service_io.dart)
- [原生AAC录音配置](../pocket_companion/android/app/src/main/kotlin/com/example/pocket_companion/MainActivity.kt)
- [完整播报与系统回退](../pocket_companion/lib/features/voice/tts_service_io.dart)
- [表情能力](../pocket_companion/lib/features/face/expression_state.dart)
- [当前口型动画](../pocket_companion/lib/features/face/painters/robot_face_painter.dart)
- [本地设置](../pocket_companion/lib/features/settings/companion_settings.dart)
- [网关、人设、记忆与兼容接口](../ai_gateway/main.py)
- [当前部署与代理记录](speech_and_domain_architecture.md)

本文仅提出对接需求，不扩大Robot到EnterpriseAI企业数据、业务工具或其他应用会话的权限，也未执行代码、配置或线上服务修改。

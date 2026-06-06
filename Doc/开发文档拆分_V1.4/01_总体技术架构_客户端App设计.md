## 5. 总体技术架构

### 5.1 架构原则

1. 前端负责感知采集、表情渲染和设备交互；
2. AI Gateway 负责模型调用、情绪判断、记忆管理和工具路由；
3. LLM 输出必须结构化，方便前端稳定解析；
4. 摄像头和麦克风默认应遵循最小权限原则；
5. 隐私数据优先本地处理；
6. 云端能力作为 fallback，而不是唯一依赖；
7. 初期以 Flutter 跨平台实现为主。

### 5.2 总体架构图

```text
┌────────────────────────────────────────────┐
│                手机 App                    │
│                                            │
│  ┌──────────── Screen Face ─────────────┐  │
│  │ Eyes / Mouth / Emotion / Animation   │  │
│  └──────────────────────────────────────┘  │
│                                            │
│  Camera / Mic / Speaker / Touch / Sensor   │
│  Gyro / Accelerometer / Haptics / Battery  │
└─────────────────────┬──────────────────────┘
                      │
                      ▼
┌────────────────────────────────────────────┐
│              App 感知事件层                │
│  STT / Sensor Parser / Device State        │
│  Touch Event / Motion Event / Face Event   │
└─────────────────────┬──────────────────────┘
                      │
                      ▼
┌────────────────────────────────────────────┐
│              AI Gateway                    │
│                                            │
│  Dialogue Manager                          │
│  Emotion Engine                            │
│  Memory Manager                            │
│  Model Router                              │
│  Safety & Privacy Filter                   │
└─────────────────────┬──────────────────────┘
                      │
        ┌─────────────┼─────────────┐
        ▼             ▼             ▼
┌────────────┐ ┌────────────┐ ┌──────────────┐
│ Local LLM  │ │ Cloud LLM  │ │ Vision Model │
│ Ollama/MLX │ │ API        │ │ Local/Cloud  │
└────────────┘ └────────────┘ └──────────────┘
                      │
                      ▼
┌────────────────────────────────────────────┐
│             Response Orchestrator          │
│ Text / Emotion / Expression / Voice/Haptic │
└─────────────────────┬──────────────────────┘
                      │
                      ▼
┌────────────────────────────────────────────┐
│                 手机表达层                 │
│ TTS / Face Animation / Mouth / Vibration   │
└────────────────────────────────────────────┘
```

---

## 6. 客户端 App 设计

### 6.1 推荐技术栈

推荐使用 Flutter。

主要原因：

- 可同时支持 iOS 和 Android；
- UI 动画能力强；
- 插件生态覆盖摄像头、麦克风、传感器、震动、TTS；
- 适合快速开发 MVP；
- 后续可扩展到 macOS、Windows、Web 等平台。

### 6.2 主要 Flutter 插件

| 功能 | 插件建议 |
|---|---|
| 摄像头 | camera |
| 语音识别 | speech_to_text 或平台原生 STT |
| TTS | flutter_tts |
| 传感器 | sensors_plus |
| 震动 | vibration |
| 常亮 | wakelock_plus |
| 权限 | permission_handler |
| 动画 | rive / lottie / CustomPainter |
| 网络请求 | dio |
| 状态管理 | Riverpod / Bloc / Provider |
| 本地存储 | shared_preferences / hive / drift |
| 电量状态 | battery_plus |
| 设备信息 | device_info_plus |

### 6.3 App 模块划分

```text
lib/
  app/
    app.dart
    router.dart
    app_controller.dart

  core/
    network/
      ai_gateway_client.dart
      api_response.dart
    permissions/
      permission_service.dart
    storage/
      local_storage.dart
    utils/
      logger.dart

  features/
    face/
      face_page.dart
      face_controller.dart
      expression_state.dart
      painters/
        eye_painter.dart
        mouth_painter.dart
    voice/
      speech_service.dart
      tts_service.dart
      audio_state.dart
    sensors/
      sensor_service.dart
      motion_classifier.dart
    emotion/
      emotion_state.dart
      emotion_mapper.dart
    chat/
      chat_controller.dart
      chat_message.dart
    settings/
      settings_page.dart
      settings_controller.dart
    memory/
      memory_page.dart
      memory_controller.dart
```

---


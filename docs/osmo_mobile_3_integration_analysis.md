# Mengmeng × DJI Osmo Mobile 3：人物唤醒与跟随能力集成分析

> 日期：2026-09-27（同日完成阶段 1–3 的代码集成，进度见 `docs/gimbal_follow_progress.md`）
> 输入：DJI Mobile SDK 官方文档/仓库（V5 5.18.0、V4 4.18）、目录 `Mobile-SDK-Android-V4`、Mengmeng V1.4 开发文档与 pocket_companion V2.0-alpha 代码现状

---

## 1. 结论先行

| # | 结论 | 影响 |
|---|---|---|
| 1 | **目录下的 Mobile-SDK-Android-V5（5.18.0）无法驱动 Osmo Mobile 3。** V5 只支持飞机（Mavic/Matrice/Mini 系列），DJI 官方已在 GitHub 明确回复：MSDK V5 不支持 Osmo Mobile 系列，且无支持计划 | 必须引入 **MSDK V4（最终版 4.18，legacy）**；本地 V5 目录仅作架构参考，代码不可复用 |
| 2 | **SDK 不向 Osmo Mobile 开放 ActiveTrack。** ActiveTrackMission 是飞机专属（依赖机身视觉系统）；OM3 的 ActiveTrack 3.0 是 DJI Mimo App 私有实现 | “跟随”必须**自研闭环**：手机摄像头 → 人脸/人体检测 → 偏差计算 → PID → 云台转动指令 |
| 3 | **自研跟随反而与 Mengmeng 架构完美互补。** 项目视觉系统文档（V1.4 第 04 篇 10A 章）已完整定义“看见有人 → vision.user_present → 唤醒/表情”链路，且坚持本地处理隐私原则 | “人物唤醒”链路设计已就绪（当前代码只差帧流检测）；云台把“眼睛跟随”从屏幕动画升级为**物理转头** |
| 4 | 集成路径清晰：**Android 原生层嵌 MSDK V4 + 平台通道桥接 Flutter**，完全复用项目已验证的 sherpa-onnx 桥接模式（MainActivity.kt 的 MethodChannel/EventChannel） | 不引入新框架；iOS/web 端自动降级（stub），不影响现有平台 |

---

## 2. 现状盘点

### 2.1 硬件：DJI Osmo Mobile 3

- 手机稳定云台（三轴电机：pan/yaw、pitch、roll），**无自带相机**——手机摄像头即“眼睛”。
- 通过**蓝牙（BLE）**与手机连接；夹持手机，屏幕与前置摄像头朝向用户一侧（伴侣机器人形态下：屏幕显示表情 = 脸，前置摄像头 = 眼睛，云台 = 脖子）。
- 内置电池（自供电，不能反向给手机充电）；机身上有物理模式滑块/M 键（部分模式为物理切换，SDK 不可控）。
- 云台物理行程有限（yaw/pitch 约 ±140°/+35°/-110° 量级，实现时以 `GimbalState` 实测限位为准）。

### 2.2 目录 SDK：已更换为 Mobile-SDK-Android-V4（4.18）

- 原 `Mobile-SDK-Android-V5`（5.18.0）已于 2026-09-27 删除：V5 支持列表全部为飞机、AAR 无手持包、Sample 全仓库无手持实现（已逐一核实后删除）。
- 现目录 `mimo/Mobile-SDK-Android-V4`（2026-09-27 克隆自 `dji-sdk/Mobile-SDK-Android`，HEAD 即 4.18 发布提交）：
  - `Sample Code/`：官方 Sample 工程（`com.dji.sdk.sample`），**云台相关演示可直接作原生层参考**：
    - `demo/gimbal/MoveGimbalWithSpeedView.java`（速度控制——跟随闭环主用）
    - `demo/gimbal/PushGimbalDataView.java`（GimbalState 姿态推送）
    - `demo/gimbal/GimbalCapabilityView.java`（行程/能力查询——软限位用）
    - `demo/mobileremotecontroller/MobileRemoteControllerView.java`（虚拟摇杆）
  - `aar/`：本地归档 `dji-sdk-4.18.aar`（56 MB，含 78 个 .so）+ `dji-sdk-provided-4.18.jar`（16 MB，公共 API 类）+ POM。
  - 已验证事实：官方 Sample `targetSdkVersion 34`、依赖声明为 `implementation 'com.dji:dji-sdk:4.18'` + `compileOnly 'com.dji:dji-sdk-provided:4.18'`，仓库来源 `google()` + `mavenCentral()`（构件确认在 Maven Central，可从阿里云镜像 `https://maven.aliyun.com/repository/central` 拉取）。
  - API 类已在 AAR 内核实存在：`dji.sdk.sdkmanager.DJISDKManager`、`dji.sdk.gimbal.Gimbal`、`dji.common.gimbal.Rotation/RotationMode/GimbalState`、`dji.keysdk.HandheldControllerKey/MobileRemoteControllerKey`。
- 注意：V4 官方 Sample 的 AndroidManifest **只声明了 `BLUETOOTH`/`BLUETOOTH_ADMIN`/`ACCESS_FINE_LOCATION`，没有 Android 12+ 的 `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT`**——Mengmeng 集成时必须自行补齐（见 §6 阶段 1）。

### 2.3 Mengmeng 现状（pocket_companion V2.0-alpha）

- **语音唤醒已闭环**：sherpa-onnx KWS（本地模型）→ EventChannel 16kHz PCM → 关键词命中 → 唤醒事件；含 STT 回退、barge-in、生命周期治理。
- **视觉现状**：`features/vision/vision_service_io.dart` 只有“拍一张照片”的检查能力；帧流人脸检测、VisionState/VisionEvent（文档 10A.5/10A.6 已定义）尚未实现。
- **原生桥接模式已验证**：`MainActivity.kt` 已实现 `device_capabilities`、`sherpa_wake_control` MethodChannel + `sherpa_wake_audio` EventChannel——DJI 桥接可完全照此模式扩展。
- **文档体系完备**：视觉五层架构、动态降频状态机（10A.3A）、事件冷却机制、隐私原则均已定义，本方案直接复用。

---

## 3. 关键可行性判定（硬事实）

| 事项 | 判定 | 依据 |
|---|---|---|
| V5 SDK（目录现有）驱动 OM3 | ❌ 不可行 | DJI 官方 GitHub 回复：V5 不支持 OM 系列、无计划；本地 README 支持列表无手持 |
| MSDK V4 支持 OM3 | ✅ 可行 | V4（最新 4.18）支持列表含 Osmo Mobile 系列，提供 Handheld 产品线 API |
| SDK 直接调用 ActiveTrack 跟随 | ❌ 不可行 | ActiveTrackMission 为飞机专属 mission；OM3 的 ActiveTrack 3.0 封闭在 Mimo App 内 |
| 自研“检测+云台闭环”跟随 | ✅ 唯一路径 | V4 开放 `Gimbal.rotate()`（角度）与 `MobileRemoteController`（虚拟摇杆连续速度）控制 + `GimbalState` 姿态回调 |
| OM3 官方支持前景 | ⚠️ 收窄中 | DJI 已开始收缩 OM3/OM4 支持（2026-05 媒体报道）；宜尽早真机验证、锁定固件版本 |
| V4 SDK 维护状态 | ⚠️ legacy | 4.18 为最终版，不再更新；对新版 Android 的 BLE 兼容性是最大不确定点（见 §9 风险） |

---

## 4. 目标能力定义

### 4.1 人物唤醒（Person Wake）

**定义**：机器人处于 idle/sleeping 时，用户走到设备前方（进入前置摄像头视野并稳定出现），机器人自动醒来：睁眼 + 表情 + 可选语音问候 + **转头看向用户**。

- 与现有语音唤醒（“萌萌”KWS）**并联**成双通道唤醒：视觉 OR 声音任一命中即唤醒；沿用现有事件冷却表（user_absent 30s 等）防抖。
- 视觉唤醒条件（防误触）：连续 N 帧（如 3 帧 / ≤1.5s 内）检测到人脸 → `vision.user_present`；用户离开 ≥30s 后重新出现 → `vision.user_returned`（更热情的欢迎）。
- 唤醒后的第一个云台动作：若人脸偏离画面中心（face_position ≠ center），先 `rotate()` 转头把人带到中心——**“它注意到我了”**。

### 4.2 人物跟随（Person Follow）

**定义**：云台闭环控制，把目标人物保持在画面中央——机器人的“头”物理地跟着人转，屏幕表情始终朝向用户。

- 分级：
  - **L1 人脸跟随**（MVP）：桌面近场，人脸框中心偏差驱动 yaw/pitch。
  - **L2 人体跟随**：远场/侧身无人脸时，切换人体检测框（ML Kit Pose/物体检测或 TFLite 轻量 person 模型）。
  - **L3 丢失重捕获**：目标短暂遮挡→保持最后姿态等待；持续丢失→小范围慢速扫描找回；≥30s→回中进入 idle。
- 与屏幕眼睛联动：眼睛动画继续跟 face_position 细微偏移（云台收敛后人回到中心附近，眼睛负责“微调注视”，云台负责“大范围转头”）——层次感是拟生命感的关键。

---

## 5. 系统架构

```text
┌─────────────────────────── Mengmeng App (Flutter) ────────────────────────────┐
│                                                                                │
│  features/vision/（增强）           features/gimbal/（新增）                     │
│   camera_service: 帧流采集           gimbal_service.dart      (抽象+stub)        │
│   face_detection_service: ML Kit    gimbal_service_io.dart   (Android 通道实现)  │
│   vision_state / vision_event       follow_controller.dart   (PID 闭环)          │
│        │                                 ▲                                      │
│        │ VisionEvent(user_present/       │ 转速指令                                │
│        │ face_position/…)                │                                        │
│        ▼                                 │                                        │
│  WakeOrchestrator（新增：视觉唤醒 ∥ 语音唤醒）   features/face/ 表情联动            │
│                                                                                │
└───────────────┬──────────────────────────────────────────┬─────────────────────┘
                │ MethodChannel                             │ EventChannel
                │ "pocket_companion/dji_gimbal"             │ "pocket_companion/dji_gimbal_state"
                │ register/connect/rotate/stop/center       │ (连接态/云台姿态/电量)
┌───────────────▼──────────────────────────────────────────▼─────────────────────┐
│  Android 原生层（新增 DjiGimbalPlugin.kt，模式同现有 sherpa 桥接）                 │
│   MSDK V4 4.18:                                                                │
│     DJISDKManager.registerApp() → Handheld(OM3) → Gimbal                       │
│     Gimbal.rotate(Rotation, cb)          // 绝对/相对角度                        │
│     MobileRemoteController               // 虚拟摇杆=连续速度控制                  │
│     GimbalStateCallback → 姿态(°)                                              │
└───────────────┬ BLE ───────────────────────────────────────────────────────────┘
                ▼
        Osmo Mobile 3（夹持手机：屏幕=脸，前置摄像头=眼睛，云台=脖子）
```

要点：

1. **控制闭环放在 Flutter 侧**（FollowController），原生层只做 SDK 封装的无状态转发——便于跨平台迁移与单元测试；若实测通道延迟过大，再把 PID 下沉到 Kotlin（接口已隔离，可平滑迁移）。
2. **GimbalService 抽象层**是关键解耦点：今天实现是 DJI OM3，未来可替换任何开放 API 的云台，甚至“无云台纯屏幕跟随”退化实现。
3. 视觉部分**完全本地**（ML Kit 端侧），不上传图像，遵循 V1.4 隐私原则；AI Gateway 无需改动（`/vision/analyze` 仍只服务“你看看这个”的主动场景）。

---

## 6. 分阶段实施计划

### 阶段 0：硬件可行性验证（0.5–1 天，必须最先做）

> 目的：在写任何集成代码之前，用最小成本证伪最大风险（V4 SDK 在当代 Android 上的 BLE 连接能力）。

1. V4 仓库已就位：直接用 `mimo/Mobile-SDK-Android-V4/Sample Code/` 构建官方 Sample App，装到**实际要用的手机**上。
2. developer.dji.com 注册开发者账号 → 创建 App（绑定包名）→ 拿到 App Key 填入 Sample。
3. 系统蓝牙中先配对 OM3 → 打开 Sample → 验证三件事：**能连接（读到 OSMO_MOBILE_3 型号）、能收到 GimbalState 姿态、`rotate()` 能让云台动**。
4. 同时在 Android 12+ 手机上验证（权限弹窗、BLE 扫描是否工作）。
5. ✅ 全部通过 → 进入阶段 1；❌ 任一失败 → 走 §10 备选方案，避免沉没成本。

### 阶段 1：SDK 接入与通道桥接（1–2 天）

**Android 侧：**

- `android/app/build.gradle.kts`（与 V4 Sample 声明保持一致，已验证可用）：
  ```kotlin
  // settings.gradle.kts 的 dependencyResolutionManagement 中加镜像（国内网络 repo1 不稳时自动可用）
  // maven("https://maven.aliyun.com/repository/central")
  implementation("com.dji:dji-sdk:4.18")      // 传递依赖会自动带入 POM 中的全部依赖
  compileOnly("com.dji:dji-sdk-provided:4.18")
  ```
  **优先走 Maven 依赖而非本地 AAR**：POM 传递依赖很多（gson 2.8.2、eventbus 3.0.0、okio、wire-runtime、bouncycastle、disruptor，以及 DJI 子包 utmiss / library-anti-distortion / library-networkrtk-helper / fly-safe-database），本地 `files('libs/*.aar')` 方式需手工补齐全部传递依赖，得不偿失。本地归档（`mimo/Mobile-SDK-Android-V4/aar/`）仅作断网兜底。可参照 Sample 的 `exclude module: 'library-anti-distortion'` 缩小包体；`packagingOptions`/proguard 规则从 Sample 的 `app/build.gradle` 抄（含 78 个 .so 的 doNotStrip 清单）。
- `AndroidManifest.xml` 新增：
  - 蓝牙权限：`BLUETOOTH`、`BLUETOOTH_ADMIN`、`ACCESS_FINE_LOCATION`（Android ≤11 BLE 扫描必需）；Android 12+ 另加 `BLUETOOTH_SCAN`（建议 `neverForLocation`）、`BLUETOOTH_CONNECT`。
  - `<meta-data android:name="com.dji.sdk.API_KEY" android:value="…"/>`。
  - 建议：先把 `applicationId` 从 `com.example.pocket_companion` 定稿为正式包名再生成 App Key（App Key 与包名绑定，换名要重注册）。
- 新建 `DjiGimbalPlugin.kt`（或独立 Application 回调）：`registerApp` → `startConnectionToProduct` → `SDKManager` 产品回调拿到 `Handheld` → `gimbal`。方法集：
  - `register/start/stop`（连接管理）
  - `rotateTo(yawDeg, pitchDeg, durationMs)`（角度模式，`Rotation` + `RotationMode.ABSOLUTE_CONTROL`）
  - `setVelocity(yawDps, pitchDps)`（连续速度，虚拟摇杆通道，跟随主用）
  - `stop()`（速度归零）、`center()`（回中）
  - EventChannel 推送：连接状态、`GimbalState`（姿态°）、云台电量。

**Flutter 侧：**

- 新增 `features/gimbal/`：`gimbal_service.dart`（抽象：connect/rotateTo/setVelocity/stop/center + stateStream）、`gimbal_service_io.dart`（Android 通道实现）、`gimbal_service_stub.dart`（iOS/web）；顶层暴露 `GimbalCapability` 探测（无云台时一切跟随逻辑优雅降级为纯屏幕模式）。

**验收**：设置页出现“云台设备”项，真机可连接 OM3；手动按钮可左转/右转/回中；姿态角实时回显。

### 阶段 2：人物唤醒（1–2 天）

- `vision_service` 升级为帧流模式：`camera` 插件 `startImageStream`（前置、`ResolutionPreset.low`）+ `google_mlkit_face_detection`（文档 10A.3 既定选型）抽帧检测（5–10 fps，遵守 10A.3A 动态频率状态机）。
- 产出文档已定义的 `VisionState`（user_present/face_position/distance）与 `VisionEvent`（user_present/user_absent/user_returned）。
- 新增 `WakeOrchestrator`：视觉唤醒与现有 `VoiceWakeController` 并联，任一触发唤醒；沿用冷却与生命周期治理（视觉检测在对话中降频，避免与音频/网络并发满载）。
- 唤醒动作编排：睁眼表情 → 云台转头对准用户 →（可选）TTS 问候。
- **验收**：用户走入画面 2s 内唤醒；离开 30s 不重复唤醒；隐私模式/视觉开关关闭时不采集。

### 阶段 3：人物跟随闭环（2–3 天）

- `FollowController`（纯 Dart，可单测）：

```text
输入: face/person bbox 中心归一化偏差 (dx, dy) ∈ [-1,1]，检测时间戳
逻辑:
  1. 死区: |dx| < 0.08 且 |dy| < 0.10 → 速度置零（防抖动，省电）
  2. PID(先只 P+限幅):
       yawVel  = clamp(Kp_yaw  * dx, ±25°/s)   // 方向符号随前后摄/镜像校准
       pitchVel= clamp(Kp_pitch* dy, ±15°/s)
  3. 以检测帧率(≈10Hz)下发 setVelocity；两帧间隔用 GimbalState 反馈平滑
  4. 丢失 <1.5s: 保持末速度衰减(惯性等待，应对遮挡)
     丢失 1.5–5s: ±15° 慢速扫描重捕获
     丢失 >30s: stop + 回中 + 视觉降频(user_absent)
  5. 软限位: 由 GimbalState 实测行程建软件限幅，防止堵转
```

- 多人策略（MVP）：取最大人脸框（最近者）；多人持续 >3s → 表情“左右扫视”+ 语音询问，不强行切换目标。
- **验收**：用户在桌面 ±60° 范围左右走动，人脸保持画面中央 ±10% 内；云台动作平滑无振荡；丢失后能重捕获或 30s 回中待机。

### 阶段 4：体验与模式融合（1–2 天）

- 表情联动：转头瞬间眼睛动画同方向超前一点（生物感）；跟随中“注视”微表情；跟随丢失时“找一找”表情。
- 工作模式接入：`陪伴模式`启用跟随；`专注/夜间/隐私模式`禁用（对齐 10A.3A 策略表）；低电量(<20%)关闭跟随仅保留唤醒检测；发热降级时跟随降频为“检测+间歇校正”。
- 功耗提示：跟随模式建议插电使用（云台电池与手机电池独立，二者都耗）。

---

## 7. 权限与隐私清单

| 权限 | 用途 | 备注 |
|---|---|---|
| CAMERA（已有） | 前置帧流人脸检测 | 遵循现有“默认关、可感知、可关闭”原则 |
| BLUETOOTH / BLUETOOTH_ADMIN | 连接 OM3（Android ≤11） | |
| ACCESS_FINE_LOCATION | Android ≤11 的 BLE 扫描 | 仅系统要求，App 不采集位置 |
| BLUETOOTH_SCAN / BLUETOOTH_CONNECT | Android 12+ | SCAN 建议声明 `neverForLocation` |
| INTERNET（已有） | App Key 首次激活需联网 | 之后离线可控云台 |

隐私对齐：视觉检测全部端侧；不保存帧；云台跟随状态在 UI 有明确指示（眼睛图标 + “跟随中”），随时一键停止（物理安全感）。

---

## 8. 风险与缓解

| 风险 | 等级 | 缓解 |
|---|---|---|
| V4 SDK 在 Android 12–15 上的 BLE 连接兼容性（SDK 停更） | **高** | 阶段 0 真机优先验证；系统蓝牙预先配对再进 App。已核实：官方 Sample targetSdk=34 但**未声明** `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT`，DJI 未适配 Android 12+，集成时必须自行补权限并实测 |
| OM3 官方支持持续收窄、固件不兼容新 SDK | 中高 | 阶段 0 锁定“手机型号 + OM3 固件 + SDK 4.18”组合并归档验证记录；GimbalService 抽象保证硬件可替换 |
| AAR 获取渠道不稳定（jcenter 已关） | ~~中~~ **已消除** | 已验证构件在 Maven Central（阿里云镜像可达），`mimo/Mobile-SDK-Android-V4/aar/` 已归档 AAR+POM |
| App Key 绑定包名，后改包名需重注册 | 低 | 阶段 1 前定稿 applicationId |
| 视觉+音频+动画+云台并发导致发热耗电 | 中 | 复用 10A.3A 动态降级；跟随仅在陪伴模式且建议充电时开启 |
| 前置摄像头镜像导致方向符号错误 | 低 | 实现时用“向左走→云台左转”一次校准；FollowController 符号可配置 |
| 多人/遮挡误跟、跟丢振荡 | 中 | 死区+限幅+惯性等待；多人不自动切换目标；验收表含振荡与丢失用例 |
| V4 API 无维护文档老化 | 低 | 以 4.18 官方 API 文档 + V4 Sample 源码为准，封装层薄、注释完整 |

---

## 9. V5 → V4 目录更换记录

- 2026-09-27：`Mobile-SDK-Android-V5`（5.18.0，仅飞机）已整体删除；`Mobile-SDK-Android-V4`（4.18 官方仓库 + `Sample Code/` + `aar/` 本地归档）已就位。
- V4 Sample 的 gimbal/mobileremotecontroller 演示代码是阶段 1 原生层的直接参考；API 与 V5 完全不同（V4 回调式 vs V5 KeyManager 推拉式），不要混用两套文档。

---

## 10. 备选方案（若阶段 0 验证失败）

| 方案 | 说明 | 评价 |
|---|---|---|
| 换 OM5/OM6/OM SE | ❌ V5 同样全系不支持 OM；V4 才支持旧型号 | 换新 OM 系列无意义 |
| 其他开放 API 云台（如影/飞宇等有开放协议的型号） | GimbalService 抽象层直接换实现 | 可行，保架构不变 |
| 纯屏幕跟随（无云台） | 退回 V1.4 文档既有设计：眼睛动画跟随 + 头像转动动画 | 零硬件成本保底 |
| 逆向 OM3 私有 BLE 协议 | 社区有零星逆向尝试 | 不推荐：脆弱、固件升级即失效、条款风险 |

---

## 11. 参考

- DJI MSDK V5 仓库（本地 `Mobile-SDK-Android-V5`，5.18.0，仅飞机）
- DJI MSDK V4 仓库：github.com/dji-sdk/Mobile-SDK-Android（4.18，含手持支持与 Sample）——已克隆至 `mimo/Mobile-SDK-Android-V4`，AAR 归档于其 `aar/` 子目录
- DJI 开发者中心 App Key 注册：developer.dji.com
- V5 不支持 OM 系列的官方回复：dji-sdk GitHub issues
- OM3/OM4 支持收窄报道：dronedj.com（2026-05）
- Mengmeng 内部：`Doc/开发文档拆分_V1.4/04_传感器_摄像头视觉系统.md`（视觉事件/降频/隐私）、`docs/voice_wake_progress.md`（唤醒管线现状）

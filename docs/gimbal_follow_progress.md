# Gimbal Follow & Person Wake Progress

## Current Status

As of 2026-09-27, the DJI Osmo Mobile 3 integration (person wake + gimbal follow) has completed its first code integration pass. All code paths compile-pass on the Dart side; native side targets the verified MSDK V4 4.18 APIs.

Completed:

- F1.0: Feasibility analysis (`docs/osmo_mobile_3_integration_analysis.md`): V5 SDK cannot drive OM3; V4 4.18 required; ActiveTrack not exposed for handheld → custom closed loop.
- F1.1: SDK swap: `Mobile-SDK-Android-V5` deleted; `Mobile-SDK-Android-V4` cloned (4.18) with AARs archived under `aar/`.
- F2.1: Android native bridge `DjiGimbalPlugin.kt`: registerApp → BLE search/auto-connect (`BluetoothProductConnector`) → `Gimbal.rotate()` speed/absolute modes + `GimbalState` attitude push (throttled to 10Hz), all marshalled to the main thread.
- F2.2: Android wiring: MainActivity attach/detach, manifest Bluetooth permissions (legacy + Android 12+ `BLUETOOTH_SCAN/CONNECT`), DJI `API_KEY` meta-data placeholder, gradle DJI deps + Aliyun mirrors + packaging/proguard rules.
- F3.1: Flutter `features/gimbal/`: `GimbalService` (io/stub via conditional export), models, `FollowController` (deadband → P-control → clamp; lost-target state machine: holding → scanning → lost).
- F4.1: Flutter `features/vision/`: `FaceStreamService` (front camera NV21 stream @~6fps + ML Kit on-device face detection), `PresenceTracker` (debounced present/absent/returned events with cooldown), `FaceObservation` model.
- F5.1: FacePage wiring: control-panel toggle “云台跟随/人物唤醒” (`toggleGimbalFollow` key); local presence events reuse the existing `person_seen`/`person_left` gateway path; follow commands throttle to `setVelocity`; camera yielding between face stream and snapshot vision (`看一下`/语音看图先 release 再恢复); lifecycle pause stops follow.
- F6.1: Tests: `follow_controller_test.dart` (10 cases), `presence_tracker_test.dart` (5 cases). Full suite: 107 passed; `dart analyze`: clean.
- F7.1: Android build verified locally (`./gradlew :app:assembleDebug` → BUILD SUCCESSFUL; APK at `pocket_companion/build/app/outputs/flutter-apk/app-debug.apk`, 379MB debug, 20 DJI `.so` across arm64-v8a/armeabi-v7a). Toolchain installed on this Mac: Homebrew OpenJDK 17, Android SDK at `~/Library/Android/sdk` (platforms 33–36, build-tools 35/36, NDK 27 & 28.2, CMake 3.22.1).

Facts discovered during build verification (keep for future reference):

- DJI AAR layouts reference constraintlayout attributes without declaring the dependency → app must add `androidx.constraintlayout:constraintlayout` (done, 2.1.4).
- Exact V4 4.18 API surface (javap-verified): `RotationMode` = `RELATIVE_ANGLE/ABSOLUTE_ANGLE/SPEED` (no ABSOLUTE_CONTROL); `Rotation.Builder.time(double)`; `Gimbal.rotate(Rotation, CommonCallbacks.CompletionCallback<DJIError>)` takes a non-null Rotation — stop is done by sending a zero-speed SPEED rotation (Kotlin type-safe equivalent of the Java sample's `rotate(null)`).
- `BluetoothProductConnector.BluetoothDevicesListCallback.onUpdate(List<BluetoothDevice>)` is annotated non-null in Kotlin.
- Aliyun mirrors are required in BOTH `settings.gradle.kts pluginManagement.repositories` AND root `build.gradle.kts allprojects` — repo.maven.apache.org times out on this network.
- sherpa_onnx plugin requires `platforms;android-34`; Flutter requires NDK 27.0.12077973; google_mlkit_face_detection pulls NDK 28.2.13676358; AGP 8.11 needs build-tools 35.
- `libDJIFlySafeCore.so` cannot be stripped by NDK 28 llvm-strip ("packaging as-is" warning) — harmless.

Current follow pipeline:

```text
FacePage 控制面板「云台跟随」
  -> FaceStreamService.start()  (前置摄像头 NV21 帧流)
  -> ML Kit FaceDetector (端侧, ~6fps, 最大人脸框)
  -> FaceObservation { centerX/Y, areaRatio, faceCount }
     ├─> PresenceTracker (去抖+冷却)
     │     -> person_seen / person_left (本地优先，云台在跑时视觉守望不再调用云端)
     │     -> _handleVisualPresenceChanged -> 表情 + Gateway 事件
     └─> FollowController (死区 -> P -> 限幅; 丢失: hold 1.5s -> scan ±8°/s -> 30s lost)
           -> GimbalService.setVelocity(yawDps, pitchDps)
           -> [MethodChannel pocket_companion/dji_gimbal]
           -> DjiGimbalPlugin -> Gimbal.rotate(RotationMode.SPEED)
           -> BLE -> Osmo Mobile 3
```

Degradation rules:

- No gimbal connected / not Android: the same toggle still runs local person wake (screen-only), log notes “无(仅本地唤醒)”.
- Privacy mode or vision disabled: toggle disabled, same as existing vision gating.
- App backgrounded: follow stops, camera released, gimbal `stop()`.

## Real-Device Session (2026-09-28)

Device: HUAWEI P30 Pro (VOG-AL10), Android 10 / EMUI —— 老权限模型（BLUETOOTH_SCAN/CONNECT 不适用），恰为 MSDK V4 原生适配区间，兼容性风险低。

- Installed via adb (旧版为异机签名，先卸载再装；应用内本地数据被清除)。
- 首装启动即崩溃 `NoClassDefFoundError: DJISDKManager$SDKManagerCallback` → 排查发现 **2024 年重打包的 dji-sdk 4.18 AAR 的 classes.jar 已不含任何 DJI 类**（仅加固加载器 com.cySdkyc.clx.Helper + okhttp 数据），全部实现类在 `dji-sdk-provided-4.18.jar`（16MB）中；官方 Sample 的 `compileOnly` 写法照抄必崩。**修复：`implementation("com.dji:dji-sdk-provided:4.18")`**，另需 `packaging { resources.pickFirsts += "dji/thirdparty/okhttp3/internal/publicsuffix/publicsuffixes.gz" }`（两个构件各带一份）。
- 修复后：APK dex 中确认包含 DJI 类（classes14/15/16.dex），真机安装启动成功、进程存活、无 FATAL、前台正常；已预授权 CAMERA/RECORD_AUDIO/ACCESS_FINE_LOCATION。
- D8 对 provided jar 输出大量 "Invalid stack map table" 警告——老字节码的常规警告，不影响运行。
- 注意：macOS BSD grep 对 dex 二进制的 `-c` 计数不可靠（返回空），验证 dex 内容请用 python 字节搜索。

## Known Gaps / Next Steps

1. ~~**DJI App Key placeholder**~~ — 已于 2026-09-27 填入（`com.dji.sdk.API_KEY`，绑定包名 `com.example.pocket_companion`），并已重新打包进 `app-debug.apk`。注意：若日后更改 `applicationId`，需在 developer.dji.com 重新生成 Key。首次 `registerApp` 需联网激活。
2. **Real-device validation (阶段 0 依然必做)** — BLE connect + rotate on the actual phone/OM3 pair. Watch for: Android 12+ permission dialogs, gimbal direction signs (calibrate `mirrorYaw`/`invertPitch` in `FollowConfig`), deadband feel, yaw/pitch limits.
3. **iOS path** — `FaceStreamService` is Android-only (`isSupported=false` elsewhere); iOS needs the BGRA branch for `InputImage` + DJI iOS SDK if gimbal control is wanted there.
4. Person-body tracking (L2) for far-field; currently face-only.
5. Follow-state indicator on the face screen (currently control panel + logs only).
6. Battery/thermal gating: reuse the doc-10A.3A policy to downshift follow frequency.

## Non-goals for this pass

- No ActiveTrack usage (not exposed for handheld products by MSDK).
- No cloud upload of frames; detection is fully on-device.
- No changes to conversation STT or the voice wake pipeline.

## 2026-09-28 沉浸式 UI + 云台跟随按钮修正（已完成并真机验证）

- **状态栏隐藏**：MainActivity `onCreate`/`onWindowFocusChanged` 调 `hideSystemStatusBar()`（WindowCompat + WindowInsetsControllerCompat，Android 10 兼容，BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE 上滑可临时呼出）。依赖 `androidx.core:core-ktx:1.13.1`。
- **底部输入区触摸唤出**：脸区外层 `Listener(onPointerDown: _revealComposer)`（用 Listener 而非 onTapDown：onDoubleTap 注册会使 tap 回调被手势竞技场延迟）；`Visibility(maintainState/maintainAnimation)` 包裹 composer；8s 无操作自动隐藏；测试需 pump 400ms 排空双击计时器。
- **云台跟随按钮**：从面板第二行行尾（图标无文字，此前"找不到"的根因之一）提至首位 + emphasized(FilledButton) 高亮；文案由动态（未连云台显示"人物唤醒"）改为固定 `云台跟随`/`停止跟随`。
- **release 构建修复**：DJI 自带 LMAX Disruptor 引用 `java.lang.management.*` 导致 R8 失败 → proguard-rules.pro 加 `-dontwarn java.lang.management.**`。
- 真机验证（P30 Pro 截图三连）：主屏状态栏隐藏✓ 底部无输入区✓ 触摸脸后输入框+语音+发送出现✓ 面板首位"云台跟随"浅绿高亮✓
- 测试 107/107 通过，analyze 无问题。

## 2026-09-28 追加：顶部状态条同样触摸唤出

- `_StatusBar`（状态文字/云同步/电量/设置齿轮 `openControlPanel`）与底部输入区共用 `_overlayVisible`：默认全部隐藏，触摸脸区一起出现，共用 8s 自动隐藏定时器。
- 测试：`_openControls` 先 `_revealComposer` 再点设置；smoke 断言 `openControlPanel` 触摸前 findsNothing。
- analyze 无问题，107/107 通过，release APK 已构建（291.8MB）。**安装时手机 USB 断开未装上——重新插上后执行 `flutter build apk --release` 后的安装即可**（APK 在 build/app/outputs/flutter-apk/app-release.apk）。

## 2026-09-28 云台连接总攻：三层叠加的根因全部修复（云台已连上！）

**症状**：点"云台跟随"毫无反应/无日志；曾以为按钮位置、UI 遮挡问题，最终全链路诊断出三层叠加根因：

1. **致命（崩溃层）**：DJI 4.18 构件为加固分发——`dji-sdk.aar` 的 classes.jar 只有加载器 `com.cySdkyc.clx.Helper`，真实类加密在 `libdataclx.so` 运行时解密；`dji-sdk-provided` 的类是**故意损坏的字节码桩**（`DJISDKManager.<init>` 首指令就是 `return`，javap 实锤），打包进 APK 必然 `VerifyError` 崩溃。
   - 修复：provided 回归 `compileOnly`；新增 `CompanionApplication.attachBaseContext` 调 `com.cySdkyc.clx.Helper.install(this)`（官方 Sample DJISampleApplication.java:77 同款）+ manifest `android:name=".CompanionApplication"`。
   - ⚠️ 此前"provided 必须 implementation 否则 NoClassDefFoundError"的结论是**误诊**（真正缺的是 Helper.install）。
2. **缺失声明**：DJI 用旧 Apache HTTP → `NoClassDefFoundError BasicHttpParams` → manifest 加 `<uses-library android:name="org.apache.http.legacy" android:required="false"/>`。
3. **静默失效层**：
   - 隐私模式开→强制关 allowVision，关隐私不恢复 → 按钮禁用且无提示。修复：copyWith 隐私关闭时恢复能力开关；按钮不再因 vision 关而禁用；_toggleFollow 自动开"看"并弹 SnackBar。
   - phase 事件缺 `hasGimbal` 字段 → `isControllable` 恒 false（连上也不发指令）。修复：phasePayload 带 hasGimbal。
   - 顶栏无云台状态 → follow 激活时顶栏最高优先级显示（云台跟随中/正在连接云台…/连接失败等）。

**自动重连**：attach 1.5s 后自动 registerApp；`onInitProcess` 等 `InitializationState.DATABASE_LOADED`（4.18 无 START_CONNECTION_COMPLETE）后再 startConnectionToProduct/搜索；搜索"system too busy"自动重试 5 次（间隔 6s）。

**验证（P30 Pro 真机日志）**：`onRegister: API Key successfully registered` → `bindProduct: model=OSMO_MOBILE` → `phase -> connected`。**OM3 已自动重连成功**。

**其他修复**：语音调试面板不再随启动恢复（每次启动收起）；release 关闭 R8 minify（`isMinifyEnabled=false`，加固字节码 + R8 full mode 风险；provided 改回 compileOnly 后理论可重开，暂留关闭）。

**adb 测试坑（仅影响自动化，不影响用户手指）**：该机 `input tap` 常被 Flutter 丢弃，用 `input swipe x y x y 150` 替代；面板内 adb 点击仍有随机失效，与真实触摸无关。测试时 `settings put system screen_off_timeout 600000` 防熄屏。

**待用户实测**：手指点面板"云台跟随"→ 顶栏应变"云台跟随中"，人脸左右移动云台应水平跟随；若方向反了调 `FollowConfig.mirrorYaw`，俯仰反了调 `invertPitch`。

## 2026-09-28 终局：跟随已激活（顶栏"云台跟随中"实测确认）

- 反馈补强：`_faceStream.start()` 失败从静默 return 改为 SnackBar「跟随启动失败：<原因>」+ debugPrint。
- **实测链路**（swipe 按下面板首位按钮后）：顶栏显示「**云台跟随中**」= `_isFollowActive && _isGimbalControllable` 同时成立——跟随循环在跑、相机人脸流已启动、OM3 已连接可控。
- 新增 adb 自动化发现：P30 Pro 顶部约 100px（挖孔/系统手势保留区）会吞掉触摸注入——齿轮要点 **y≈110**（非 y=70）；面板/脸区 swipe（200ms 同点滑动）可靠，`input tap` 不可靠。
- 用户手指点按钮无效的历史疑云：大概率发生在旧构建（VerifyError/allowVision 静默禁用阶段）或云台未完成自动重连的 10 秒窗口内（此时顶栏会显示连接中/仅人物唤醒状态）。
- logcat 缓冲被 DJI UDT-JNI 每秒刷屏导致秒级轮转——诊断用 `adb logcat -G 16M` 扩容。
- **待用户现场确认**：脸对前置摄像头，云台应水平跟随；方向反了调 `mirrorYaw`，俯仰反了调 `invertPitch`（lib/features/gimbal/follow_controller.dart FollowConfig）。

## 2026-09-28 收尾：云台不动的最终定位 = OM3 休眠（硬件侧）

- 诊断链路全部 E 级日志化（EMUI 会限流 I 级应用日志，E 级穿透；Dart 侧镜像进 _logs 应用内日志）。
- 实测铁证：注册成功 → 搜索 success → **`ble list onUpdate: count=0`**（每 2 秒，持续 2 分钟+）——OM3 不在蓝牙广播 = 休眠/关机。OM3 休眠后必须物理按键唤醒，App 无法远程唤醒。
- 修正：busy 重试完全静默（不再漏出"bluetooth search failed"SnackBar）；超时文案改为"未发现云台：请短按 Osmo 电源键唤醒云台，App 会自动重连"；重连循环 36 次 × 10s（约 6 分钟）。
- 用户操作指引：短按 OM3 电源键唤醒（电机"起身"）→ App 10 秒内自动连上 → 顶栏"云台跟随中" → 对镜头测试。OM3 长时间闲置会再次休眠，重现"不动"时先按电源键。

## 2026-09-28 17:16 OM3 已连通（最终根因：GATT 僵死链路）

- 现象：BLE 搜索持续 `count=0`，但手机蓝牙栈显示 OM3（`OM3-40JSY0-7`）是已配对设备 → OM3 醒着但不广播。
- 根因：App 进程被 force-stop 时 GATT 链路未优雅断开，OM3 端仍认为"已连接"→ 不广播 → SDK 永远搜不到/连不上。与"OM3 休眠"症状相同，区分方法：休眠=按键唤醒；僵死=重启手机蓝牙。
- **解法（运维手册）**：`adb shell svc bluetooth disable && sleep 4 && adb shell svc bluetooth enable`，然后重启 App——本轮实测重启蓝牙后 2 秒 `bindProduct: OSMO_MOBILE → connected`。
- 注意：scheduleReconnectAttempts 连接成功后即停（不再循环）；OM3 断开后重开"云台跟随"按钮即可重新触发连接。

## 2026-09-28 17:43 按钮"点不了"根因修复 + 云台物理摇摆定性

- **按钮点不了**：`_applyGatewayCall` 置 `_isBusy=true` 后 await AI 响应（chat 90s/vision 120s 超时，无 finally）——语音对话被唤醒词频繁误触发期间，面板按钮几乎永远禁用。修复：①云台跟随按钮不再受 isBusy 限制（硬件控制随时可点）；②`_runGatewayCall` 异常兜底回落 busy。
- **云台反复摇摆（用户报告）**：日志证据（rotate 零条 + 跟随未激活）→ 摇摆非 App 指令，是 OM3 本体：P30 Pro 192g 贴 OM3 200±30g 上限，装夹偏心/带壳 → 电机过载纠偏。指引：摘壳居中夹持、必要时 Mimo 自动校准。
- 17:43 新包：BT-off→force-stop→install→BT-on→launch，2 秒重连（bindProduct → connected）。

## 2026-09-28 18:0x 指令通道超时定位（待用户物理唤醒/激活）

- 用户实测反馈链路全通：按钮可点（busy 修复生效）→ 跟随激活（顶栏"云台跟随中"）→ 人脸驱动 rotate 指令 → 但云台报 **`rotate failed: execution of this process has timed out`**。
- 结合 15:12 的 `DJIHandheldHelper: set led failedTIMEOUT`：BLE 链路通、指令送达、**OM3 本体不执行**（一直如此）。
- 判定：①OM3 待机休眠（电机锁定，需短按电源键/半按快门唤醒，唤醒后 1-2 分钟内有效）；②若仍超时 → OM3 未激活，需 DJI Mimo App 首次激活 + 固件检查。
- EMUI 新坑：自定义 tag 日志（连 Log.e）会被 logd 拉黑（tag 级限流/黑名单），诊断要趁早读或走应用内日志面板。


## 2026-09-28 代码链路复查：NV21 帧丢弃与转动时长修复

- 当前锁定依赖 `camera_android_camerax 0.6.30` 将 NV21 输出整理为**单平面**紧密缓冲；原 `_toInputImage` 要求至少两个平面，导致正常相机帧直接丢弃，不能据“云台跟随中”状态推断检测已运行。
- 修复：直接传入单平面 NV21 缓冲，校验格式、平面数、尺寸、行跨度及缓冲长度；拒绝将原始多平面 YUV420 拼接后冒充 NV21。新增 3 项回归测试。
- DJI 本地官方 API 文档说明 `Rotation.Builder.time(double)` 的单位是秒；`rotateTo` 的 `durationMs / 100` 已改为 `/ 1000.0`，800ms 正确对应 0.8s。此修复针对角度控制，不是对 SPEED 指令超时原因的判断。
- 验证：Flutter 全量测试 110 项通过；Android debug APK 构建成功。
- 本轮 ADB 未检测到手机，尚未安装或做物理跟踪、方向标定、姿态反馈及超时复测。历史“休眠/未激活”等判断不能替代本轮实测证据。
- 现场顺序：连接并授权 USB 调试 → 保留数据覆盖安装 → 启动跟随 → 确认 `face detected` 及非零偏差 → 对照 `cmd`、DJI rotate 回调和姿态变化 → 最后测试停止、左右/上下方向及丢失目标行为。


## 2026-09-28 USB 实测：连接状态被旧搜索覆盖

- 修复 NV21 的 debug APK 已保留数据覆盖安装到 P30 Pro，启动成功。
- 本轮日志（手机时间）23:40:30 扫到 OM3，23:40:31 `bindProduct -> connected`；23:40:32 旧 busy 重试又启动搜索；23:40:36 更早的超时任务将状态改成 `disconnected`。因此本轮“未发现云台”有明确的软件竞态证据，不能归因为云台休眠。
- 修复：每次搜索使用独立 generation，过期的列表/完成/重试/超时回调不再推进状态；连接成功使旧搜索失效，已连接不重新搜索；detach 取消延迟任务并失效旧搜索。
- 新修复版 Android debug 构建通过，但打包完成时手机 USB 已断开，尚未覆盖安装及验证本次连接状态修复。
- Gateway：电脑请求默认公网 `/health` 返回 HTTP 200；手机 `dumpsys connectivity` 为 `Active default network: none`，需要手机联网后重测聊天/语音。


## 2026-09-29 转动失败实测：仍需验证 SDK 兼容性

- 设备包更新时间：2026-09-29 17:48:39。读取到 18:04:07 `rotate result: Execution of this process has timed out`，18:04:08 `mode=SPEED yaw=8.0 pitch=0.0`。证明转动请求已发出，但没有成功执行证据；不能凭此诊断为待机、未激活或硬件损坏。
- 修正前提：DJI 官方 Hardware Introduction 支持表列出 Osmo Mobile 和 Osmo Mobile 2，未明确列出 Osmo Mobile 3。SDK 回报通用 `OSMO_MOBILE` 与 BLE 连接成功，不等于 OM3 电机控制兼容性已经确认。
- 官方支持表：https://developer.dji.com/mobile-sdk/documentation/introduction/product_introduction.html
- 待现场对照：停止本 App 跟随后，分别测试 DJI Mimo 控制和手柄摇杆。Mimo/摇杆正常时优先排查 SDK/固件兼容及控制协议；两者均异常时再查设备状态。当前未收到对照结果。


### 2026-09-29 Mimo 对照与指令链路修正

- 用户确认：DJI Mimo 和手柄摇杆均可正常控制。当前故障优先定位本应用及 SDK 兼容性，不能继续归因为未激活/休眠/电机故障。
- 对照官方 `MoveGimbalWithSpeedView.java`（每 100ms 重发），发现 App 对相同非零速度会等到 800ms 才重发。改为移动时每个检测帧刷新（约 160ms），仅对零速去重。尚不能据此断言能解决 SDK 超时。
- 原生 `rotateWithCompletion` 原来调用 SDK 后立刻 `result.success`，现改为 SDK 完成回调中成功或失败；日志附带 mode/yaw/pitch，避免将接受调用误当执行成功。
- 相关 21 项 Flutter 测试通过，Android debug 构建通过。物理效果需新包安装后复测。

### 2026-09-29 18:12 新包现场回调验证

- 保留数据覆盖安装成功；新进程 PID 20890。18:12:29 开启跟随，320×240 单平面 NV21 帧正常进入检测；18:12:36 记录到 `face detected=true`。
- 18:12:30–18:12:37 的转动回调连续返回 `ok`，包含正负 yaw、非零 pitch 和零速停止请求；该段日志没有转动超时。此前旧进程的超时不能混入本次结果。
- 验证：相关 21 项测试、Android 构建及 Flutter 静态分析通过。SDK 指令回调现已成功；实际运动方向、跟随稳定性仍等待用户现场确认。未隔离重连、Mimo 对照和发送频率各因素，因此不单独归因于频率修改。

### 2026-09-29 人在镜头前仍无法识别

- 用户反馈重点为人脸识别不到，并非 SDK 回调再次失败。发现帧旋转角固定为传感器角度，未补偿设备横竖屏；现每帧按镜头方向与设备方向计算旋转，检测坐标使用同一帧的旋转值。检测分辨率由 low 改为 medium。
- 旋转处理对照维护者示例：https://github.com/flutter-ml/google_ml_kit_flutter/blob/master/packages/example/lib/vision_detector_views/camera_view.dart 。新增前置四方向及后置旋转回归验证。
- 相机启动/释放串行执行，停止后丢弃未完成检测的旧结果；跟随启动防重复、会话失效后不重新激活。拍照结束释放相机，避免后续跟随争用。
- 控制面板开关操作后刷新；状态区分启动、等待人脸、已识别人脸；连续 8 秒无人脸才提示，避免正常短暂漏检反复弹提示。
- 22 项相关测试、静态检查及 Android debug 构建通过。尚需新版本真机确认横竖屏识别效果。

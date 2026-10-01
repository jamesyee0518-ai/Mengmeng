# Voice Wake-up Progress

## Current Status

As of the current V2.0-alpha checkpoint, the voice wake-up pipeline has moved from a FacePage-managed loop into a controller-driven voice subsystem.

Completed:

- V1.1: text-level wake-word matching with primary, alias, fuzzy, and similarity scoring.
- V1.2: Android audio RMS metadata, lightweight audio gate, and Gateway `/stt` empty or short-audio fallback.
- V1.2.5: `recordUntilSilence` for conversation recording.
- V1.3: `VoiceWakeController` extracted from `FacePage`.
- V1.4: `VoiceDebugSnapshot` and debug panel.
- V1.4.5: dynamic tuning and debug sample labeling.
- V1.4.6: JSONL sample persistence, recent sample view, summary, export path, and clear action.
- V1.5: simplified high-RMS TTS barge-in.
- V1.6: sample replay analysis and threshold recommendation.
- V1.6.5: stable widget smoke tests and key-based control panel tests.
- V1.7: lifecycle governance, cancellation generation token, microphone permission handling, and native recording mutex.
- V1.7.5: Gateway `/health`, timeout protection, and offline degradation.
- V1.8: runtime voice profiles and persistent settings.
- V2.0-alpha: `WakeDetector` abstraction, default `SttWakeDetector`, and native detector stubs for Sherpa-ONNX and openWakeWord.
- V2.1-alpha: Sherpa-ONNX 1.13.4 Android KWS integration, bundled Mengmeng model, 16 kHz native PCM stream, and automatic STT fallback.

Current Android monitoring path:

```text
VoiceWakeController
  -> SherpaOnnxWakeDetector
  -> Android EventChannel (16 kHz mono PCM)
  -> local sherpa-onnx keyword spotter
  -> Mengmeng / Xiaoyuan / Qunqun teacher
  -> WakeDetectorDetected / WakeDetectorIgnored
  -> VoiceWakeController converts to VoiceEvent
```

If native initialization or model loading fails, monitoring falls back to the existing STT wake path. Conversation recording and conversation STT are unchanged.

Compatibility retained:

- Monitoring still defaults to STT fallback.
- Conversation still uses `listenForUtterance` and must not be replaced by local wake detection.
- Barge-in, debug panel, JSONL samples, health check, lifecycle handling, and TTS cooldown remain in place.
- Wake matcher rules are preserved, including fuzzy words not waking alone and prompt-leak flag penalties.

Latest verification:

- `dart analyze`: passed.
- `flutter test`: passed.
- `python3 -m py_compile ai_gateway/main.py`: passed.
- `git diff --check`: passed.

## Next Development Plan

Goal: complete real-device tuning of Sherpa-ONNX monitoring wake-up. Do not change conversation STT.

1. Run real-device experiments.
   - Test quiet room, noisy room, far-field, TTS playback, and lifecycle transitions.
   - Verify that monitoring local wake does not call Gateway `/stt` unless fallback is explicitly used.
   - Verify conversation still records with `recordUntilSilence` and sends user utterances to STT.

2. Add Debug Panel switching and JSONL fields.
   - Allow selecting STT / Sherpa-ONNX / openWakeWord from the debug panel.
   - Persist selected detector type with voice settings.
   - Record detector type, native score, model status, and fallback reason in JSONL samples.

Non-goals for the next step:

- Do not modify conversation STT.
- Do not train a custom wake-word model.
- Do not save raw audio files.
- Do not remove STT fallback.
- Do not make large UI changes.

## 2026-09-29 Voice and conversation audit

- Found split gateway defaults: chat used the public endpoint while Android STT still used an obsolete LAN address. Chat, health, and STT now share gateway_config.dart; FacePage passes the active chat endpoint to SpeechService.
- Local keyword spotting now releases its microphone before conversation recording and TTS. Sherpa resumes its stream after returning to monitoring, and avoids native stop calls when never started. Corrected the Qunqun persona key to qunqun_teacher.
- Waiting for a response and speaking no longer consume the conversation inactivity window.
- Added endpoint consistency, microphone handoff, and busy-conversation timeout regressions. All 114 Flutter tests, static analysis, and Android debug build passed.
- Public health reports STT/LLM/TTS available. A real chat request with memory disabled returned 对话正常~ with model_provider=lmstudio, without fallback. This checks the server from the development machine; physical phone wake, speech transcription, and audible playback still require user verification.

### Control panel activation fix

- Phone screenshot confirmed all five voice/vision actions were disabled while input/vision permissions were enabled. The modal retained the busy state from when it opened. It now refreshes from live page state after page updates instead of retaining a snapshot.
- First touch reveals the overlay without issuing a tap event to the gateway; subsequent intentional touches retain their interaction behavior.
- Regression tests open the modal during a pending chat request, verify all five actions are disabled, then complete the request and verify all five are enabled without closing the modal. Vision monitoring toggles on/off in the same panel; revealing controls issues no gateway event.
- Full suite: 116 tests passed; final notifier implementation: 10 widget tests and static analysis passed.
- Installed successfully on P30 Pro. At 19:06 the live control panel showed all five actions enabled; before/after screenshots confirmed disabled gray changed to enabled green. Panel left open for user testing.

### Voice unavailable health timeout

- Live public /health returned HTTP 200 with STT/LLM/TTS healthy, taking 4.09 seconds from the development machine. App health probes previously timed out at 2 seconds, causing a false unavailable result.
- Both health clients now share a 12-second timeout. Voice startup retains the actual failure reason and distinguishes a timeout, gateway connection failure, and STT failure in user messages.
- Added a delayed healthy-response regression (4 seconds). All 117 tests and static analysis passed. Phone startup verification remains necessary; desktop health alone does not prove the phone connection.

- Phone entered local wake capture after the health fix. Live PID 4508 logs exposed RangeError: Offset (5) must be a multiple of BYTES_PER_ELEMENT (2) in SherpaOnnxWakeDetector._consumeAudio. EventChannel Uint8List can have an odd buffer offset; replaced Int16List.view with byte-offset-safe little-endian ByteData decoding. Added odd-offset and empty/truncated PCM tests. All 119 tests, static analysis and APK build passed.
- Final APK installed successfully. Fresh process PID 5997: after tapping wake, the live button changed to 关闭唤醒; no PCM RangeError appeared in that process log. Health gate no longer blocked this start. Spoken keyword accuracy and full audio conversation still need physical user confirmation.

## 2026-09-30 唤醒异常恢复

现场手机麦克风权限已授予，开启后显示 sherpaOnnx/running；诊断快照同时含过短语音、低音量拦截及打断记录，不能仅凭历史字段认定当前漏唤醒的具体原因。

修复 Sherpa 原生启动结果未校验、音频流错误后继续空转的问题：先订阅再启动，校验 started，异常释放本地录音并回退 STT 唤醒；初始化中停止会使后续启动失效，销毁等待初始化结束后释放模型。Android 增加录音初始化、录制状态、读取失败及麦克风被其他录音占用的错误上报。

当前 VAD 是手机音频能量与持续时间门限，不是 Silero/WebRTC。本地 Sherpa KWS 独立检测唤醒词，连续对话由音量及静音超时断句，服务器 FunASR SenseVoice 执行转写。本轮未更换 VAD 算法或覆盖用户自定义阈值。

验证：全量 138 项 Flutter 测试和静态检查通过；随后增加初始化期间销毁测试，4 项 Sherpa 生命周期测试全部通过；最终 Android debug 构建成功，2026-09-30 00:36 已覆盖安装并启动华为 P30 Pro。真人唤醒成功率仍待现场复测，不将软件测试视为实机声学验收。

## 默认唤醒与提示中心（2026-09-30）

用户现场两次呼叫未产生网关请求；实际 UI 为 idle、唤醒关闭，但 detectorStatus 残留 running。修正停止时的诊断状态，并将唤醒改为启动默认开启、前后台切换完成停止后恢复。用户主动关闭或改为手动输入/对话后，本次运行不自动重开；隐私和禁用语音输入时不启动。局部关键词监听不再由网关健康检查阻止。

主屏移除状态文字与所有 FacePage SnackBar；右上角提示点始终可访问，未读红色，阅读后变灰。警告、错误和操作提示集中在弹层中，重复内容去重，保留最多 50 条。语音诊断移至限定高度的可滚动弹层，修复用户截图中的横屏 Column 溢出。

验证：141 项全量 Flutter 测试与静态检查通过，另补横屏弹层/前台恢复测试；真机关键词触发仍需升级后实测。

新版构建及覆盖安装成功。实机主屏仅显示“有新提示”入口与表情；点开提示显示“低功耗监听中”“萌萌唤醒已开启”，诊断为 monitoring / granted / running，warning 为空。15 项页面测试通过，包含横屏诊断滚动、默认启动、前台恢复和手动关闭不自动重开。已再次请用户进行真人唤醒确认。

## 真人漏唤醒继续排查（2026-09-30）

用户报告呼叫无回应。实机权限已授予，词表与安装包一致，旧诊断仅显示 running，且错误地混入 STT 的零值快照，不能证明收音状态。加入每秒本地 PCM 的 RMS 和峰值，状态 receiving_audio 仅由实际 PCM 推进；连续三次两秒检查未收到有效帧时释放本地录音并启用现有 STT 备用检测。停止时取消检查定时器。

识别结果改为每次 decode 后立即检查、命中后立即 reset，避免积压多个分块时覆盖中途命中；顺序与 Sherpa 官方麦克风示例一致： https://github.com/k2-fsa/sherpa-onnx/blob/master/python-api-examples/keyword-spotter-from-microphone.py 。这项修正不代表已经证明本次真人漏检由分块覆盖导致。

本机隔离环境使用项目同一模型和词表，合成“萌萌”可以命中；该实验使用 Python sherpa-onnx 1.13.8，手机 Dart 依赖 1.13.4，不能视为同平台声学验收。151 项 Flutter 测试通过，静态检查和 APK 构建通过，已覆盖安装。实机收到有效 PCM（一个采样窗口 RMS 90.2，峰值 379），无错误，等待用户真人复测。没有降低关键词阈值，也未保存用户原始录音。

## 新增小易唤醒词（2026-09-30）

加入“小易”“你好小易”“小易小易”，均映射现有 mengmeng 人设，原词保留。同步本地 Sherpa 音素词表和 STT 文本匹配；相同分数优先较长唤醒词，避免重复词或问候前缀残留为指令。初始化时刷新 keywords.txt，模型权重仍复用缓存，使覆盖升级能实际更新词表。

154 项 Flutter 测试、静态检查与 Android 构建通过，新版已覆盖安装手机。新增测试覆盖三个词单独唤醒、尾随指令提取；真人声学识别效果仍需现场试用。

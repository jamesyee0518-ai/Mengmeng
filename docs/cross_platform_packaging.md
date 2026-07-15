# 跨平台打包说明

## 运行 Gateway

使用 medium Whisper 模型启动：

```bash
cd /Users/jamesyee/Desktop/Mengmeng
scripts/run_gateway_medium.sh
```

默认配置：

```text
LM Studio: http://127.0.0.1:1234/v1
模型: qwen3-vl-8b-instruct
Whisper: /Users/jamesyee/Models/whisper/ggml-medium.bin
Gateway: http://0.0.0.0:8787
```

如需临时换模型或地址，可在命令前覆盖环境变量：

```bash
LMSTUDIO_MODEL=qwen3-vl-8b-instruct \
WHISPER_MODEL=/Users/jamesyee/Models/whisper/ggml-medium.bin \
scripts/run_gateway_medium.sh
```

## 打包 App

统一入口：

```bash
cd /Users/jamesyee/Desktop/Mengmeng
AI_GATEWAY_BASE_URL=http://192.168.1.111:8787 scripts/build_pocket_companion.sh android-apk
```

可选目标：

```text
android-apk        Android 正式 APK
android-apk-debug  Android 调试 APK
android-aab        Android 上架用 App Bundle
macos              macOS .app
linux              Linux 桌面包
windows            Windows 桌面包
all-local          Android + 当前系统支持的桌面包
```

## 产物位置

```text
Android APK: pocket_companion/build/app/outputs/flutter-apk/app-release.apk
Android Debug APK: pocket_companion/build/app/outputs/flutter-apk/app-debug.apk
Android AAB: pocket_companion/build/app/outputs/bundle/release/app-release.aab
macOS: pocket_companion/build/macos/Build/Products/Release/pocket_companion.app
Linux: pocket_companion/build/linux/x64/release/bundle
Windows: pocket_companion/build/windows/x64/runner/Release
```

## 平台限制

Android 可以在 macOS/Linux/Windows 上打包，只要 Android SDK 配好。

macOS 桌面包必须在 macOS 上打包。

Linux 桌面包建议在 Linux 上打包。

Windows 桌面包建议在 Windows 上打包。

这不是工程限制，而是 Flutter 桌面平台工具链的常规限制。

## 分辨率和宽高比

Flutter 会按设备窗口尺寸自适应，不需要为每种分辨率分别打包。当前 App 的核心页面已经按移动端和桌面窗口使用响应式布局处理。

如果后续要做桌面版专门体验，建议增加这些检查：

```text
手机竖屏: 360x780
手机横屏: 780x360
平板: 1024x768
桌面小窗: 900x700
桌面宽屏: 1440x900
```

## TTS 说明

当前 TTS 由 Flutter App 端调用系统语音能力：

```text
pocket_companion/lib/features/voice/tts_service_io.dart
```

small/medium 是 Whisper 语音识别模型，不是 TTS 模型。TTS 的男女声、语速、音高、音量由 App 端根据 Gateway 返回的 voice 字段设置。

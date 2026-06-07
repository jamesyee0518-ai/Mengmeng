# MVP 真机验收清单

## 启动条件

Gateway:

```bash
cd /Users/jamesyee/Desktop/Mengmeng
scripts/run_gateway_medium.sh
```

Android 调试包:

```bash
cd /Users/jamesyee/Desktop/Mengmeng
AI_GATEWAY_BASE_URL=http://192.168.1.111:8787 scripts/build_pocket_companion.sh android-apk-debug
adb install -r -g pocket_companion/build/app/outputs/flutter-apk/app-debug.apk
```

## App 内验收

打开设置齿轮，进入“设备自检”。

先点击“网关”，确认网关、模型、STT 三项就绪。

逐项完成“MVP 验收”中的项目，并标记通过或失败：

```text
Gateway 连接
语音识别
语音回复
唤醒词
看图问答
视觉守望
触摸打断
强度识别
隐私模式
稳定运行
```

## 关键日志

网关诊断:

```text
GET /diagnostics
device_check · gateway ok model=... stt=Whisper OK
```

语音识别:

```text
[gateway] stt ok=True text=...
```

普通对话:

```text
[gateway] chat input text='...'
[gateway] lmstudio chat messages[...]
```

看图问答:

```text
[gateway] chat/vision text='...' has_image=True base64_len=...
[gateway] lmstudio vision messages[...] images=1
[gateway] chat/vision final text='...' vision_used=True
```

视觉守望:

```text
vision · presence scan
vision · presence result: 有人
vision · presence changed: person_seen
```

触摸打断:

```text
tts · stop
```

隐私模式:

```text
settings · privacy=true ...
vision · monitor stop: vision disabled
```

## 日志复制

打开“日志”面板，点击复制按钮，可将最近日志复制出来用于定位。

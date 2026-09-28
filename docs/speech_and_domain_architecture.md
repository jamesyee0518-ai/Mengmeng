# 语音链路与域名接入架构（FunASR / edge-tts / 域名反代）

> 日期：2026-09-28。STT/TTS 从"Mac 本地 whisper.cpp + 手机系统合成"迁移为"Ubuntu 服务器网络调用"，并统一通过域名对外服务。

## 总体链路

```text
手机 App（任何网络，无需内网）
    │  https://aipipeline.hiqer.top/mengmeng/gw/*      ← 唯一入口，不依赖 IP
    ▼
frp 穿透 → video_dub_pipeline webui (Ubuntu 192.168.11.10:17890)
    │  apps/mengmeng_proxy.py 蓝图（/mengmeng/* 反向代理）
    ├─ /mengmeng/gw/<path>     → Mac ai_gateway (192.168.11.13:8787，失败自动切 .226)
    │      ├─ LLM: MiniMax-M3（api.minimaxi.com，聊天/视觉同模型）
    │      └─ STT/TTS: 转发 → mengmeng_speech
    └─ /mengmeng/speech/<path> → mengmeng_speech (127.0.0.1:8801)
           ├─ /stt: FunASR SenseVoiceSmall（RTX 4060 Ti GPU，二次调用 ~0.2s，RTF 0.018）
           └─ /tts: edge-tts（zh-CN 晓晓/晓依/云希，按 persona 映射）

/mengmeng/ping  → 入口探活
```

## 各组件位置与运维

| 组件 | 位置 | 启动/重启 |
|---|---|---|
| mengmeng_speech | 服务器 `~/mengmeng_speech/server.py`（venvs/main 运行） | `bash ~/mengmeng_speech/ensure_speech.sh`；crontab `@reboot` 自启；日志 `~/mengmeng_speech/speech.log` |
| mengmeng-proxy 蓝图 | 服务器 `~/video_dub_pipeline/apps/mengmeng_proxy.py`（已加入 webui.py `PANEL_ORDER`） | 随 webui 重启生效 |
| webui（域名入口） | 服务器 :17890，由 frpc 穿透 `aipipeline.hiqer.top`（frpc 配置 /etc/frp/frpc.toml 仅 root 可读） | `cd ~/video_dub_pipeline && nohup bash run_webui.sh &`；日志 `outputs/logs/webui.log` |
| Mac ai_gateway | `Mengmeng/ai_gateway/main.py`，`scripts/run_gateway_medium.sh` | 当前正运行于 Mac :8787 |
| 手机 App | baseUrl 默认 `https://aipipeline.hiqer.top/mengmeng/gw`（可用 `--dart-define=AI_GATEWAY_BASE_URL=...` 覆盖） | — |

## 降级链路（全部自动）

- **STT**：funasr_http 不可达 → Mac 本地 whisper（ggml-medium）→ 仍失败则返回错误
- **TTS**：网关 /tts 502 → 手机 flutter_tts 系统合成
- **LLM**：MiniMax 失败 → 网关内置规则回复（is_fallback）
- **网关主备**：Mac 双地址 192.168.11.13 / .226 在代理层自动切换

## 本轮踩坑记录

1. edge-tts CLI 的 `--rate -5%` 会被 argparse 当成新参数 → 必须用等号形式 `--rate=-5%`。
2. 服务器 webui 的旧进程 SIGTERM 杀不死，需 `kill -9`；且 `pkill -f 'webui.py --port'` 会误杀含同样文本的 ssh 会话自身。
3. `pkill` 后端口短暂残留，ensure 脚本的"端口已监听则跳过"会误判，需稍后重跑。
4. audioplayers 锁 6.4.0+（6.8.x 要 Flutter≥3.44，本项目 Dart 3.11.5 不满足）；6.7.1 无 `onPlayerError`、`play()` 返回 Future<void>。
5. FunASR 注册键 = hub id 末段（iic/SenseVoiceSmall → SenseVoiceSmall），配 model_path 本地直读可完全离线加载。

## 待办 / 已知边界

- **手机当前无任何网络**（Active default network: none，2026-09-28 实测）——接 WiFi 或插 SIM 后域名链路即用；Mac 侧同路径已全验证（聊天 2.3s / TTS 14KB mp3 / 健康全绿）。
- frp 链路超时上限未知；MiniMax 长推理（>60s）若经域名被 frp 断连，可考虑 webui 侧改为异步轮询。
- 域名走公网绕行（手机→VPS→家宽服务器→LAN Mac→公网 MiniMax），聊天 RTT ~2-3s；若需提速可再给网关加一条 frp 映射直连。
- /mengmeng/speech/* 暴露在公网（无鉴权）——仅限家庭使用场景；如需加固可在蓝图加共享 token。

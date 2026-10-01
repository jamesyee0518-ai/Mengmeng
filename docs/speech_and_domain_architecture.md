# 语音链路与域名接入架构（FunASR / edge-tts / 域名反代）

> 当前部署：2026-09-30。网关、语音服务和域名代理均在 Ubuntu 语音服务器，手机无需连接 Mac。下方历史记录保留用于追溯。

## 总体链路

```text
手机 App（任何网络，无需内网）
    │  https://aipipeline.hiqer.top/mengmeng/gw/*      ← 唯一入口，不依赖 IP
    ▼
frp 穿透 → video_dub_pipeline webui (Ubuntu 192.168.11.10:17890)
    │  apps/mengmeng_proxy.py 蓝图（/mengmeng/* 反向代理）
    ├─ /mengmeng/gw/<path>     → 服务器本机 127.0.0.1:8787（systemd 用户服务）
    │      ├─ LLM: MiniMax-M3（api.minimaxi.com，聊天/视觉同模型）
    │      └─ STT/TTS: 直接访问 http://127.0.0.1:8801 → mengmeng_speech
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
| 服务器 ai_gateway | `~/video_dub_pipeline/services/mengmeng_gateway/` | `systemctl --user restart mengmeng-gateway.service`；已 enable，用户 Linger=yes |
| 手机 App | baseUrl 默认 `https://aipipeline.hiqer.top/mengmeng/gw`（可用 `--dart-define=AI_GATEWAY_BASE_URL=...` 覆盖） | — |

## 降级链路（全部自动）

- **STT**：直接调用本机 FunASR；服务器未安装 whisper-cli，本机 FunASR 故障时会返回错误，不再回退 Mac。
- **TTS**：网关 /tts 502 → 手机 flutter_tts 系统合成
- **LLM**：MiniMax 失败 → 网关内置规则回复（is_fallback）
- **网关通道**：代理直接访问服务器本机 8787，无 Mac SSH 反向隧道依赖。

## 本轮踩坑记录

1. edge-tts CLI 的 `--rate -5%` 会被 argparse 当成新参数 → 必须用等号形式 `--rate=-5%`。
2. 服务器 webui 的旧进程 SIGTERM 杀不死，需 `kill -9`；且 `pkill -f 'webui.py --port'` 会误杀含同样文本的 ssh 会话自身。
3. `pkill` 后端口短暂残留，ensure 脚本的"端口已监听则跳过"会误判，需稍后重跑。
4. audioplayers 锁 6.4.0+（6.8.x 要 Flutter≥3.44，本项目 Dart 3.11.5 不满足）；6.7.1 无 `onPlayerError`、`play()` 返回 Future<void>。
5. FunASR 注册键 = hub id 末段（iic/SenseVoiceSmall → SenseVoiceSmall），配 model_path 本地直读可完全离线加载。

## 待办 / 已知边界

- frp 链路超时上限未知；MiniMax 长推理（>60s）若经域名被 frp 断连，可考虑 webui 侧改为异步轮询。
- 域名走公网绕行（手机→VPS→语音服务器→公网 MiniMax），聊天 RTT ~2-3s；若需提速可再给网关加一条 frp 映射直连。
- /mengmeng/speech/* 暴露在公网（无鉴权）——仅限家庭使用场景；如需加固可在蓝图加共享 token。


## 2026-09-30 跨网络链路更新

- Mac 网关启动脚本的 `SPEECH_BASE_URL` 默认值已改为 `https://aipipeline.hiqer.top/mengmeng/speech`。当前进程也已加载此配置，MiniMax 参数保留。
- 服务器 `apps/mengmeng_proxy.py` 的默认网关目标改为 `http://127.0.0.1:18787`，禁用旧 IP 回退；原文件备份在 `outputs/backups/mengmeng_proxy.before_ssh_tunnel.20260930.py`。WebUI 已保留环境重启。
- Mac LaunchAgent：`~/Library/LaunchAgents/com.mengmeng.gateway-tunnel.plist`，直接启动 `/usr/bin/ssh`，登录自启、失败重试，15 秒保活、连续 3 次无响应退出重连。无需开放服务器公网端口。
- 项目提供等价的手动启动脚本 `scripts/run_gateway_tunnel.sh`；后台服务运行时不要再手动重复启动，以免争用远端端口。
- 通道依赖原有 frpc SSH visitor 的本地 6001 端口、Mac 在线且网关运行。Mac 休眠时服务不可用，恢复网络后通道会自动重连；网关自身仍沿用原启动脚本。
- 公网网关健康检查已通过：版本 `20260930-conversation-context`，FunASR 可达、MiniMax-M3 可达、TTS 为 edge-tts。

完整公网链路实测通过：经 `/mengmeng/gw/tts` 合成约 2.16 秒，`/mengmeng/gw/stt` 识别约 0.31 秒，MiniMax 首轮约 3.24 秒、追问约 1.68 秒；识别测试代号后，第二轮正确引用“蓝鲸四十七”。测试关闭长期记忆。现有手机 APK 的域名入口不变，无需重装。

## 2026-09-30 网关迁入语音服务器

- 代码位于 `~/video_dub_pipeline/services/mengmeng_gateway/`；服务只监听 `127.0.0.1:8787`，版本 `20260930-server-boss`。
- `runtime.json` 权限 600，保存由旧进程迁移的 MiniMax 设置；不提交到仓库或在日志中输出密钥。`start.py` 加载配置后启动网关。
- `mengmeng-gateway.service` 已启用，异常退出自动重启；`loginctl enable-linger yzq` 已生效，用户退出登录后仍运行并支持开机启动。服务日志使用 `journalctl --user -u mengmeng-gateway.service`。部署模板在仓库 `deploy/mengmeng_gateway/`。
- `apps/mengmeng_proxy.py` 默认目标改为本机 8787，当前 WebUI 环境同步更新；备份文件 `outputs/backups/mengmeng_proxy.before_server_gateway.20260929-183422.py`。
- 服务器直接使用本机 FunASR/edge-tts，去掉语音请求经过公网回环的路径；模型、人设、老板称呼、表情字段、多轮上下文协议不变。手机地址不变，不需重装。
- 验证：服务器 13 项网关测试通过；公网 TTS 返回 20,304 字节音频，STT 正确识别“老板服务器迁移测试成功”，MiniMax 追问正确回忆“蓝鲸四十七”。
- Mac 旧网关进程已停止，`com.mengmeng.gateway-tunnel` 已 disable 并 bootout，plist 保留用于人工回滚；停用后公网健康检查继续显示服务器版本且 STT/LLM/TTS 全部正常。
- 回滚时需要人工重新启动 Mac 网关、启用隧道并把代理改回 18787；当前不配置自动回退到 Mac，以免重新引入依赖。

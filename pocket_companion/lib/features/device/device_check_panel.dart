import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/logging/debug_log_store.dart';
import '../../core/network/ai_gateway_client.dart';
import '../settings/companion_settings.dart';
import '../vision/vision_service.dart';
import '../voice/speech_service.dart';
import '../voice/tts_service.dart';
import 'device_event.dart';
import 'device_event_service.dart';

class DeviceCheckPanel extends StatefulWidget {
  const DeviceCheckPanel({
    super.key,
    required this.gateway,
    required this.deviceEvents,
    required this.speech,
    required this.vision,
    required this.tts,
    required this.logs,
    required this.settings,
    required this.onSettingsChanged,
  });

  final AiGatewayClient gateway;
  final DeviceEventService deviceEvents;
  final SpeechService speech;
  final VisionService vision;
  final TtsService tts;
  final DebugLogStore logs;
  final CompanionSettings settings;
  final ValueChanged<CompanionSettings> onSettingsChanged;

  @override
  State<DeviceCheckPanel> createState() => _DeviceCheckPanelState();
}

class _DeviceCheckPanelState extends State<DeviceCheckPanel> {
  StreamSubscription<DeviceEvent>? _subscription;
  StreamSubscription<DeviceSensorSample>? _sensorSubscription;
  DeviceEvent? _lastEvent;
  DeviceSensorSample? _lastSample;
  DeviceSensorSample? _peakSample;
  String _gatewayStatus = '未测试';
  String _modelStatus = '未测试';
  String _sttStatus = '未测试';
  String _speechStatus = '未测试';
  String _visionStatus = '未测试';
  String _ttsStatus = '未测试';
  bool _isListening = false;
  bool _isLooking = false;
  bool _isSpeaking = false;
  bool _isCheckingGateway = false;
  late CompanionSettings _settings;
  final Map<String, _AcceptanceStatus> _acceptance = {};

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
    _subscription = widget.deviceEvents.events.listen((event) {
      if (!mounted) {
        return;
      }
      setState(() => _lastEvent = event);
    });
    _sensorSubscription = widget.deviceEvents.sensorSamples.listen((sample) {
      if (!mounted) {
        return;
      }
      setState(() {
        _lastSample = sample;
        _peakSample = _nextPeakSample(sample);
      });
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_sensorSubscription?.cancel());
    super.dispose();
  }

  Future<void> _testSpeech() async {
    if (_isListening || !_settings.allowSpeechInput) {
      return;
    }
    widget.logs.info('device_check', 'speech test start');
    setState(() {
      _isListening = true;
      _speechStatus = '正在听';
    });
    final text = await widget.speech.listenOnce();
    if (!mounted) {
      return;
    }
    setState(() {
      _isListening = false;
      _speechStatus = text?.trim().isNotEmpty == true ? text!.trim() : '无结果';
    });
    widget.logs.info('device_check', 'speech test: $_speechStatus');
  }

  Future<void> _testGateway() async {
    if (_isCheckingGateway) {
      return;
    }
    widget.logs.info('device_check', 'gateway diagnostics start');
    setState(() {
      _isCheckingGateway = true;
      _gatewayStatus = '诊断中';
      _modelStatus = '诊断中';
      _sttStatus = '诊断中';
    });
    final diagnostics = await widget.gateway.diagnostics();
    if (!mounted) {
      return;
    }
    if (diagnostics == null) {
      setState(() {
        _isCheckingGateway = false;
        _gatewayStatus = '不可达';
        _modelStatus = '未知';
        _sttStatus = '未知';
      });
      widget.logs.warning('device_check', 'gateway diagnostics failed');
      return;
    }
    final lmstudio = diagnostics['lmstudio'];
    final stt = diagnostics['stt'];
    final model = lmstudio is Map ? lmstudio['model'] : null;
    final enabled = lmstudio is Map ? lmstudio['enabled'] : null;
    final modelError = lmstudio is Map ? lmstudio['last_error'] : null;
    final whisperOk = stt is Map ? stt['whisper_model_exists'] == true : false;
    final cliOk = stt is Map ? stt['whisper_cli_ok'] == true : false;
    final ffmpegOk = stt is Map ? stt['ffmpeg_ok'] == true : false;
    final whisperModel = stt is Map ? stt['whisper_model'] : null;
    setState(() {
      _isCheckingGateway = false;
      _gatewayStatus = '已连接';
      _modelStatus = enabled == true
          ? '${model ?? 'local-model'}'
          : 'LM Studio 未启用';
      if (modelError is String && modelError.isNotEmpty) {
        _modelStatus = '异常 $modelError';
      }
      _sttStatus = whisperOk && cliOk && ffmpegOk
          ? 'Whisper OK'
          : 'STT 未就绪';
    });
    widget.logs.info(
      'device_check',
      'gateway ok model=$_modelStatus stt=$_sttStatus whisper=$whisperModel',
    );
  }

  Future<void> _testVision() async {
    if (_isLooking || !_settings.allowVision) {
      return;
    }
    widget.logs.info('device_check', 'vision test start');
    setState(() {
      _isLooking = true;
      _visionStatus = '正在看';
    });
    final result = await widget.vision.checkOnce();
    if (!mounted) {
      return;
    }
    setState(() {
      _isLooking = false;
      _visionStatus = result.label;
    });
    final detail = result.detail == null ? '' : ' ${result.detail}';
    widget.logs.info('device_check', 'vision test: ${result.label}$detail');
  }

  Future<void> _testTts() async {
    if (_isSpeaking || !_settings.allowSpeechOutput) {
      return;
    }
    widget.logs.info('device_check', 'tts test start');
    setState(() {
      _isSpeaking = true;
      _ttsStatus = '播放中';
    });
    await widget.tts.speak('萌萌设备自检完成。');
    if (!mounted) {
      return;
    }
    setState(() {
      _isSpeaking = false;
      _ttsStatus = '完成';
    });
    widget.logs.info('device_check', 'tts test end');
  }

  void _toggleKeepAwake() {
    final next = _settings.copyWith(keepAwake: !_settings.keepAwake);
    setState(() => _settings = next);
    widget.onSettingsChanged(next);
    widget.logs.info('device_check', 'keep awake: ${next.keepAwake}');
  }

  void _emit(String type, {double? intensity, String? intensityLevel}) {
    if (intensity != null) {
      widget.deviceEvents.emitSimulatedSensorSample(intensity);
    }
    widget.deviceEvents.emitSimulated(
      type,
      intensity: intensity,
      intensityLevel: intensityLevel,
    );
    widget.logs.info('device_check', 'simulate $type');
  }

  void _markAcceptance(String id, _AcceptanceStatus status) {
    setState(() => _acceptance[id] = status);
    final item = _AcceptanceItem.items.firstWhere((item) => item.id == id);
    widget.logs.info(
      'acceptance',
      '${item.title}: ${status == _AcceptanceStatus.passed ? 'passed' : 'failed'}',
    );
  }

  void _resetAcceptance() {
    setState(_acceptance.clear);
    widget.logs.info('acceptance', 'reset');
  }

  DeviceSensorSample _nextPeakSample(DeviceSensorSample sample) {
    final peak = _peakSample;
    if (peak == null ||
        sample.force >= peak.force ||
        sample.createdAt.difference(peak.createdAt) >
            const Duration(seconds: 8)) {
      return sample;
    }
    return peak;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 72 + bottomInset),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('设备自检', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    key: const ValueKey('closeDeviceCheck'),
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _StatusRow(
                icon: Icons.sensors,
                label: '事件',
                value: _lastEvent?.label ?? '未触发',
              ),
              _StatusRow(
                icon: Icons.speed,
                label: '强度',
                value: _lastSample?.label ?? '等待传感器',
              ),
              _StatusRow(
                icon: Icons.show_chart,
                label: '峰值',
                value: _peakSample?.label ?? '等待传感器',
              ),
              _StatusRow(
                icon: Icons.cloud_done,
                label: '网关',
                value: _gatewayStatus,
              ),
              _StatusRow(
                icon: Icons.psychology,
                label: '模型',
                value: _modelStatus,
              ),
              _StatusRow(icon: Icons.graphic_eq, label: 'STT', value: _sttStatus),
              _StatusRow(icon: Icons.mic, label: '听', value: _speechStatus),
              _StatusRow(
                icon: Icons.visibility,
                label: '看',
                value: _visionStatus,
              ),
              _StatusRow(icon: Icons.volume_up, label: '说', value: _ttsStatus),
              _StatusRow(
                icon: Icons.light_mode,
                label: '常亮',
                value: _settings.keepAwake ? '开' : '关',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _CheckButton(
                    key: const ValueKey('checkGateway'),
                    icon: _isCheckingGateway
                        ? Icons.sync
                        : Icons.cloud_done,
                    label: '网关',
                    onPressed: _isCheckingGateway ? null : _testGateway,
                  ),
                  _CheckButton(
                    key: const ValueKey('checkSpeech'),
                    icon: _isListening ? Icons.graphic_eq : Icons.mic,
                    label: '听',
                    onPressed: _settings.allowSpeechInput && !_isListening
                        ? _testSpeech
                        : null,
                  ),
                  _CheckButton(
                    key: const ValueKey('checkVision'),
                    icon: _isLooking
                        ? Icons.center_focus_strong
                        : Icons.visibility,
                    label: '看',
                    onPressed: _settings.allowVision && !_isLooking
                        ? _testVision
                        : null,
                  ),
                  _CheckButton(
                    key: const ValueKey('checkTts'),
                    icon: _isSpeaking ? Icons.stop : Icons.volume_up,
                    label: '说',
                    onPressed: _settings.allowSpeechOutput && !_isSpeaking
                        ? _testTts
                        : null,
                  ),
                  _CheckButton(
                    key: const ValueKey('checkKeepAwake'),
                    icon: Icons.light_mode,
                    label: '常亮',
                    onPressed: _toggleKeepAwake,
                  ),
                  _CheckButton(
                    key: const ValueKey('checkLightImpact'),
                    icon: Icons.touch_app,
                    label: '轻拍',
                    onPressed: () =>
                        _emit('shake', intensity: 14, intensityLevel: 'light'),
                  ),
                  _CheckButton(
                    key: const ValueKey('checkMediumImpact'),
                    icon: Icons.vibration,
                    label: '中拍',
                    onPressed: () =>
                        _emit('shake', intensity: 28, intensityLevel: 'medium'),
                  ),
                  _CheckButton(
                    key: const ValueKey('checkStrongImpact'),
                    icon: Icons.offline_bolt,
                    label: '重拍',
                    onPressed: () =>
                        _emit('shake', intensity: 34, intensityLevel: 'strong'),
                  ),
                  _CheckButton(
                    key: const ValueKey('checkExtremeImpact'),
                    icon: Icons.warning_amber,
                    label: '很重',
                    onPressed: () => _emit(
                      'shake',
                      intensity: 44,
                      intensityLevel: 'extreme',
                    ),
                  ),
                  _CheckButton(
                    key: const ValueKey('checkCharging'),
                    icon: Icons.battery_charging_full,
                    label: '充电',
                    onPressed: () => _emit('charging'),
                  ),
                  _CheckButton(
                    key: const ValueKey('checkLowBattery'),
                    icon: Icons.battery_alert,
                    label: '低电',
                    onPressed: () => _emit('low_battery'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _AcceptanceChecklist(
                statuses: _acceptance,
                onMark: _markAcceptance,
                onReset: _resetAcceptance,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _AcceptanceStatus { passed, failed }

class _AcceptanceItem {
  const _AcceptanceItem({
    required this.id,
    required this.title,
    required this.expected,
  });

  final String id;
  final String title;
  final String expected;

  static const items = [
    _AcceptanceItem(
      id: 'gateway',
      title: 'Gateway 连接',
      expected: '顶部云图标为已连接，日志出现 health ok。',
    ),
    _AcceptanceItem(
      id: 'speech',
      title: '语音识别',
      expected: '点击“听”后说一句中文，识别文本显示在“听”状态行。',
    ),
    _AcceptanceItem(
      id: 'chat_tts',
      title: '语音回复',
      expected: '说“你好”，萌萌能回复并播放 TTS，嘴型进入说话状态。',
    ),
    _AcceptanceItem(
      id: 'wake',
      title: '唤醒词',
      expected: '开启“萌萌唤醒”，说“萌萌”，进入语音对话状态。',
    ),
    _AcceptanceItem(
      id: 'vision_chat',
      title: '看图问答',
      expected: '说“萌萌，你看到了什么”，日志出现 chat/vision。',
    ),
    _AcceptanceItem(
      id: 'vision_monitor',
      title: '视觉守望',
      expected: '开启“视觉守望”，有人/无人变化时表情变化但不主动说话。',
    ),
    _AcceptanceItem(
      id: 'interrupt',
      title: '触摸打断',
      expected: 'TTS 播放时轻触脸部，语音立即停止。',
    ),
    _AcceptanceItem(
      id: 'impact',
      title: '强度识别',
      expected: '轻拍/中拍/重拍/很重显示不同强度，并有不同反应。',
    ),
    _AcceptanceItem(
      id: 'privacy',
      title: '隐私模式',
      expected: '开启隐私后，听、看、记忆关闭，视觉守望停止。',
    ),
    _AcceptanceItem(
      id: 'stability',
      title: '稳定运行',
      expected: '前台运行 30 分钟，无白屏、无闪退、表情仍然活动。',
    ),
  ];
}

class _AcceptanceChecklist extends StatelessWidget {
  const _AcceptanceChecklist({
    required this.statuses,
    required this.onMark,
    required this.onReset,
  });

  final Map<String, _AcceptanceStatus> statuses;
  final void Function(String id, _AcceptanceStatus status) onMark;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final passed = statuses.values
        .where((status) => status == _AcceptanceStatus.passed)
        .length;
    final failed = statuses.values
        .where((status) => status == _AcceptanceStatus.failed)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('MVP 验收', style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            Text(
              '$passed/${_AcceptanceItem.items.length} 通过',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            if (failed > 0) ...[
              const SizedBox(width: 8),
              Text(
                '$failed 失败',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: const Color(0xFFFF6B6B),
                ),
              ),
            ],
            IconButton(
              tooltip: '重置验收',
              visualDensity: VisualDensity.compact,
              onPressed: onReset,
              icon: const Icon(Icons.restart_alt),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._AcceptanceItem.items.map((item) {
          return _AcceptanceTile(
            item: item,
            status: statuses[item.id],
            onPass: () => onMark(item.id, _AcceptanceStatus.passed),
            onFail: () => onMark(item.id, _AcceptanceStatus.failed),
          );
        }),
      ],
    );
  }
}

class _AcceptanceTile extends StatelessWidget {
  const _AcceptanceTile({
    required this.item,
    required this.status,
    required this.onPass,
    required this.onFail,
  });

  final _AcceptanceItem item;
  final _AcceptanceStatus? status;
  final VoidCallback onPass;
  final VoidCallback onFail;

  @override
  Widget build(BuildContext context) {
    final icon = switch (status) {
      _AcceptanceStatus.passed => Icons.check_circle,
      _AcceptanceStatus.failed => Icons.cancel,
      null => Icons.radio_button_unchecked,
    };
    final color = switch (status) {
      _AcceptanceStatus.passed => const Color(0xFF36D399),
      _AcceptanceStatus.failed => const Color(0xFFFF6B6B),
      null => const Color(0xFF9AA7BD),
    };
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(item.title),
      subtitle: Text(item.expected),
      trailing: Wrap(
        spacing: 4,
        children: [
          IconButton(
            tooltip: '通过',
            visualDensity: VisualDensity.compact,
            onPressed: onPass,
            icon: const Icon(Icons.check),
          ),
          IconButton(
            tooltip: '失败',
            visualDensity: VisualDensity.compact,
            onPressed: onFail,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF74D8FF)),
          const SizedBox(width: 10),
          SizedBox(
            width: 52,
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              key: ValueKey('deviceCheck_$label'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckButton extends StatelessWidget {
  const _CheckButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: IconButton.filledTonal(onPressed: onPressed, icon: Icon(icon)),
    );
  }
}

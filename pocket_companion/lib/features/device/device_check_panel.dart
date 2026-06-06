import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/logging/debug_log_store.dart';
import '../settings/companion_settings.dart';
import '../vision/vision_service.dart';
import '../voice/speech_service.dart';
import '../voice/tts_service.dart';
import 'device_event.dart';
import 'device_event_service.dart';

class DeviceCheckPanel extends StatefulWidget {
  const DeviceCheckPanel({
    super.key,
    required this.deviceEvents,
    required this.speech,
    required this.vision,
    required this.tts,
    required this.logs,
    required this.settings,
    required this.onSettingsChanged,
  });

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
  String _speechStatus = '未测试';
  String _visionStatus = '未测试';
  String _ttsStatus = '未测试';
  bool _isListening = false;
  bool _isLooking = false;
  bool _isSpeaking = false;
  late CompanionSettings _settings;

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
            ],
          ),
        ),
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

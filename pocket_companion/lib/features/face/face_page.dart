import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/logging/debug_log_store.dart';
import '../../core/network/ai_gateway_client.dart';
import '../../core/network/gateway_health.dart';
import '../../core/network/gateway_health_service.dart';
import '../chat/robot_response.dart';
import '../device/device_check_panel.dart';
import '../device/device_event.dart';
import '../device/device_event_service.dart';
import '../logs/debug_log_panel.dart';
import '../memory/memory_panel.dart';
import '../settings/companion_settings.dart';
import '../vision/vision_service.dart';
import '../voice/barge_in_config.dart';
import '../voice/speech_service.dart';
import '../voice/tts_service.dart';
import '../voice/voice_audio_gate_config.dart';
import '../voice/voice_debug_sample_analyzer.dart';
import '../voice/voice_debug_sample.dart';
import '../voice/voice_debug_sample_store.dart';
import '../voice/voice_debug_sample_summary.dart';
import '../voice/voice_debug_snapshot.dart';
import '../voice/voice_events.dart';
import '../voice/voice_runtime_profile.dart';
import '../voice/voice_settings_store.dart';
import '../voice/voice_state.dart';
import '../voice/voice_tuning_recommendation.dart';
import '../voice/voice_wake_config.dart';
import '../voice/widgets/voice_debug_panel.dart';
import '../voice/voice_wake_controller.dart';
import 'expression_state.dart';
import 'face_controller.dart';
import 'painters/robot_face_painter.dart';

class FacePage extends StatefulWidget {
  const FacePage({
    super.key,
    this.gateway,
    this.tts,
    this.speech,
    this.vision,
    this.logs,
    this.deviceEvents,
    this.gatewayHealthService,
    this.voiceSettingsStore,
  });

  final AiGatewayClient? gateway;
  final TtsService? tts;
  final SpeechService? speech;
  final VisionService? vision;
  final DebugLogStore? logs;
  final DeviceEventService? deviceEvents;
  final GatewayHealthService? gatewayHealthService;
  final VoiceSettingsStore? voiceSettingsStore;

  @override
  State<FacePage> createState() => _FacePageState();
}

class _FacePageState extends State<FacePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const Duration _visionSeenInterval = Duration(seconds: 4);
  static const Duration _visionIdleInterval = Duration(seconds: 10);

  late final AnimationController _animation;
  late final FaceController _controller;
  late final AiGatewayClient _gateway;
  late final TtsService _tts;
  late final SpeechService _speech;
  late final VisionService _vision;
  late final GatewayHealthService _gatewayHealthService;
  late final DebugLogStore _logs;
  late final DeviceEventService _deviceEvents;
  late final TextEditingController _chatTextController;
  late final VoiceWakeController _voiceWakeController;
  VoiceDebugSampleStore _voiceDebugSampleStore = MemoryVoiceDebugSampleStore();
  VoiceSettingsStore _voiceSettingsStore = MemoryVoiceSettingsStore();
  StreamSubscription<DeviceEvent>? _deviceEventSubscription;
  StreamSubscription<VoiceEvent>? _voiceEventSubscription;
  StreamSubscription<VoiceDebugSnapshot>? _voiceDebugSubscription;
  Timer? _gatewayHealthTimer;
  bool _isGatewayOnline = false;
  GatewayHealth? _gatewayHealth;
  bool _isBusy = false;
  bool _isSpeaking = false;
  bool _isListening = false;
  bool _isVisionMonitoring = false;
  bool _showVoiceDebugPanel = false;
  VoiceState _voiceState = VoiceState.idle;
  VoiceDebugSnapshot _voiceDebugSnapshot = VoiceDebugSnapshot();
  List<VoiceDebugSample> _recentVoiceDebugSamples = const [];
  VoiceDebugSampleSummary _voiceDebugSampleSummary =
      VoiceDebugSampleSummary.empty();
  VoiceTuningRecommendation _voiceTuningRecommendation =
      const VoiceDebugSampleAnalyzer().analyze(
        samples: [],
        wakeConfig: VoiceWakeConfig(),
        audioGateConfig: VoiceAudioGateConfig(),
        bargeInConfig: BargeInConfig(),
      );
  String? _voiceDebugSamplePath;
  String _currentPersona = 'mengmeng';
  CompanionSettings _settings = CompanionSettings.initial();
  int _speechToken = 0;
  int _visionLoopToken = 0;
  bool? _lastVisualPresence;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = FaceController();
    _gateway = widget.gateway ?? AiGatewayClient();
    _tts = widget.tts ?? TtsService();
    _speech = widget.speech ?? SpeechService();
    _vision = widget.vision ?? VisionService();
    _gatewayHealthService =
        widget.gatewayHealthService ??
        GatewayHealthService(baseUrl: _gateway.debugBaseUrl);
    _logs = widget.logs ?? DebugLogStore();
    _deviceEvents = widget.deviceEvents ?? DeviceEventService();
    _deviceEventSubscription = _deviceEvents.events.listen(_handleDeviceEvent);
    _voiceWakeController = VoiceWakeController(
      speech: _speech,
      canListen: () =>
          mounted &&
          _settings.allowSpeechInput &&
          !_settings.privacyMode &&
          !_isBusy &&
          !_isSpeaking,
    );
    _voiceEventSubscription = _voiceWakeController.events.listen(
      (event) => unawaited(_handleVoiceEvent(event)),
    );
    _voiceDebugSubscription = _voiceWakeController.debugSnapshots.listen((
      snapshot,
    ) {
      if (mounted) {
        setState(() => _voiceDebugSnapshot = _withGatewayHealth(snapshot));
      }
    });
    _chatTextController = TextEditingController();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _logs.info('gateway', 'base ${_gateway.debugBaseUrl}');
    unawaited(_deviceEvents.start(keepAwake: _settings.keepAwake));
    unawaited(_initializeVoiceSettings());
    unawaited(_initializeVoiceDebugSampleStore());
    _gatewayHealthTimer = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(_refreshGatewayStatus()),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gatewayHealthTimer?.cancel();
    _visionLoopToken++;
    _voiceWakeController.dispose();
    _animation.dispose();
    _speech.stop();
    _vision.stop();
    _tts.stop();
    unawaited(_deviceEventSubscription?.cancel());
    unawaited(_voiceEventSubscription?.cancel());
    unawaited(_voiceDebugSubscription?.cancel());
    if (widget.deviceEvents == null) {
      unawaited(_deviceEvents.dispose());
    }
    _chatTextController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _voiceWakeController.notifyLifecycleResumed();
        _logs.info('lifecycle', 'resumed');
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _logs.info('lifecycle', state.name);
        unawaited(_pauseForAppLifecycle(state));
    }
  }

  Future<void> _pauseForAppLifecycle(AppLifecycleState state) async {
    _speechToken++;
    _visionLoopToken++;
    await _voiceWakeController.pauseForLifecycle(state.name);
    await _tts.stop();
    _voiceWakeController.notifyTtsEnded();
    try {
      await _speech.stop();
    } catch (_) {}
    if (!mounted) {
      return;
    }
    setState(() {
      _isSpeaking = false;
      _isListening = false;
      _isVisionMonitoring = false;
    });
  }

  Future<void> _refreshGatewayStatus() async {
    final health = await _gatewayHealthService.checkHealth();
    if (!mounted) {
      return;
    }
    _applyGatewayHealth(health);
    _logs.info(
      'gateway',
      health.ok ? 'health ok' : 'health failed ${health.reason}',
    );
  }

  void _applyGatewayHealth(GatewayHealth health) {
    _gatewayHealth = health;
    final nextSnapshot = _withGatewayHealth(
      _voiceDebugSnapshot,
      health: health,
      runtimeWarning: health.ok ? '' : health.reason,
    );
    setState(() {
      _isGatewayOnline = health.gateway.ok;
      _voiceDebugSnapshot = nextSnapshot;
    });
  }

  VoiceDebugSnapshot _withGatewayHealth(
    VoiceDebugSnapshot snapshot, {
    GatewayHealth? health,
    String? runtimeWarning,
  }) {
    final currentHealth = health ?? _gatewayHealth;
    if (currentHealth == null) {
      return snapshot;
    }
    return snapshot.copyWith(
      gatewayOk: currentHealth.gateway.ok,
      sttOk: currentHealth.stt.ok,
      llmOk: currentHealth.llm.ok,
      ttsOk: currentHealth.tts.ok,
      gatewayHealthReason: currentHealth.reason,
      gatewayCheckedAt: currentHealth.checkedAt,
      runtimeWarning: runtimeWarning ?? snapshot.runtimeWarning,
    );
  }

  Future<bool> _ensureVoiceGatewayReady() async {
    final health = await _gatewayHealthService.checkHealth();
    if (!mounted) {
      return false;
    }
    _applyGatewayHealth(health);
    if (!health.gateway.ok || !health.stt.ok) {
      final reason = !health.gateway.ok
          ? 'gateway_unavailable'
          : 'stt_unavailable';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('语音服务暂不可用：$reason')));
      _logs.warning('gateway', 'voice start blocked: $reason');
      return false;
    }
    return true;
  }

  Future<void> _initializeVoiceSettings() async {
    try {
      _voiceSettingsStore =
          widget.voiceSettingsStore ??
          await SharedPreferencesVoiceSettingsStore.create();
      final settings = await _voiceSettingsStore.load();
      if (!mounted) {
        return;
      }
      setState(() {
        if (settings.activeProfile == VoiceRuntimeProfile.custom) {
          _voiceWakeController.applyCustomConfig(
            wakeConfig: settings.wakeConfig,
            audioGateConfig: settings.audioGateConfig,
            bargeInConfig: settings.bargeInConfig,
            source: 'stored',
          );
        } else {
          _voiceWakeController.applyProfile(settings.activeProfile);
        }
        _showVoiceDebugPanel = settings.showVoiceDebugPanel;
      });
      _logs.info(
        'speech',
        'voice profile loaded ${settings.activeProfile.name}',
      );
    } catch (error) {
      _voiceSettingsStore = MemoryVoiceSettingsStore();
      _voiceWakeController.applyProfile(VoiceRuntimeProfile.balanced);
      _voiceDebugSnapshot = _voiceDebugSnapshot.copyWith(
        runtimeWarning: 'voice_settings_load_failed',
      );
      _logs.warning('speech', 'voice settings fallback: $error');
    }
  }

  Future<void> _persistVoiceSettings() async {
    final saved = await _voiceSettingsStore.save(
      VoiceSettingsData(
        activeProfile: _voiceWakeController.activeProfile,
        wakeConfig: _voiceWakeController.config,
        audioGateConfig: _voiceWakeController.audioGateConfig,
        bargeInConfig: _voiceWakeController.bargeInConfig,
        showVoiceDebugPanel: _showVoiceDebugPanel,
      ),
    );
    if (!saved) {
      _logs.warning('speech', 'voice settings save failed');
      if (mounted) {
        setState(() {
          _voiceDebugSnapshot = _voiceDebugSnapshot.copyWith(
            runtimeWarning: 'voice_settings_save_failed',
          );
        });
      }
    }
  }

  Future<void> _initializeVoiceDebugSampleStore() async {
    try {
      _voiceDebugSampleStore = await JsonlVoiceDebugSampleStore.create();
    } catch (error) {
      _logs.warning('speech', 'voice sample store fallback: $error');
      _voiceDebugSampleStore = MemoryVoiceDebugSampleStore();
    }
    await _refreshVoiceDebugSamples();
  }

  Future<void> _refreshVoiceDebugSamples() async {
    try {
      final samples = await _voiceDebugSampleStore.listRecent();
      final analysisSamples = await _voiceDebugSampleStore.listRecent(
        limit: 200,
      );
      final summary = await _voiceDebugSampleStore.summarize();
      final path = await _voiceDebugSampleStore.exportPath();
      final recommendation = const VoiceDebugSampleAnalyzer().analyze(
        samples: analysisSamples,
        wakeConfig: _voiceWakeController.config,
        audioGateConfig: _voiceWakeController.audioGateConfig,
        bargeInConfig: _voiceWakeController.bargeInConfig,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _recentVoiceDebugSamples = samples;
        _voiceDebugSampleSummary = summary;
        _voiceDebugSamplePath = path;
        _voiceTuningRecommendation = recommendation;
      });
    } catch (error) {
      _logs.warning('speech', 'voice sample refresh failed: $error');
    }
  }

  Future<void> _sendChat() async {
    final text = _chatTextController.text.trim();
    if (text.isEmpty || _isBusy) {
      return;
    }
    _chatTextController.clear();
    _logs.info('chat', 'send text');
    await _sendText(text);
  }

  Future<void> _sendText(String text) async {
    _controller.thinking(label: '正在想');
    await _applyGatewayCall(
      () => _gateway.chat(text, settings: _settings, persona: _currentPersona),
    );
  }

  Future<void> _lookAndAsk({String prompt = '请用一句中文描述你看到了什么。'}) async {
    if (_isBusy || !_settings.allowVision) {
      return;
    }
    await _sendTextWithVision(prompt, source: 'manual');
  }

  void _toggleVisionMonitoring() {
    if (_isVisionMonitoring) {
      _visionLoopToken++;
      setState(() {
        _isVisionMonitoring = false;
        _lastVisualPresence = null;
      });
      _logs.info('vision', 'monitor stop');
      return;
    }
    if (!_settings.allowVision || _settings.privacyMode) {
      _logs.warning('vision', 'monitor ignored: vision disabled');
      return;
    }
    setState(() => _isVisionMonitoring = true);
    _logs.info('vision', 'monitor start');
    final token = ++_visionLoopToken;
    unawaited(_runVisionMonitorLoop(token));
  }

  Future<void> _runVisionMonitorLoop(int token) async {
    while (mounted && _isVisionMonitoring && token == _visionLoopToken) {
      if (!_settings.allowVision || _settings.privacyMode) {
        _toggleVisionMonitoring();
        return;
      }
      if (_isBusy || _isListening || _isSpeaking) {
        await Future<void>.delayed(const Duration(seconds: 2));
        continue;
      }
      final hasPerson = await _checkVisualPresence();
      if (!mounted || !_isVisionMonitoring || token != _visionLoopToken) {
        return;
      }
      if (hasPerson != null && hasPerson != _lastVisualPresence) {
        _lastVisualPresence = hasPerson;
        await _handleVisualPresenceChanged(hasPerson);
      }
      final nextDelay = hasPerson == true
          ? _visionSeenInterval
          : _visionIdleInterval;
      await Future<void>.delayed(nextDelay);
    }
  }

  Future<bool?> _checkVisualPresence() async {
    _logs.info('vision', 'presence scan');
    try {
      final result = await _vision.checkOnce();
      if (!result.ok ||
          result.imageBytes == null ||
          result.imageBytes!.isEmpty) {
        _logs.warning('vision', 'presence capture failed: ${result.label}');
        return null;
      }
      final response = await _gateway.vision(
        result.imageBytes!,
        prompt: '只回答“有人”或“无人”：图片里是否有人、人脸或明显的人体？',
        settings: _settings,
        persona: _currentPersona,
      );
      final text = response.text.trim();
      _logs.info('vision', 'presence result: $text');
      if (text.contains('无人') || text.contains('没有人') || text.contains('沒有人')) {
        return false;
      }
      if (text.contains('有人') || text.contains('人脸') || text.contains('人臉')) {
        return true;
      }
      return null;
    } catch (error) {
      _logs.warning('vision', 'presence failed: $error');
      return null;
    }
  }

  Future<void> _handleVisualPresenceChanged(bool hasPerson) async {
    final eventType = hasPerson ? 'person_seen' : 'person_left';
    _logs.info('vision', 'presence changed: $eventType');
    if (hasPerson) {
      _controller.doubleTap();
    } else {
      _controller.longPress();
    }
    await _applyGatewayCall(
      () => _gateway.event(
        eventType,
        settings: _settings,
        persona: _currentPersona,
        source: 'vision_monitor',
      ),
      speakResponse: false,
    );
  }

  Future<void> _listenAndChat() async {
    if (_isBusy || _isListening || !_settings.allowSpeechInput) {
      return;
    }
    try {
      await _listenAndSendOnce();
    } catch (error) {
      _logs.warning('speech', 'listen failed: $error');
      if (mounted) {
        setState(() => _isListening = false);
      }
    }
  }

  /// 开启/关闭唤醒监听（齿轮页面控制）
  Future<void> _toggleWakeListening() async {
    if (_voiceState == VoiceState.monitoring) {
      await _voiceWakeController.stop();
      return;
    }
    if (!await _ensureVoiceGatewayReady()) {
      return;
    }
    await _voiceWakeController.start();
  }

  /// 手动触发一次语音对话（麦克风按钮）
  Future<void> _toggleVoiceConversation() async {
    if (_voiceState == VoiceState.conversation) {
      await _voiceWakeController.stop();
      return;
    }
    if (!await _ensureVoiceGatewayReady()) {
      return;
    }
    await _voiceWakeController.startConversation();
  }

  Future<void> _listenAndSendOnce() async {
    await _stopSpeaking();
    if (!mounted || _isBusy || _isListening || !_settings.allowSpeechInput) {
      return;
    }
    _controller.doubleTap();
    _logs.info('speech', 'listen start');
    setState(() => _isListening = true);
    final text = await _speech.listenOnce();
    if (!mounted) {
      return;
    }
    setState(() => _isListening = false);
    final normalized = text?.trim();
    if (normalized == null || normalized.isEmpty) {
      _logs.warning('speech', 'empty transcript');
      _controller.doubleTap();
      return;
    }
    _logs.info('speech', 'recognized: $normalized');
    await _handleRecognizedCommand(normalized);
  }

  Future<void> _handleVoiceEvent(VoiceEvent event) async {
    switch (event) {
      case VoiceStateChanged(:final state):
        _logs.info('speech', 'state ${_voiceState.name} -> ${state.name}');
        if (mounted) {
          setState(() {
            _voiceState = state;
            _isListening =
                state == VoiceState.recording ||
                state == VoiceState.bargeInListening;
          });
        }
      case WakeDetected():
        await _handleWakeDetected(event);
      case UserUtteranceDetected(:final text):
        await _handleRecognizedCommand(text);
      case BargeInDetected(:final reason, :final avgRms, :final maxRms):
        _logs.info(
          'speech',
          'barge-in detected reason=$reason avgRms=${avgRms.toStringAsFixed(1)} maxRms=${maxRms.toStringAsFixed(1)}',
        );
        await _handleBargeInDetected();
      case BargeInIgnored(:final reason):
        _logs.info('speech', 'barge-in ignored reason=$reason');
      case WakeIgnored(:final reason, :final text):
        _logs.info('speech', 'wake ignored reason=$reason text=$text');
      case VoiceLogEvent(:final message):
        _logs.info('speech', message);
      case VoiceError(:final error):
        _logs.warning('speech', 'voice controller error: $error');
      case WakeOnlyDetected():
        break;
    }
  }

  Future<void> _handleBargeInDetected() async {
    await _stopSpeaking();
    _controller.doubleTap();
    if (mounted) {
      setState(() => _isListening = false);
    }
  }

  Future<void> _handleWakeDetected(WakeDetected event) async {
    _currentPersona = event.persona;
    _logs.info(
      'speech',
      'persona ${event.persona} wake=${event.wakeWord} score=${event.score.toStringAsFixed(2)}',
    );
    _controller.setRole(_faceRoleForPersona(event.persona));
    _controller.doubleTap();
    if (event.command.isEmpty) {
      await _applyGatewayCall(
        () => _gateway.event(
          'wake',
          settings: _settings,
          persona: _currentPersona,
          source: 'voice_wake',
        ),
      );
      return;
    }
    await _handleRecognizedCommand(event.command);
  }

  Future<void> _handleRecognizedCommand(String commandText) async {
    if (_isVisionCommand(commandText)) {
      if (!_settings.allowVision) {
        _logs.warning('vision', 'voice command ignored: vision disabled');
        _controller.doubleTap();
        return;
      }
      _logs.info('vision', 'voice trigger vision: $commandText');
      await _listenWithVision(commandText);
      return;
    }
    await _sendText(commandText);
  }

  /// 语音触发视觉：先拍照，然后将文本+图片一起发给LLM
  Future<void> _listenWithVision(String commandText) async {
    await _sendTextWithVision(commandText, source: 'voice');
  }

  Future<void> _sendTextWithVision(
    String text, {
    required String source,
  }) async {
    _controller.thinking(label: '正在看');
    _logs.info('vision', 'capture start source=$source text=$text');
    try {
      final result = await _vision.checkOnce();
      if (!result.ok ||
          result.imageBytes == null ||
          result.imageBytes!.isEmpty) {
        _logs.warning('vision', 'capture failed: ${result.label}');
        if (source == 'voice') {
          await _sendText(text);
        } else {
          _controller.doubleTap();
        }
        return;
      }
      _logs.info(
        'vision',
        'captured ${result.imageBytes!.length} bytes, sending chat+vision',
      );
      await _applyGatewayCall(
        () => _gateway.chatWithVision(
          text,
          result.imageBytes!,
          settings: _settings,
          persona: _currentPersona,
        ),
      );
    } catch (error) {
      _logs.warning('vision', 'look failed: $error');
      if (source == 'voice') {
        await _sendText(text);
      } else {
        _controller.doubleTap();
      }
    }
  }

  FaceRole _faceRoleForPersona(String persona) {
    return switch (persona) {
      'xiaoyuan' => FaceRole.maleCalm,
      'qunqun_teacher' => FaceRole.femaleSoft,
      _ => FaceRole.femaleLively,
    };
  }

  bool _isVisionCommand(String text) {
    final compact = text.toLowerCase().replaceAll(
      RegExp(r'[\s，。！？、,.!?~～：:]'),
      '',
    );
    return compact.contains('你看到了什么') ||
        compact.contains('你看見了什麼') ||
        compact.contains('你看见了什么') ||
        compact.contains('你看到什么') ||
        compact.contains('看到了什么') ||
        compact.contains('看到了什麼') ||
        compact.contains('看看') ||
        compact.contains('看一下') ||
        compact.contains('帮我看') ||
        compact.contains('幫我看');
  }

  Future<void> _handleDeviceEvent(DeviceEvent event) async {
    if (_isBusy) {
      return;
    }
    _previewDeviceEvent(event.type);
    _logs.info('event', event.label);
    final didPlayImpactCue = await _playImpactCue(event);
    final shouldSpeakEvent =
        event.source != 'hardware' || event.type == 'shake';
    await _applyGatewayCall(
      () => _gateway.event(
        event.type,
        settings: _settings,
        deviceEvent: event,
        persona: _currentPersona,
      ),
      speakResponse: shouldSpeakEvent && !didPlayImpactCue,
    );
  }

  void _previewDeviceEvent(String type) {
    switch (type) {
      case 'tap':
        _controller.tap();
      case 'wake':
        _controller.doubleTap();
      case 'thinking':
        _controller.longPress();
      case 'speaking':
        _controller.speak();
      case 'shake':
        _controller.shake();
      case 'charging':
        _controller.charge();
      case 'low_battery':
        _controller.lowBattery();
      case 'flip_down':
        _controller.flipDown();
    }
  }

  Future<void> _applyGatewayCall(
    Future<RobotResponse> Function() call, {
    bool speakResponse = true,
  }) async {
    _controller.thinking(label: '正在想');
    setState(() => _isBusy = true);
    final response = await call();
    if (!mounted) {
      return;
    }
    _controller.applyRobotResponse(response);
    if (response.isFallback) {
      _logs.warning('fallback', response.fallbackReason);
      if (response.fallbackReason == 'gateway_timeout' ||
          response.fallbackReason == 'gateway_unreachable') {
        _voiceDebugSnapshot = _voiceDebugSnapshot.copyWith(
          runtimeWarning: response.fallbackReason,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gateway 调用失败：${response.fallbackReason}')),
        );
      }
    } else {
      final modelError = response.modelError.isEmpty
          ? ''
          : ' error=${response.modelError}';
      _logs.info(
        'gateway',
        'response ${response.expression.name} source=${response.modelProvider}$modelError',
      );
    }
    setState(() {
      _isBusy = false;
      _isGatewayOnline = true;
    });
    if (speakResponse) {
      await _speakResponse(response);
    }
  }

  Future<bool> _playImpactCue(DeviceEvent event) async {
    if (event.type != 'shake' || !_settings.allowSpeechOutput) {
      return false;
    }
    final cue = _ImpactVoiceCue.fromEvent(event);
    final token = ++_speechToken;
    await _pauseListeningForSpeech();
    _voiceWakeController.notifyTtsStarted();
    _controller.beginSpeaking();
    _logs.info('tts', 'impact ${cue.level}');
    setState(() => _isSpeaking = true);
    await _tts.speak(
      cue.text,
      style: 'impact',
      speed: cue.speed,
      pitch: cue.pitch,
      volume: cue.volume,
    );
    if (!mounted || token != _speechToken) {
      return true;
    }
    _controller.endSpeaking();
    _voiceWakeController.notifyTtsEnded();
    setState(() => _isSpeaking = false);
    return true;
  }

  Future<void> _speakResponse(RobotResponse response) async {
    if (!response.shouldSpeak ||
        !_settings.allowSpeechOutput ||
        response.text.trim().isEmpty) {
      return;
    }
    final health = _gatewayHealth;
    if (health != null && !health.tts.ok) {
      _logs.warning('tts', 'skip: tts_unavailable');
      _voiceDebugSnapshot = _voiceDebugSnapshot.copyWith(
        runtimeWarning: 'tts_unavailable',
      );
      return;
    }
    final token = ++_speechToken;
    await _pauseListeningForSpeech();
    _voiceWakeController.notifyTtsStarted();
    _controller.beginSpeaking();
    _logs.info('tts', 'start');
    setState(() => _isSpeaking = true);
    await _tts.speak(
      response.text,
      style: response.voice.style,
      speed: response.voice.speed,
      pitch: response.voice.pitch,
      volume: response.voice.volume,
    );
    if (!mounted || token != _speechToken) {
      return;
    }
    _controller.endSpeaking();
    _logs.info('tts', 'end');
    _voiceWakeController.notifyTtsEnded();
    setState(() => _isSpeaking = false);
  }

  Future<void> _pauseListeningForSpeech() async {
    try {
      await _speech.stop();
    } catch (_) {}
    if (!mounted || !_isListening) {
      return;
    }
    setState(() => _isListening = false);
  }

  void _updateSettings(CompanionSettings settings) {
    setState(() => _settings = settings);
    _logs.info(
      'settings',
      'privacy=${settings.privacyMode}, listen=${settings.allowSpeechInput}, vision=${settings.allowVision}, speak=${settings.allowSpeechOutput}, memory=${settings.allowMemory}, awake=${settings.keepAwake}',
    );
    unawaited(_deviceEvents.setKeepAwake(settings.keepAwake));
    if (!settings.allowSpeechOutput) {
      _stopSpeaking();
    }
    if (!settings.allowSpeechInput &&
        (_voiceState != VoiceState.idle || _isListening)) {
      _voiceWakeController.stop();
      setState(() => _isListening = false);
    }
    if ((!settings.allowVision || settings.privacyMode) &&
        _isVisionMonitoring) {
      _visionLoopToken++;
      setState(() {
        _isVisionMonitoring = false;
        _lastVisualPresence = null;
      });
      _logs.info('vision', 'monitor stop: vision disabled');
    }
    if (!settings.allowVision || settings.privacyMode) {
      unawaited(_vision.stop());
    }
  }

  Future<void> _showMemoryPanel() async {
    _logs.info('memory', 'open panel');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const MemoryPanel(),
    );
  }

  Future<void> _showLogPanel() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DebugLogPanel(store: _logs),
    );
  }

  Future<void> _showDeviceCheckPanel() async {
    _logs.info('device_check', 'open panel');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DeviceCheckPanel(
        gateway: _gateway,
        deviceEvents: _deviceEvents,
        speech: _speech,
        vision: _vision,
        tts: _tts,
        logs: _logs,
        settings: _settings,
        onSettingsChanged: _updateSettings,
      ),
    );
  }

  Future<void> _showControlPanel() async {
    var panelSettings = _settings;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setPanelState) => _ControlPanel(
          settings: panelSettings,
          isBusy: _isBusy,
          isListening: _isListening,
          isVisionMonitoring: _isVisionMonitoring,
          showVoiceDebugPanel: _showVoiceDebugPanel,
          voiceState: _voiceState,
          controller: _controller,
          onSettingsChanged: (next) {
            setPanelState(() => panelSettings = next);
            _updateSettings(next);
          },
          onListen: _listenAndChat,
          onLook: () => _lookAndAsk(),
          onToggleVisionMonitoring: _toggleVisionMonitoring,
          onToggleVoiceDebugPanel: () {
            setState(() => _showVoiceDebugPanel = !_showVoiceDebugPanel);
            unawaited(_persistVoiceSettings());
            if (!_showVoiceDebugPanel) {
              return;
            }
            unawaited(_refreshGatewayStatus());
          },
          onToggleVoiceConversation: _toggleVoiceConversation,
          onToggleWakeListening: _toggleWakeListening,
          onShowMemory: _showMemoryPanel,
          onShowLogs: _showLogPanel,
          onShowDeviceCheck: _showDeviceCheckPanel,
          onEvent: _deviceEvents.emitSimulated,
        ),
      ),
    );
  }

  Future<void> _stopSpeaking() async {
    _speechToken++;
    await _tts.stop();
    _controller.endSpeaking();
    _voiceWakeController.notifyTtsEnded();
    _logs.info('tts', 'stop');
    if (!mounted) {
      return;
    }
    setState(() => _isSpeaking = false);
  }

  Future<void> _saveVoiceDebugSample(VoiceDebugSampleLabel label) async {
    final sample = VoiceDebugSample.fromSnapshot(
      label: label,
      snapshot: _voiceDebugSnapshot,
      voiceWakeConfig: _voiceWakeController.config,
      audioGateConfig: _voiceWakeController.audioGateConfig,
    );
    await _voiceDebugSampleStore.add(sample);
    await _refreshVoiceDebugSamples();
    _logs.info(
      'speech',
      'voice debug sample saved label=${label.name} total=${_voiceDebugSampleSummary.total}',
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已记录语音样本：${label.name}')));
  }

  Future<void> _clearVoiceDebugSamples() async {
    await _voiceDebugSampleStore.clear();
    await _refreshVoiceDebugSamples();
    _logs.info('speech', 'voice debug samples cleared');
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已清空语音样本')));
  }

  void _applyVoiceTuningRecommendation() {
    setState(() {
      _voiceWakeController.applyRecommendationAsCustom(
        _voiceTuningRecommendation,
      );
    });
    unawaited(_persistVoiceSettings());
    unawaited(_refreshVoiceDebugSamples());
    _logs.info('speech', 'voice tuning recommendation applied');
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已应用推荐语音参数')));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final state = _controller.state;
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                _StatusBar(
                  state: state,
                  statusLabel: _activityLabelFor(state),
                  isGatewayOnline: _isGatewayOnline,
                  isBusy: _isBusy,
                  isSpeaking: _isSpeaking,
                  isListening: _isListening,
                  isVisionMonitoring: _isVisionMonitoring,
                  voiceState: _voiceState,
                  onRefresh: _refreshGatewayStatus,
                  onStopSpeaking: _stopSpeaking,
                  onOpenControls: _showControlPanel,
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (_isSpeaking) {
                        unawaited(_stopSpeaking());
                        return;
                      }
                      _deviceEvents.emitSimulated('tap');
                    },
                    onDoubleTap: () => _deviceEvents.emitSimulated('wake'),
                    onLongPress: () => _deviceEvents.emitSimulated('thinking'),
                    child: Semantics(
                      label: 'robot face ${state.expression.name}',
                      child: AnimatedBuilder(
                        animation: _animation,
                        builder: (context, _) {
                          return CustomPaint(
                            painter: RobotFacePainter(
                              state: state,
                              tick: _animation.value,
                            ),
                            child: const SizedBox.expand(),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                _ChatComposer(
                  controller: _chatTextController,
                  isBusy: _isBusy,
                  isListening: _isListening,
                  allowSpeechInput: _settings.allowSpeechInput,
                  onSend: _sendChat,
                  onListen: _listenAndChat,
                ),
                if (_showVoiceDebugPanel)
                  VoiceDebugPanel(
                    snapshot: _voiceDebugSnapshot,
                    wakeConfig: _voiceWakeController.config,
                    audioGateConfig: _voiceWakeController.audioGateConfig,
                    bargeInConfig: _voiceWakeController.bargeInConfig,
                    activeProfile: _voiceWakeController.activeProfile,
                    isCustomProfile: _voiceWakeController.isCustomProfile,
                    tuningRecommendation: _voiceTuningRecommendation,
                    onProfileChanged: (profile) {
                      setState(() {
                        _voiceWakeController.applyProfile(profile);
                      });
                      unawaited(_persistVoiceSettings());
                      unawaited(_refreshVoiceDebugSamples());
                    },
                    onWakeConfigChanged: (config) {
                      setState(() => _voiceWakeController.updateConfig(config));
                      unawaited(_persistVoiceSettings());
                      unawaited(_refreshVoiceDebugSamples());
                    },
                    onAudioGateConfigChanged: (config) {
                      setState(
                        () =>
                            _voiceWakeController.updateAudioGateConfig(config),
                      );
                      unawaited(_persistVoiceSettings());
                      unawaited(_refreshVoiceDebugSamples());
                    },
                    onBargeInConfigChanged: (config) {
                      setState(
                        () => _voiceWakeController.updateBargeInConfig(config),
                      );
                      unawaited(_persistVoiceSettings());
                      unawaited(_refreshVoiceDebugSamples());
                    },
                    onApplyTuningRecommendation:
                        _applyVoiceTuningRecommendation,
                    onRefreshGatewayHealth: _refreshGatewayStatus,
                    onSaveSample: _saveVoiceDebugSample,
                    recentSamples: _recentVoiceDebugSamples,
                    sampleSummary: _voiceDebugSampleSummary,
                    sampleExportPath: _voiceDebugSamplePath,
                    onClearSamples: () => unawaited(_clearVoiceDebugSamples()),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _activityLabelFor(ExpressionState state) {
    if (_isSpeaking) {
      return '正在说话，轻触可打断';
    }
    if (_isListening) {
      return switch (_voiceState) {
        VoiceState.monitoring => '低功耗监听唤醒词',
        VoiceState.conversation => '正在听你说',
        VoiceState.bargeInListening => '正在听打断',
        _ => '正在识别语音',
      };
    }
    if (_voiceState == VoiceState.bargeInListening) {
      return '正在听打断';
    }
    if (_isBusy) {
      return state.expression == RobotExpression.focus ? '正在看' : '正在想';
    }
    if (_voiceState == VoiceState.conversation) {
      return '语音对话中';
    }
    if (_voiceState == VoiceState.monitoring) {
      return '低功耗监听中';
    }
    if (_isVisionMonitoring) {
      return '视觉守望中';
    }
    return state.label;
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.state,
    required this.statusLabel,
    required this.isGatewayOnline,
    required this.isBusy,
    required this.isSpeaking,
    required this.isListening,
    required this.isVisionMonitoring,
    required this.voiceState,
    required this.onRefresh,
    required this.onStopSpeaking,
    required this.onOpenControls,
  });

  final ExpressionState state;
  final String statusLabel;
  final bool isGatewayOnline;
  final bool isBusy;
  final bool isSpeaking;
  final bool isListening;
  final bool isVisionMonitoring;
  final VoiceState voiceState;
  final VoidCallback onRefresh;
  final VoidCallback onStopSpeaking;
  final VoidCallback onOpenControls;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: Colors.white.withValues(alpha: 0.82),
      letterSpacing: 0,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          Icon(
            state.isAwake ? Icons.radio_button_checked : Icons.nightlight_round,
            size: 18,
            color: state.isAwake
                ? const Color(0xFF36D399)
                : const Color(0xFF8EA4FF),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              statusLabel,
              key: const ValueKey('expressionLabel'),
              style: textStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: isGatewayOnline ? 'Gateway 已连接' : 'Gateway 未连接',
            child: IconButton(
              key: const ValueKey('gatewayStatus'),
              visualDensity: VisualDensity.compact,
              onPressed: onRefresh,
              icon: Icon(
                isGatewayOnline ? Icons.cloud_done : Icons.cloud_off,
                size: 18,
                color: isGatewayOnline
                    ? const Color(0xFF36D399)
                    : const Color(0xFFFFC857),
              ),
            ),
          ),
          if (isBusy) ...[
            const SizedBox(width: 8),
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
          if (isListening) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.mic,
              size: 18,
              color: const Color(0xFF74D8FF).withValues(alpha: 0.92),
            ),
          ],
          if (voiceState == VoiceState.monitoring) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: '低功耗监听唤醒词',
              child: Icon(
                Icons.radar,
                size: 18,
                color: const Color(0xFFB8FF74).withValues(alpha: 0.92),
              ),
            ),
          ],
          if (voiceState == VoiceState.conversation) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: '连续语音对话',
              child: Icon(
                Icons.hearing,
                size: 18,
                color: const Color(0xFF74D8FF).withValues(alpha: 0.92),
              ),
            ),
          ],
          if (isVisionMonitoring) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: '低频视觉守望',
              child: Icon(
                Icons.center_focus_strong,
                size: 18,
                color: const Color(0xFFFFD166).withValues(alpha: 0.92),
              ),
            ),
          ],
          if (isSpeaking) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: '停止说话',
              child: IconButton.filledTonal(
                key: const ValueKey('stopSpeaking'),
                visualDensity: VisualDensity.compact,
                onPressed: onStopSpeaking,
                icon: const Icon(Icons.stop, size: 18),
              ),
            ),
          ],
          const SizedBox(width: 8),
          Icon(
            Icons.battery_4_bar,
            size: 18,
            color: Colors.white.withValues(alpha: 0.72),
          ),
          const SizedBox(width: 4),
          Text('${state.energy}%', style: textStyle),
          const SizedBox(width: 8),
          Tooltip(
            message: '设置',
            child: IconButton.filledTonal(
              key: const ValueKey('openControlPanel'),
              visualDensity: VisualDensity.compact,
              onPressed: onOpenControls,
              icon: const Icon(Icons.settings, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatComposer extends StatelessWidget {
  const _ChatComposer({
    required this.controller,
    required this.isBusy,
    required this.isListening,
    required this.allowSpeechInput,
    required this.onSend,
    required this.onListen,
  });

  final TextEditingController controller;
  final bool isBusy;
  final bool isListening;
  final bool allowSpeechInput;
  final VoidCallback onSend;
  final VoidCallback onListen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('chatInput'),
              controller: controller,
              enabled: !isBusy,
              minLines: 1,
              maxLines: 2,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: '和我说一句',
                isDense: true,
                filled: true,
                fillColor: const Color(0xFF111820),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: isListening ? '正在听' : '语音输入',
            child: IconButton.filledTonal(
              key: const ValueKey('listenVoice'),
              onPressed: isBusy || isListening || !allowSpeechInput
                  ? null
                  : onListen,
              icon: Icon(isListening ? Icons.graphic_eq : Icons.mic),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: '发送',
            child: IconButton.filled(
              key: const ValueKey('sendChat'),
              onPressed: isBusy ? null : onSend,
              icon: const Icon(Icons.send),
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.settings,
    required this.isBusy,
    required this.isListening,
    required this.isVisionMonitoring,
    required this.showVoiceDebugPanel,
    required this.voiceState,
    required this.controller,
    required this.onSettingsChanged,
    required this.onListen,
    required this.onLook,
    required this.onToggleVisionMonitoring,
    required this.onToggleVoiceDebugPanel,
    required this.onToggleVoiceConversation,
    required this.onToggleWakeListening,
    required this.onShowMemory,
    required this.onShowLogs,
    required this.onShowDeviceCheck,
    required this.onEvent,
  });

  final CompanionSettings settings;
  final bool isBusy;
  final bool isListening;
  final bool isVisionMonitoring;
  final bool showVoiceDebugPanel;
  final VoiceState voiceState;
  final FaceController controller;
  final ValueChanged<CompanionSettings> onSettingsChanged;
  final VoidCallback onListen;
  final VoidCallback onLook;
  final VoidCallback onToggleVisionMonitoring;
  final VoidCallback onToggleVoiceDebugPanel;
  final VoidCallback onToggleVoiceConversation;
  final VoidCallback onToggleWakeListening;
  final VoidCallback onShowMemory;
  final VoidCallback onShowLogs;
  final VoidCallback onShowDeviceCheck;
  final ValueChanged<String> onEvent;

  @override
  Widget build(BuildContext context) {
    final isMonitoring = voiceState == VoiceState.monitoring;
    final isConversation = voiceState == VoiceState.conversation;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('控制', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _PanelAction(
                  key: const ValueKey('toggleWakeListening'),
                  icon: isMonitoring ? Icons.radar : Icons.hearing,
                  label: isMonitoring ? '关闭唤醒' : '萌萌唤醒',
                  onPressed: isBusy || !settings.allowSpeechInput
                      ? null
                      : onToggleWakeListening,
                ),
                _PanelAction(
                  key: const ValueKey('toggleVoiceConversation'),
                  icon: isConversation
                      ? Icons.hearing
                      : Icons.record_voice_over,
                  label: isConversation ? '关闭对话' : '语音对话',
                  onPressed: isBusy || !settings.allowSpeechInput
                      ? null
                      : onToggleVoiceConversation,
                ),
                _PanelAction(
                  key: const ValueKey('panelListenVoice'),
                  icon: isListening ? Icons.graphic_eq : Icons.mic,
                  label: isListening ? '正在听' : '语音输入',
                  onPressed: isBusy || isListening || !settings.allowSpeechInput
                      ? null
                      : onListen,
                ),
                _PanelAction(
                  key: const ValueKey('panelLook'),
                  icon: Icons.visibility,
                  label: '看一下',
                  onPressed: isBusy || !settings.allowVision ? null : onLook,
                ),
                _PanelAction(
                  key: const ValueKey('toggleVisionMonitoring'),
                  icon: isVisionMonitoring
                      ? Icons.visibility_off
                      : Icons.center_focus_strong,
                  label: isVisionMonitoring ? '关闭守望' : '视觉守望',
                  onPressed: isBusy || !settings.allowVision
                      ? null
                      : onToggleVisionMonitoring,
                ),
                _PanelAction(
                  key: const ValueKey('toggleVoiceDebugPanel'),
                  icon: showVoiceDebugPanel
                      ? Icons.bug_report
                      : Icons.bug_report_outlined,
                  label: showVoiceDebugPanel ? '关闭语音调试' : '语音调试',
                  onPressed: onToggleVoiceDebugPanel,
                ),
              ],
            ),
            const SizedBox(height: 18),
            _SettingsDock(
              settings: settings,
              onChanged: onSettingsChanged,
              onShowMemory: onShowMemory,
              onShowLogs: onShowLogs,
              onShowDeviceCheck: onShowDeviceCheck,
            ),
            const Divider(height: 20),
            _DebugDock(
              controller: controller,
              isBusy: isBusy,
              onEvent: onEvent,
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelAction extends StatelessWidget {
  const _PanelAction({
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
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _SettingsDock extends StatelessWidget {
  const _SettingsDock({
    required this.settings,
    required this.onChanged,
    required this.onShowMemory,
    required this.onShowLogs,
    required this.onShowDeviceCheck,
  });

  final CompanionSettings settings;
  final ValueChanged<CompanionSettings> onChanged;
  final VoidCallback onShowMemory;
  final VoidCallback onShowLogs;
  final VoidCallback onShowDeviceCheck;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.zero,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          _SettingChip(
            key: const ValueKey('togglePrivacy'),
            icon: settings.privacyMode ? Icons.lock : Icons.lock_open,
            label: '隐私',
            selected: settings.privacyMode,
            onTap: () {
              onChanged(settings.copyWith(privacyMode: !settings.privacyMode));
            },
          ),
          _SettingChip(
            key: const ValueKey('toggleSpeechInput'),
            icon: Icons.mic,
            label: '听',
            selected: settings.allowSpeechInput,
            onTap: settings.privacyMode
                ? null
                : () {
                    onChanged(
                      settings.copyWith(
                        allowSpeechInput: !settings.allowSpeechInput,
                      ),
                    );
                  },
          ),
          _SettingChip(
            key: const ValueKey('toggleSpeechOutput'),
            icon: Icons.volume_up,
            label: '说',
            selected: settings.allowSpeechOutput,
            onTap: settings.privacyMode
                ? null
                : () {
                    onChanged(
                      settings.copyWith(
                        allowSpeechOutput: !settings.allowSpeechOutput,
                      ),
                    );
                  },
          ),
          _SettingChip(
            key: const ValueKey('toggleVision'),
            icon: Icons.visibility,
            label: '看',
            selected: settings.allowVision,
            onTap: settings.privacyMode
                ? null
                : () {
                    onChanged(
                      settings.copyWith(allowVision: !settings.allowVision),
                    );
                  },
          ),
          _SettingChip(
            key: const ValueKey('toggleMemory'),
            icon: Icons.memory,
            label: '记忆',
            selected: settings.allowMemory,
            onTap: settings.privacyMode
                ? null
                : () {
                    onChanged(
                      settings.copyWith(allowMemory: !settings.allowMemory),
                    );
                  },
          ),
          _SettingChip(
            key: const ValueKey('toggleKeepAwake'),
            icon: Icons.light_mode,
            label: '常亮',
            selected: settings.keepAwake,
            onTap: () {
              onChanged(settings.copyWith(keepAwake: !settings.keepAwake));
            },
          ),
          Tooltip(
            message: '查看记忆',
            child: IconButton.filledTonal(
              key: const ValueKey('openMemory'),
              onPressed: onShowMemory,
              icon: const Icon(Icons.list_alt),
            ),
          ),
          Tooltip(
            message: '查看日志',
            child: IconButton.filledTonal(
              key: const ValueKey('openLogs'),
              onPressed: onShowLogs,
              icon: const Icon(Icons.receipt_long),
            ),
          ),
          Tooltip(
            message: '设备自检',
            child: IconButton.filledTonal(
              key: const ValueKey('openDeviceCheck'),
              onPressed: onShowDeviceCheck,
              icon: const Icon(Icons.fact_check),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingChip extends StatelessWidget {
  const _SettingChip({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      showCheckmark: false,
      avatar: Icon(icon, size: 16),
      label: Text(label),
      selected: selected,
      onSelected: onTap == null ? null : (_) => onTap?.call(),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _DebugDock extends StatelessWidget {
  const _DebugDock({
    required this.controller,
    required this.isBusy,
    required this.onEvent,
  });

  final FaceController controller;
  final bool isBusy;
  final ValueChanged<String> onEvent;

  @override
  Widget build(BuildContext context) {
    final buttons = [
      _DebugAction(Icons.touch_app, '轻触', 'tap', controller.tap),
      _DebugAction(Icons.hearing, '倾听', 'wake', controller.doubleTap),
      _DebugAction(Icons.psychology, '思考', 'thinking', controller.longPress),
      _DebugAction(Icons.record_voice_over, '说话', 'speaking', controller.speak),
      _DebugAction(Icons.vibration, '摇晃', 'shake', controller.shake),
      _DebugAction(
        Icons.battery_charging_full,
        '充电',
        'charging',
        controller.charge,
      ),
      _DebugAction(
        Icons.battery_alert,
        '低电',
        'low_battery',
        controller.lowBattery,
      ),
      _DebugAction(Icons.bedtime, '休眠', 'flip_down', controller.flipDown),
      _DebugAction(Icons.refresh, '复位', 'reset', controller.reset),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF111820),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final action in buttons)
            Tooltip(
              message: action.label,
              child: IconButton.filledTonal(
                key: ValueKey(
                  action.eventType == 'shake'
                      ? 'debugShakeButton'
                      : 'debug_${action.label}',
                ),
                onPressed: isBusy
                    ? null
                    : () {
                        if (action.eventType == 'reset') {
                          action.localPreview();
                          return;
                        }
                        onEvent(action.eventType);
                      },
                icon: Icon(action.icon),
              ),
            ),
        ],
      ),
    );
  }
}

class _DebugAction {
  const _DebugAction(this.icon, this.label, this.eventType, this.localPreview);

  final IconData icon;
  final String label;
  final String eventType;
  final VoidCallback localPreview;
}

class _ImpactVoiceCue {
  const _ImpactVoiceCue({
    required this.level,
    required this.text,
    required this.speed,
    required this.pitch,
    required this.volume,
  });

  factory _ImpactVoiceCue.fromEvent(DeviceEvent event) {
    final level = event.intensityLevel ?? 'medium';
    return switch (level) {
      'light' => const _ImpactVoiceCue(
        level: 'light',
        text: '嗯？',
        speed: 0.75,
        pitch: 1.18,
        volume: 0.45,
      ),
      'strong' => const _ImpactVoiceCue(
        level: 'strong',
        text: '哇！',
        speed: 1.0,
        pitch: 0.92,
        volume: 0.9,
      ),
      'extreme' => const _ImpactVoiceCue(
        level: 'extreme',
        text: '啊！疼。',
        speed: 1.0,
        pitch: 0.82,
        volume: 1.0,
      ),
      _ => const _ImpactVoiceCue(
        level: 'medium',
        text: '哎呀。',
        speed: 0.9,
        pitch: 1.0,
        volume: 0.7,
      ),
    };
  }

  final String level;
  final String text;
  final double speed;
  final double pitch;
  final double volume;
}

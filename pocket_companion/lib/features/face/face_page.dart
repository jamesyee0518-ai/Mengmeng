import '../chat/conversation_context.dart';
import '../chat/conversation_coordinator.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../core/logging/debug_log_store.dart';
import '../../core/logging/debug_log_entry.dart';
import '../../core/network/ai_gateway_client.dart';
import '../../core/network/gateway_health.dart';
import '../../core/network/gateway_health_service.dart';
import '../chat/robot_response.dart';
import '../device/device_check_panel.dart';
import '../device/device_event.dart';
import '../device/device_event_service.dart';
import '../gimbal/follow_controller.dart';
import '../gimbal/gimbal_models.dart';
import '../gimbal/gimbal_service.dart';
import '../logs/debug_log_panel.dart';
import '../memory/memory_panel.dart';
import '../settings/companion_settings.dart';
import '../vision/face_observation.dart';
import '../vision/face_stream_service.dart';
import '../vision/presence_tracker.dart';
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
import '../voice/wake_detector_type.dart';
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
    this.gimbal,
    this.faceStream,
    this.logs,
    this.deviceEvents,
    this.gatewayHealthService,
    this.voiceSettingsStore,
    this.autoStartWake = true,
  });

  final AiGatewayClient? gateway;
  final TtsService? tts;
  final SpeechService? speech;
  final VisionService? vision;
  final GimbalService? gimbal;
  final FaceStreamService? faceStream;
  final DebugLogStore? logs;
  final DeviceEventService? deviceEvents;
  final GatewayHealthService? gatewayHealthService;
  final VoiceSettingsStore? voiceSettingsStore;
  final bool autoStartWake;

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
  late final GimbalService _gimbal;
  late final FaceStreamService _faceStream;
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
  StreamSubscription<FaceObservation>? _faceStreamSubscription;
  StreamSubscription<GimbalDeviceState>? _gimbalStateSubscription;
  StreamSubscription<String>? _gimbalErrorSubscription;
  Timer? _gatewayHealthTimer;
  Timer? _overlayHideTimer;
  bool _overlayVisible = false;
  bool _overlayVisibleAtTouch = false;
  final ValueNotifier<int> _controlPanelUpdates = ValueNotifier(0);
  bool _isControlPanelOpen = false;
  bool _isGatewayOnline = false;
  GatewayHealth? _gatewayHealth;
  final ConversationCoordinator _conversation = ConversationCoordinator();
  bool get _isBusy => _conversation.isBusy;
  bool _isSpeaking = false;
  bool _isListening = false;
  bool _isVisionMonitoring = false;
  bool _showVoiceDebugPanel = false;
  bool _isFollowActive = false;
  bool _isFollowStarting = false;
  int _followSession = 0;
  bool? _faceDetected;
  bool _isGimbalControllable = false;
  String _gimbalModel = '';
  GimbalPhase _gimbalPhase = GimbalPhase.idle;
  FollowCommand _lastFollowCommand = const FollowCommand(
    phase: FollowPhase.idle,
    yawDps: 0,
    pitchDps: 0,
  );
  DateTime? _lastVelocitySentAt;
  final PresenceTracker _presenceTracker = PresenceTracker();
  final FollowController _followController = FollowController();
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
  final _notices = ValueNotifier<List<String>>([]);
  bool _hasUnreadNotice = false;
  bool _noticePanelOpen = false;
  int _lastNoticeLogId = 0;
  bool _wakeDesired = true;
  bool _voiceSettingsReady = false;
  bool _startingDefaultWake = false;
  Future<void>? _lifecyclePause;
  String _currentPersona = 'mengmeng';
  CompanionSettings _settings = CompanionSettings.initial();
  int _speechToken = 0;
  int _visionLoopToken = 0;
  bool? _lastVisualPresence;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _conversation.addListener(_onConversationChanged);
    _controller = FaceController();
    _gateway = widget.gateway ?? AiGatewayClient();
    _tts = widget.tts ?? TtsService(networkBaseUrl: _gateway.baseUrl);
    _speech = widget.speech ?? SpeechService(baseUrl: _gateway.baseUrl);
    _vision = widget.vision ?? VisionService();
    _gimbal = widget.gimbal ?? GimbalService();
    _faceStream = widget.faceStream ?? FaceStreamService();
    _gimbalStateSubscription = _gimbal.deviceStates.listen((state) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isGimbalControllable = state.isControllable;
        _gimbalModel = state.model;
        _gimbalPhase = state.phase;
      });
    });
    _gimbalErrorSubscription = _gimbal.errors.listen((message) {
      _logs.warning('gimbal', message);
      if (!mounted) {
        return;
      }
      _addNotice(message);
    });
    _gatewayHealthService =
        widget.gatewayHealthService ??
        GatewayHealthService(baseUrl: _gateway.debugBaseUrl);
    _logs = widget.logs ?? DebugLogStore();
    _logs.addListener(_captureLogNotices);
    _deviceEvents = widget.deviceEvents ?? DeviceEventService();
    _deviceEventSubscription = _deviceEvents.events.listen(_handleDeviceEvent);
    _voiceWakeController = VoiceWakeController(
      speech: _speech,
      config: VoiceWakeConfig(
        wakeDetectorType: defaultTargetPlatform == TargetPlatform.android
            ? WakeDetectorType.sherpaOnnx
            : WakeDetectorType.stt,
      ),
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
        if (snapshot.runtimeWarning.isNotEmpty) {
          _addNotice('语音提示：${snapshot.runtimeWarning}');
        }
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

  Future<void> _startDefaultWake() async {
    if (!mounted ||
        !widget.autoStartWake ||
        !_wakeDesired ||
        !_voiceSettingsReady ||
        _startingDefaultWake ||
        !_settings.allowSpeechInput ||
        _settings.privacyMode ||
        _voiceWakeController.mode != VoiceMode.off ||
        (WidgetsBinding.instance.lifecycleState != null &&
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed)) {
      return;
    }
    _startingDefaultWake = true;
    try {
      await _lifecyclePause;
      if (!mounted ||
          !_wakeDesired ||
          _settings.privacyMode ||
          !_settings.allowSpeechInput ||
          (WidgetsBinding.instance.lifecycleState != null &&
              WidgetsBinding.instance.lifecycleState !=
                  AppLifecycleState.resumed)) {
        return;
      }
      await _voiceWakeController.start();
      if (mounted && _voiceWakeController.mode == VoiceMode.wake) {
        _addNotice('萌萌唤醒已开启，可以直接叫“萌萌”。');
      }
    } catch (error) {
      _logs.warning('speech', '唤醒启动失败：$error');
    } finally {
      _startingDefaultWake = false;
    }
  }

  void _captureLogNotices() {
    for (final entry in _logs.entries.reversed) {
      if (entry.id <= _lastNoticeLogId) continue;
      _lastNoticeLogId = entry.id;
      if (entry.level != DebugLogLevel.info) _addNotice(entry.message);
    }
  }

  void _addNotice(String message) {
    if (!mounted ||
        message.trim().isEmpty ||
        _notices.value.contains(message)) {
      return;
    }
    _notices.value = [message, ..._notices.value].take(50).toList();
    setState(() => _hasUnreadNotice = !_noticePanelOpen);
  }

  Future<void> _openVoiceDiagnostics() async {
    if (_showVoiceDebugPanel) return;
    setState(() => _showVoiceDebugPanel = true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.8,
            child: SingleChildScrollView(
              key: const ValueKey('voiceDiagnosticsScroll'),
              child: ListenableBuilder(
                listenable: _controlPanelUpdates,
                builder: (context, _) => VoiceDebugPanel(
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
                      () => _voiceWakeController.updateAudioGateConfig(config),
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
                  onApplyTuningRecommendation: _applyVoiceTuningRecommendation,
                  onRefreshGatewayHealth: _refreshGatewayStatus,
                  onSaveSample: _saveVoiceDebugSample,
                  recentSamples: _recentVoiceDebugSamples,
                  sampleSummary: _voiceDebugSampleSummary,
                  sampleExportPath: _voiceDebugSamplePath,
                  onClearSamples: () => unawaited(_clearVoiceDebugSamples()),
                ),
              ),
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _showVoiceDebugPanel = false);
    }
  }

  Future<void> _showNotices() async {
    setState(() {
      _hasUnreadNotice = false;
      _noticePanelOpen = true;
    });
    try {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.65,
            child: ValueListenableBuilder<List<String>>(
              valueListenable: _notices,
              builder: (context, notices, _) => ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text('提示', style: Theme.of(context).textTheme.titleLarge),
                  TextButton(
                    onPressed: _openVoiceDiagnostics,
                    child: const Text('语音诊断'),
                  ),
                  ListTile(
                    title: const Text('当前状态'),
                    subtitle: Text(_activityLabelFor(_controller.state)),
                  ),
                  if (notices.isEmpty) const ListTile(title: Text('暂无提示')),
                  for (final notice in notices) ListTile(title: Text(notice)),
                ],
              ),
            ),
          ),
        ),
      );
    } finally {
      _noticePanelOpen = false;
    }
  }

  void _onConversationChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _conversation.removeListener(_onConversationChanged);
    _conversation.dispose();
    _logs.removeListener(_captureLogNotices);
    _notices.dispose();
    _gatewayHealthTimer?.cancel();
    _overlayHideTimer?.cancel();
    _controlPanelUpdates.dispose();
    _visionLoopToken++;
    _voiceWakeController.dispose();
    _animation.dispose();
    _speech.stop();
    _vision.stop();
    unawaited(_faceStreamSubscription?.cancel());
    _faceStreamSubscription = null;
    unawaited(_faceStream.dispose());
    unawaited(_gimbalStateSubscription?.cancel());
    unawaited(_gimbalErrorSubscription?.cancel());
    if (widget.gimbal == null) {
      unawaited(_gimbal.stop());
      unawaited(_gimbal.dispose());
    }
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
        unawaited(_startDefaultWake());
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _logs.info('lifecycle', state.name);
        _lifecyclePause = _pauseForAppLifecycle(state);
        unawaited(_lifecyclePause);
    }
  }

  Future<void> _pauseForAppLifecycle(AppLifecycleState state) async {
    _conversation.cancel(clearHistory: true);
    _speechToken++;
    _visionLoopToken++;
    await _voiceWakeController.pauseForLifecycle(state.name);
    await _stopFollow();
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
    if (!health.ok) _addNotice('语音服务状态异常：${health.reason}');
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
          ? (health.gateway.reason.isEmpty
                ? 'gateway_unavailable'
                : health.gateway.reason)
          : (health.stt.reason.isEmpty ? 'stt_unavailable' : health.stt.reason);
      final message = switch (reason) {
        'gateway_timeout' => '语音连接检查超时，请稍后重试',
        'health_check_failed' || 'gateway_unavailable' => '暂时无法连接语音网关，请检查网络',
        _ => '语音识别服务暂不可用：$reason',
      };
      _addNotice(message);
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
        // 语音调试面板不跨启动恢复，每次启动默认收起，需要时从控制面板打开
        _showVoiceDebugPanel = false;
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
    } finally {
      _voiceSettingsReady = true;
      await _startDefaultWake();
    }
  }

  Future<void> _persistVoiceSettings() async {
    final saved = await _voiceSettingsStore.save(
      VoiceSettingsData(
        activeProfile: _voiceWakeController.activeProfile,
        wakeConfig: _voiceWakeController.config,
        audioGateConfig: _voiceWakeController.audioGateConfig,
        bargeInConfig: _voiceWakeController.bargeInConfig,
        showVoiceDebugPanel: false,
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
    await _applyGatewayCall(
      (context, isCurrent) => _gateway.chat(
        text,
        settings: _settings,
        persona: context.persona,
        context: context,
      ),
      userText: text,
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
      if (_isBusy ||
          _isListening ||
          _isSpeaking ||
          _voiceWakeController.mode == VoiceMode.conversation) {
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
    // 本地人脸流在跑时直接复用其结果，避免抢占相机与云端调用。
    if (_faceStream.isRunning) {
      return _faceStream.latest?.detected;
    }
    bool? hasPerson;
    final outcome = await _conversation.run(
      persona: _currentPersona,
      automatic: true,
      useContext: false,
      request: (context, isCurrent) async {
        final result = await _vision.checkOnce();
        if (!isCurrent() || !_isVisionMonitoring || _settings.privacyMode) {
          throw StateError('presence scan cancelled');
        }
        if (!result.ok ||
            result.imageBytes == null ||
            result.imageBytes!.isEmpty) {
          throw StateError('presence capture failed: ${result.label}');
        }
        return _gateway.vision(
          result.imageBytes!,
          prompt: '只回答“有人”或“无人”：图片里是否有人、人脸或明显的人体？',
          settings: _settings,
          persona: context.persona,
        );
      },
      deliver: (response, isCurrent) async {
        if (!_isVisionMonitoring ||
            response.isFallback ||
            response.modelError.isNotEmpty) {
          return;
        }
        final text = response.text.trim();
        if (text.contains('无人') ||
            text.contains('没有人') ||
            text.contains('沒有人')) {
          hasPerson = false;
        } else if (text.contains('有人') ||
            text.contains('人脸') ||
            text.contains('人臉')) {
          hasPerson = true;
        }
      },
    );
    if (outcome == TurnResult.failed) {
      _logs.warning('vision', 'presence failed: ${_conversation.lastError}');
    }
    return outcome == TurnResult.completed ? hasPerson : null;
  }

  Future<void> _handleVisualPresenceChanged(bool hasPerson) async {
    if (_isBusy ||
        _isListening ||
        _isSpeaking ||
        _voiceWakeController.mode == VoiceMode.conversation) {
      return;
    }
    final eventType = hasPerson ? 'person_seen' : 'person_left';
    _logs.info('vision', 'presence changed: $eventType');
    if (hasPerson) {
      _controller.doubleTap();
    } else {
      _controller.longPress();
    }
    await _applyGatewayCall(
      (context, isCurrent) => _gateway.event(
        eventType,
        settings: _settings,
        persona: _currentPersona,
        source: 'vision_monitor',
      ),
      speakResponse: false,
      automatic: true,
    );
  }

  /// 触摸唤出底部输入区，8 秒无操作自动隐藏（沉浸式模式）。
  void _revealOverlay() {
    _overlayHideTimer?.cancel();
    if (!mounted) {
      return;
    }
    if (!_overlayVisible) {
      setState(() => _overlayVisible = true);
    }
    _overlayHideTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) {
        setState(() => _overlayVisible = false);
      }
    });
  }

  // ---------------------------------------------------------------- 云台跟随

  /// 开关“云台跟随”：本地人脸流驱动（a）人物唤醒（在场事件）与
  /// （b）云台速度闭环。无云台时自动退化为纯本地人物唤醒。
  void _showFollowHint(String message) {
    if (!mounted) {
      return;
    }
    _addNotice(message);
  }

  Future<void> _toggleFollow() async {
    if (_isFollowStarting) return;
    _isFollowStarting = true;
    try {
      await _changeFollow();
    } finally {
      _isFollowStarting = false;
    }
  }

  Future<void> _changeFollow() async {
    final session = ++_followSession;
    debugPrint(
      '[follow] toggle: active=$_isFollowActive allowVision=${_settings.allowVision} privacy=${_settings.privacyMode}',
    );
    if (_isFollowActive) {
      await _stopFollow();
      return;
    }
    if (_settings.privacyMode) {
      _logs.warning('vision', 'follow ignored: privacy mode');
      _showFollowHint('隐私模式已开启，无法使用云台跟随');
      return;
    }
    if (!_settings.allowVision) {
      // 自动开启视觉能力：隐私未开时不应让按钮静默失效。
      _updateSettings(_settings.copyWith(allowVision: true));
      _showFollowHint('已自动开启"看"，正在启动云台跟随');
    }
    if (_gimbal.isSupported && !_isGimbalControllable) {
      await _connectGimbal();
    }
    if (!mounted || session != _followSession) return;
    final streamError = await _faceStream.start();
    if (!mounted || session != _followSession) return;
    if (streamError != null) {
      debugPrint('[follow] face stream failed: $streamError');
      _logs.warning('vision', 'face stream start failed: $streamError');
      _showFollowHint('跟随启动失败：$streamError');
      return;
    }
    debugPrint(
      '[follow] active: gimbalControllable=$_isGimbalControllable model=$_gimbalModel',
    );
    _followController.reset();
    _lastFollowCommand = const FollowCommand(
      phase: FollowPhase.idle,
      yawDps: 0,
      pitchDps: 0,
    );
    _lastVelocitySentAt = null;
    _faceStreamSubscription = _faceStream.observations.listen(
      _handleFaceObservation,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _isFollowActive = true;
      _faceDetected = null;
    });
    _noFaceSince = DateTime.now();
    _followNoFaceHintShown = false;
    debugPrint(
      '[follow] started gimbal=${_isGimbalControllable ? _gimbalModel : "无(仅本地唤醒)"}',
    );
    _logs.info(
      'follow',
      'start gimbal=${_isGimbalControllable ? _gimbalModel : "无(仅本地唤醒)"}',
    );
  }

  Future<void> _connectGimbal() async {
    try {
      var state = await _gimbal.register();
      if (!state.isControllable) {
        state = await _gimbal.connectBluetooth();
      }
      if (mounted) {
        setState(() => _isGimbalControllable = state.isControllable);
      }
      debugPrint(
        '[gimbal] phase=${state.phase.name} model=${state.model.isEmpty ? "未知" : state.model} controllable=${state.isControllable}',
      );
      _logs.info(
        'gimbal',
        'phase=${state.phase.name} model=${state.model.isEmpty ? "未知" : state.model}',
      );
    } catch (error) {
      debugPrint('[gimbal] connect failed: $error');
      _logs.warning('gimbal', 'connect failed: $error');
    }
  }

  Future<void> _stopFollow() async {
    _followSession++;
    if (mounted) {
      setState(() {
        _isFollowActive = false;
        _faceDetected = null;
      });
    }
    await _faceStreamSubscription?.cancel();
    _faceStreamSubscription = null;
    await _faceStream.release();
    _followController.reset();
    _presenceTracker.reset();
    if (_isGimbalControllable) {
      try {
        await _gimbal.stop();
      } catch (_) {}
    }
    if (!mounted) {
      return;
    }
    setState(() => _isFollowActive = false);
    _logs.info('follow', 'stop');
  }

  DateTime? _lastFollowDiagAt;
  bool _followNoFaceHintShown = false;
  DateTime? _noFaceSince;

  void _handleFaceObservation(FaceObservation observation) {
    if (!mounted || !_isFollowActive) return;
    if (_faceDetected != observation.detected) {
      setState(() => _faceDetected = observation.detected);
    }
    final diagNow = DateTime.now();
    if (_lastFollowDiagAt == null ||
        diagNow.difference(_lastFollowDiagAt!).inSeconds >= 3) {
      _lastFollowDiagAt = diagNow;
      debugPrint(
        '[follow] face detected=${observation.detected} '
        'offsetX=${observation.offsetX.toStringAsFixed(3)} '
        'offsetY=${observation.offsetY.toStringAsFixed(3)}',
      );
      _logs.info(
        'follow',
        'face detected=${observation.detected} '
            'offsetX=${observation.offsetX.toStringAsFixed(3)} '
            'offsetY=${observation.offsetY.toStringAsFixed(3)}',
      );
    }
    if (observation.detected) {
      _noFaceSince = null;
      _followNoFaceHintShown = false;
    } else {
      _noFaceSince ??= DateTime.now();
    }
    if (!observation.detected &&
        _isFollowActive &&
        !_followNoFaceHintShown &&
        _noFaceSince != null &&
        DateTime.now().difference(_noFaceSince!).inSeconds >= 8) {
      _followNoFaceHintShown = true;
      _showFollowHint('未检测到人脸：请正对手机前置摄像头（光线充足）');
    }
    final presenceEvent = _presenceTracker.update(observation);
    if (presenceEvent != null) {
      unawaited(_handleVisionPresenceEvent(presenceEvent));
    }
    final command = _followController.update(
      faceDetected: observation.detected,
      offsetX: observation.offsetX,
      offsetY: observation.offsetY,
      now: observation.timestamp,
    );
    _applyFollowCommand(command);
  }

  Future<void> _handleVisionPresenceEvent(VisionPresenceEvent event) async {
    final hasPerson = event.type != VisionPresenceEventType.userAbsent;
    _logs.info(
      'vision',
      'local presence ${event.type.name} after=${event.absentDuration.inSeconds}s',
    );
    await _handleVisualPresenceChanged(hasPerson);
  }

  void _applyFollowCommand(FollowCommand command) {
    if (!_isGimbalControllable) {
      return;
    }
    final now = DateTime.now();
    final unchanged =
        command.yawDps == _lastFollowCommand.yawDps &&
        command.pitchDps == _lastFollowCommand.pitchDps;
    final stale =
        _lastVelocitySentAt == null ||
        now.difference(_lastVelocitySentAt!) >
            const Duration(milliseconds: 800);
    // SPEED 控制需要持续刷新；移动时按人脸帧率（约 160ms）发送。
    // 仅对重复的零速停止指令去重。
    if (command.isNeutral && unchanged && !stale) {
      return;
    }
    _lastFollowCommand = command;
    _lastVelocitySentAt = now;
    _logs.info(
      'follow',
      'cmd ${command.phase.name} yaw=${command.yawDps.toStringAsFixed(1)} pitch=${command.pitchDps.toStringAsFixed(1)}',
    );
    if (command.isNeutral) {
      unawaited(_gimbal.stop().catchError((_) {}));
    } else {
      unawaited(
        _gimbal
            .setVelocity(yawDps: command.yawDps, pitchDps: command.pitchDps)
            .catchError((_) {}),
      );
    }
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

  Future<void> _stopConversation() async {
    _wakeDesired = false;
    _conversation.cancel(clearHistory: true);
    await _voiceWakeController.stop();
    await _stopSpeaking();
  }

  /// 开启/关闭唤醒监听（齿轮页面控制）
  Future<void> _toggleWakeListening() async {
    if (_voiceWakeController.mode == VoiceMode.wake) {
      await _stopConversation();
      return;
    }
    _wakeDesired = true;
    // Local keyword spotting must not depend on a remote health request.
    try {
      _conversation.newSession(persona: _currentPersona);
      await _voiceWakeController.start();
      if (_voiceWakeController.mode == VoiceMode.wake) _addNotice('萌萌唤醒已开启');
    } catch (error) {
      _logs.warning('speech', '唤醒启动失败：$error');
    }
  }

  /// 手动触发一次语音对话（麦克风按钮）
  Future<void> _toggleVoiceConversation() async {
    _wakeDesired = false;
    if (_voiceWakeController.mode == VoiceMode.conversation) {
      await _stopConversation();
      return;
    }
    if (!await _ensureVoiceGatewayReady()) {
      return;
    }
    _conversation.newSession(persona: _currentPersona);
    await _voiceWakeController.startConversation();
  }

  Future<void> _listenAndSendOnce() async {
    _wakeDesired = false;
    await _voiceWakeController.stop();
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
    _conversation.newSession(persona: event.persona);
    _currentPersona = event.persona;
    _logs.info(
      'speech',
      'persona ${event.persona} wake=${event.wakeWord} score=${event.score.toStringAsFixed(2)}',
    );
    _controller.setRole(_faceRoleForPersona(event.persona));
    _controller.doubleTap();
    if (event.command.isEmpty) {
      await _applyGatewayCall(
        (context, isCurrent) => _gateway.event(
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
    await _applyGatewayCall((context, isCurrent) async {
      final wasStreamRunning = _faceStream.isRunning;
      if (wasStreamRunning) await _faceStream.release();
      try {
        if (!isCurrent()) throw StateError('turn cancelled');
        final result = await _vision.checkOnce();
        if (!isCurrent()) throw StateError('turn cancelled');
        if (!result.ok ||
            result.imageBytes == null ||
            result.imageBytes!.isEmpty) {
          if (source == 'voice') {
            return _gateway.chat(
              text,
              settings: _settings,
              persona: context.persona,
              context: context,
            );
          }
          throw StateError('拍照失败：${result.label}');
        }
        return await _gateway.chatWithVision(
          text,
          result.imageBytes!,
          settings: _settings,
          persona: context.persona,
          context: context,
        );
      } finally {
        if (mounted &&
            wasStreamRunning &&
            _isFollowActive &&
            !_settings.privacyMode) {
          final error = await _faceStream.start();
          if (error != null) {
            _logs.warning('vision', 'face stream restart failed: $error');
          }
        }
      }
    }, userText: text);
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
    if (_isBusy ||
        _isListening ||
        _isSpeaking ||
        _voiceWakeController.mode == VoiceMode.conversation) {
      return;
    }
    _previewDeviceEvent(event.type);
    _logs.info('event', event.label);
    final shouldSpeakEvent =
        event.source != 'hardware' || event.type == 'shake';
    await _applyGatewayCall(
      (context, isCurrent) => _gateway.event(
        event.type,
        settings: _settings,
        deviceEvent: event,
        persona: _currentPersona,
      ),
      speakResponse: shouldSpeakEvent,
      automatic: true,
      playCue: () => _playImpactCue(event),
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
    Future<RobotResponse> Function(
      ConversationContext context,
      bool Function() isCurrent,
    )
    call, {
    bool speakResponse = true,
    bool automatic = false,
    String? userText,
    Future<bool> Function()? playCue,
  }) async {
    if (!mounted) return;
    final outcome = await _conversation.run(
      persona: _currentPersona,
      automatic: automatic,
      useContext: !_settings.privacyMode,
      userText: userText,
      request: (context, isCurrent) async {
        _controller.thinking(label: '正在想');
        return call(context, isCurrent);
      },
      deliver: (response, isCurrent) async {
        if (!mounted) return;
        _controller.applyRobotResponse(response);
        if (response.isFallback) {
          _logs.warning('fallback', response.fallbackReason);
          if (response.fallbackReason == 'gateway_timeout' ||
              response.fallbackReason == 'gateway_unreachable') {
            _voiceDebugSnapshot = _voiceDebugSnapshot.copyWith(
              runtimeWarning: response.fallbackReason,
            );
            _addNotice('Gateway 调用失败：${response.fallbackReason}');
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
          _isGatewayOnline = ![
            'gateway_timeout',
            'gateway_unreachable',
          ].contains(response.fallbackReason);
        });
        final playedCue = await (playCue?.call() ?? Future.value(false));
        if (isCurrent() && mounted && speakResponse && !playedCue) {
          await _speakResponse(response);
        }
      },
    );
    if (!mounted) return;
    if (outcome == TurnResult.busy) _showFollowHint('正在处理上一条，请稍候');
    if (outcome == TurnResult.failed) {
      _logs.warning('conversation', 'failed: ${_conversation.lastError}');
      _showFollowHint('本次对话未完成，请重试');
    }
  }

  Future<bool> _playImpactCue(DeviceEvent event) async {
    if (event.type != 'shake' || !_settings.allowSpeechOutput) {
      return false;
    }
    final cue = _ImpactVoiceCue.fromEvent(event);
    final token = ++_speechToken;
    _voiceWakeController.notifyTtsStarted();
    await _pauseListeningForSpeech();
    if (!mounted || token != _speechToken) return true;
    _controller.beginSpeaking();
    _logs.info('tts', 'impact ${cue.level}');
    setState(() => _isSpeaking = true);
    try {
      await _tts.speak(
        cue.text,
        persona: _currentPersona,
        style: 'impact',
        speed: cue.speed,
        pitch: cue.pitch,
        volume: cue.volume,
      );
    } finally {
      if (mounted && token == _speechToken) {
        _controller.endSpeaking();
        _voiceWakeController.notifyTtsEnded();
        setState(() => _isSpeaking = false);
      }
    }
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
    _voiceWakeController.notifyTtsStarted();
    await _pauseListeningForSpeech();
    if (!mounted || token != _speechToken) return;
    _controller.beginSpeaking();
    _logs.info('tts', 'start');
    setState(() => _isSpeaking = true);
    try {
      await _tts.speak(
        response.text,
        persona: _currentPersona,
        style: response.voice.style,
        speed: response.voice.speed,
        pitch: response.voice.pitch,
        volume: response.voice.volume,
      );
    } finally {
      if (mounted && token == _speechToken) {
        _controller.endSpeaking();
        _logs.info('tts', 'end');
        _voiceWakeController.notifyTtsEnded();
        setState(() => _isSpeaking = false);
      }
    }
  }

  Future<void> _pauseListeningForSpeech() async {
    try {
      await _voiceWakeController.pauseInput();
    } catch (_) {}
    if (!mounted || !_isListening) {
      return;
    }
    setState(() => _isListening = false);
  }

  void _updateSettings(CompanionSettings settings) {
    if (settings.privacyMode && !_settings.privacyMode) {
      _conversation.newSession();
    }
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
    _isControlPanelOpen = true;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => ListenableBuilder(
          listenable: _controlPanelUpdates,
          builder: (context, _) => _ControlPanel(
            settings: _settings,
            isBusy: _isBusy,
            isListening: _isListening,
            isVisionMonitoring: _isVisionMonitoring,
            isFollowActive: _isFollowActive,
            isGimbalControllable: _isGimbalControllable,
            gimbalModel: _gimbalModel,
            showVoiceDebugPanel: _showVoiceDebugPanel,
            voiceState: _voiceState,
            voiceMode: _voiceWakeController.mode,
            controller: _controller,
            onSettingsChanged: _updateSettings,
            onListen: _listenAndChat,
            onLook: () => _lookAndAsk(),
            onToggleVisionMonitoring: _toggleVisionMonitoring,
            onToggleFollow: () => unawaited(_toggleFollow()),
            onToggleVoiceDebugPanel: _openVoiceDiagnostics,
            onToggleVoiceConversation: _toggleVoiceConversation,
            onToggleWakeListening: _toggleWakeListening,
            onShowMemory: _showMemoryPanel,
            onShowLogs: _showLogPanel,
            onShowDeviceCheck: _showDeviceCheckPanel,
            onEvent: _deviceEvents.emitSimulated,
          ),
        ),
      );
    } finally {
      _isControlPanelOpen = false;
    }
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
    _addNotice('已记录语音样本：${label.name}');
  }

  Future<void> _clearVoiceDebugSamples() async {
    await _voiceDebugSampleStore.clear();
    await _refreshVoiceDebugSamples();
    _logs.info('speech', 'voice debug samples cleared');
    if (!mounted) {
      return;
    }
    _addNotice('已清空语音样本');
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
    _addNotice('已应用推荐语音参数');
  }

  @override
  Widget build(BuildContext context) {
    // The modal is a separate route; rebuild it when page state changes.
    if (_isControlPanelOpen || _showVoiceDebugPanel) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && (_isControlPanelOpen || _showVoiceDebugPanel)) {
          _controlPanelUpdates.value++;
        }
      });
    }
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final state = _controller.state;
        return Scaffold(
          body: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    Visibility(
                      visible: _overlayVisible,
                      maintainState: true,
                      maintainAnimation: true,
                      child: _StatusBar(
                        state: state,
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
                    ),
                    Expanded(
                      child: Listener(
                        onPointerDown: (_) {
                          _overlayVisibleAtTouch = _overlayVisible;
                          _revealOverlay();
                        },
                        child: GestureDetector(
                          key: const ValueKey('robotFaceArea'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (_isSpeaking) {
                              unawaited(_stopSpeaking());
                              return;
                            }
                            if (!_overlayVisibleAtTouch) return;
                            _deviceEvents.emitSimulated('tap');
                          },
                          onDoubleTap: () =>
                              _deviceEvents.emitSimulated('wake'),
                          onLongPress: () =>
                              _deviceEvents.emitSimulated('thinking'),
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
                    ),
                    Visibility(
                      visible: _overlayVisible,
                      maintainState: true,
                      maintainAnimation: true,
                      child: _ChatComposer(
                        controller: _chatTextController,
                        isBusy: _isBusy,
                        isListening: _isListening,
                        allowSpeechInput: _settings.allowSpeechInput,
                        onSend: _sendChat,
                        onListen: _listenAndChat,
                      ),
                    ),
                  ],
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Semantics(
                    label: _hasUnreadNotice ? '有新提示' : '查看提示',
                    button: true,
                    child: IconButton(
                      key: const ValueKey('noticeButton'),
                      onPressed: _showNotices,
                      icon: Container(
                        key: ValueKey(
                          _hasUnreadNotice
                              ? 'unreadNoticeDot'
                              : 'readNoticeDot',
                        ),
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _hasUnreadNotice
                              ? Colors.redAccent
                              : Colors.white38,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _activityLabelFor(ExpressionState state) {
    if (_isFollowActive) {
      if (_faceDetected == null) return '正在启动人脸检测…';
      if (_faceDetected == false) return '等待人脸，请正对前置镜头';
      if (_isGimbalControllable) {
        return '云台跟随中';
      }
      final connecting = switch (_gimbalPhase) {
        GimbalPhase.registering ||
        GimbalPhase.registered ||
        GimbalPhase.connecting => true,
        _ => false,
      };
      if (connecting) {
        return '正在连接云台…';
      }
      if (_gimbalPhase == GimbalPhase.error) {
        return '云台连接失败，仅人物唤醒';
      }
      return '已识别人脸（未连接云台）';
    }
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
      padding: const EdgeInsets.fromLTRB(16, 10, 64, 0),
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
          const Spacer(),
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
    required this.isFollowActive,
    required this.isGimbalControllable,
    required this.gimbalModel,
    required this.showVoiceDebugPanel,
    required this.voiceState,
    required this.voiceMode,
    required this.controller,
    required this.onSettingsChanged,
    required this.onListen,
    required this.onLook,
    required this.onToggleVisionMonitoring,
    required this.onToggleVoiceDebugPanel,
    required this.onToggleVoiceConversation,
    required this.onToggleWakeListening,
    required this.onToggleFollow,
    required this.onShowMemory,
    required this.onShowLogs,
    required this.onShowDeviceCheck,
    required this.onEvent,
  });

  final CompanionSettings settings;
  final bool isBusy;
  final bool isListening;
  final bool isVisionMonitoring;
  final bool isFollowActive;
  final bool isGimbalControllable;
  final String gimbalModel;
  final bool showVoiceDebugPanel;
  final VoiceState voiceState;
  final VoiceMode voiceMode;
  final FaceController controller;
  final ValueChanged<CompanionSettings> onSettingsChanged;
  final VoidCallback onListen;
  final VoidCallback onLook;
  final VoidCallback onToggleVisionMonitoring;
  final VoidCallback onToggleFollow;
  final VoidCallback onToggleVoiceDebugPanel;
  final VoidCallback onToggleVoiceConversation;
  final VoidCallback onToggleWakeListening;
  final VoidCallback onShowMemory;
  final VoidCallback onShowLogs;
  final VoidCallback onShowDeviceCheck;
  final ValueChanged<String> onEvent;

  @override
  Widget build(BuildContext context) {
    final isMonitoring = voiceMode == VoiceMode.wake;
    final isConversation = voiceMode == VoiceMode.conversation;
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
                  key: const ValueKey('toggleGimbalFollow'),
                  icon: isFollowActive
                      ? Icons.follow_the_signs
                      : Icons.control_camera,
                  label: isFollowActive ? '停止跟随' : '云台跟随',
                  onPressed: onToggleFollow,
                  emphasized: true,
                ),
                _PanelAction(
                  key: const ValueKey('toggleWakeListening'),
                  icon: isMonitoring ? Icons.radar : Icons.hearing,
                  label: isMonitoring ? '关闭唤醒' : '萌萌唤醒',
                  onPressed: isMonitoring
                      ? onToggleWakeListening
                      : isBusy || !settings.allowSpeechInput
                      ? null
                      : onToggleWakeListening,
                ),
                _PanelAction(
                  key: const ValueKey('toggleVoiceConversation'),
                  icon: isConversation
                      ? Icons.hearing
                      : Icons.record_voice_over,
                  label: isConversation ? '关闭对话' : '语音对话',
                  onPressed: isConversation
                      ? onToggleVoiceConversation
                      : isBusy || !settings.allowSpeechInput
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
            if (isFollowActive &&
                isGimbalControllable &&
                gimbalModel.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '云台已连接：$gimbalModel',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
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
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    if (emphasized) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
    }
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

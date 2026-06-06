import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/logging/debug_log_store.dart';
import '../../core/network/ai_gateway_client.dart';
import '../chat/robot_response.dart';
import '../device/device_check_panel.dart';
import '../device/device_event.dart';
import '../device/device_event_service.dart';
import '../logs/debug_log_panel.dart';
import '../memory/memory_panel.dart';
import '../settings/companion_settings.dart';
import '../vision/vision_service.dart';
import '../voice/speech_service.dart';
import '../voice/tts_service.dart';
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
  });

  final AiGatewayClient? gateway;
  final TtsService? tts;
  final SpeechService? speech;
  final VisionService? vision;
  final DebugLogStore? logs;
  final DeviceEventService? deviceEvents;

  @override
  State<FacePage> createState() => _FacePageState();
}

class _FacePageState extends State<FacePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  late final FaceController _controller;
  late final AiGatewayClient _gateway;
  late final TtsService _tts;
  late final SpeechService _speech;
  late final VisionService _vision;
  late final DebugLogStore _logs;
  late final DeviceEventService _deviceEvents;
  late final TextEditingController _chatTextController;
  StreamSubscription<DeviceEvent>? _deviceEventSubscription;
  bool _isGatewayOnline = false;
  bool _isBusy = false;
  bool _isSpeaking = false;
  bool _isListening = false;
  bool _isWakeListening = false;
  bool _isVoiceConversation = false;
  String _currentPersona = 'mengmeng';
  CompanionSettings _settings = CompanionSettings.initial();
  int _speechToken = 0;
  int _voiceLoopToken = 0;
  int _wakeListenToken = 0;

  @override
  void initState() {
    super.initState();
    _controller = FaceController();
    _gateway = widget.gateway ?? AiGatewayClient();
    _tts = widget.tts ?? TtsService();
    _speech = widget.speech ?? SpeechService();
    _vision = widget.vision ?? VisionService();
    _logs = widget.logs ?? DebugLogStore();
    _deviceEvents = widget.deviceEvents ?? DeviceEventService();
    _deviceEventSubscription = _deviceEvents.events.listen(_handleDeviceEvent);
    _chatTextController = TextEditingController();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _logs.info('gateway', 'base ${_gateway.debugBaseUrl}');
    unawaited(_deviceEvents.start(keepAwake: _settings.keepAwake));
    _refreshGatewayStatus();
  }

  @override
  void dispose() {
    _wakeListenToken++;
    _animation.dispose();
    _speech.stop();
    _vision.stop();
    _tts.stop();
    unawaited(_deviceEventSubscription?.cancel());
    if (widget.deviceEvents == null) {
      unawaited(_deviceEvents.dispose());
    }
    _chatTextController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _refreshGatewayStatus() async {
    final online = await _gateway.health();
    if (!mounted) {
      return;
    }
    setState(() => _isGatewayOnline = online);
    _logs.info('gateway', online ? 'health ok' : 'health failed');
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
      () => _gateway.chat(
        text,
        settings: _settings,
        persona: _currentPersona,
      ),
    );
  }

  Future<void> _lookAndAsk({String prompt = '请用一句中文描述你看到了什么。'}) async {
    if (_isBusy || !_settings.allowVision) {
      return;
    }
    _controller.thinking(label: '正在看');
    _logs.info('vision', 'capture start');
    try {
      final result = await _vision.checkOnce();
      if (!result.ok || result.imageBytes == null || result.imageBytes!.isEmpty) {
        _logs.warning('vision', 'capture failed: ${result.label}');
        _controller.doubleTap();
        return;
      }
      _logs.info('vision', 'captured ${result.imageBytes!.length} bytes');
      await _applyGatewayCall(
        () => _gateway.vision(
          result.imageBytes!,
          prompt: prompt,
          settings: _settings,
          persona: _currentPersona,
        ),
      );
    } catch (error) {
      _logs.warning('vision', 'look failed: $error');
      _controller.doubleTap();
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

  Future<void> _toggleVoiceConversation() async {
    final next = !_isVoiceConversation;
    ++_voiceLoopToken;
    setState(() => _isVoiceConversation = next);
    _logs.info('speech', next ? 'voice round start' : 'voice round stop');
    if (!next) {
      await _speech.stop();
      if (mounted) {
        setState(() => _isListening = false);
      }
      return;
    }
    try {
      await _listenAndSendOnce();
    } catch (error) {
      _logs.warning('speech', 'voice round failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isListening = false;
          _isVoiceConversation = false;
        });
      }
    }
  }

  Future<void> _toggleWakeListening() async {
    final next = !_isWakeListening;
    final token = ++_wakeListenToken;
    setState(() => _isWakeListening = next);
    _logs.info('speech', next ? 'wake listening start' : 'wake listening stop');
    if (!next) {
      await _speech.stop();
      if (mounted) {
        setState(() => _isListening = false);
      }
      return;
    }
    unawaited(_runWakeListeningLoop(token));
  }

  Future<void> _runWakeListeningLoop(int token) async {
    while (mounted && _isWakeListening && token == _wakeListenToken) {
      if (!_settings.allowSpeechInput || _isBusy || _isSpeaking) {
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        continue;
      }
      setState(() => _isListening = true);
      String? text;
      try {
        text = await _speech.listenOnce(
          listenFor: const Duration(seconds: 3),
        );
      } catch (error) {
        _logs.warning('speech', 'wake listen failed: $error');
      }
      if (!mounted || !_isWakeListening || token != _wakeListenToken) {
        if (mounted) {
          setState(() => _isListening = false);
        }
        return;
      }
      setState(() => _isListening = false);
      final normalized = text?.trim();
      if (normalized != null && normalized.isNotEmpty) {
        _logs.info('speech', 'wake listen heard: $normalized');
        final wakeCommand = _extractWakeCommand(normalized);
        if (wakeCommand != null) {
          await _handleWakeCommand(wakeCommand);
        } else {
          _logs.info('speech', 'wake word not matched');
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    }
    if (mounted && _isListening) {
      setState(() => _isListening = false);
    }
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
    final wakeCommand = _extractWakeCommand(normalized);
    if (wakeCommand != null) {
      _logs.info('speech', 'wake word detected');
      await _handleWakeCommand(wakeCommand);
      return;
    }
    final commandText = normalized;
    await _handleRecognizedCommand(commandText);
  }

  Future<void> _handleWakeCommand(_WakeCommand wakeCommand) async {
    _currentPersona = wakeCommand.persona;
    _logs.info('speech', 'persona ${wakeCommand.persona}');
    _controller.setRole(_faceRoleForPersona(wakeCommand.persona));
    _controller.doubleTap();
    if (wakeCommand.command.isEmpty) {
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
    await _handleRecognizedCommand(wakeCommand.command);
  }

  Future<void> _handleRecognizedCommand(String commandText) async {
    if (_isVisionCommand(commandText)) {
      if (!_settings.allowVision) {
        _logs.warning('vision', 'voice command ignored: vision disabled');
        _controller.doubleTap();
        return;
      }
      _logs.info('vision', 'voice command: $commandText');
      await _lookAndAsk(prompt: commandText);
      return;
    }
    await _sendText(commandText);
  }

  FaceRole _faceRoleForPersona(String persona) {
    return switch (persona) {
      'xiaoyuan' => FaceRole.maleCalm,
      'qunqun_teacher' => FaceRole.femaleSoft,
      _ => FaceRole.femaleLively,
    };
  }

  _WakeCommand? _extractWakeCommand(String text) {
    final trimmed = text.trim();
    final normalized = _normalizeWakeText(trimmed);
    if (normalized.isEmpty) {
      return null;
    }
    final wakeWords = _wakeWords();
    for (final wakeWord in wakeWords) {
      final alias = _normalizeWakeText(wakeWord.text);
      final index = normalized.indexOf(alias);
      if (index >= 0) {
        final command = normalized.replaceFirst(alias, '');
        return _WakeCommand(persona: wakeWord.persona, command: _cleanWakeCommand(command));
      }
    }
    if (normalized.length <= 8) {
      _WakeWord? best;
      var bestScore = 0.0;
      for (final wakeWord in wakeWords) {
        final score = _similarity(normalized, _normalizeWakeText(wakeWord.text));
        if (score > bestScore) {
          bestScore = score;
          best = wakeWord;
        }
      }
      if (best != null && bestScore >= 0.62) {
        return _WakeCommand(persona: best.persona, command: '');
      }
    }
    return null;
  }

  List<_WakeWord> _wakeWords() {
    return const [
      _WakeWord('群群老师', 'qunqun_teacher'),
      _WakeWord('群群老師', 'qunqun_teacher'),
      _WakeWord('群俊老师', 'qunqun_teacher'),
      _WakeWord('秦军老师', 'qunqun_teacher'),
      _WakeWord('秦群老师', 'qunqun_teacher'),
      _WakeWord('群君老师', 'qunqun_teacher'),
      _WakeWord('群軍老師', 'qunqun_teacher'),
      _WakeWord('群老师', 'qunqun_teacher'),
      _WakeWord('群老師', 'qunqun_teacher'),
      _WakeWord('群群', 'qunqun_teacher'),
      _WakeWord('萌萌', 'mengmeng'),
      _WakeWord('萌', 'mengmeng'),
      _WakeWord('梦梦', 'mengmeng'),
      _WakeWord('夢夢', 'mengmeng'),
      _WakeWord('蒙蒙', 'mengmeng'),
      _WakeWord('濛濛', 'mengmeng'),
      _WakeWord('朦朦', 'mengmeng'),
      _WakeWord('妹妹', 'mengmeng'),
      _WakeWord('么么', 'mengmeng'),
      _WakeWord('萌妹', 'mengmeng'),
      _WakeWord('农农', 'mengmeng'),
      _WakeWord('農農', 'mengmeng'),
      _WakeWord('蜘蛛蜘蛛蜘蛛', 'mengmeng'),
      _WakeWord('小远同学', 'xiaoyuan'),
      _WakeWord('小圆同学', 'xiaoyuan'),
      _WakeWord('小園同学', 'xiaoyuan'),
      _WakeWord('小远', 'xiaoyuan'),
      _WakeWord('小遠', 'xiaoyuan'),
      _WakeWord('小圆', 'xiaoyuan'),
      _WakeWord('小園', 'xiaoyuan'),
      _WakeWord('小袁', 'xiaoyuan'),
      _WakeWord('小源', 'xiaoyuan'),
      _WakeWord('小元', 'xiaoyuan'),
      _WakeWord('小语言', 'xiaoyuan'),
    ];
  }

  String _normalizeWakeText(String text) {
    return text
        .trim()
        .replaceAll(RegExp(r'[\s，。！？、,.!?~～：:（）()\[\]【】《》"“”‘’]'), '');
  }

  String _cleanWakeCommand(String text) {
    final cleaned = _normalizeWakeText(text);
    const noiseCommands = {'同学', '老師', '老师', '啊', '呀', '呢', '喂'};
    return noiseCommands.contains(cleaned) ? '' : cleaned;
  }

  double _similarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) {
      return 0;
    }
    final distance = _levenshtein(a, b);
    final longest = a.length > b.length ? a.length : b.length;
    return 1 - distance / longest;
  }

  int _levenshtein(String a, String b) {
    final left = a.runes.toList();
    final right = b.runes.toList();
    final previous = List<int>.generate(right.length + 1, (index) => index);
    for (var i = 0; i < left.length; i++) {
      var diagonal = previous[0];
      previous[0] = i + 1;
      for (var j = 0; j < right.length; j++) {
        final insert = previous[j + 1] + 1;
        final delete = previous[j] + 1;
        final replace = diagonal + (left[i] == right[j] ? 0 : 1);
        diagonal = previous[j + 1];
        previous[j + 1] = [insert, delete, replace].reduce(
          (x, y) => x < y ? x : y,
        );
      }
    }
    return previous[right.length];
  }

  bool _isVisionCommand(String text) {
    final compact = text
        .toLowerCase()
        .replaceAll(RegExp(r'[\s，。！？、,.!?~～：:]'), '');
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
    setState(() => _isSpeaking = false);
    return true;
  }

  Future<void> _speakResponse(RobotResponse response) async {
    if (!response.shouldSpeak ||
        !_settings.allowSpeechOutput ||
        response.text.trim().isEmpty) {
      return;
    }
    final token = ++_speechToken;
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
    setState(() => _isSpeaking = false);
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
    if (!settings.allowSpeechInput && _isListening) {
      _voiceLoopToken++;
      _wakeListenToken++;
      _speech.stop();
      setState(() {
        _isListening = false;
        _isVoiceConversation = false;
        _isWakeListening = false;
      });
    }
    if (!settings.allowSpeechInput && _isVoiceConversation) {
      _voiceLoopToken++;
      setState(() => _isVoiceConversation = false);
    }
    if (!settings.allowSpeechInput && _isWakeListening) {
      _wakeListenToken++;
      setState(() => _isWakeListening = false);
    }
    if (!settings.allowVision) {
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
          isVoiceConversation: _isVoiceConversation,
          isWakeListening: _isWakeListening,
          controller: _controller,
          onSettingsChanged: (next) {
            setPanelState(() => panelSettings = next);
            _updateSettings(next);
          },
          onListen: _listenAndChat,
          onLook: () => _lookAndAsk(),
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
    _logs.info('tts', 'stop');
    if (!mounted) {
      return;
    }
    setState(() => _isSpeaking = false);
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
                  isGatewayOnline: _isGatewayOnline,
                  isBusy: _isBusy,
                  isSpeaking: _isSpeaking,
                  isListening: _isListening,
                  isWakeListening: _isWakeListening,
                  onRefresh: _refreshGatewayStatus,
                  onStopSpeaking: _stopSpeaking,
                  onOpenControls: _showControlPanel,
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _deviceEvents.emitSimulated('tap'),
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
              ],
            ),
          ),
        );
      },
    );
  }
}

class _WakeWord {
  const _WakeWord(this.text, this.persona);

  final String text;
  final String persona;
}

class _WakeCommand {
  const _WakeCommand({required this.persona, required this.command});

  final String persona;
  final String command;
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.state,
    required this.isGatewayOnline,
    required this.isBusy,
    required this.isSpeaking,
    required this.isListening,
    required this.isWakeListening,
    required this.onRefresh,
    required this.onStopSpeaking,
    required this.onOpenControls,
  });

  final ExpressionState state;
  final bool isGatewayOnline;
  final bool isBusy;
  final bool isSpeaking;
  final bool isListening;
  final bool isWakeListening;
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
              state.label,
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
          if (isWakeListening) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.radar,
              size: 18,
              color: const Color(0xFFB8FF74).withValues(alpha: 0.92),
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
              key: const ValueKey('openControls'),
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
    required this.isVoiceConversation,
    required this.isWakeListening,
    required this.controller,
    required this.onSettingsChanged,
    required this.onListen,
    required this.onLook,
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
  final bool isVoiceConversation;
  final bool isWakeListening;
  final FaceController controller;
  final ValueChanged<CompanionSettings> onSettingsChanged;
  final VoidCallback onListen;
  final VoidCallback onLook;
  final VoidCallback onToggleVoiceConversation;
  final VoidCallback onToggleWakeListening;
  final VoidCallback onShowMemory;
  final VoidCallback onShowLogs;
  final VoidCallback onShowDeviceCheck;
  final ValueChanged<String> onEvent;

  @override
  Widget build(BuildContext context) {
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
                  icon: isWakeListening ? Icons.radar : Icons.hearing,
                  label: isWakeListening ? '关闭唤醒' : '萌萌唤醒',
                  onPressed: isBusy || !settings.allowSpeechInput
                      ? null
                      : onToggleWakeListening,
                ),
                _PanelAction(
                  icon: isVoiceConversation
                      ? Icons.hearing
                      : Icons.record_voice_over,
                  label: isVoiceConversation ? '关闭对话' : '语音对话',
                  onPressed: isBusy || !settings.allowSpeechInput
                      ? null
                      : onToggleVoiceConversation,
                ),
                _PanelAction(
                  icon: isListening ? Icons.graphic_eq : Icons.mic,
                  label: isListening ? '正在听' : '语音输入',
                  onPressed: isBusy || isListening || !settings.allowSpeechInput
                      ? null
                      : onListen,
                ),
                _PanelAction(
                  icon: Icons.visibility,
                  label: '看一下',
                  onPressed: isBusy || !settings.allowVision ? null : onLook,
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
                key: ValueKey('debug_${action.label}'),
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

import 'dart:async';

import 'barge_in_config.dart';
import 'barge_in_result.dart';
import 'native_wake_detector_stub.dart';
import 'speech_service.dart';
import 'stt_wake_detector.dart';
import 'voice_audio_gate_config.dart';
import 'voice_debug_snapshot.dart';
import 'voice_events.dart';
import 'voice_profile_preset.dart';
import 'voice_runtime_profile.dart';
import 'voice_state.dart';
import 'voice_tuning_recommendation.dart';
import 'voice_wake_config.dart';
import 'wake_detector.dart';
import 'wake_detector_type.dart';
import 'wake_word_matcher.dart';

class VoiceWakeController {
  VoiceWakeController({
    required SpeechService speech,
    WakeWordMatcher matcher = const WakeWordMatcher(),
    VoiceWakeConfig config = const VoiceWakeConfig(),
    BargeInConfig bargeInConfig = const BargeInConfig(),
    WakeDetector? wakeDetector,
    bool Function()? canListen,
  }) : _speech = speech,
       _config = config,
       _bargeInConfig = bargeInConfig,
       _canListen = canListen {
    _wakeDetector =
        wakeDetector ??
        _createWakeDetector(
          type: config.wakeDetectorType,
          speech: speech,
          matcher: matcher,
          wakeConfigProvider: () => _config,
          audioGateConfigProvider: () => audioGateConfig,
        );
    _wakeDetectorSubscription = _wakeDetector.events.listen(
      _handleWakeDetectorEvent,
    );
    _updateDebug(
      _latestDebugSnapshot.copyWith(
        wakeDetectorType: _wakeDetector.type.name,
        wakeDetectorStatus: 'ready',
      ),
    );
  }

  final SpeechService _speech;
  late final WakeDetector _wakeDetector;
  final bool Function()? _canListen;
  final StreamController<VoiceEvent> _events =
      StreamController<VoiceEvent>.broadcast();
  final StreamController<VoiceDebugSnapshot> _debugSnapshots =
      StreamController<VoiceDebugSnapshot>.broadcast();

  VoiceState _state = VoiceState.idle;
  VoiceDebugSnapshot _latestDebugSnapshot = VoiceDebugSnapshot();
  VoiceWakeConfig _config;
  BargeInConfig _bargeInConfig;
  VoiceRuntimeProfile _activeProfile = VoiceRuntimeProfile.balanced;
  bool _isCustomProfile = false;
  String _profileSource = 'preset';
  int _runId = 0;
  int _loopToken = 0;
  int _bargeInToken = 0;
  Timer? _bargeInGraceTimer;
  StreamSubscription<WakeDetectorEvent>? _wakeDetectorSubscription;
  bool _disposed = false;
  bool _ttsActive = false;
  DateTime? _lastWakeAt;
  DateTime? _lastTtsEndAt;
  DateTime _lastConversationActivity = DateTime.fromMillisecondsSinceEpoch(0);

  Stream<VoiceEvent> get events => _events.stream;
  Stream<VoiceDebugSnapshot> get debugSnapshots => _debugSnapshots.stream;
  VoiceState get state => _state;
  VoiceDebugSnapshot get latestDebugSnapshot => _latestDebugSnapshot;
  VoiceWakeConfig get config => _config;
  BargeInConfig get bargeInConfig => _bargeInConfig;
  VoiceAudioGateConfig get audioGateConfig => _speech.audioGateConfig;
  VoiceRuntimeProfile get activeProfile => _activeProfile;
  bool get isCustomProfile => _isCustomProfile;

  void updateConfig(VoiceWakeConfig config) {
    applyCustomConfig(wakeConfig: config);
  }

  void updateAudioGateConfig(VoiceAudioGateConfig config) {
    applyCustomConfig(audioGateConfig: config);
  }

  void updateBargeInConfig(BargeInConfig config) {
    applyCustomConfig(bargeInConfig: config);
  }

  void applyProfile(VoiceRuntimeProfile profile) {
    if (profile == VoiceRuntimeProfile.custom) {
      _markCustomProfile('manual');
      _updateDebug(_latestDebugSnapshot);
      return;
    }
    final preset = VoiceProfilePreset.forProfile(profile);
    _config = preset.wakeConfig;
    _speech.updateAudioGateConfig(preset.audioGateConfig);
    _bargeInConfig = preset.bargeInConfig;
    _activeProfile = profile;
    _isCustomProfile = false;
    _profileSource = 'preset';
    _updateDebug(
      _latestDebugSnapshot.copyWith(
        wakeCooldownActive: _isWakeCoolingDown(),
        ttsCooldownActive: _isTtsCooldownActive(),
      ),
    );
  }

  void applyCustomConfig({
    VoiceWakeConfig? wakeConfig,
    VoiceAudioGateConfig? audioGateConfig,
    BargeInConfig? bargeInConfig,
    String source = 'manual',
  }) {
    _config = wakeConfig ?? _config;
    if (audioGateConfig != null) {
      _speech.updateAudioGateConfig(audioGateConfig);
    }
    _bargeInConfig = bargeInConfig ?? _bargeInConfig;
    _markCustomProfile(source);
    _updateDebug(
      _latestDebugSnapshot.copyWith(
        wakeCooldownActive: _isWakeCoolingDown(),
        ttsCooldownActive: _isTtsCooldownActive(),
      ),
    );
  }

  void applyRecommendationAsCustom(VoiceTuningRecommendation recommendation) {
    applyCustomConfig(
      wakeConfig: _config.copyWith(
        wakeScoreThreshold: recommendation.recommendedWakeScoreThreshold,
      ),
      audioGateConfig: audioGateConfig.copyWith(
        minAvgRms: recommendation.recommendedMinAvgRms,
        minMaxRms: recommendation.recommendedMinMaxRms,
        minSpeechLikeRatio: recommendation.recommendedMinSpeechLikeRatio,
      ),
      bargeInConfig: _bargeInConfig.copyWith(
        minAvgRms: recommendation.recommendedBargeInMinAvgRms,
        minMaxRms: recommendation.recommendedBargeInMinMaxRms,
        minSpeechLikeRatio: recommendation.recommendedBargeInSpeechLikeRatio,
        postTtsStartGracePeriod:
            recommendation.recommendedPostTtsStartGracePeriod,
      ),
      source: 'recommendation',
    );
  }

  Future<void> start() async {
    await _startInState(VoiceState.monitoring);
  }

  Future<void> startConversation() async {
    _lastConversationActivity = DateTime.now();
    await _startInState(VoiceState.conversation);
  }

  Future<void> stop() async {
    _runId++;
    _loopToken++;
    _bargeInToken++;
    _bargeInGraceTimer?.cancel();
    await _wakeDetector.stop();
    await _speech.stop();
    _setState(VoiceState.idle);
  }

  Future<void> pauseForLifecycle(String lifecycleState) async {
    _updateDebug(
      _latestDebugSnapshot.copyWith(
        lifecycleState: lifecycleState,
        lifecycleReason: 'app_backgrounded',
        runtimeWarning: '',
      ),
    );
    await stop();
  }

  void notifyLifecycleResumed() {
    _updateDebug(
      _latestDebugSnapshot.copyWith(
        lifecycleState: 'resumed',
        lifecycleReason: 'app_foregrounded',
      ),
    );
  }

  void notifyTtsStarted() {
    _ttsActive = true;
    final token = ++_bargeInToken;
    final runId = _runId;
    _bargeInGraceTimer?.cancel();
    _updateDebug(
      _latestDebugSnapshot.copyWith(
        ttsCooldownActive: true,
        wakeCooldownActive: _isWakeCoolingDown(),
        bargeInDetected: false,
        bargeInAvgRms: 0,
        bargeInMaxRms: 0,
        bargeInSpeechLikeRatio: 0,
        bargeInReason: '',
      ),
    );
    _setState(VoiceState.speaking);
    if (_bargeInConfig.enabled) {
      _bargeInGraceTimer = Timer(_bargeInConfig.postTtsStartGracePeriod, () {
        unawaited(_listenForBargeIn(token, runId));
      });
    }
  }

  void notifyTtsEnded() {
    _ttsActive = false;
    _bargeInToken++;
    _bargeInGraceTimer?.cancel();
    _lastTtsEndAt = DateTime.now();
    _updateDebug(
      _latestDebugSnapshot.copyWith(
        ttsCooldownActive: true,
        wakeCooldownActive: _isWakeCoolingDown(),
      ),
    );
    if (_state == VoiceState.speaking ||
        _state == VoiceState.bargeInListening) {
      _setState(VoiceState.conversation);
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _runId++;
    _loopToken++;
    _bargeInToken++;
    _bargeInGraceTimer?.cancel();
    unawaited(_wakeDetectorSubscription?.cancel());
    unawaited(_wakeDetector.dispose());
    unawaited(_speech.stop());
    _events.close();
    _debugSnapshots.close();
  }

  Future<void> _startInState(VoiceState next) async {
    if (_disposed) {
      return;
    }
    final permissionStatus = await _speech.microphonePermissionStatus();
    _updateDebug(
      _latestDebugSnapshot.copyWith(
        permissionStatus: permissionStatus,
        runtimeWarning: permissionStatus == 'denied' ? 'permissionDenied' : '',
      ),
    );
    if (permissionStatus == 'denied') {
      _emit(const VoiceLogEvent('microphone permission denied'));
      _setState(VoiceState.idle);
      return;
    }
    _runId++;
    _loopToken++;
    await _speech.stop();
    if (next == VoiceState.monitoring) {
      await _wakeDetector.start();
    }
    _setState(next);
    final runId = _runId;
    final token = ++_loopToken;
    unawaited(Future<void>.microtask(() => _runLoop(token, runId)));
  }

  Future<void> _runLoop(int token, int runId) async {
    while (!_disposed &&
        _state != VoiceState.idle &&
        token == _loopToken &&
        runId == _runId) {
      if (_state == VoiceState.conversation &&
          DateTime.now().difference(_lastConversationActivity) >
              _config.conversationIdleTimeout) {
        _emit(const VoiceLogEvent('conversation idle timeout'));
        _setState(VoiceState.monitoring);
      }

      if (_ttsActive ||
          _state == VoiceState.speaking ||
          _state == VoiceState.bargeInListening ||
          !(_canListen?.call() ?? true)) {
        await Future<void>.delayed(_config.monitoringLoopDelay);
        continue;
      }

      try {
        if (_state == VoiceState.monitoring) {
          await _listenWakeRound(token, runId);
        } else if (_state == VoiceState.conversation) {
          await _listenConversationRound(token, runId);
        } else {
          await Future<void>.delayed(_config.monitoringLoopDelay);
        }
      } catch (error) {
        _emit(VoiceError(error));
        _setState(VoiceState.error);
        await Future<void>.delayed(_config.monitoringLoopDelay);
        if (!_disposed && token == _loopToken && runId == _runId) {
          _setState(VoiceState.monitoring);
        }
      }

      await Future<void>.delayed(_config.monitoringLoopDelay);
    }
  }

  Future<void> _listenWakeRound(int token, int runId) async {
    _setState(VoiceState.recording);
    _updateDebug(
      _latestDebugSnapshot.copyWith(
        wakeDetectorType: _wakeDetector.type.name,
        wakeDetectorStatus: 'running',
      ),
    );
    await _wakeDetector.detectOnce();
    _mergeSpeechDebug();
    if (_disposed ||
        token != _loopToken ||
        runId != _runId ||
        _state == VoiceState.idle) {
      return;
    }
    if (_state == VoiceState.recording || _state == VoiceState.wakeCandidate) {
      _setState(VoiceState.monitoring);
    }
  }

  Future<void> _listenConversationRound(int token, int runId) async {
    _setState(VoiceState.recording);
    final text = await _speech.listenForUtterance(
      maxDuration: _config.conversationMaxDuration,
      silenceTimeout: _config.conversationSilenceTimeout,
      startTimeout: _config.conversationStartTimeout,
    );
    _mergeSpeechDebug();
    if (_disposed ||
        token != _loopToken ||
        runId != _runId ||
        _state == VoiceState.idle) {
      return;
    }
    final normalized = text?.trim();
    if (normalized == null || normalized.isEmpty) {
      _setState(VoiceState.conversation);
      return;
    }
    _lastConversationActivity = DateTime.now();
    _emit(UserUtteranceDetected(text: normalized));
    _setState(VoiceState.conversation);
  }

  Future<void> _listenForBargeIn(int token, int runId) async {
    if (_disposed ||
        token != _bargeInToken ||
        runId != _runId ||
        !_ttsActive ||
        _state == VoiceState.idle) {
      return;
    }
    _setState(VoiceState.bargeInListening);
    final result = await _speech.listenForBargeIn(_bargeInConfig);
    _mergeBargeInDebug(result);
    if (_disposed || token != _bargeInToken || runId != _runId || !_ttsActive) {
      return;
    }
    if (result.detected) {
      _emit(
        BargeInDetected(
          avgRms: result.avgRms,
          maxRms: result.maxRms,
          speechLikeRatio: result.speechLikeRatio,
          reason: result.reason,
        ),
      );
      _setState(VoiceState.conversation);
      return;
    }
    _emit(
      BargeInIgnored(
        avgRms: result.avgRms,
        maxRms: result.maxRms,
        speechLikeRatio: result.speechLikeRatio,
        reason: result.reason,
      ),
    );
    if (_ttsActive && _state == VoiceState.bargeInListening) {
      _setState(VoiceState.speaking);
    }
  }

  void _handleWakeDetectorEvent(WakeDetectorEvent event) {
    if (_disposed || _state == VoiceState.idle) {
      return;
    }
    switch (event) {
      case WakeDetectorDetected():
        _handleWakeDetectorDetected(event);
      case WakeDetectorIgnored():
        _handleWakeDetectorIgnored(event);
      case WakeDetectorError():
        _updateDebug(
          _latestDebugSnapshot.copyWith(
            wakeDetectorType: _wakeDetector.type.name,
            wakeDetectorStatus: event.reason,
            runtimeWarning: event.reason,
          ),
        );
        _emit(VoiceError(event.error ?? event.reason));
      case WakeDetectorLog():
        _emit(VoiceLogEvent(event.message));
    }
  }

  void _handleWakeDetectorDetected(WakeDetectorDetected event) {
    _setState(VoiceState.wakeCandidate);
    _updateDebug(
      _latestDebugSnapshot.copyWith(
        rawText: event.rawText ?? _latestDebugSnapshot.rawText,
        normalizedText:
            event.normalizedText ?? _latestDebugSnapshot.normalizedText,
        sttFlags: event.flags,
        wakeWord: event.wakeWord,
        matchType: event.matchType,
        wakeScore: event.score,
        command: event.command,
        wakeIgnoredReason: '',
        wakeDetectorType: _wakeDetector.type.name,
        wakeDetectorStatus: 'detected',
        wakeCooldownActive: _isWakeCoolingDown(),
        ttsCooldownActive: _isTtsCooldownActive(),
      ),
    );
    if (_isWakeCoolingDown()) {
      _updateDebug(
        _latestDebugSnapshot.copyWith(
          wakeIgnoredReason: 'cooldown',
          wakeDetectorStatus: 'cooldown',
          wakeCooldownActive: true,
          ttsCooldownActive: _isTtsCooldownActive(),
        ),
      );
      _emit(
        WakeIgnored(
          reason: 'cooldown',
          text: event.normalizedText ?? '',
          score: event.score,
          flags: event.flags,
        ),
      );
      _setState(VoiceState.monitoring);
      return;
    }
    _lastWakeAt = DateTime.now();
    _lastConversationActivity = DateTime.now();
    _updateDebug(
      _latestDebugSnapshot.copyWith(
        wakeCooldownActive: true,
        ttsCooldownActive: _isTtsCooldownActive(),
      ),
    );
    _setState(VoiceState.awakened);
    _emit(
      WakeDetected(
        persona: event.persona,
        wakeWord: event.wakeWord,
        command: event.command,
        score: event.score,
        matchType: _wakeMatchTypeFromName(event.matchType),
      ),
    );
    if (event.command.isEmpty) {
      _emit(WakeOnlyDetected(persona: event.persona));
    }
    _setState(VoiceState.conversation);
  }

  void _handleWakeDetectorIgnored(WakeDetectorIgnored event) {
    _setState(VoiceState.wakeCandidate);
    _updateDebug(
      _latestDebugSnapshot.copyWith(
        rawText: event.rawText ?? _latestDebugSnapshot.rawText,
        normalizedText:
            event.normalizedText ?? _latestDebugSnapshot.normalizedText,
        sttFlags: event.flags,
        wakeWord: '',
        matchType: '',
        wakeScore: event.score ?? 0,
        command: '',
        wakeIgnoredReason: event.reason,
        wakeDetectorType: _wakeDetector.type.name,
        wakeDetectorStatus: event.reason,
        wakeCooldownActive: _isWakeCoolingDown(),
        ttsCooldownActive: _isTtsCooldownActive(),
      ),
    );
    if (event.reason != 'empty') {
      _emit(
        WakeIgnored(
          reason: event.reason,
          text: event.normalizedText ?? '',
          score: event.score ?? 0,
          flags: event.flags,
        ),
      );
    }
    _setState(VoiceState.monitoring);
  }

  WakeMatchType _wakeMatchTypeFromName(String name) {
    return WakeMatchType.values.firstWhere(
      (type) => type.name == name,
      orElse: () => WakeMatchType.primary,
    );
  }

  bool _isWakeCoolingDown() {
    final now = DateTime.now();
    final lastWakeAt = _lastWakeAt;
    if (lastWakeAt != null &&
        now.difference(lastWakeAt) < _config.wakeCooldown) {
      return true;
    }
    final lastTtsEndAt = _lastTtsEndAt;
    return lastTtsEndAt != null &&
        now.difference(lastTtsEndAt) < _config.ttsCooldown;
  }

  bool _isTtsCooldownActive() {
    final lastTtsEndAt = _lastTtsEndAt;
    if (_ttsActive || _state == VoiceState.speaking) {
      return true;
    }
    return lastTtsEndAt != null &&
        DateTime.now().difference(lastTtsEndAt) < _config.ttsCooldown;
  }

  void _setState(VoiceState next) {
    if (_disposed || _state == next) {
      return;
    }
    _state = next;
    _updateDebug(
      _latestDebugSnapshot.copyWith(
        voiceState: next,
        wakeCooldownActive: _isWakeCoolingDown(),
        ttsCooldownActive: _isTtsCooldownActive(),
      ),
    );
    _emit(VoiceStateChanged(next));
  }

  void _mergeSpeechDebug() {
    final speechSnapshot = _speech.latestDebugSnapshot;
    _updateDebug(
      _latestDebugSnapshot.copyWith(
        durationMs: speechSnapshot.durationMs,
        speechDurationMs: speechSnapshot.speechDurationMs,
        avgRms: speechSnapshot.avgRms,
        maxRms: speechSnapshot.maxRms,
        speechLikeRatio: speechSnapshot.speechLikeRatio,
        recordReason: speechSnapshot.recordReason,
        callStt: speechSnapshot.callStt,
        gateReason: speechSnapshot.gateReason,
        gateFlags: speechSnapshot.gateFlags,
        rawText: speechSnapshot.rawText,
        normalizedText: speechSnapshot.normalizedText,
        sttFlags: speechSnapshot.sttFlags,
        permissionStatus: speechSnapshot.permissionStatus.isEmpty
            ? _latestDebugSnapshot.permissionStatus
            : speechSnapshot.permissionStatus,
        recordingInProgress: speechSnapshot.recordingInProgress,
        runtimeWarning: speechSnapshot.runtimeWarning,
        wakeCooldownActive: _isWakeCoolingDown(),
        ttsCooldownActive: _isTtsCooldownActive(),
      ),
    );
  }

  void _mergeBargeInDebug(BargeInResult result) {
    _updateDebug(
      _latestDebugSnapshot.copyWith(
        bargeInDetected: result.detected,
        bargeInAvgRms: result.avgRms,
        bargeInMaxRms: result.maxRms,
        bargeInSpeechLikeRatio: result.speechLikeRatio,
        bargeInReason: result.reason,
        wakeCooldownActive: _isWakeCoolingDown(),
        ttsCooldownActive: _isTtsCooldownActive(),
      ),
    );
  }

  void _markCustomProfile(String source) {
    _activeProfile = VoiceRuntimeProfile.custom;
    _isCustomProfile = true;
    _profileSource = source;
  }

  void _updateDebug(VoiceDebugSnapshot snapshot) {
    if (_disposed) {
      return;
    }
    _latestDebugSnapshot = snapshot.copyWith(
      voiceProfile: _activeProfile.name,
      isCustomVoiceProfile: _isCustomProfile,
      profileSource: _profileSource,
      wakeDetectorType: _wakeDetector.type.name,
      updatedAt: DateTime.now(),
    );
    if (!_debugSnapshots.isClosed) {
      _debugSnapshots.add(_latestDebugSnapshot);
    }
  }

  void _emit(VoiceEvent event) {
    if (!_disposed && !_events.isClosed) {
      _events.add(event);
    }
  }
}

WakeDetector _createWakeDetector({
  required WakeDetectorType type,
  required SpeechService speech,
  required WakeWordMatcher matcher,
  required VoiceWakeConfig Function() wakeConfigProvider,
  required VoiceAudioGateConfig Function() audioGateConfigProvider,
}) {
  return switch (type) {
    WakeDetectorType.stt => SttWakeDetector(
      speechService: speech,
      wakeWordMatcher: matcher,
      wakeConfigProvider: wakeConfigProvider,
      audioGateConfigProvider: audioGateConfigProvider,
    ),
    WakeDetectorType.sherpaOnnx ||
    WakeDetectorType.openWakeWord => NativeWakeDetectorStub(type),
  };
}

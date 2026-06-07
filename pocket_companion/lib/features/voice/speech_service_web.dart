import 'dart:async';

import 'barge_in_config.dart';
import 'barge_in_result.dart';
import 'voice_audio_gate_config.dart';
import 'voice_debug_snapshot.dart';

class SpeechService {
  Timer? _timer;
  Completer<String?>? _activeCompleter;
  VoiceDebugSnapshot _latestDebugSnapshot = VoiceDebugSnapshot();
  VoiceAudioGateConfig _audioGateConfig = const VoiceAudioGateConfig();

  VoiceDebugSnapshot get latestDebugSnapshot => _latestDebugSnapshot;
  VoiceAudioGateConfig get audioGateConfig => _audioGateConfig;

  void updateAudioGateConfig(VoiceAudioGateConfig config) {
    _audioGateConfig = config;
  }

  Future<String> microphonePermissionStatus() async => 'granted';

  Future<String?> listenOnce({
    Duration listenFor = const Duration(seconds: 5),
  }) {
    _timer?.cancel();
    _activeCompleter?.complete(null);
    final completer = Completer<String?>();
    _activeCompleter = completer;
    _timer = Timer(const Duration(milliseconds: 800), () {
      if (!completer.isCompleted) {
        _latestDebugSnapshot = _latestDebugSnapshot.copyWith(
          normalizedText: '今天有点累',
          rawText: '今天有点累',
        );
        completer.complete('今天有点累');
      }
    });
    return completer.future;
  }

  Future<String?> listenForUtterance({
    Duration maxDuration = const Duration(seconds: 12),
    Duration silenceTimeout = const Duration(milliseconds: 1200),
    Duration startTimeout = const Duration(seconds: 3),
  }) {
    return listenOnce(listenFor: maxDuration);
  }

  Future<BargeInResult> listenForBargeIn(BargeInConfig config) async {
    return const BargeInResult(
      detected: false,
      durationMs: 0,
      speechDurationMs: 0,
      avgRms: 0,
      maxRms: 0,
      speechLikeRatio: 0,
      reason: 'unsupported_platform',
    );
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    if (_activeCompleter?.isCompleted == false) {
      _activeCompleter?.complete(null);
    }
    _activeCompleter = null;
  }
}

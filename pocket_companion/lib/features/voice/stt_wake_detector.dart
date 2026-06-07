import 'dart:async';

import 'speech_service.dart';
import 'voice_audio_gate_config.dart';
import 'voice_wake_config.dart';
import 'wake_detector.dart';
import 'wake_detector_type.dart';
import 'wake_word_matcher.dart';

class SttWakeDetector implements WakeDetector {
  SttWakeDetector({
    required this.speechService,
    this.wakeWordMatcher = const WakeWordMatcher(),
    required this.wakeConfigProvider,
    required this.audioGateConfigProvider,
  });

  final SpeechService speechService;
  final WakeWordMatcher wakeWordMatcher;
  final VoiceWakeConfig Function() wakeConfigProvider;
  final VoiceAudioGateConfig Function() audioGateConfigProvider;
  final StreamController<WakeDetectorEvent> _events =
      StreamController<WakeDetectorEvent>.broadcast();

  bool _running = false;
  bool _disposed = false;

  @override
  WakeDetectorType get type => WakeDetectorType.stt;

  @override
  Stream<WakeDetectorEvent> get events => _events.stream;

  @override
  Future<void> start() async {
    _running = true;
    _emit(const WakeDetectorLog('stt wake detector started'));
  }

  @override
  Future<void> stop() async {
    _running = false;
    await speechService.stop();
  }

  @override
  Future<void> detectOnce() async {
    if (_disposed) {
      return;
    }
    _running = true;
    final config = wakeConfigProvider();
    speechService.updateAudioGateConfig(audioGateConfigProvider());
    try {
      final text = await speechService.listenOnce(
        listenFor: config.monitoringListenDuration,
      );
      if (!_running || _disposed) {
        return;
      }
      final snapshot = speechService.latestDebugSnapshot;
      final rawText = snapshot.rawText.isNotEmpty ? snapshot.rawText : text;
      final normalized = snapshot.normalizedText.isNotEmpty
          ? snapshot.normalizedText.trim()
          : text?.trim();
      final flags = snapshot.sttFlags;
      if (normalized == null || normalized.isEmpty) {
        _emit(
          WakeDetectorIgnored(
            reason: 'empty',
            rawText: rawText,
            normalizedText: normalized,
            flags: flags,
          ),
        );
        return;
      }
      final match = wakeWordMatcher.match(normalized, flags: flags);
      if (match == null) {
        _emit(
          WakeDetectorIgnored(
            reason: 'not_matched',
            rawText: rawText,
            normalizedText: normalized,
            flags: flags,
          ),
        );
        return;
      }
      if (match.score < config.wakeScoreThreshold) {
        _emit(
          WakeDetectorIgnored(
            reason: 'below_threshold',
            rawText: rawText,
            normalizedText: normalized,
            score: match.score,
            flags: flags,
          ),
        );
        return;
      }
      _emit(
        WakeDetectorDetected(
          persona: match.persona,
          wakeWord: match.wakeWord,
          command: match.command,
          score: match.score,
          matchType: match.type.name,
          rawText: rawText,
          normalizedText: normalized,
          flags: flags,
        ),
      );
    } catch (error) {
      _emit(WakeDetectorError(reason: 'stt_wake_detector_error', error: error));
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _running = false;
    await speechService.stop();
    await _events.close();
  }

  void _emit(WakeDetectorEvent event) {
    if (!_disposed && !_events.isClosed) {
      _events.add(event);
    }
  }
}

import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_companion/features/voice/speech_service.dart';
import 'package:pocket_companion/features/voice/stt_wake_detector.dart';
import 'package:pocket_companion/features/voice/voice_audio_gate_config.dart';
import 'package:pocket_companion/features/voice/voice_debug_snapshot.dart';
import 'package:pocket_companion/features/voice/voice_wake_config.dart';
import 'package:pocket_companion/features/voice/wake_detector.dart';
import 'package:pocket_companion/features/voice/wake_detector_type.dart';

void main() {
  test('SttWakeDetector emits detected when wake word matches', () async {
    final speech = _DetectorSpeechService(texts: ['萌萌帮我看看这个']);
    final detector = SttWakeDetector(
      speechService: speech,
      wakeConfigProvider: () => const VoiceWakeConfig(),
      audioGateConfigProvider: () => const VoiceAudioGateConfig(),
    );
    final events = <WakeDetectorEvent>[];
    final sub = detector.events.listen(events.add);

    await detector.detectOnce();
    await Future<void>.delayed(Duration.zero);

    expect(detector.type, WakeDetectorType.stt);
    final detected = events.whereType<WakeDetectorDetected>().single;
    expect(detected.persona, 'mengmeng');
    expect(detected.wakeWord, '萌萌');
    expect(detected.command, '帮我看看这个');
    expect(detected.score, greaterThanOrEqualTo(0.85));
    expect(detected.normalizedText, '萌萌帮我看看这个');

    await sub.cancel();
    await detector.dispose();
  });

  test('SttWakeDetector emits ignored when text does not match', () async {
    final speech = _DetectorSpeechService(texts: ['普通聊天']);
    final detector = SttWakeDetector(
      speechService: speech,
      wakeConfigProvider: () => const VoiceWakeConfig(),
      audioGateConfigProvider: () => const VoiceAudioGateConfig(),
    );
    final events = <WakeDetectorEvent>[];
    final sub = detector.events.listen(events.add);

    await detector.detectOnce();
    await Future<void>.delayed(Duration.zero);

    final ignored = events.whereType<WakeDetectorIgnored>().single;
    expect(ignored.reason, 'not_matched');
    expect(ignored.normalizedText, '普通聊天');

    await sub.cancel();
    await detector.dispose();
  });
}

class _DetectorSpeechService extends SpeechService {
  _DetectorSpeechService({required List<String?> texts})
    : _texts = Queue<String?>.of(texts);

  final Queue<String?> _texts;
  VoiceDebugSnapshot _snapshot = VoiceDebugSnapshot();
  VoiceAudioGateConfig _audioGateConfig = const VoiceAudioGateConfig();

  @override
  VoiceDebugSnapshot get latestDebugSnapshot => _snapshot;

  @override
  VoiceAudioGateConfig get audioGateConfig => _audioGateConfig;

  @override
  void updateAudioGateConfig(VoiceAudioGateConfig config) {
    _audioGateConfig = config;
  }

  @override
  Future<String?> listenOnce({
    Duration listenFor = const Duration(seconds: 5),
  }) async {
    final text = _texts.isEmpty ? null : _texts.removeFirst();
    _snapshot = _snapshot.copyWith(
      rawText: text ?? '',
      normalizedText: text ?? '',
      sttFlags: const [],
    );
    return text;
  }

  @override
  Future<void> stop() async {}
}

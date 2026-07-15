import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_companion/features/voice/speech_service.dart';
import 'package:pocket_companion/features/voice/voice_audio_gate_config.dart';
import 'package:pocket_companion/features/voice/voice_wake_config.dart';
import 'package:pocket_companion/features/voice/voice_wake_controller.dart';

void main() {
  test('VoiceWakeConfig.copyWith updates selected fields', () {
    final config = const VoiceWakeConfig().copyWith(
      wakeScoreThreshold: 0.92,
      conversationSilenceTimeout: const Duration(milliseconds: 900),
    );

    expect(config.wakeScoreThreshold, 0.92);
    expect(config.conversationSilenceTimeout.inMilliseconds, 900);
    expect(config.monitoringListenDuration, const Duration(seconds: 3));
  });

  test('VoiceAudioGateConfig.copyWith updates selected fields', () {
    final config = const VoiceAudioGateConfig().copyWith(
      minAvgRms: 120,
      minSpeechLikeRatio: 0.12,
    );

    expect(config.minAvgRms, 120);
    expect(config.minSpeechLikeRatio, 0.12);
    expect(config.minMaxRms, 400);
  });

  test(
    'updateConfig changes controller config used by next wake round',
    () async {
      final speech = _ConfigSpeechService(wakeTexts: ['梦梦帮我看']);
      final controller = VoiceWakeController(
        speech: speech,
        config: const VoiceWakeConfig(
          monitoringListenDuration: Duration(milliseconds: 5),
          monitoringLoopDelay: Duration(milliseconds: 10),
          wakeScoreThreshold: 1.10,
        ),
      );

      controller.updateConfig(
        controller.config.copyWith(wakeScoreThreshold: 0.70),
      );
      await controller.start();
      await _waitFor(() => controller.latestDebugSnapshot.wakeWord.isNotEmpty);

      expect(controller.config.wakeScoreThreshold, 0.70);
      expect(controller.latestDebugSnapshot.command, '帮我看');
      controller.dispose();
    },
  );
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('condition not met before timeout');
}

class _ConfigSpeechService extends SpeechService {
  _ConfigSpeechService({List<String?> wakeTexts = const []})
    : _wakeTexts = Queue<String?>.of(wakeTexts);

  final Queue<String?> _wakeTexts;

  @override
  Future<String?> listenOnce({
    Duration listenFor = const Duration(seconds: 5),
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    return _wakeTexts.isEmpty ? null : _wakeTexts.removeFirst();
  }

  @override
  Future<void> stop() async {}
}

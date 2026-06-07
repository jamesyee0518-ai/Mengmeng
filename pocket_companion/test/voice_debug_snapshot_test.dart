import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_companion/features/voice/barge_in_config.dart';
import 'package:pocket_companion/features/voice/speech_service.dart';
import 'package:pocket_companion/features/voice/voice_debug_snapshot.dart';
import 'package:pocket_companion/features/voice/voice_events.dart';
import 'package:pocket_companion/features/voice/voice_state.dart';
import 'package:pocket_companion/features/voice/voice_wake_config.dart';
import 'package:pocket_companion/features/voice/voice_wake_controller.dart';

void main() {
  test('state changes update debug snapshot', () async {
    final controller = _controller(_DebugSpeechService());

    await controller.start();

    expect(controller.latestDebugSnapshot.voiceState, VoiceState.monitoring);
    controller.dispose();
  });

  test('WakeDetected updates wake debug fields', () async {
    final speech = _DebugSpeechService(wakeTexts: ['萌萌帮我看看这个']);
    final controller = _controller(speech);

    await controller.start();
    await _waitFor(() => controller.latestDebugSnapshot.wakeWord.isNotEmpty);

    final snapshot = controller.latestDebugSnapshot;
    expect(snapshot.wakeWord, '萌萌');
    expect(snapshot.matchType, isNotEmpty);
    expect(snapshot.wakeScore, greaterThanOrEqualTo(0.85));
    expect(snapshot.command, '帮我看看这个');
    controller.dispose();
  });

  test('WakeIgnored updates ignored reason', () async {
    final speech = _DebugSpeechService(wakeTexts: ['普通聊天']);
    final controller = _controller(speech);
    final events = <VoiceEvent>[];
    final sub = controller.events.listen(events.add);

    await controller.start();
    await _waitFor(() => events.whereType<WakeIgnored>().isNotEmpty);

    expect(controller.latestDebugSnapshot.wakeIgnoredReason, 'not_matched');
    await sub.cancel();
    controller.dispose();
  });

  test('TTS started and ended update cooldown snapshot', () {
    final controller = _controller(_DebugSpeechService());

    controller.notifyTtsStarted();
    expect(controller.latestDebugSnapshot.ttsCooldownActive, isTrue);
    expect(controller.latestDebugSnapshot.voiceState, VoiceState.speaking);

    controller.notifyTtsEnded();
    expect(controller.latestDebugSnapshot.ttsCooldownActive, isTrue);
    controller.dispose();
  });

  test('debug snapshot records gateway health fields', () {
    final snapshot = VoiceDebugSnapshot(
      gatewayOk: true,
      sttOk: false,
      llmOk: true,
      ttsOk: true,
      gatewayHealthReason: 'stt_unavailable',
      voiceProfile: 'strict',
      isCustomVoiceProfile: false,
      profileSource: 'preset',
      wakeDetectorType: 'stt',
      wakeDetectorStatus: 'detected',
      gatewayCheckedAt: DateTime(2026),
    );

    expect(snapshot.gatewayOk, isTrue);
    expect(snapshot.sttOk, isFalse);
    expect(snapshot.gatewayHealthReason, 'stt_unavailable');
    expect(snapshot.voiceProfile, 'strict');
    expect(snapshot.isCustomVoiceProfile, isFalse);
    expect(snapshot.profileSource, 'preset');
    expect(snapshot.wakeDetectorType, 'stt');
    expect(snapshot.wakeDetectorStatus, 'detected');
    expect(snapshot.gatewayCheckedAt, DateTime(2026));
  });
}

VoiceWakeController _controller(_DebugSpeechService speech) {
  return VoiceWakeController(
    speech: speech,
    config: const VoiceWakeConfig(
      monitoringListenDuration: Duration(milliseconds: 5),
      monitoringLoopDelay: Duration(milliseconds: 10),
      conversationMaxDuration: Duration(milliseconds: 30),
      conversationSilenceTimeout: Duration(milliseconds: 5),
      conversationStartTimeout: Duration(milliseconds: 5),
      conversationIdleTimeout: Duration(seconds: 2),
      wakeCooldown: Duration(seconds: 2),
      ttsCooldown: Duration(milliseconds: 800),
    ),
    bargeInConfig: const BargeInConfig(enabled: false),
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

class _DebugSpeechService extends SpeechService {
  _DebugSpeechService({List<String?> wakeTexts = const []})
    : _wakeTexts = Queue<String?>.of(wakeTexts);

  final Queue<String?> _wakeTexts;
  VoiceDebugSnapshot _snapshot = VoiceDebugSnapshot();

  @override
  VoiceDebugSnapshot get latestDebugSnapshot => _snapshot;

  @override
  Future<String?> listenOnce({
    Duration listenFor = const Duration(seconds: 5),
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    final text = _wakeTexts.isEmpty ? null : _wakeTexts.removeFirst();
    _snapshot = _snapshot.copyWith(
      durationMs: 500,
      avgRms: 120,
      maxRms: 900,
      speechLikeRatio: 0.2,
      recordReason: 'max_duration',
      callStt: true,
      gateReason: 'send_to_stt',
      rawText: text ?? '',
      normalizedText: text ?? '',
    );
    return text;
  }

  @override
  Future<String?> listenForUtterance({
    Duration maxDuration = const Duration(seconds: 12),
    Duration silenceTimeout = const Duration(milliseconds: 1200),
    Duration startTimeout = const Duration(seconds: 3),
  }) async {
    return null;
  }

  @override
  Future<void> stop() async {}
}

import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_companion/features/voice/barge_in_config.dart';
import 'package:pocket_companion/features/voice/barge_in_result.dart';
import 'package:pocket_companion/features/voice/speech_service.dart';
import 'package:pocket_companion/features/voice/voice_debug_snapshot.dart';
import 'package:pocket_companion/features/voice/voice_events.dart';
import 'package:pocket_companion/features/voice/voice_state.dart';
import 'package:pocket_companion/features/voice/voice_wake_config.dart';
import 'package:pocket_companion/features/voice/voice_wake_controller.dart';
import 'package:pocket_companion/features/voice/wake_detector.dart';
import 'package:pocket_companion/features/voice/wake_detector_type.dart';

void main() {
  test('start enters monitoring', () async {
    final speech = _FakeSpeechService();
    final controller = _controller(speech);

    await controller.start();

    expect(controller.state, VoiceState.monitoring);
    controller.dispose();
  });

  test('stop enters idle', () async {
    final speech = _FakeSpeechService();
    final controller = _controller(speech);

    await controller.start();
    await controller.stop();

    expect(controller.state, VoiceState.idle);
    controller.dispose();
  });

  test('wake match emits WakeDetected', () async {
    final speech = _FakeSpeechService(wakeTexts: ['萌萌帮我看看这个']);
    final controller = _controller(speech);
    final events = <VoiceEvent>[];
    final sub = controller.events.listen(events.add);

    await controller.start();
    await _waitFor(() => events.whereType<WakeDetected>().isNotEmpty);

    final wake = events.whereType<WakeDetected>().single;
    expect(wake.persona, 'mengmeng');
    expect(wake.command, '帮我看看这个');
    expect(wake.score, greaterThanOrEqualTo(0.85));

    await sub.cancel();
    controller.dispose();
  });

  test('wake cooldown prevents repeated wake', () async {
    final speech = _FakeSpeechService(
      wakeTexts: ['萌萌', '萌萌'],
      utteranceTexts: ['萌萌'],
    );
    final controller = _controller(speech);
    final events = <VoiceEvent>[];
    final sub = controller.events.listen(events.add);

    await controller.start();
    await _waitFor(() => events.whereType<WakeDetected>().isNotEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(events.whereType<WakeDetected>(), hasLength(1));

    await sub.cancel();
    controller.dispose();
  });

  test('tts speaking state skips recording', () async {
    final speech = _FakeSpeechService(wakeTexts: ['萌萌']);
    final controller = _controller(speech);

    controller.notifyTtsStarted();
    await controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(speech.listenOnceCalls, 0);
    controller.dispose();
  });

  test('notifyTtsStarted enters speaking then bargeInListening', () async {
    final speech = _FakeSpeechService(
      bargeInResults: [
        const BargeInResult(
          detected: false,
          durationMs: 100,
          speechDurationMs: 0,
          avgRms: 10,
          maxRms: 80,
          speechLikeRatio: 0,
          reason: 'max_duration',
        ),
      ],
      bargeInDelay: const Duration(milliseconds: 60),
    );
    final controller = _controller(speech);

    controller.notifyTtsStarted();

    expect(controller.state, VoiceState.speaking);
    await _waitFor(() => controller.state == VoiceState.bargeInListening);

    controller.dispose();
  });

  test('BargeInDetected event is emitted', () async {
    final speech = _FakeSpeechService(
      bargeInResults: [
        const BargeInResult(
          detected: true,
          durationMs: 800,
          speechDurationMs: 450,
          avgRms: 260,
          maxRms: 1800,
          speechLikeRatio: 0.31,
          reason: 'barge_in_detected',
        ),
      ],
    );
    final controller = _controller(speech);
    final events = <VoiceEvent>[];
    final sub = controller.events.listen(events.add);

    controller.notifyTtsStarted();
    await _waitFor(() => events.whereType<BargeInDetected>().isNotEmpty);

    final event = events.whereType<BargeInDetected>().single;
    expect(event.avgRms, 260);
    expect(event.maxRms, 1800);
    expect(event.reason, 'barge_in_detected');

    await sub.cancel();
    controller.dispose();
  });

  test('notifyTtsEnded ignores late barge-in result', () async {
    final speech = _FakeSpeechService(
      bargeInResults: [
        const BargeInResult(
          detected: true,
          durationMs: 800,
          speechDurationMs: 450,
          avgRms: 260,
          maxRms: 1800,
          speechLikeRatio: 0.31,
          reason: 'barge_in_detected',
        ),
      ],
      bargeInDelay: const Duration(milliseconds: 60),
    );
    final controller = _controller(speech);
    final events = <VoiceEvent>[];
    final sub = controller.events.listen(events.add);

    controller.notifyTtsStarted();
    await _waitFor(() => controller.state == VoiceState.bargeInListening);
    controller.notifyTtsEnded();
    await Future<void>.delayed(const Duration(milliseconds: 90));

    expect(events.whereType<BargeInDetected>(), isEmpty);

    await sub.cancel();
    controller.dispose();
  });

  test('conversation utterance emits UserUtteranceDetected', () async {
    final speech = _FakeSpeechService(utteranceTexts: ['今天有点累']);
    final controller = _controller(speech);
    final events = <VoiceEvent>[];
    final sub = controller.events.listen(events.add);

    await controller.startConversation();
    await _waitFor(() => events.whereType<UserUtteranceDetected>().isNotEmpty);

    final utterance = events.whereType<UserUtteranceDetected>().single;
    expect(utterance.text, '今天有点累');

    await sub.cancel();
    controller.dispose();
  });

  test('empty utterances do not emit UserUtteranceDetected', () async {
    final speech = _FakeSpeechService(utteranceTexts: [null, null]);
    final controller = _controller(speech);
    final events = <VoiceEvent>[];
    final sub = controller.events.listen(events.add);

    await controller.startConversation();
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(events.whereType<UserUtteranceDetected>(), isEmpty);

    await sub.cancel();
    controller.dispose();
  });

  test('dispose stops future events', () async {
    final speech = _FakeSpeechService(wakeTexts: ['萌萌']);
    final controller = _controller(speech);
    final events = <VoiceEvent>[];
    final sub = controller.events.listen(events.add);

    controller.dispose();
    await controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(events, isEmpty);

    await sub.cancel();
  });

  test('microphone permission denied does not start monitoring', () async {
    final speech = _FakeSpeechService(permissionStatus: 'denied');
    final controller = _controller(speech);

    await controller.start();

    expect(controller.state, VoiceState.idle);
    expect(controller.latestDebugSnapshot.permissionStatus, 'denied');
    expect(controller.latestDebugSnapshot.runtimeWarning, 'permissionDenied');
    expect(speech.listenOnceCalls, 0);
    controller.dispose();
  });

  test('late wake result after stop is ignored', () async {
    final speech = _FakeSpeechService(
      wakeTexts: ['萌萌'],
      listenOnceDelay: const Duration(milliseconds: 60),
    );
    final controller = _controller(speech);
    final events = <VoiceEvent>[];
    final sub = controller.events.listen(events.add);

    await controller.start();
    await controller.stop();
    await Future<void>.delayed(const Duration(milliseconds: 90));

    expect(events.whereType<WakeDetected>(), isEmpty);

    await sub.cancel();
    controller.dispose();
  });

  test('recording_in_progress is handled without wake event', () async {
    final speech = _FakeSpeechService(
      wakeTexts: [null],
      recordingInProgress: true,
    );
    final controller = _controller(speech);
    final events = <VoiceEvent>[];
    final sub = controller.events.listen(events.add);

    await controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(events.whereType<WakeDetected>(), isEmpty);
    expect(controller.latestDebugSnapshot.recordingInProgress, isTrue);
    expect(
      controller.latestDebugSnapshot.runtimeWarning,
      'recording_in_progress',
    );

    await sub.cancel();
    controller.dispose();
  });

  test('WakeDetectorDetected converts to WakeDetected', () async {
    final detector = _FakeWakeDetector(
      eventsToEmit: [
        const WakeDetectorDetected(
          persona: 'mengmeng',
          wakeWord: '萌萌',
          command: '帮我看看这个',
          score: 0.95,
          matchType: 'primary',
          normalizedText: '萌萌帮我看看这个',
        ),
      ],
    );
    final controller = _controller(
      _FakeSpeechService(),
      wakeDetector: detector,
    );
    final events = <VoiceEvent>[];
    final sub = controller.events.listen(events.add);

    await controller.start();
    await _waitFor(() => events.whereType<WakeDetected>().isNotEmpty);

    final wake = events.whereType<WakeDetected>().single;
    expect(wake.persona, 'mengmeng');
    expect(wake.command, '帮我看看这个');
    expect(wake.matchType.name, 'primary');

    await sub.cancel();
    controller.dispose();
  });

  test('WakeDetectorIgnored converts to WakeIgnored', () async {
    final detector = _FakeWakeDetector(
      eventsToEmit: [
        const WakeDetectorIgnored(
          reason: 'not_matched',
          normalizedText: '普通聊天',
        ),
      ],
    );
    final controller = _controller(
      _FakeSpeechService(),
      wakeDetector: detector,
    );
    final events = <VoiceEvent>[];
    final sub = controller.events.listen(events.add);

    await controller.start();
    await _waitFor(() => events.whereType<WakeIgnored>().isNotEmpty);

    final ignored = events.whereType<WakeIgnored>().single;
    expect(ignored.reason, 'not_matched');
    expect(ignored.text, '普通聊天');

    await sub.cancel();
    controller.dispose();
  });
}

VoiceWakeController _controller(
  _FakeSpeechService speech, {
  WakeDetector? wakeDetector,
}) {
  return VoiceWakeController(
    speech: speech,
    wakeDetector: wakeDetector,
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
    bargeInConfig: const BargeInConfig(
      maxDuration: Duration(milliseconds: 80),
      postTtsStartGracePeriod: Duration(milliseconds: 5),
    ),
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

class _FakeSpeechService extends SpeechService {
  _FakeSpeechService({
    List<String?> wakeTexts = const [],
    List<String?> utteranceTexts = const [],
    List<BargeInResult> bargeInResults = const [],
    Duration bargeInDelay = const Duration(milliseconds: 1),
    Duration listenOnceDelay = const Duration(milliseconds: 1),
    String permissionStatus = 'granted',
    bool recordingInProgress = false,
  }) : _wakeTexts = Queue<String?>.of(wakeTexts),
       _utteranceTexts = Queue<String?>.of(utteranceTexts),
       _bargeInResults = Queue<BargeInResult>.of(bargeInResults),
       _bargeInDelay = bargeInDelay,
       _listenOnceDelay = listenOnceDelay,
       _permissionStatus = permissionStatus,
       _recordingInProgress = recordingInProgress;

  final Queue<String?> _wakeTexts;
  final Queue<String?> _utteranceTexts;
  final Queue<BargeInResult> _bargeInResults;
  final Duration _bargeInDelay;
  final Duration _listenOnceDelay;
  final String _permissionStatus;
  final bool _recordingInProgress;
  VoiceDebugSnapshot _snapshot = VoiceDebugSnapshot();
  int listenOnceCalls = 0;

  @override
  VoiceDebugSnapshot get latestDebugSnapshot => _snapshot;

  @override
  Future<String> microphonePermissionStatus() async => _permissionStatus;

  @override
  Future<String?> listenOnce({
    Duration listenFor = const Duration(seconds: 5),
  }) async {
    listenOnceCalls++;
    await Future<void>.delayed(_listenOnceDelay);
    final text = _wakeTexts.isEmpty ? null : _wakeTexts.removeFirst();
    _snapshot = _snapshot.copyWith(
      normalizedText: text ?? '',
      rawText: text ?? '',
      recordReason: _recordingInProgress
          ? 'recording_in_progress'
          : 'max_duration',
      recordingInProgress: _recordingInProgress,
      runtimeWarning: _recordingInProgress ? 'recording_in_progress' : '',
    );
    return text;
  }

  @override
  Future<String?> listenForUtterance({
    Duration maxDuration = const Duration(seconds: 12),
    Duration silenceTimeout = const Duration(milliseconds: 1200),
    Duration startTimeout = const Duration(seconds: 3),
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    return _utteranceTexts.isEmpty ? null : _utteranceTexts.removeFirst();
  }

  @override
  Future<BargeInResult> listenForBargeIn(BargeInConfig config) async {
    await Future<void>.delayed(_bargeInDelay);
    return _bargeInResults.isEmpty
        ? const BargeInResult(
            detected: false,
            durationMs: 0,
            speechDurationMs: 0,
            avgRms: 0,
            maxRms: 0,
            speechLikeRatio: 0,
            reason: 'max_duration',
          )
        : _bargeInResults.removeFirst();
  }

  @override
  Future<void> stop() async {}
}

class _FakeWakeDetector implements WakeDetector {
  _FakeWakeDetector({required List<WakeDetectorEvent> eventsToEmit})
    : _eventsToEmit = Queue<WakeDetectorEvent>.of(eventsToEmit);

  final Queue<WakeDetectorEvent> _eventsToEmit;
  final _controller = StreamController<WakeDetectorEvent>.broadcast();
  bool _disposed = false;

  @override
  WakeDetectorType get type => WakeDetectorType.stt;

  @override
  Stream<WakeDetectorEvent> get events => _controller.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> detectOnce() async {
    if (_disposed || _eventsToEmit.isEmpty) {
      return;
    }
    _controller.add(_eventsToEmit.removeFirst());
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _controller.close();
  }
}

import 'dart:async';
import 'dart:typed_data';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_companion/features/voice/sherpa_onnx_wake_detector.dart';
import 'package:pocket_companion/features/voice/wake_detector.dart';
import 'package:pocket_companion/features/voice/wake_detector_type.dart';

class Fallback implements WakeDetector {
  final output = StreamController<WakeDetectorEvent>.broadcast();
  int starts = 0;
  int rounds = 0;
  @override
  WakeDetectorType get type => WakeDetectorType.stt;
  @override
  Stream<WakeDetectorEvent> get events => output.stream;
  @override
  Future<void> start() async {
    starts++;
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> detectOnce() async {
    rounds++;
  }

  @override
  Future<void> dispose() => output.close();
}

class FakeStream implements sherpa.OnlineStream {
  @override
  void acceptWaveform({
    required Float32List samples,
    required int sampleRate,
  }) {}
  @override
  void free() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSpotter implements sherpa.KeywordSpotter {
  int decoded = 0;
  int resets = 0;
  @override
  bool isReady(sherpa.OnlineStream stream) => decoded < 2;
  @override
  void decode(sherpa.OnlineStream stream) {
    decoded++;
  }

  @override
  sherpa.KeywordResult getResult(sherpa.OnlineStream stream) =>
      sherpa.KeywordResult(keyword: decoded == 1 ? '萌萌' : '');
  @override
  void reset(sherpa.OnlineStream stream) {
    resets++;
  }

  @override
  void free() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const control = MethodChannel('test/wake/control');
  const audio = EventChannel('test/wake/audio');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    messenger.setMockMethodCallHandler(
      const MethodChannel('test/wake/audio'),
      (_) async => null,
    );
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(control, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('test/wake/audio'),
      null,
    );
  });
  test(
    'reads each decode result before a later chunk can replace it',
    () async {
      messenger.setMockMethodCallHandler(
        control,
        (call) async => call.method == 'start' ? {'started': true} : null,
      );
      final spotter = FakeSpotter();
      final detector = SherpaOnnxWakeDetector(
        controlChannel: control,
        audioChannel: audio,
        initialize: () async {},
        spotter: spotter,
        stream: FakeStream(),
      );
      final events = <WakeDetectorEvent>[];
      final subscription = detector.events.listen(events.add);
      await detector.start();
      final pcm = Uint8List(32000);
      for (var i = 0; i < pcm.length; i += 2) {
        pcm[i + 1] = 1;
      }
      await messenger.handlePlatformMessage(
        'test/wake/audio',
        const StandardMethodCodec().encodeSuccessEnvelope(pcm),
        (_) {},
      );
      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<WakeDetectorDetected>().single.wakeWord, '萌萌');
      expect(events.whereType<WakeDetectorAudio>().single.avgRms, 256);
      expect(spotter.decoded, 1);
      await detector.dispose();
      await subscription.cancel();
    },
  );
  test('started but stalled audio switches to fallback', () async {
    final fallback = Fallback();
    messenger.setMockMethodCallHandler(
      control,
      (call) async => call.method == 'start' ? {'started': true} : null,
    );
    final detector = SherpaOnnxWakeDetector(
      controlChannel: control,
      audioChannel: audio,
      fallback: fallback,
      initialize: () async {},
    );
    await detector.start();
    await Future<void>.delayed(const Duration(milliseconds: 6200));
    await detector.detectOnce();
    expect(fallback.starts, 1);
    await detector.dispose();
  });
  test(
    'dispose waits for initialization without starting native recording',
    () async {
      final ready = Completer<void>();
      final calls = <String>[];
      messenger.setMockMethodCallHandler(control, (call) async {
        calls.add(call.method);
        return {'started': true};
      });
      final detector = SherpaOnnxWakeDetector(
        controlChannel: control,
        audioChannel: audio,
        initialize: () => ready.future,
      );
      final pending = detector.start();
      final disposed = detector.dispose();
      ready.complete();
      await pending;
      await disposed;
      expect(calls, isEmpty);
    },
  );
  test('native start false releases recorder and uses STT fallback', () async {
    final fallback = Fallback();
    final calls = <String>[];
    messenger.setMockMethodCallHandler(control, (call) async {
      calls.add(call.method);
      return call.method == 'start'
          ? {'started': false, 'reason': 'recording_busy'}
          : null;
    });
    final detector = SherpaOnnxWakeDetector(
      fallback: fallback,
      controlChannel: control,
      audioChannel: audio,
      initialize: () async {},
    );
    await detector.start();
    await detector.detectOnce();
    expect(calls, ['start', 'stop']);
    expect(fallback.starts, 1);
    expect(fallback.rounds, 1);
    await detector.dispose();
  });
  test('stop while models initialize prevents late recorder start', () async {
    final ready = Completer<void>();
    final calls = <String>[];
    messenger.setMockMethodCallHandler(control, (call) async {
      calls.add(call.method);
      return {'started': true};
    });
    final detector = SherpaOnnxWakeDetector(
      controlChannel: control,
      audioChannel: audio,
      initialize: () => ready.future,
    );
    final pending = detector.start();
    await detector.stop();
    ready.complete();
    await pending;
    expect(calls, isEmpty);
    await detector.dispose();
  });
  test(
    'audio stream error activates fallback instead of staying silently armed',
    () async {
      final fallback = Fallback();
      messenger.setMockMethodCallHandler(
        control,
        (call) async => call.method == 'start' ? {'started': true} : null,
      );
      final detector = SherpaOnnxWakeDetector(
        fallback: fallback,
        controlChannel: control,
        audioChannel: audio,
        initialize: () async {},
      );
      await detector.start();
      await messenger.handlePlatformMessage(
        'test/wake/audio',
        const StandardMethodCodec().encodeErrorEnvelope(
          code: 'audio_failed',
          message: 'read failed',
        ),
        (_) {},
      );
      await Future<void>.delayed(Duration.zero);
      await detector.detectOnce();
      expect(fallback.starts, 1);
      expect(fallback.rounds, 1);
      await detector.dispose();
    },
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_companion/features/voice/native_wake_detector_stub.dart';
import 'package:pocket_companion/features/voice/wake_detector.dart';
import 'package:pocket_companion/features/voice/wake_detector_type.dart';

void main() {
  test('WakeDetectorType defaults can use stt', () {
    expect(WakeDetectorType.stt.name, 'stt');
  });

  test('NativeWakeDetectorStub emits not implemented error', () async {
    final detector = NativeWakeDetectorStub(WakeDetectorType.sherpaOnnx);
    final events = <WakeDetectorEvent>[];
    final sub = detector.events.listen(events.add);

    await detector.detectOnce();
    await Future<void>.delayed(Duration.zero);

    final error = events.whereType<WakeDetectorError>().single;
    expect(error.reason, 'sherpaOnnx_not_implemented');

    await sub.cancel();
    await detector.dispose();
  });
}

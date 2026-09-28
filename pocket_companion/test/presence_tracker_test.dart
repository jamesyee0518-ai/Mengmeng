import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_companion/features/vision/face_observation.dart';
import 'package:pocket_companion/features/vision/presence_tracker.dart';

FaceObservation obs({
  required int at,
  bool detected = false,
  int faceCount = 0,
}) {
  final seconds = at;
  return FaceObservation(
    timestamp: DateTime(2026, 1, 1, 10, 0, seconds),
    detected: detected,
    faceCount: faceCount,
  );
}

void main() {

  test('单帧人脸不触发在场，需连续帧去抖', () {
    final tracker = PresenceTracker(presentDebounceFrames: 2);

    final first = tracker.update(obs(at: 0, detected: true));
    expect(first, isNull);

    final second = tracker.update(obs(at: 1, detected: true));
    expect(second?.type, VisionPresenceEventType.userPresent);
  });

  test('首次在场为 userPresent，长时间离开后回来为 userReturned', () {
    final tracker = PresenceTracker(
      presentDebounceFrames: 1,
      returnedThreshold: const Duration(seconds: 30),
    );

    tracker.update(obs(at: 0, detected: true));
    expect(tracker.isPresent, isTrue);

    final absent = tracker.update(obs(at: 5));
    expect(absent?.type, VisionPresenceEventType.userAbsent);

    final returned = tracker.update(obs(at: 600, detected: true));
    expect(returned?.type, VisionPresenceEventType.userReturned);
    expect(returned!.absentDuration.inSeconds, greaterThan(30));
  });

  test('在场后短于超时的无人帧不触发离开', () {
    final tracker = PresenceTracker(
      presentDebounceFrames: 1,
      absentTimeout: const Duration(seconds: 3),
    );

    tracker.update(obs(at: 0, detected: true));
    final stillHere = tracker.update(obs(at: 2));
    expect(stillHere, isNull);

    final gone = tracker.update(obs(at: 4));
    expect(gone?.type, VisionPresenceEventType.userAbsent);
  });

  test('presentCooldown 抑制抖动产生的重复在场事件', () {
    final tracker = PresenceTracker(
      presentDebounceFrames: 1,
      absentTimeout: const Duration(seconds: 1),
      presentCooldown: const Duration(seconds: 60),
    );

    tracker.update(obs(at: 0, detected: true));
    tracker.update(obs(at: 2)); // absent
    final flapping = tracker.update(obs(at: 3, detected: true));
    expect(flapping, isNull);
    expect(tracker.isPresent, isTrue);
  });

  test('reset 后重新累计在场判定', () {
    final tracker = PresenceTracker(presentDebounceFrames: 1);

    tracker.update(obs(at: 0, detected: true));
    expect(tracker.isPresent, isTrue);

    tracker.reset();
    expect(tracker.isPresent, isFalse);

    final again = tracker.update(obs(at: 100, detected: true));
    expect(again?.type, VisionPresenceEventType.userPresent);
  });
}

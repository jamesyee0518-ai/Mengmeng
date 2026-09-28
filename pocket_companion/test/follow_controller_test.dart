import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_companion/features/gimbal/follow_controller.dart';
import 'package:pocket_companion/features/gimbal/gimbal_models.dart';

void main() {
  DateTime at(int seconds, [int ms = 0]) =>
      DateTime(2026, 1, 1, 10, 0, seconds, ms);

  group('FollowController tracking', () {
    test('目标在死区内时输出零速', () {
      final controller = FollowController();
      final command = controller.update(
        faceDetected: true,
        offsetX: 0.05,
        offsetY: 0.08,
        now: at(0),
      );

      expect(command.phase, FollowPhase.tracking);
      expect(command.yawDps, 0);
      expect(command.pitchDps, 0);
    });

    test('目标偏右时云台向右转，速度与偏差成正比', () {
      final controller = FollowController();
      final command = controller.update(
        faceDetected: true,
        offsetX: 0.3,
        offsetY: 0,
        now: at(0),
      );

      expect(command.yawDps, greaterThan(0));
      expect(command.pitchDps, 0);
    });

    test('速度输出被限幅', () {
      final controller = FollowController();
      final command = controller.update(
        faceDetected: true,
        offsetX: 0.5,
        offsetY: -0.5,
        now: at(0),
      );

      expect(command.yawDps, controller.config.maxYawDps);
      expect(command.pitchDps, -controller.config.maxPitchDps);
    });

    test('mirrorYaw 翻转水平方向', () {
      final controller = FollowController(
        config: const FollowConfig(mirrorYaw: true),
      );
      final command = controller.update(
        faceDetected: true,
        offsetX: 0.3,
        offsetY: 0,
        now: at(0),
      );

      expect(command.yawDps, lessThan(0));
    });
  });

  group('FollowController 丢失目标', () {
    test('未见目标时保持 idle 零速', () {
      final controller = FollowController();
      final command = controller.update(
        faceDetected: false,
        now: at(0),
      );

      expect(command.phase, FollowPhase.idle);
      expect(command.isNeutral, isTrue);
    });

    test('短暂丢失进入 holding 静止', () {
      final controller = FollowController();
      controller.update(faceDetected: true, now: at(0));
      final command = controller.update(
        faceDetected: false,
        now: at(1),
      );

      expect(command.phase, FollowPhase.holding);
      expect(command.isNeutral, isTrue);
    });

    test('持续丢失进入 scanning 慢速扫描', () {
      final controller = FollowController();
      controller.update(faceDetected: true, now: at(0));
      final command = controller.update(
        faceDetected: false,
        now: at(3),
      );

      expect(command.phase, FollowPhase.scanning);
      expect(command.yawDps.abs(), controller.config.scanDps);
      expect(command.pitchDps, 0);
    });

    test('扫描方向按间隔往复翻转', () {
      final controller = FollowController();
      controller.update(faceDetected: true, now: at(0));
      final first = controller.update(faceDetected: false, now: at(3));
      final second = controller.update(
        faceDetected: false,
        now: at(3, 500),
      );
      final third = controller.update(
        faceDetected: false,
        now: at(5, 500),
      );

      expect(second.yawDps, first.yawDps);
      expect(third.yawDps, -first.yawDps);
    });

    test('超过放弃时长后停止转动并进入 lost', () {
      final controller = FollowController();
      controller.update(faceDetected: true, now: at(0));
      final command = controller.update(
        faceDetected: false,
        now: at(35),
      );

      expect(command.phase, FollowPhase.lost);
      expect(command.isNeutral, isTrue);
    });

    test('重新看到目标立即恢复 tracking', () {
      final controller = FollowController();
      controller.update(faceDetected: true, now: at(0));
      controller.update(faceDetected: false, now: at(10));
      final command = controller.update(
        faceDetected: true,
        offsetX: -0.2,
        offsetY: 0,
        now: at(11),
      );

      expect(command.phase, FollowPhase.tracking);
      expect(command.yawDps, lessThan(0));
    });
  });
}

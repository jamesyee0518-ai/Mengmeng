import 'dart:async';

import 'gimbal_models.dart';

/// 非 io 平台（Web）的空实现：始终不可用。
class GimbalService {
  final bool isSupported = false;

  GimbalDeviceState get deviceState => const GimbalDeviceState(
    phase: GimbalPhase.idle,
  );

  Stream<GimbalDeviceState> get deviceStates => const Stream.empty();

  Stream<GimbalAttitude> get attitudes => const Stream.empty();

  Stream<String> get errors => const Stream.empty();

  Future<GimbalDeviceState> register() async => deviceState;

  Future<GimbalDeviceState> connectBluetooth() async => deviceState;

  Future<void> setVelocity({required double yawDps, required double pitchDps}) async {}

  Future<void> stop() async {}

  Future<void> rotateTo({
    required double yawDeg,
    required double pitchDeg,
    int durationMs = 800,
  }) async {}

  Future<void> center() async {}

  Future<void> dispose() async {}
}

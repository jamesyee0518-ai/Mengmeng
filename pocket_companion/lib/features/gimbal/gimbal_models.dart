import 'package:flutter/foundation.dart';

/// 云台设备连接阶段，对应原生层 DjiGimbalPlugin 推送的 phase 字符串。
enum GimbalPhase {
  idle,
  registering,
  registered,
  connecting,
  connected,
  connectedNoGimbal,
  disconnected,
  error;

  static GimbalPhase fromName(String? name) {
    return GimbalPhase.values.firstWhere(
      (phase) => phase.name == name,
      orElse: () => GimbalPhase.idle,
    );
  }
}

@immutable
class GimbalDeviceState {
  const GimbalDeviceState({
    required this.phase,
    this.model = '',
    this.hasGimbal = false,
  });

  final GimbalPhase phase;
  final String model;
  final bool hasGimbal;

  bool get isControllable => phase == GimbalPhase.connected && hasGimbal;
}

@immutable
class GimbalAttitude {
  const GimbalAttitude({
    required this.pitchDeg,
    required this.yawDeg,
    required this.rollDeg,
    required this.timestamp,
  });

  final double pitchDeg;
  final double yawDeg;
  final double rollDeg;
  final DateTime timestamp;
}

/// FollowController 输出的云台速度指令（度/秒）。
@immutable
class FollowCommand {
  const FollowCommand({
    required this.phase,
    required this.yawDps,
    required this.pitchDps,
    this.offsetX = 0,
    this.offsetY = 0,
  });

  final FollowPhase phase;
  final double yawDps;
  final double pitchDps;

  /// 最近一次目标偏差（诊断用，归一化 -0.5..0.5）。
  final double offsetX;
  final double offsetY;

  bool get isNeutral => yawDps == 0 && pitchDps == 0;
}

enum FollowPhase { idle, tracking, holding, scanning, lost }

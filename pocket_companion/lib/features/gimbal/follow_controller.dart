import 'gimbal_models.dart';

/// 人物跟随闭环参数。
///
/// 输入为人脸框中心相对画面中心的归一化偏差（-0.5..0.5），
/// 输出为云台速度指令（度/秒），以检测帧率（约 5-10Hz）持续下发。
class FollowConfig {
  const FollowConfig({
    this.deadbandX = 0.08,
    this.deadbandY = 0.10,
    this.kpYaw = 70.0,
    this.kpPitch = 45.0,
    this.maxYawDps = 30.0,
    this.maxPitchDps = 18.0,
    /// 前置摄像头镜像时水平方向取反（真机标定一次即可）。
    this.mirrorYaw = false,
    /// 俯仰方向符号取决于云台安装姿态（真机标定）。
    this.invertPitch = false,
    this.holdTimeout = const Duration(milliseconds: 1500),
    this.scanDelay = const Duration(milliseconds: 500),
    this.scanDps = 8.0,
    this.scanInterval = const Duration(seconds: 2),
    this.giveUpTimeout = const Duration(seconds: 30),
  });

  final double deadbandX;
  final double deadbandY;
  final double kpYaw;
  final double kpPitch;
  final double maxYawDps;
  final double maxPitchDps;
  final bool mirrorYaw;
  final bool invertPitch;
  final Duration holdTimeout;
  final Duration scanDelay;
  final double scanDps;
  final Duration scanInterval;
  final Duration giveUpTimeout;
}

/// 目标丢失处理状态机：
/// tracking（有人脸）→ holding（短暂遮挡保持静止）→ scanning（慢速扫描找回）
/// → lost（超过 giveUpTimeout，静止等待上层降级）。
class FollowController {
  FollowController({this.config = const FollowConfig()});

  final FollowConfig config;

  DateTime? _lastSeenAt;
  DateTime? _scanStartedAt;
  DateTime? _lastScanFlipAt;
  int _scanDirection = 1;
  FollowPhase _phase = FollowPhase.idle;

  FollowPhase get phase => _phase;

  /// 是否重新看到目标（用于复位扫描方向等外部状态）。
  bool get hadSight => _lastSeenAt != null;

  /// 输入一帧观测，输出云台速度指令。
  FollowCommand update({
    required bool faceDetected,
    double offsetX = 0,
    double offsetY = 0,
    required DateTime now,
  }) {
    if (faceDetected) {
      _lastSeenAt = now;
      _scanStartedAt = null;
      _lastScanFlipAt = null;
      return _track(offsetX, offsetY);
    }
    return _noFace(now);
  }

  FollowCommand _track(double offsetX, double offsetY) {
    _phase = FollowPhase.tracking;
    final inDeadband = offsetX.abs() < config.deadbandX &&
        offsetY.abs() < config.deadbandY;
    if (inDeadband) {
      return FollowCommand(
        phase: _phase,
        yawDps: 0,
        pitchDps: 0,
        offsetX: offsetX,
        offsetY: offsetY,
      );
    }
    final yawSign = config.mirrorYaw ? -1.0 : 1.0;
    final pitchSign = config.invertPitch ? -1.0 : 1.0;
    return FollowCommand(
      phase: _phase,
      yawDps: _clamp(config.kpYaw * offsetX * yawSign, config.maxYawDps),
      pitchDps: _clamp(
        config.kpPitch * offsetY * pitchSign,
        config.maxPitchDps,
      ),
      offsetX: offsetX,
      offsetY: offsetY,
    );
  }

  FollowCommand _noFace(DateTime now) {
    final lastSeen = _lastSeenAt;
    if (lastSeen == null) {
      _phase = FollowPhase.idle;
      return FollowCommand(phase: _phase, yawDps: 0, pitchDps: 0);
    }
    final elapsed = now.difference(lastSeen);
    if (elapsed < config.holdTimeout) {
      _phase = FollowPhase.holding;
      return FollowCommand(phase: _phase, yawDps: 0, pitchDps: 0);
    }
    if (elapsed > config.giveUpTimeout) {
      _phase = FollowPhase.lost;
      return FollowCommand(phase: _phase, yawDps: 0, pitchDps: 0);
    }
    // 丢失后先静默等待 scanDelay，再开始慢速往复扫描。
    final scanElapsed = elapsed - config.holdTimeout;
    if (scanElapsed < config.scanDelay) {
      _phase = FollowPhase.holding;
      return FollowCommand(phase: _phase, yawDps: 0, pitchDps: 0);
    }
    _phase = FollowPhase.scanning;
    final scanStarted = _scanStartedAt ??= now;
    final flipAnchor = _lastScanFlipAt ?? scanStarted;
    if (now.difference(flipAnchor) >= config.scanInterval) {
      _scanDirection = -_scanDirection;
      _lastScanFlipAt = now;
    }
    return FollowCommand(
      phase: _phase,
      yawDps: config.scanDps * _scanDirection,
      pitchDps: 0,
    );
  }

  /// 重置状态（停止跟随时调用）。
  void reset() {
    _lastSeenAt = null;
    _scanStartedAt = null;
    _lastScanFlipAt = null;
    _scanDirection = 1;
    _phase = FollowPhase.idle;
  }

  static double _clamp(double value, double limit) {
    if (value > limit) {
      return limit;
    }
    if (value < -limit) {
      return -limit;
    }
    return value;
  }
}

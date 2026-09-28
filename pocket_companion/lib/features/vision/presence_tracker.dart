import 'face_observation.dart';

enum VisionPresenceEventType { userPresent, userAbsent, userReturned }

/// 视觉在场事件（对应文档 10A.6 的 vision.user_present / user_absent /
/// user_returned，事件名沿用 person_seen / person_left 的网关语义）。
class VisionPresenceEvent {
  const VisionPresenceEvent({
    required this.type,
    this.absentDuration = Duration.zero,
    required this.timestamp,
  });

  final VisionPresenceEventType type;

  /// userReturned/userAbsent 时距离上一次在场的时长。
  final Duration absentDuration;

  final DateTime timestamp;
}

/// 把连续的人脸观测去抖为在场/离开事件：
/// - 连续 [presentDebounceFrames] 帧检测到人脸 → 在场（回来超过
///   [returnedThreshold] 则发 userReturned，否则 userPresent）；
/// - 在场后超过 [absentTimeout] 未见人脸 → 离开；
/// - 两次在场事件之间至少间隔 [presentCooldown]，避免抖动。
class PresenceTracker {
  PresenceTracker({
    this.presentDebounceFrames = 2,
    this.absentTimeout = const Duration(seconds: 3),
    this.returnedThreshold = const Duration(seconds: 30),
    this.presentCooldown = const Duration(seconds: 10),
  });

  final int presentDebounceFrames;
  final Duration absentTimeout;
  final Duration returnedThreshold;
  final Duration presentCooldown;

  bool _isPresent = false;
  int _consecutiveDetected = 0;
  DateTime? _lastFaceAt;
  DateTime? _lastPresentEventAt;
  DateTime? _absentSince;

  bool get isPresent => _isPresent;

  /// 重置状态（停止跟随/守望时调用），下次开启后重新累计在场判定。
  void reset() {
    _isPresent = false;
    _consecutiveDetected = 0;
    _lastFaceAt = null;
    _lastPresentEventAt = null;
    _absentSince = null;
  }

  VisionPresenceEvent? update(FaceObservation observation) {
    final now = observation.timestamp;
    if (observation.detected) {
      _lastFaceAt = now;
      _consecutiveDetected += 1;
      if (!_isPresent && _consecutiveDetected >= presentDebounceFrames) {
        final cooldownElapsed = _lastPresentEventAt == null ||
            now.difference(_lastPresentEventAt!) >= presentCooldown;
        if (cooldownElapsed) {
          final awayFor = _absentSince == null
              ? Duration.zero
              : now.difference(_absentSince!);
          _isPresent = true;
          _lastPresentEventAt = now;
          return VisionPresenceEvent(
            type: awayFor >= returnedThreshold
                ? VisionPresenceEventType.userReturned
                : VisionPresenceEventType.userPresent,
            absentDuration: awayFor,
            timestamp: now,
          );
        }
        _isPresent = true;
      }
      return null;
    }

    _consecutiveDetected = 0;
    if (!_isPresent) {
      return null;
    }
    final lastFace = _lastFaceAt;
    if (lastFace == null || now.difference(lastFace) < absentTimeout) {
      return null;
    }
    _isPresent = false;
    _absentSince = now;
    return VisionPresenceEvent(
      type: VisionPresenceEventType.userAbsent,
      absentDuration: now.difference(lastFace),
      timestamp: now,
    );
  }
}

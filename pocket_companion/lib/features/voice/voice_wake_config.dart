import 'wake_detector_type.dart';

class VoiceWakeConfig {
  const VoiceWakeConfig({
    this.wakeDetectorType = WakeDetectorType.stt,
    this.monitoringListenDuration = const Duration(seconds: 3),
    this.monitoringLoopDelay = const Duration(milliseconds: 800),
    this.conversationMaxDuration = const Duration(seconds: 12),
    this.conversationSilenceTimeout = const Duration(milliseconds: 1200),
    this.conversationStartTimeout = const Duration(seconds: 3),
    this.conversationIdleTimeout = const Duration(seconds: 15),
    this.wakeCooldown = const Duration(seconds: 2),
    this.ttsCooldown = const Duration(milliseconds: 800),
    this.wakeScoreThreshold = 0.85,
  });

  final WakeDetectorType wakeDetectorType;
  final Duration monitoringListenDuration;
  final Duration monitoringLoopDelay;
  final Duration conversationMaxDuration;
  final Duration conversationSilenceTimeout;
  final Duration conversationStartTimeout;
  final Duration conversationIdleTimeout;
  final Duration wakeCooldown;
  final Duration ttsCooldown;
  final double wakeScoreThreshold;

  factory VoiceWakeConfig.fromJson(Object? value) {
    if (value is! Map) {
      return const VoiceWakeConfig();
    }
    return VoiceWakeConfig(
      wakeDetectorType: _detectorTypeValue(value['wakeDetectorType']),
      monitoringListenDuration: Duration(
        milliseconds: _intValue(value['monitoringListenDurationMs'], 3000),
      ),
      monitoringLoopDelay: Duration(
        milliseconds: _intValue(value['monitoringLoopDelayMs'], 800),
      ),
      conversationMaxDuration: Duration(
        milliseconds: _intValue(value['conversationMaxDurationMs'], 12000),
      ),
      conversationSilenceTimeout: Duration(
        milliseconds: _intValue(value['conversationSilenceTimeoutMs'], 1200),
      ),
      conversationStartTimeout: Duration(
        milliseconds: _intValue(value['conversationStartTimeoutMs'], 3000),
      ),
      conversationIdleTimeout: Duration(
        milliseconds: _intValue(value['conversationIdleTimeoutMs'], 15000),
      ),
      wakeCooldown: Duration(
        milliseconds: _intValue(value['wakeCooldownMs'], 2000),
      ),
      ttsCooldown: Duration(
        milliseconds: _intValue(value['ttsCooldownMs'], 800),
      ),
      wakeScoreThreshold: _doubleValue(value['wakeScoreThreshold'], 0.85),
    );
  }

  VoiceWakeConfig copyWith({
    WakeDetectorType? wakeDetectorType,
    Duration? monitoringListenDuration,
    Duration? monitoringLoopDelay,
    Duration? conversationMaxDuration,
    Duration? conversationSilenceTimeout,
    Duration? conversationStartTimeout,
    Duration? conversationIdleTimeout,
    Duration? wakeCooldown,
    Duration? ttsCooldown,
    double? wakeScoreThreshold,
  }) {
    return VoiceWakeConfig(
      wakeDetectorType: wakeDetectorType ?? this.wakeDetectorType,
      monitoringListenDuration:
          monitoringListenDuration ?? this.monitoringListenDuration,
      monitoringLoopDelay: monitoringLoopDelay ?? this.monitoringLoopDelay,
      conversationMaxDuration:
          conversationMaxDuration ?? this.conversationMaxDuration,
      conversationSilenceTimeout:
          conversationSilenceTimeout ?? this.conversationSilenceTimeout,
      conversationStartTimeout:
          conversationStartTimeout ?? this.conversationStartTimeout,
      conversationIdleTimeout:
          conversationIdleTimeout ?? this.conversationIdleTimeout,
      wakeCooldown: wakeCooldown ?? this.wakeCooldown,
      ttsCooldown: ttsCooldown ?? this.ttsCooldown,
      wakeScoreThreshold: wakeScoreThreshold ?? this.wakeScoreThreshold,
    );
  }

  Map<String, Object> toJson() {
    return {
      'wakeDetectorType': wakeDetectorType.name,
      'monitoringListenDurationMs': monitoringListenDuration.inMilliseconds,
      'monitoringLoopDelayMs': monitoringLoopDelay.inMilliseconds,
      'conversationMaxDurationMs': conversationMaxDuration.inMilliseconds,
      'conversationSilenceTimeoutMs': conversationSilenceTimeout.inMilliseconds,
      'conversationStartTimeoutMs': conversationStartTimeout.inMilliseconds,
      'conversationIdleTimeoutMs': conversationIdleTimeout.inMilliseconds,
      'wakeCooldownMs': wakeCooldown.inMilliseconds,
      'ttsCooldownMs': ttsCooldown.inMilliseconds,
      'wakeScoreThreshold': wakeScoreThreshold,
    };
  }
}

WakeDetectorType _detectorTypeValue(Object? value) {
  if (value is String) {
    return WakeDetectorType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => WakeDetectorType.stt,
    );
  }
  return WakeDetectorType.stt;
}

int _intValue(Object? value, int fallback) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return fallback;
}

double _doubleValue(Object? value, double fallback) {
  if (value is num) {
    return value.toDouble();
  }
  return fallback;
}

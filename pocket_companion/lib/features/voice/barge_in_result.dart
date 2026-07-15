class BargeInResult {
  const BargeInResult({
    required this.detected,
    required this.durationMs,
    required this.speechDurationMs,
    required this.avgRms,
    required this.maxRms,
    required this.speechLikeRatio,
    required this.reason,
  });

  factory BargeInResult.fromJson(Object? value) {
    if (value is! Map) {
      return const BargeInResult(
        detected: false,
        durationMs: 0,
        speechDurationMs: 0,
        avgRms: 0,
        maxRms: 0,
        speechLikeRatio: 0,
        reason: 'invalid_result',
      );
    }
    return BargeInResult(
      detected: value['detected'] == true,
      durationMs: _intValue(value['durationMs']),
      speechDurationMs: _intValue(value['speechDurationMs']),
      avgRms: _doubleValue(value['avgRms']),
      maxRms: _doubleValue(value['maxRms']),
      speechLikeRatio: _doubleValue(value['speechLikeRatio']),
      reason: _stringValue(value['reason']),
    );
  }

  final bool detected;
  final int durationMs;
  final int speechDurationMs;
  final double avgRms;
  final double maxRms;
  final double speechLikeRatio;
  final String reason;

  Map<String, Object> toJson() {
    return {
      'detected': detected,
      'durationMs': durationMs,
      'speechDurationMs': speechDurationMs,
      'avgRms': avgRms,
      'maxRms': maxRms,
      'speechLikeRatio': speechLikeRatio,
      'reason': reason,
    };
  }
}

String _stringValue(Object? value) => value is String ? value : '';

int _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return 0;
}

double _doubleValue(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return 0;
}

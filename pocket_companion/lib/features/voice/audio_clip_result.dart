class AudioClipResult {
  const AudioClipResult({
    required this.path,
    required this.durationMs,
    required this.speechDurationMs,
    required this.avgRms,
    required this.maxRms,
    required this.speechLikeRatio,
    required this.hasSpeechLikeAudio,
    required this.reason,
  });

  factory AudioClipResult.fromPlatformResult(Object? value) {
    if (value is String) {
      return AudioClipResult(
        path: value,
        durationMs: 0,
        speechDurationMs: 0,
        avgRms: 0,
        maxRms: 0,
        speechLikeRatio: 0,
        hasSpeechLikeAudio: true,
        reason: 'legacy_path',
      );
    }
    if (value is Map) {
      return AudioClipResult(
        path: _stringValue(value['path']),
        durationMs: _intValue(value['durationMs']),
        speechDurationMs: _intValue(value['speechDurationMs']),
        avgRms: _doubleValue(value['avgRms']),
        maxRms: _doubleValue(value['maxRms']),
        speechLikeRatio: _doubleValue(value['speechLikeRatio']),
        hasSpeechLikeAudio: value['hasSpeechLikeAudio'] == true,
        reason: _stringValue(value['reason']),
      );
    }
    return const AudioClipResult.empty(reason: 'invalid_platform_result');
  }

  const AudioClipResult.empty({required this.reason})
    : path = '',
      durationMs = 0,
      speechDurationMs = 0,
      avgRms = 0,
      maxRms = 0,
      speechLikeRatio = 0,
      hasSpeechLikeAudio = false;

  final String path;
  final int durationMs;
  final int speechDurationMs;
  final double avgRms;
  final double maxRms;
  final double speechLikeRatio;
  final bool hasSpeechLikeAudio;
  final String reason;

  bool get isLegacy => reason == 'legacy_path';
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

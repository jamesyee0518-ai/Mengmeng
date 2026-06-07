class VoiceAudioGateConfig {
  const VoiceAudioGateConfig({
    this.minDurationMs = 600,
    this.minAvgRms = 80,
    this.minMaxRms = 400,
    this.minSpeechLikeRatio = 0.08,
  });

  final int minDurationMs;
  final double minAvgRms;
  final double minMaxRms;
  final double minSpeechLikeRatio;

  factory VoiceAudioGateConfig.fromJson(Object? value) {
    if (value is! Map) {
      return const VoiceAudioGateConfig();
    }
    return VoiceAudioGateConfig(
      minDurationMs: _intValue(value['minDurationMs'], 600),
      minAvgRms: _doubleValue(value['minAvgRms'], 80),
      minMaxRms: _doubleValue(value['minMaxRms'], 400),
      minSpeechLikeRatio: _doubleValue(value['minSpeechLikeRatio'], 0.08),
    );
  }

  VoiceAudioGateConfig copyWith({
    int? minDurationMs,
    double? minAvgRms,
    double? minMaxRms,
    double? minSpeechLikeRatio,
  }) {
    return VoiceAudioGateConfig(
      minDurationMs: minDurationMs ?? this.minDurationMs,
      minAvgRms: minAvgRms ?? this.minAvgRms,
      minMaxRms: minMaxRms ?? this.minMaxRms,
      minSpeechLikeRatio: minSpeechLikeRatio ?? this.minSpeechLikeRatio,
    );
  }

  Map<String, Object> toJson() {
    return {
      'minDurationMs': minDurationMs,
      'minAvgRms': minAvgRms,
      'minMaxRms': minMaxRms,
      'minSpeechLikeRatio': minSpeechLikeRatio,
    };
  }
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

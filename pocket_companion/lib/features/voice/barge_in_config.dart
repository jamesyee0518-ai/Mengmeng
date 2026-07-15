class BargeInConfig {
  const BargeInConfig({
    this.enabled = true,
    this.maxDuration = const Duration(seconds: 10),
    this.minSpeechDuration = const Duration(milliseconds: 400),
    this.minAvgRms = 180,
    this.minMaxRms = 1200,
    this.minSpeechLikeRatio = 0.18,
    this.postTtsStartGracePeriod = const Duration(milliseconds: 500),
  });

  final bool enabled;
  final Duration maxDuration;
  final Duration minSpeechDuration;
  final double minAvgRms;
  final double minMaxRms;
  final double minSpeechLikeRatio;
  final Duration postTtsStartGracePeriod;

  factory BargeInConfig.fromJson(Object? value) {
    if (value is! Map) {
      return const BargeInConfig();
    }
    return BargeInConfig(
      enabled: value['enabled'] is bool ? value['enabled'] as bool : true,
      maxDuration: Duration(
        milliseconds: _intValue(value['maxDurationMs'], 10000),
      ),
      minSpeechDuration: Duration(
        milliseconds: _intValue(value['minSpeechMs'], 400),
      ),
      minAvgRms: _doubleValue(value['minAvgRms'], 180),
      minMaxRms: _doubleValue(value['minMaxRms'], 1200),
      minSpeechLikeRatio: _doubleValue(value['minSpeechLikeRatio'], 0.18),
      postTtsStartGracePeriod: Duration(
        milliseconds: _intValue(value['postTtsStartGracePeriodMs'], 500),
      ),
    );
  }

  BargeInConfig copyWith({
    bool? enabled,
    Duration? maxDuration,
    Duration? minSpeechDuration,
    double? minAvgRms,
    double? minMaxRms,
    double? minSpeechLikeRatio,
    Duration? postTtsStartGracePeriod,
  }) {
    return BargeInConfig(
      enabled: enabled ?? this.enabled,
      maxDuration: maxDuration ?? this.maxDuration,
      minSpeechDuration: minSpeechDuration ?? this.minSpeechDuration,
      minAvgRms: minAvgRms ?? this.minAvgRms,
      minMaxRms: minMaxRms ?? this.minMaxRms,
      minSpeechLikeRatio: minSpeechLikeRatio ?? this.minSpeechLikeRatio,
      postTtsStartGracePeriod:
          postTtsStartGracePeriod ?? this.postTtsStartGracePeriod,
    );
  }

  Map<String, Object> toJson() {
    return {
      'enabled': enabled,
      'maxDurationMs': maxDuration.inMilliseconds,
      'minSpeechMs': minSpeechDuration.inMilliseconds,
      'minAvgRms': minAvgRms,
      'minMaxRms': minMaxRms,
      'minSpeechLikeRatio': minSpeechLikeRatio,
      'postTtsStartGracePeriodMs': postTtsStartGracePeriod.inMilliseconds,
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

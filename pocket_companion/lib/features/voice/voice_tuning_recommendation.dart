class VoiceTuningRecommendation {
  const VoiceTuningRecommendation({
    required this.sampleCount,
    required this.enoughSamples,
    required this.recommendedWakeScoreThreshold,
    required this.recommendedMinAvgRms,
    required this.recommendedMinMaxRms,
    required this.recommendedMinSpeechLikeRatio,
    required this.recommendedBargeInMinAvgRms,
    required this.recommendedBargeInMinMaxRms,
    required this.recommendedBargeInSpeechLikeRatio,
    required this.recommendedPostTtsStartGracePeriod,
    required this.findings,
    required this.warnings,
  });

  final int sampleCount;
  final bool enoughSamples;
  final double recommendedWakeScoreThreshold;
  final double recommendedMinAvgRms;
  final double recommendedMinMaxRms;
  final double recommendedMinSpeechLikeRatio;
  final double recommendedBargeInMinAvgRms;
  final double recommendedBargeInMinMaxRms;
  final double recommendedBargeInSpeechLikeRatio;
  final Duration recommendedPostTtsStartGracePeriod;
  final List<String> findings;
  final List<String> warnings;

  Map<String, Object> toJson() {
    return {
      'sampleCount': sampleCount,
      'enoughSamples': enoughSamples,
      'recommendedWakeScoreThreshold': recommendedWakeScoreThreshold,
      'recommendedMinAvgRms': recommendedMinAvgRms,
      'recommendedMinMaxRms': recommendedMinMaxRms,
      'recommendedMinSpeechLikeRatio': recommendedMinSpeechLikeRatio,
      'recommendedBargeInMinAvgRms': recommendedBargeInMinAvgRms,
      'recommendedBargeInMinMaxRms': recommendedBargeInMinMaxRms,
      'recommendedBargeInSpeechLikeRatio': recommendedBargeInSpeechLikeRatio,
      'recommendedPostTtsStartGracePeriodMs':
          recommendedPostTtsStartGracePeriod.inMilliseconds,
      'findings': findings,
      'warnings': warnings,
    };
  }
}

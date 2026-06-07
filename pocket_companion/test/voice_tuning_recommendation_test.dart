import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_companion/features/voice/voice_tuning_recommendation.dart';

void main() {
  test('VoiceTuningRecommendation serializes to JSON', () {
    const recommendation = VoiceTuningRecommendation(
      sampleCount: 12,
      enoughSamples: true,
      recommendedWakeScoreThreshold: 0.89,
      recommendedMinAvgRms: 90,
      recommendedMinMaxRms: 500,
      recommendedMinSpeechLikeRatio: 0.09,
      recommendedBargeInMinAvgRms: 220,
      recommendedBargeInMinMaxRms: 1400,
      recommendedBargeInSpeechLikeRatio: 0.22,
      recommendedPostTtsStartGracePeriod: Duration(milliseconds: 650),
      findings: ['ok'],
      warnings: ['check'],
    );

    final json = recommendation.toJson();

    expect(json['sampleCount'], 12);
    expect(json['enoughSamples'], isTrue);
    expect(json['recommendedPostTtsStartGracePeriodMs'], 650);
    expect(json['findings'], ['ok']);
    expect(json['warnings'], ['check']);
  });
}

import 'package:flutter/material.dart';

import '../voice_tuning_recommendation.dart';

class VoiceTuningRecommendationView extends StatelessWidget {
  const VoiceTuningRecommendationView({
    super.key,
    required this.recommendation,
    required this.onApply,
  });

  final VoiceTuningRecommendation recommendation;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 18),
        Text('样本分析', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(
          'samples=${recommendation.sampleCount} enough=${recommendation.enoughSamples}',
          style: style,
        ),
        Text(
          'wakeScore=${recommendation.recommendedWakeScoreThreshold.toStringAsFixed(2)} '
          'avg=${recommendation.recommendedMinAvgRms.toStringAsFixed(1)} '
          'max=${recommendation.recommendedMinMaxRms.toStringAsFixed(1)} '
          'ratio=${recommendation.recommendedMinSpeechLikeRatio.toStringAsFixed(3)}',
          style: style,
        ),
        Text(
          'bargeAvg=${recommendation.recommendedBargeInMinAvgRms.toStringAsFixed(1)} '
          'bargeMax=${recommendation.recommendedBargeInMinMaxRms.toStringAsFixed(1)} '
          'bargeRatio=${recommendation.recommendedBargeInSpeechLikeRatio.toStringAsFixed(3)} '
          'grace=${recommendation.recommendedPostTtsStartGracePeriod.inMilliseconds}ms',
          style: style,
        ),
        const SizedBox(height: 6),
        FilledButton.tonalIcon(
          onPressed: onApply,
          icon: const Icon(Icons.tune, size: 16),
          label: const Text('应用推荐参数'),
        ),
        const SizedBox(height: 6),
        if (recommendation.findings.isNotEmpty) ...[
          Text('findings', style: style),
          ...recommendation.findings.map(
            (finding) => Text('- $finding', style: style),
          ),
        ],
        if (recommendation.warnings.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('warnings', style: style),
          ...recommendation.warnings.map(
            (warning) => Text('- $warning', style: style),
          ),
        ],
      ],
    );
  }
}

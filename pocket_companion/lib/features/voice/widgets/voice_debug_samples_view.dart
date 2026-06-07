import 'package:flutter/material.dart';

import '../voice_debug_sample.dart';
import '../voice_debug_sample_summary.dart';

class VoiceDebugSamplesView extends StatelessWidget {
  const VoiceDebugSamplesView({
    super.key,
    required this.samples,
    required this.summary,
    required this.exportPath,
    required this.onClear,
  });

  final List<VoiceDebugSample> samples;
  final VoiceDebugSampleSummary summary;
  final String? exportPath;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 18),
        Text(
          '样本统计 total=${summary.total} normal=${summary.normalWakeCount} false=${summary.falseWakeCount} missed=${summary.missedWakeCount} ignored=${summary.ignoredCorrectlyCount} barge=${summary.normalBargeInCount}/${summary.falseBargeInCount}',
          style: style,
        ),
        Text(
          'avgScore=${summary.avgWakeScore.toStringAsFixed(2)} false=${summary.avgFalseWakeScore.toStringAsFixed(2)} missed=${summary.avgMissedWakeScore.toStringAsFixed(2)} avgRms=${summary.avgRms.toStringAsFixed(1)} max=${summary.avgMaxRms.toStringAsFixed(1)}',
          style: style,
        ),
        Text('file=${exportPath ?? '-'}', style: style),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            onPressed: onClear,
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('清空样本'),
          ),
        ),
        const SizedBox(height: 6),
        Text('最近样本', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        if (samples.isEmpty)
          Text('暂无样本', style: style)
        else
          ...samples.map((sample) => _SampleRow(sample: sample)),
      ],
    );
  }
}

class _SampleRow extends StatelessWidget {
  const _SampleRow({required this.sample});

  final VoiceDebugSample sample;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        '${sample.label.name} | ${sample.normalizedText.isEmpty ? '-' : sample.normalizedText} | score=${sample.wakeScore.toStringAsFixed(2)} avg=${sample.avgRms.toStringAsFixed(1)} max=${sample.maxRms.toStringAsFixed(1)} | ${sample.createdAt.toIso8601String()}',
        style: style,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

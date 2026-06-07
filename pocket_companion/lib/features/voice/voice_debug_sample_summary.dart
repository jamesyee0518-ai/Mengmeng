import 'voice_debug_sample.dart';

class VoiceDebugSampleSummary {
  const VoiceDebugSampleSummary({
    required this.total,
    required this.normalWakeCount,
    required this.falseWakeCount,
    required this.missedWakeCount,
    required this.ignoredCorrectlyCount,
    required this.normalBargeInCount,
    required this.falseBargeInCount,
    required this.avgWakeScore,
    required this.avgFalseWakeScore,
    required this.avgMissedWakeScore,
    required this.avgRms,
    required this.avgMaxRms,
  });

  factory VoiceDebugSampleSummary.empty() {
    return const VoiceDebugSampleSummary(
      total: 0,
      normalWakeCount: 0,
      falseWakeCount: 0,
      missedWakeCount: 0,
      ignoredCorrectlyCount: 0,
      normalBargeInCount: 0,
      falseBargeInCount: 0,
      avgWakeScore: 0,
      avgFalseWakeScore: 0,
      avgMissedWakeScore: 0,
      avgRms: 0,
      avgMaxRms: 0,
    );
  }

  factory VoiceDebugSampleSummary.fromSamples(List<VoiceDebugSample> samples) {
    if (samples.isEmpty) {
      return VoiceDebugSampleSummary.empty();
    }
    final normal = samples
        .where((sample) => sample.label == VoiceDebugSampleLabel.normalWake)
        .toList();
    final falseWake = samples
        .where((sample) => sample.label == VoiceDebugSampleLabel.falseWake)
        .toList();
    final missed = samples
        .where((sample) => sample.label == VoiceDebugSampleLabel.missedWake)
        .toList();
    final ignored = samples
        .where(
          (sample) => sample.label == VoiceDebugSampleLabel.ignoredCorrectly,
        )
        .toList();
    final normalBargeIn = samples
        .where((sample) => sample.label == VoiceDebugSampleLabel.normalBargeIn)
        .toList();
    final falseBargeIn = samples
        .where((sample) => sample.label == VoiceDebugSampleLabel.falseBargeIn)
        .toList();
    return VoiceDebugSampleSummary(
      total: samples.length,
      normalWakeCount: normal.length,
      falseWakeCount: falseWake.length,
      missedWakeCount: missed.length,
      ignoredCorrectlyCount: ignored.length,
      normalBargeInCount: normalBargeIn.length,
      falseBargeInCount: falseBargeIn.length,
      avgWakeScore: _avg(samples.map((sample) => sample.wakeScore)),
      avgFalseWakeScore: _avg(falseWake.map((sample) => sample.wakeScore)),
      avgMissedWakeScore: _avg(missed.map((sample) => sample.wakeScore)),
      avgRms: _avg(samples.map((sample) => sample.avgRms)),
      avgMaxRms: _avg(samples.map((sample) => sample.maxRms)),
    );
  }

  final int total;
  final int normalWakeCount;
  final int falseWakeCount;
  final int missedWakeCount;
  final int ignoredCorrectlyCount;
  final int normalBargeInCount;
  final int falseBargeInCount;
  final double avgWakeScore;
  final double avgFalseWakeScore;
  final double avgMissedWakeScore;
  final double avgRms;
  final double avgMaxRms;
}

double _avg(Iterable<double> values) {
  final list = values.toList();
  if (list.isEmpty) {
    return 0;
  }
  return list.reduce((left, right) => left + right) / list.length;
}

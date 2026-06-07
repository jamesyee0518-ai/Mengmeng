import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_companion/features/voice/voice_debug_sample.dart';
import 'package:pocket_companion/features/voice/voice_debug_sample_summary.dart';

import 'voice_debug_sample_test.dart' as fixture;

void main() {
  test('summary counts labels and averages values', () {
    final samples = [
      fixture.sample(
        VoiceDebugSampleLabel.normalWake,
        wakeScore: 0.9,
        avgRms: 100,
        maxRms: 500,
      ),
      fixture.sample(
        VoiceDebugSampleLabel.falseWake,
        wakeScore: 0.7,
        avgRms: 200,
        maxRms: 800,
      ),
      fixture.sample(
        VoiceDebugSampleLabel.missedWake,
        wakeScore: 0.3,
        avgRms: 300,
        maxRms: 1100,
      ),
      fixture.sample(
        VoiceDebugSampleLabel.ignoredCorrectly,
        wakeScore: 0.1,
        avgRms: 400,
        maxRms: 1400,
      ),
      fixture.sample(VoiceDebugSampleLabel.normalBargeIn),
      fixture.sample(VoiceDebugSampleLabel.falseBargeIn),
    ];

    final summary = VoiceDebugSampleSummary.fromSamples(samples);

    expect(summary.total, 6);
    expect(summary.normalWakeCount, 1);
    expect(summary.falseWakeCount, 1);
    expect(summary.missedWakeCount, 1);
    expect(summary.ignoredCorrectlyCount, 1);
    expect(summary.normalBargeInCount, 1);
    expect(summary.falseBargeInCount, 1);
    expect(summary.avgWakeScore, closeTo(0.66, 0.01));
    expect(summary.avgFalseWakeScore, 0.7);
    expect(summary.avgMissedWakeScore, 0.3);
    expect(summary.avgRms, closeTo(226.66, 0.01));
    expect(summary.avgMaxRms, closeTo(1033.33, 0.01));
  });
}

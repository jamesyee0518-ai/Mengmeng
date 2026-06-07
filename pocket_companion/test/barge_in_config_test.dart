import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_companion/features/voice/barge_in_config.dart';

void main() {
  test('BargeInConfig defaults and copyWith work', () {
    const config = BargeInConfig();

    expect(config.enabled, isTrue);
    expect(config.maxDuration, const Duration(seconds: 10));
    expect(config.minSpeechDuration, const Duration(milliseconds: 400));
    expect(config.minAvgRms, 180);
    expect(config.minMaxRms, 1200);
    expect(config.minSpeechLikeRatio, 0.18);

    final updated = config.copyWith(
      enabled: false,
      minAvgRms: 260,
      postTtsStartGracePeriod: const Duration(milliseconds: 10),
    );

    expect(updated.enabled, isFalse);
    expect(updated.minAvgRms, 260);
    expect(updated.minMaxRms, 1200);
    expect(updated.postTtsStartGracePeriod, const Duration(milliseconds: 10));
  });
}

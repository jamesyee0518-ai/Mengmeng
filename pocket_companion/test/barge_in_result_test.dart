import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_companion/features/voice/barge_in_result.dart';

void main() {
  test('BargeInResult fromJson and toJson work', () {
    final result = BargeInResult.fromJson({
      'detected': true,
      'durationMs': 800,
      'speechDurationMs': 450,
      'avgRms': 260,
      'maxRms': 1800,
      'speechLikeRatio': 0.31,
      'reason': 'barge_in_detected',
    });

    expect(result.detected, isTrue);
    expect(result.durationMs, 800);
    expect(result.speechDurationMs, 450);
    expect(result.avgRms, 260);
    expect(result.maxRms, 1800);
    expect(result.speechLikeRatio, 0.31);
    expect(result.reason, 'barge_in_detected');
    expect(result.toJson()['detected'], isTrue);
  });
}

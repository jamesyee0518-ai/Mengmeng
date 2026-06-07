import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_companion/features/voice/barge_in_config.dart';
import 'package:pocket_companion/features/voice/voice_audio_gate_config.dart';
import 'package:pocket_companion/features/voice/voice_debug_sample.dart';
import 'package:pocket_companion/features/voice/voice_debug_sample_analyzer.dart';
import 'package:pocket_companion/features/voice/voice_wake_config.dart';

void main() {
  const analyzer = VoiceDebugSampleAnalyzer();
  const wakeConfig = VoiceWakeConfig(wakeScoreThreshold: 0.85);
  const gateConfig = VoiceAudioGateConfig(
    minAvgRms: 80,
    minMaxRms: 400,
    minSpeechLikeRatio: 0.08,
  );
  const bargeConfig = BargeInConfig(
    minAvgRms: 180,
    minMaxRms: 1200,
    minSpeechLikeRatio: 0.18,
    postTtsStartGracePeriod: Duration(milliseconds: 500),
  );

  test('empty samples return enoughSamples false', () {
    final result = analyzer.analyze(
      samples: const [],
      wakeConfig: wakeConfig,
      audioGateConfig: gateConfig,
      bargeInConfig: bargeConfig,
    );

    expect(result.sampleCount, 0);
    expect(result.enoughSamples, isFalse);
    expect(result.warnings.join(), contains('暂无可分析样本'));
  });

  test('less than ten samples warn that data is limited', () {
    final result = analyzer.analyze(
      samples: [_sample(VoiceDebugSampleLabel.normalWake)],
      wakeConfig: wakeConfig,
      audioGateConfig: gateConfig,
      bargeInConfig: bargeConfig,
    );

    expect(result.enoughSamples, isFalse);
    expect(result.warnings.join(), contains('样本较少'));
  });

  test('falseWake near threshold recommends raising wake threshold', () {
    final samples = List.generate(
      10,
      (_) => _sample(
        VoiceDebugSampleLabel.falseWake,
        wakeScore: 0.84,
        matchType: 'primary',
      ),
    );

    final result = analyzer.analyze(
      samples: samples,
      wakeConfig: wakeConfig,
      audioGateConfig: gateConfig,
      bargeInConfig: bargeConfig,
    );

    expect(result.recommendedWakeScoreThreshold, greaterThan(0.85));
    expect(result.findings.join(), contains('误唤醒分数接近当前阈值'));
  });

  test('fuzzy and alias falseWake produce lexicon finding', () {
    final samples = [
      ...List.generate(
        5,
        (_) => _sample(
          VoiceDebugSampleLabel.falseWake,
          wakeScore: 0.86,
          matchType: 'fuzzy',
        ),
      ),
      ...List.generate(
        5,
        (_) => _sample(
          VoiceDebugSampleLabel.falseWake,
          wakeScore: 0.86,
          matchType: 'alias',
        ),
      ),
    ];

    final result = analyzer.analyze(
      samples: samples,
      wakeConfig: wakeConfig,
      audioGateConfig: gateConfig,
      bargeInConfig: bargeConfig,
    );

    expect(result.findings.join(), contains('fuzzy/alias'));
  });

  test('missedWake near threshold outputs missed wake suggestion', () {
    final samples = List.generate(
      10,
      (_) => _sample(
        VoiceDebugSampleLabel.missedWake,
        wakeScore: 0.79,
        avgRms: 60,
        maxRms: 300,
      ),
    );

    final result = analyzer.analyze(
      samples: samples,
      wakeConfig: wakeConfig,
      audioGateConfig: gateConfig,
      bargeInConfig: bargeConfig,
    );

    expect(result.findings.join(), contains('漏唤醒'));
    expect(result.findings.join(), contains('远场/轻声'));
  });

  test('falseBargeIn recommends raising barge-in threshold or grace', () {
    final samples = List.generate(
      10,
      (_) => _sample(
        VoiceDebugSampleLabel.falseBargeIn,
        bargeInAvgRms: 260,
        bargeInMaxRms: 1500,
        bargeInSpeechLikeRatio: 0.3,
      ),
    );

    final result = analyzer.analyze(
      samples: samples,
      wakeConfig: wakeConfig,
      audioGateConfig: gateConfig,
      bargeInConfig: bargeConfig,
    );

    expect(result.recommendedBargeInMinMaxRms, greaterThan(1200));
    expect(
      result.recommendedPostTtsStartGracePeriod.inMilliseconds,
      greaterThan(500),
    );
    expect(result.findings.join(), contains('误打断'));
  });

  test('normalWake samples produce audio gate recommendation', () {
    final samples = [
      _sample(VoiceDebugSampleLabel.normalWake, avgRms: 120, maxRms: 900),
      _sample(VoiceDebugSampleLabel.normalWake, avgRms: 150, maxRms: 1000),
      _sample(VoiceDebugSampleLabel.normalWake, avgRms: 180, maxRms: 1100),
      _sample(VoiceDebugSampleLabel.normalWake, avgRms: 220, maxRms: 1300),
      _sample(VoiceDebugSampleLabel.normalWake, avgRms: 260, maxRms: 1500),
      ...List.generate(5, (_) => _sample(VoiceDebugSampleLabel.normalWake)),
    ];

    final result = analyzer.analyze(
      samples: samples,
      wakeConfig: wakeConfig,
      audioGateConfig: gateConfig,
      bargeInConfig: bargeConfig,
    );

    expect(result.recommendedMinAvgRms, greaterThan(80));
    expect(result.recommendedMinMaxRms, greaterThan(400));
    expect(result.findings.join(), contains('audio gate'));
  });

  test('findings and warnings are useful with limited samples', () {
    final result = analyzer.analyze(
      samples: [_sample(VoiceDebugSampleLabel.falseWake, wakeScore: 0.86)],
      wakeConfig: wakeConfig,
      audioGateConfig: gateConfig,
      bargeInConfig: bargeConfig,
    );

    expect(result.findings, isNotEmpty);
    expect(result.warnings, isNotEmpty);
  });
}

VoiceDebugSample _sample(
  VoiceDebugSampleLabel label, {
  double wakeScore = 0.9,
  String matchType = 'primary',
  double avgRms = 180,
  double maxRms = 1200,
  double speechLikeRatio = 0.3,
  double bargeInAvgRms = 260,
  double bargeInMaxRms = 1800,
  double bargeInSpeechLikeRatio = 0.31,
}) {
  return VoiceDebugSample(
    createdAt: DateTime(2026),
    label: label,
    rawText: '萌萌帮我看',
    normalizedText: '萌萌帮我看',
    sttFlags: const [],
    wakeWord: '萌萌',
    matchType: matchType,
    wakeScore: wakeScore,
    command: '帮我看',
    durationMs: 1800,
    speechDurationMs: 1000,
    avgRms: avgRms,
    maxRms: maxRms,
    speechLikeRatio: speechLikeRatio,
    gateReason: 'send_to_stt',
    gateFlags: const [],
    recordReason: 'silence_timeout',
    bargeInDetected:
        label == VoiceDebugSampleLabel.normalBargeIn ||
        label == VoiceDebugSampleLabel.falseBargeIn,
    bargeInAvgRms: bargeInAvgRms,
    bargeInMaxRms: bargeInMaxRms,
    bargeInSpeechLikeRatio: bargeInSpeechLikeRatio,
    bargeInReason: 'barge_in_detected',
    voiceWakeConfig: const VoiceWakeConfig(),
    audioGateConfig: const VoiceAudioGateConfig(),
  );
}

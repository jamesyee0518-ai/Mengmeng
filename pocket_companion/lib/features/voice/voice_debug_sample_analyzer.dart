import 'dart:math' as math;

import 'barge_in_config.dart';
import 'voice_audio_gate_config.dart';
import 'voice_debug_sample.dart';
import 'voice_tuning_recommendation.dart';
import 'voice_wake_config.dart';

class VoiceDebugSampleAnalyzer {
  const VoiceDebugSampleAnalyzer();

  VoiceTuningRecommendation analyze({
    required List<VoiceDebugSample> samples,
    required VoiceWakeConfig wakeConfig,
    required VoiceAudioGateConfig audioGateConfig,
    required BargeInConfig bargeInConfig,
  }) {
    final findings = <String>[];
    final warnings = <String>[];
    final normalWake = _byLabel(samples, VoiceDebugSampleLabel.normalWake);
    final falseWake = _byLabel(samples, VoiceDebugSampleLabel.falseWake);
    final missedWake = _byLabel(samples, VoiceDebugSampleLabel.missedWake);
    final normalBargeIn = _byLabel(
      samples,
      VoiceDebugSampleLabel.normalBargeIn,
    );
    final falseBargeIn = _byLabel(samples, VoiceDebugSampleLabel.falseBargeIn);
    var wakeScoreThreshold = wakeConfig.wakeScoreThreshold;
    var minAvgRms = audioGateConfig.minAvgRms;
    var minMaxRms = audioGateConfig.minMaxRms;
    var minSpeechLikeRatio = audioGateConfig.minSpeechLikeRatio;
    var bargeInMinAvgRms = bargeInConfig.minAvgRms;
    var bargeInMinMaxRms = bargeInConfig.minMaxRms;
    var bargeInSpeechLikeRatio = bargeInConfig.minSpeechLikeRatio;
    var postTtsStartGracePeriod = bargeInConfig.postTtsStartGracePeriod;

    if (samples.length < 10) {
      warnings.add('样本较少，建议仅参考。');
    }
    if (samples.isEmpty) {
      warnings.add('暂无可分析样本。');
    }

    if (falseWake.isNotEmpty) {
      final avgFalseWakeScore = _avg(
        falseWake.map((sample) => sample.wakeScore),
      );
      if (avgFalseWakeScore >= wakeConfig.wakeScoreThreshold - 0.05) {
        wakeScoreThreshold = _clampDouble(
          math.max(wakeScoreThreshold, wakeConfig.wakeScoreThreshold + 0.04),
          0.5,
          0.99,
        );
        findings.add('误唤醒分数接近当前阈值，建议小幅提高 wakeScoreThreshold。');
      }
      final fuzzyOrAliasCount = falseWake
          .where(
            (sample) =>
                sample.matchType == 'fuzzy' || sample.matchType == 'alias',
          )
          .length;
      if (fuzzyOrAliasCount >= (falseWake.length / 2).ceil()) {
        findings.add('误唤醒集中在 fuzzy/alias，建议优先调整词表或惩罚，不一定全局提高阈值。');
      }
      final lowFalseWakeAvgRms = _avg(falseWake.map((sample) => sample.avgRms));
      if (lowFalseWakeAvgRms > 0 &&
          lowFalseWakeAvgRms < audioGateConfig.minAvgRms * 1.4) {
        minAvgRms = math.max(minAvgRms, lowFalseWakeAvgRms + 15);
        findings.add('误唤醒样本 RMS 偏低，可考虑略提高 minAvgRms。');
      }
    }

    if (missedWake.isNotEmpty) {
      final avgMissedScore = _avg(missedWake.map((sample) => sample.wakeScore));
      if (avgMissedScore >= wakeConfig.wakeScoreThreshold - 0.12 &&
          avgMissedScore < wakeConfig.wakeScoreThreshold) {
        findings.add('存在接近阈值的漏唤醒，可考虑略降阈值或增加别名词。');
      }
      final missedAvgRms = _avg(missedWake.map((sample) => sample.avgRms));
      final missedMaxRms = _avg(missedWake.map((sample) => sample.maxRms));
      if ((missedAvgRms > 0 &&
              missedAvgRms < audioGateConfig.minAvgRms * 1.5) ||
          (missedMaxRms > 0 &&
              missedMaxRms < audioGateConfig.minMaxRms * 1.5)) {
        findings.add('漏唤醒可能来自远场/轻声，谨慎提高 audio gate。');
      }
    }

    if (normalWake.isNotEmpty) {
      final avgRmsFloor = _percentile(
        normalWake.map((sample) => sample.avgRms),
        0.2,
      );
      final maxRmsFloor = _percentile(
        normalWake.map((sample) => sample.maxRms),
        0.2,
      );
      final ratioFloor = _percentile(
        normalWake.map((sample) => sample.speechLikeRatio),
        0.2,
      );
      if (avgRmsFloor > 0) {
        minAvgRms = _clampDouble(avgRmsFloor * 0.72, 20, 600);
      }
      if (maxRmsFloor > 0) {
        minMaxRms = _clampDouble(maxRmsFloor * 0.65, 100, 5000);
      }
      if (ratioFloor > 0) {
        minSpeechLikeRatio = _clampDouble(ratioFloor * 0.7, 0.02, 0.5);
      }
      findings.add('已基于正常唤醒样本低分位生成 audio gate 推荐阈值。');
    }

    if (falseBargeIn.isNotEmpty) {
      bargeInMinMaxRms = math.max(
        bargeInMinMaxRms,
        bargeInConfig.minMaxRms + 150,
      );
      postTtsStartGracePeriod = Duration(
        milliseconds: math.min(
          bargeInConfig.postTtsStartGracePeriod.inMilliseconds + 150,
          1500,
        ),
      );
      findings.add('存在误打断样本，建议提高 barge-in minMaxRms 或延长 TTS 起播保护时间。');
    }
    if (normalBargeIn.length < 3 && falseBargeIn.length < 3) {
      warnings.add('barge-in 样本较少，暂不强行调整打断阈值。');
    } else if (normalBargeIn.isNotEmpty) {
      final normalBargeAvg = _avg(
        normalBargeIn.map((sample) => sample.bargeInAvgRms),
      );
      final normalBargeMax = _avg(
        normalBargeIn.map((sample) => sample.bargeInMaxRms),
      );
      final normalBargeRatio = _avg(
        normalBargeIn.map((sample) => sample.bargeInSpeechLikeRatio),
      );
      if (normalBargeAvg > 0 && normalBargeAvg < bargeInConfig.minAvgRms) {
        bargeInMinAvgRms = _clampDouble(normalBargeAvg * 0.85, 60, 1000);
        findings.add('正常打断 RMS 低于当前阈值，可考虑降低 barge-in minAvgRms。');
      }
      if (normalBargeMax > 0 && normalBargeMax < bargeInConfig.minMaxRms) {
        bargeInMinMaxRms = _clampDouble(normalBargeMax * 0.85, 300, 6000);
        findings.add('正常打断峰值低于当前阈值，可考虑降低 barge-in minMaxRms。');
      }
      if (normalBargeRatio > 0 &&
          normalBargeRatio < bargeInConfig.minSpeechLikeRatio) {
        bargeInSpeechLikeRatio = _clampDouble(
          normalBargeRatio * 0.85,
          0.05,
          0.8,
        );
        findings.add('正常打断 speechLikeRatio 偏低，可考虑降低 barge-in ratio 阈值。');
      }
    }

    if (findings.isEmpty) {
      findings.add('当前样本未显示明显阈值问题，建议继续收集不同距离和音量的样本。');
    }

    return VoiceTuningRecommendation(
      sampleCount: samples.length,
      enoughSamples: samples.length >= 10,
      recommendedWakeScoreThreshold: _round2(wakeScoreThreshold),
      recommendedMinAvgRms: _round1(minAvgRms),
      recommendedMinMaxRms: _round1(minMaxRms),
      recommendedMinSpeechLikeRatio: _round3(minSpeechLikeRatio),
      recommendedBargeInMinAvgRms: _round1(bargeInMinAvgRms),
      recommendedBargeInMinMaxRms: _round1(bargeInMinMaxRms),
      recommendedBargeInSpeechLikeRatio: _round3(bargeInSpeechLikeRatio),
      recommendedPostTtsStartGracePeriod: postTtsStartGracePeriod,
      findings: findings,
      warnings: warnings,
    );
  }

  List<VoiceDebugSample> _byLabel(
    List<VoiceDebugSample> samples,
    VoiceDebugSampleLabel label,
  ) {
    return samples.where((sample) => sample.label == label).toList();
  }
}

double _avg(Iterable<double> values) {
  final list = values.where((value) => value > 0).toList();
  if (list.isEmpty) {
    return 0;
  }
  return list.reduce((left, right) => left + right) / list.length;
}

double _percentile(Iterable<double> values, double percentile) {
  final list = values.where((value) => value > 0).toList()..sort();
  if (list.isEmpty) {
    return 0;
  }
  final index = ((list.length - 1) * percentile).round();
  return list[index.clamp(0, list.length - 1)];
}

double _clampDouble(double value, double min, double max) {
  return value.clamp(min, max).toDouble();
}

double _round1(double value) => (value * 10).roundToDouble() / 10;

double _round2(double value) => (value * 100).roundToDouble() / 100;

double _round3(double value) => (value * 1000).roundToDouble() / 1000;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_companion/features/voice/voice_audio_gate_config.dart';
import 'package:pocket_companion/features/voice/voice_debug_sample.dart';
import 'package:pocket_companion/features/voice/voice_debug_sample_store.dart';
import 'package:pocket_companion/features/voice/voice_debug_snapshot.dart';
import 'package:pocket_companion/features/voice/voice_wake_config.dart';

void main() {
  test('VoiceDebugSample builds from snapshot', () {
    final sample = sampleFixture(VoiceDebugSampleLabel.normalWake);

    expect(sample.label, VoiceDebugSampleLabel.normalWake);
    expect(sample.normalizedText, '萌萌帮我看');
    expect(sample.wakeWord, '萌萌');
    expect(sample.command, '帮我看');
    expect(sample.avgRms, 180);
  });

  test('VoiceDebugSample serializes to JSON', () {
    final sample = sampleFixture(VoiceDebugSampleLabel.falseWake);
    final json = sample.toJson();
    final encoded = jsonEncode(json);

    expect(json['label'], 'falseWake');
    expect(json['voiceWakeConfig'], isA<Map<String, Object>>());
    expect(json['audioGateConfig'], isA<Map<String, Object>>());
    expect(json['bargeInReason'], 'barge_in_detected');
    expect(encoded, contains('falseWake'));
  });

  test('barge-in labels serialize and deserialize', () {
    final sample = sampleFixture(VoiceDebugSampleLabel.normalBargeIn);
    final decoded = VoiceDebugSample.fromJson(sample.toJson());

    expect(decoded.label, VoiceDebugSampleLabel.normalBargeIn);
    expect(decoded.bargeInDetected, isTrue);
    expect(decoded.bargeInReason, 'barge_in_detected');
  });

  test('sample label is saved in memory store', () async {
    final store = MemoryVoiceDebugSampleStore();
    final sample = sampleFixture(VoiceDebugSampleLabel.missedWake);

    await store.append(sample);

    expect(store.samples, hasLength(1));
    expect(store.samples.single.label, VoiceDebugSampleLabel.missedWake);
  });
}

VoiceDebugSample sample(
  VoiceDebugSampleLabel label, {
  double wakeScore = 0.98,
  double avgRms = 180,
  double maxRms = 1200,
}) {
  return VoiceDebugSample.fromSnapshot(
    label: label,
    snapshot: VoiceDebugSnapshot(
      durationMs: 2200,
      speechDurationMs: 1300,
      avgRms: avgRms,
      maxRms: maxRms,
      speechLikeRatio: 0.3,
      recordReason: 'silence_timeout',
      callStt: true,
      gateReason: 'send_to_stt',
      gateFlags: const [],
      rawText: '萌萌帮我看',
      normalizedText: '萌萌帮我看',
      sttFlags: const ['short_text'],
      wakeWord: '萌萌',
      matchType: 'primary',
      wakeScore: wakeScore,
      command: '帮我看',
      bargeInDetected: true,
      bargeInAvgRms: 260,
      bargeInMaxRms: 1800,
      bargeInSpeechLikeRatio: 0.31,
      bargeInReason: 'barge_in_detected',
    ),
    voiceWakeConfig: const VoiceWakeConfig(),
    audioGateConfig: const VoiceAudioGateConfig(),
  );
}

VoiceDebugSample sampleFixture(VoiceDebugSampleLabel label) => sample(label);

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_companion/features/voice/audio_clip_result.dart';
import 'package:pocket_companion/features/voice/voice_audio_gate.dart';

void main() {
  const gate = VoiceAudioGate();

  test('allows legacy string path results', () {
    final clip = AudioClipResult.fromPlatformResult('/tmp/voice.m4a');
    final decision = gate.evaluate(clip);

    expect(decision.shouldSendToStt, isTrue);
    expect(decision.flags, isEmpty);
  });

  test('allows audio when Android stats are unavailable', () {
    final decision = gate.evaluate(
      const AudioClipResult(
        path: '/tmp/voice.m4a',
        durationMs: 2400,
        speechDurationMs: 0,
        avgRms: 0,
        maxRms: 0,
        speechLikeRatio: 0,
        hasSpeechLikeAudio: true,
        reason: 'audio_stats_unavailable',
      ),
    );

    expect(decision.shouldSendToStt, isTrue);
    expect(decision.flags, isEmpty);
  });

  test('skips short and quiet audio', () {
    final decision = gate.evaluate(
      const AudioClipResult(
        path: '/tmp/voice.m4a',
        durationMs: 300,
        speechDurationMs: 0,
        avgRms: 10,
        maxRms: 40,
        speechLikeRatio: 0,
        hasSpeechLikeAudio: false,
        reason: 'max_duration',
      ),
    );

    expect(decision.shouldSendToStt, isFalse);
    expect(decision.flags, contains('too_short_audio'));
    expect(decision.flags, contains('silent_audio_skipped'));
    expect(decision.flags, contains('low_rms_audio'));
  });

  test('allows speech-like audio', () {
    final decision = gate.evaluate(
      const AudioClipResult(
        path: '/tmp/voice.m4a',
        durationMs: 2400,
        speechDurationMs: 1800,
        avgRms: 180,
        maxRms: 1200,
        speechLikeRatio: 0.35,
        hasSpeechLikeAudio: true,
        reason: 'max_duration',
      ),
    );

    expect(decision.shouldSendToStt, isTrue);
    expect(decision.flags, isEmpty);
  });

  test('skips utterance start timeout', () {
    final decision = gate.evaluate(
      const AudioClipResult(
        path: '/tmp/voice.m4a',
        durationMs: 3000,
        speechDurationMs: 0,
        avgRms: 0,
        maxRms: 0,
        speechLikeRatio: 0,
        hasSpeechLikeAudio: false,
        reason: 'start_timeout',
      ),
    );

    expect(decision.shouldSendToStt, isFalse);
    expect(decision.flags, contains('start_timeout'));
  });

  test('skips utterance that is too short', () {
    final decision = gate.evaluate(
      const AudioClipResult(
        path: '/tmp/voice.m4a',
        durationMs: 900,
        speechDurationMs: 180,
        avgRms: 180,
        maxRms: 900,
        speechLikeRatio: 0.3,
        hasSpeechLikeAudio: false,
        reason: 'too_short_speech',
      ),
    );

    expect(decision.shouldSendToStt, isFalse);
    expect(decision.flags, contains('too_short_speech'));
  });
}

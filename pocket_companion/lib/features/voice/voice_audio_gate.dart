import 'audio_clip_result.dart';
import 'voice_audio_gate_config.dart';

class VoiceAudioGateDecision {
  const VoiceAudioGateDecision({
    required this.shouldSendToStt,
    required this.flags,
    required this.reason,
  });

  final bool shouldSendToStt;
  final List<String> flags;
  final String reason;
}

class VoiceAudioGate {
  const VoiceAudioGate({this.config = const VoiceAudioGateConfig()});

  final VoiceAudioGateConfig config;

  VoiceAudioGateDecision evaluate(AudioClipResult clip) {
    if (clip.isLegacy || clip.reason == 'audio_stats_unavailable') {
      return const VoiceAudioGateDecision(
        shouldSendToStt: true,
        flags: [],
        reason: 'audio_gate_unavailable',
      );
    }

    final flags = <String>[];
    if (clip.reason == 'start_timeout') {
      flags.add('start_timeout');
    }
    if (clip.reason == 'too_short_speech') {
      flags.add('too_short_speech');
    }
    if (clip.durationMs > 0 && clip.durationMs < config.minDurationMs) {
      flags.add('too_short_audio');
    }
    if (!clip.hasSpeechLikeAudio) {
      flags.add('silent_audio_skipped');
    }
    if (clip.avgRms < config.minAvgRms || clip.maxRms < config.minMaxRms) {
      flags.add('low_rms_audio');
    }
    if (clip.speechLikeRatio < config.minSpeechLikeRatio) {
      flags.add('silent_audio_skipped');
    }

    final uniqueFlags = flags.toSet().toList(growable: false);
    return VoiceAudioGateDecision(
      shouldSendToStt: uniqueFlags.isEmpty,
      flags: uniqueFlags,
      reason: uniqueFlags.isEmpty ? 'send_to_stt' : uniqueFlags.join(','),
    );
  }
}

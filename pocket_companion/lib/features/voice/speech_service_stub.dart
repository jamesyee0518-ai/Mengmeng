import 'barge_in_config.dart';
import 'barge_in_result.dart';
import 'voice_audio_gate_config.dart';
import 'voice_debug_snapshot.dart';

class SpeechService {
  VoiceDebugSnapshot get latestDebugSnapshot => VoiceDebugSnapshot();
  VoiceAudioGateConfig get audioGateConfig => const VoiceAudioGateConfig();

  void updateAudioGateConfig(VoiceAudioGateConfig config) {}

  Future<String> microphonePermissionStatus() async => 'unknown';

  Future<String?> listenOnce({
    Duration listenFor = const Duration(seconds: 5),
  }) {
    throw UnsupportedError(
      'Speech recognition is not available on this platform.',
    );
  }

  Future<String?> listenForUtterance({
    Duration maxDuration = const Duration(seconds: 12),
    Duration silenceTimeout = const Duration(milliseconds: 1200),
    Duration startTimeout = const Duration(seconds: 3),
  }) {
    throw UnsupportedError(
      'Speech recognition is not available on this platform.',
    );
  }

  Future<BargeInResult> listenForBargeIn(BargeInConfig config) {
    throw UnsupportedError('Barge-in is not available on this platform.');
  }

  Future<void> stop() async {}
}

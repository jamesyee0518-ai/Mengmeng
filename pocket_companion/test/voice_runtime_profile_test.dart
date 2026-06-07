import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_companion/features/voice/speech_service.dart';
import 'package:pocket_companion/features/voice/voice_audio_gate_config.dart';
import 'package:pocket_companion/features/voice/voice_debug_snapshot.dart';
import 'package:pocket_companion/features/voice/voice_profile_preset.dart';
import 'package:pocket_companion/features/voice/voice_runtime_profile.dart';
import 'package:pocket_companion/features/voice/voice_state.dart';
import 'package:pocket_companion/features/voice/voice_wake_controller.dart';

void main() {
  test('every preset has non-empty config', () {
    for (final preset in VoiceProfilePreset.values) {
      expect(preset.label, isNotEmpty);
      expect(preset.description, isNotEmpty);
      expect(
        preset.wakeConfig.monitoringListenDuration.inMilliseconds,
        greaterThan(0),
      );
      expect(preset.audioGateConfig.minDurationMs, greaterThan(0));
      expect(preset.bargeInConfig.maxDuration.inMilliseconds, greaterThan(0));
    }
  });

  test('balanced uses current defaults', () {
    const preset = VoiceProfilePreset.balanced;

    expect(preset.wakeConfig.wakeScoreThreshold, 0.85);
    expect(preset.audioGateConfig.minAvgRms, 80);
    expect(preset.audioGateConfig.minMaxRms, 400);
    expect(preset.audioGateConfig.minSpeechLikeRatio, 0.08);
    expect(preset.bargeInConfig.minAvgRms, 180);
    expect(preset.bargeInConfig.minMaxRms, 1200);
  });

  test('sensitive is more permissive than balanced', () {
    const balanced = VoiceProfilePreset.balanced;
    const sensitive = VoiceProfilePreset.sensitive;

    expect(
      sensitive.wakeConfig.wakeScoreThreshold,
      lessThan(balanced.wakeConfig.wakeScoreThreshold),
    );
    expect(
      sensitive.audioGateConfig.minAvgRms,
      lessThan(balanced.audioGateConfig.minAvgRms),
    );
    expect(
      sensitive.audioGateConfig.minSpeechLikeRatio,
      lessThan(balanced.audioGateConfig.minSpeechLikeRatio),
    );
  });

  test('strict is more conservative than balanced', () {
    const balanced = VoiceProfilePreset.balanced;
    const strict = VoiceProfilePreset.strict;

    expect(
      strict.wakeConfig.wakeScoreThreshold,
      greaterThan(balanced.wakeConfig.wakeScoreThreshold),
    );
    expect(
      strict.audioGateConfig.minAvgRms,
      greaterThan(balanced.audioGateConfig.minAvgRms),
    );
    expect(
      strict.audioGateConfig.minSpeechLikeRatio,
      greaterThan(balanced.audioGateConfig.minSpeechLikeRatio),
    );
  });

  test('noisy room has higher barge-in thresholds than balanced', () {
    const balanced = VoiceProfilePreset.balanced;
    const noisyRoom = VoiceProfilePreset.noisyRoom;

    expect(
      noisyRoom.bargeInConfig.minAvgRms,
      greaterThan(balanced.bargeInConfig.minAvgRms),
    );
    expect(
      noisyRoom.bargeInConfig.minMaxRms,
      greaterThan(balanced.bargeInConfig.minMaxRms),
    );
    expect(
      noisyRoom.bargeInConfig.postTtsStartGracePeriod,
      greaterThan(balanced.bargeInConfig.postTtsStartGracePeriod),
    );
  });

  test('controller applyProfile updates runtime configs', () {
    final speech = _ProfileSpeechService();
    final controller = VoiceWakeController(speech: speech);

    controller.applyProfile(VoiceRuntimeProfile.strict);

    expect(controller.activeProfile, VoiceRuntimeProfile.strict);
    expect(controller.isCustomProfile, isFalse);
    expect(
      controller.config.wakeScoreThreshold,
      VoiceProfilePreset.strict.wakeConfig.wakeScoreThreshold,
    );
    expect(
      controller.audioGateConfig.minAvgRms,
      VoiceProfilePreset.strict.audioGateConfig.minAvgRms,
    );
    expect(
      controller.bargeInConfig.minMaxRms,
      VoiceProfilePreset.strict.bargeInConfig.minMaxRms,
    );
    expect(controller.latestDebugSnapshot.voiceProfile, 'strict');

    controller.dispose();
  });

  test('manual tuning turns profile into custom', () {
    final controller = VoiceWakeController(speech: _ProfileSpeechService());

    controller.applyProfile(VoiceRuntimeProfile.balanced);
    controller.updateConfig(
      controller.config.copyWith(wakeScoreThreshold: 0.77),
    );

    expect(controller.activeProfile, VoiceRuntimeProfile.custom);
    expect(controller.isCustomProfile, isTrue);
    expect(controller.latestDebugSnapshot.profileSource, 'manual');

    controller.dispose();
  });
}

class _ProfileSpeechService extends SpeechService {
  VoiceDebugSnapshot _snapshot = VoiceDebugSnapshot();
  VoiceAudioGateConfig _config = const VoiceAudioGateConfig();

  @override
  VoiceDebugSnapshot get latestDebugSnapshot => _snapshot;

  @override
  VoiceAudioGateConfig get audioGateConfig => _config;

  @override
  void updateAudioGateConfig(VoiceAudioGateConfig config) {
    _config = config;
  }

  @override
  Future<String?> listenOnce({
    Duration listenFor = const Duration(seconds: 5),
  }) async {
    return null;
  }

  @override
  Future<String?> listenForUtterance({
    Duration maxDuration = const Duration(seconds: 12),
    Duration silenceTimeout = const Duration(milliseconds: 1200),
    Duration startTimeout = const Duration(seconds: 3),
  }) async {
    return null;
  }

  @override
  Future<String> microphonePermissionStatus() async => 'granted';

  @override
  Future<void> stop() async {
    _snapshot = _snapshot.copyWith(voiceState: VoiceState.idle);
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_companion/features/voice/barge_in_config.dart';
import 'package:pocket_companion/features/voice/voice_audio_gate_config.dart';
import 'package:pocket_companion/features/voice/voice_runtime_profile.dart';
import 'package:pocket_companion/features/voice/voice_settings_store.dart';
import 'package:pocket_companion/features/voice/voice_wake_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('memory store saves and restores settings', () async {
    final store = MemoryVoiceSettingsStore();
    final settings = VoiceSettingsData(
      activeProfile: VoiceRuntimeProfile.custom,
      wakeConfig: const VoiceWakeConfig(wakeScoreThreshold: 0.76),
      audioGateConfig: const VoiceAudioGateConfig(minAvgRms: 42),
      bargeInConfig: const BargeInConfig(enabled: false, minMaxRms: 888),
      showVoiceDebugPanel: true,
    );

    expect(await store.save(settings), isTrue);
    final loaded = await store.load();

    expect(loaded.activeProfile, VoiceRuntimeProfile.custom);
    expect(loaded.wakeConfig.wakeScoreThreshold, 0.76);
    expect(loaded.audioGateConfig.minAvgRms, 42);
    expect(loaded.bargeInConfig.enabled, isFalse);
    expect(loaded.bargeInConfig.minMaxRms, 888);
    expect(loaded.showVoiceDebugPanel, isTrue);
  });

  test('shared preferences store saves and restores custom config', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final store = SharedPreferencesVoiceSettingsStore(preferences);
    final settings = VoiceSettingsData(
      activeProfile: VoiceRuntimeProfile.custom,
      wakeConfig: const VoiceWakeConfig(
        wakeScoreThreshold: 0.79,
        conversationStartTimeout: Duration(seconds: 6),
      ),
      audioGateConfig: const VoiceAudioGateConfig(
        minAvgRms: 66,
        minMaxRms: 333,
      ),
      bargeInConfig: const BargeInConfig(
        enabled: false,
        minAvgRms: 155,
        postTtsStartGracePeriod: Duration(milliseconds: 900),
      ),
      showVoiceDebugPanel: true,
    );

    expect(await store.save(settings), isTrue);
    final loaded = await store.load();

    expect(loaded.activeProfile, VoiceRuntimeProfile.custom);
    expect(loaded.isCustomProfile, isTrue);
    expect(loaded.wakeConfig.wakeScoreThreshold, 0.79);
    expect(
      loaded.wakeConfig.conversationStartTimeout,
      const Duration(seconds: 6),
    );
    expect(loaded.audioGateConfig.minAvgRms, 66);
    expect(loaded.audioGateConfig.minMaxRms, 333);
    expect(loaded.bargeInConfig.enabled, isFalse);
    expect(loaded.bargeInConfig.minAvgRms, 155);
    expect(
      loaded.bargeInConfig.postTtsStartGracePeriod,
      const Duration(milliseconds: 900),
    );
    expect(loaded.showVoiceDebugPanel, isTrue);
  });

  test('preset profile restores preset config', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final store = SharedPreferencesVoiceSettingsStore(preferences);

    await store.save(
      const VoiceSettingsData(
        activeProfile: VoiceRuntimeProfile.noisyRoom,
        wakeConfig: VoiceWakeConfig(wakeScoreThreshold: 0.51),
        audioGateConfig: VoiceAudioGateConfig(minAvgRms: 1),
        bargeInConfig: BargeInConfig(minMaxRms: 1),
      ),
    );
    final loaded = await store.load();

    expect(loaded.activeProfile, VoiceRuntimeProfile.noisyRoom);
    expect(loaded.wakeConfig.wakeScoreThreshold, 0.90);
    expect(loaded.audioGateConfig.minAvgRms, 130);
    expect(loaded.bargeInConfig.minMaxRms, 1800);
  });

  test('read failure falls back to balanced', () async {
    SharedPreferences.setMockInitialValues({
      'voice.activeProfile': 'custom',
      'voice.wakeConfig': '{bad json',
      'voice.audioGateConfig': '{"minAvgRms": 42}',
      'voice.bargeInConfig': '{"minAvgRms": 155}',
    });
    final preferences = await SharedPreferences.getInstance();
    final store = SharedPreferencesVoiceSettingsStore(preferences);

    final loaded = await store.load();

    expect(loaded.activeProfile, VoiceRuntimeProfile.balanced);
    expect(loaded.wakeConfig.wakeScoreThreshold, 0.85);
    expect(loaded.audioGateConfig.minAvgRms, 80);
    expect(loaded.bargeInConfig.minAvgRms, 180);
  });
}

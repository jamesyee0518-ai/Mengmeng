import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'barge_in_config.dart';
import 'voice_audio_gate_config.dart';
import 'voice_profile_preset.dart';
import 'voice_runtime_profile.dart';
import 'voice_wake_config.dart';

class VoiceSettingsData {
  const VoiceSettingsData({
    required this.activeProfile,
    required this.wakeConfig,
    required this.audioGateConfig,
    required this.bargeInConfig,
    this.showVoiceDebugPanel = false,
  });

  factory VoiceSettingsData.balanced() {
    return VoiceSettingsData.fromPreset(VoiceProfilePreset.balanced);
  }

  factory VoiceSettingsData.fromPreset(VoiceProfilePreset preset) {
    return VoiceSettingsData(
      activeProfile: preset.profile,
      wakeConfig: preset.wakeConfig,
      audioGateConfig: preset.audioGateConfig,
      bargeInConfig: preset.bargeInConfig,
    );
  }

  final VoiceRuntimeProfile activeProfile;
  final VoiceWakeConfig wakeConfig;
  final VoiceAudioGateConfig audioGateConfig;
  final BargeInConfig bargeInConfig;
  final bool showVoiceDebugPanel;

  bool get isCustomProfile => activeProfile == VoiceRuntimeProfile.custom;

  VoiceSettingsData copyWith({
    VoiceRuntimeProfile? activeProfile,
    VoiceWakeConfig? wakeConfig,
    VoiceAudioGateConfig? audioGateConfig,
    BargeInConfig? bargeInConfig,
    bool? showVoiceDebugPanel,
  }) {
    return VoiceSettingsData(
      activeProfile: activeProfile ?? this.activeProfile,
      wakeConfig: wakeConfig ?? this.wakeConfig,
      audioGateConfig: audioGateConfig ?? this.audioGateConfig,
      bargeInConfig: bargeInConfig ?? this.bargeInConfig,
      showVoiceDebugPanel: showVoiceDebugPanel ?? this.showVoiceDebugPanel,
    );
  }
}

abstract class VoiceSettingsStore {
  Future<VoiceSettingsData> load();
  Future<bool> save(VoiceSettingsData settings);
}

class MemoryVoiceSettingsStore implements VoiceSettingsStore {
  MemoryVoiceSettingsStore([VoiceSettingsData? initial])
    : _settings = initial ?? VoiceSettingsData.balanced();

  VoiceSettingsData _settings;

  @override
  Future<VoiceSettingsData> load() async => _settings;

  @override
  Future<bool> save(VoiceSettingsData settings) async {
    _settings = settings;
    return true;
  }
}

class SharedPreferencesVoiceSettingsStore implements VoiceSettingsStore {
  SharedPreferencesVoiceSettingsStore(this._preferences);

  static Future<SharedPreferencesVoiceSettingsStore> create() async {
    return SharedPreferencesVoiceSettingsStore(
      await SharedPreferences.getInstance(),
    );
  }

  static const _activeProfileKey = 'voice.activeProfile';
  static const _wakeConfigKey = 'voice.wakeConfig';
  static const _audioGateConfigKey = 'voice.audioGateConfig';
  static const _bargeInConfigKey = 'voice.bargeInConfig';
  static const _showDebugPanelKey = 'voice.showVoiceDebugPanel';

  final SharedPreferences _preferences;

  @override
  Future<VoiceSettingsData> load() async {
    try {
      final profile = _profileFromName(
        _preferences.getString(_activeProfileKey),
      );
      final preset = VoiceProfilePreset.forProfile(profile);
      return VoiceSettingsData(
        activeProfile: profile,
        wakeConfig: profile == VoiceRuntimeProfile.custom
            ? VoiceWakeConfig.fromJson(_jsonMap(_preferences, _wakeConfigKey))
            : preset.wakeConfig,
        audioGateConfig: profile == VoiceRuntimeProfile.custom
            ? VoiceAudioGateConfig.fromJson(
                _jsonMap(_preferences, _audioGateConfigKey),
              )
            : preset.audioGateConfig,
        bargeInConfig: profile == VoiceRuntimeProfile.custom
            ? BargeInConfig.fromJson(_jsonMap(_preferences, _bargeInConfigKey))
            : preset.bargeInConfig,
        showVoiceDebugPanel: _preferences.getBool(_showDebugPanelKey) ?? false,
      );
    } catch (_) {
      return VoiceSettingsData.balanced();
    }
  }

  @override
  Future<bool> save(VoiceSettingsData settings) async {
    try {
      final results = await Future.wait([
        _preferences.setString(_activeProfileKey, settings.activeProfile.name),
        _preferences.setString(
          _wakeConfigKey,
          jsonEncode(settings.wakeConfig.toJson()),
        ),
        _preferences.setString(
          _audioGateConfigKey,
          jsonEncode(settings.audioGateConfig.toJson()),
        ),
        _preferences.setString(
          _bargeInConfigKey,
          jsonEncode(settings.bargeInConfig.toJson()),
        ),
        _preferences.setBool(_showDebugPanelKey, settings.showVoiceDebugPanel),
      ]);
      return results.every((ok) => ok);
    } catch (_) {
      return false;
    }
  }
}

VoiceRuntimeProfile _profileFromName(String? name) {
  return VoiceRuntimeProfile.values.firstWhere(
    (profile) => profile.name == name,
    orElse: () => VoiceRuntimeProfile.balanced,
  );
}

Map<String, Object?> _jsonMap(SharedPreferences preferences, String key) {
  final raw = preferences.getString(key);
  if (raw == null || raw.trim().isEmpty) {
    return const {};
  }
  final decoded = jsonDecode(raw);
  if (decoded is Map<String, Object?>) {
    return decoded;
  }
  if (decoded is Map) {
    return Map<String, Object?>.from(decoded);
  }
  return const {};
}

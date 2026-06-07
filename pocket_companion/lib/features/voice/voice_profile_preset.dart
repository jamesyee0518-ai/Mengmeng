import 'barge_in_config.dart';
import 'voice_audio_gate_config.dart';
import 'voice_runtime_profile.dart';
import 'voice_wake_config.dart';

class VoiceProfilePreset {
  const VoiceProfilePreset({
    required this.profile,
    required this.label,
    required this.description,
    required this.wakeConfig,
    required this.audioGateConfig,
    required this.bargeInConfig,
  });

  final VoiceRuntimeProfile profile;
  final String label;
  final String description;
  final VoiceWakeConfig wakeConfig;
  final VoiceAudioGateConfig audioGateConfig;
  final BargeInConfig bargeInConfig;

  static const balanced = VoiceProfilePreset(
    profile: VoiceRuntimeProfile.balanced,
    label: '平衡',
    description: '适合日常使用，兼顾唤醒率和误唤醒控制。',
    wakeConfig: VoiceWakeConfig(),
    audioGateConfig: VoiceAudioGateConfig(),
    bargeInConfig: BargeInConfig(),
  );

  static const sensitive = VoiceProfilePreset(
    profile: VoiceRuntimeProfile.sensitive,
    label: '灵敏',
    description: '适合轻声或距离稍远，误唤醒风险会更高。',
    wakeConfig: VoiceWakeConfig(wakeScoreThreshold: 0.80),
    audioGateConfig: VoiceAudioGateConfig(
      minAvgRms: 55,
      minMaxRms: 260,
      minSpeechLikeRatio: 0.05,
    ),
    bargeInConfig: BargeInConfig(
      minAvgRms: 140,
      minMaxRms: 900,
      minSpeechLikeRatio: 0.12,
    ),
  );

  static const strict = VoiceProfilePreset(
    profile: VoiceRuntimeProfile.strict,
    label: '低误唤醒',
    description: '适合更安静但更保守的唤醒，漏唤醒可能增加。',
    wakeConfig: VoiceWakeConfig(wakeScoreThreshold: 0.92),
    audioGateConfig: VoiceAudioGateConfig(
      minAvgRms: 110,
      minMaxRms: 650,
      minSpeechLikeRatio: 0.12,
    ),
    bargeInConfig: BargeInConfig(
      minAvgRms: 220,
      minMaxRms: 1500,
      minSpeechLikeRatio: 0.24,
    ),
  );

  static const noisyRoom = VoiceProfilePreset(
    profile: VoiceRuntimeProfile.noisyRoom,
    label: '嘈杂环境',
    description: '适合电视、音乐或多人说话场景，更谨慎地进入识别和打断。',
    wakeConfig: VoiceWakeConfig(wakeScoreThreshold: 0.90),
    audioGateConfig: VoiceAudioGateConfig(
      minAvgRms: 130,
      minMaxRms: 800,
      minSpeechLikeRatio: 0.16,
    ),
    bargeInConfig: BargeInConfig(
      minAvgRms: 260,
      minMaxRms: 1800,
      minSpeechLikeRatio: 0.30,
      postTtsStartGracePeriod: Duration(milliseconds: 800),
    ),
  );

  static const farField = VoiceProfilePreset(
    profile: VoiceRuntimeProfile.farField,
    label: '远场',
    description: '适合手机离人稍远，等待开口和停顿判断更宽松。',
    wakeConfig: VoiceWakeConfig(
      conversationSilenceTimeout: Duration(milliseconds: 1600),
      conversationStartTimeout: Duration(seconds: 5),
      wakeScoreThreshold: 0.82,
    ),
    audioGateConfig: VoiceAudioGateConfig(
      minAvgRms: 55,
      minMaxRms: 280,
      minSpeechLikeRatio: 0.05,
    ),
    bargeInConfig: BargeInConfig(
      minAvgRms: 150,
      minMaxRms: 950,
      minSpeechLikeRatio: 0.13,
    ),
  );

  static const custom = VoiceProfilePreset(
    profile: VoiceRuntimeProfile.custom,
    label: '自定义',
    description: '来自手动调参或样本分析推荐，会在重启后恢复。',
    wakeConfig: VoiceWakeConfig(),
    audioGateConfig: VoiceAudioGateConfig(),
    bargeInConfig: BargeInConfig(),
  );

  static const values = [
    balanced,
    sensitive,
    strict,
    noisyRoom,
    farField,
    custom,
  ];

  static VoiceProfilePreset forProfile(VoiceRuntimeProfile profile) {
    return values.firstWhere(
      (preset) => preset.profile == profile,
      orElse: () => balanced,
    );
  }
}

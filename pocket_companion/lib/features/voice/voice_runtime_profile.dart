enum VoiceRuntimeProfile {
  balanced,
  sensitive,
  strict,
  noisyRoom,
  farField,
  custom,
}

extension VoiceRuntimeProfileText on VoiceRuntimeProfile {
  String get label {
    return switch (this) {
      VoiceRuntimeProfile.balanced => '平衡',
      VoiceRuntimeProfile.sensitive => '灵敏',
      VoiceRuntimeProfile.strict => '低误唤醒',
      VoiceRuntimeProfile.noisyRoom => '嘈杂环境',
      VoiceRuntimeProfile.farField => '远场',
      VoiceRuntimeProfile.custom => '自定义',
    };
  }
}

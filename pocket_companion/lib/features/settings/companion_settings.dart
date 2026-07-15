import 'package:flutter/foundation.dart';

@immutable
class CompanionSettings {
  const CompanionSettings({
    required this.allowSpeechInput,
    required this.allowSpeechOutput,
    required this.allowVision,
    required this.allowMemory,
    required this.privacyMode,
    required this.keepAwake,
  });

  factory CompanionSettings.initial() {
    return const CompanionSettings(
      allowSpeechInput: true,
      allowSpeechOutput: true,
      allowVision: true,
      allowMemory: true,
      privacyMode: false,
      keepAwake: true,
    );
  }

  final bool allowSpeechInput;
  final bool allowSpeechOutput;
  final bool allowVision;
  final bool allowMemory;
  final bool privacyMode;
  final bool keepAwake;

  CompanionSettings copyWith({
    bool? allowSpeechInput,
    bool? allowSpeechOutput,
    bool? allowVision,
    bool? allowMemory,
    bool? privacyMode,
    bool? keepAwake,
  }) {
    final nextPrivacyMode = privacyMode ?? this.privacyMode;
    return CompanionSettings(
      allowSpeechInput: nextPrivacyMode
          ? false
          : allowSpeechInput ?? this.allowSpeechInput,
      allowSpeechOutput: nextPrivacyMode
          ? false
          : allowSpeechOutput ?? this.allowSpeechOutput,
      allowVision: nextPrivacyMode ? false : allowVision ?? this.allowVision,
      allowMemory: nextPrivacyMode ? false : allowMemory ?? this.allowMemory,
      privacyMode: nextPrivacyMode,
      keepAwake: keepAwake ?? this.keepAwake,
    );
  }

  Map<String, Object> toGatewayPayload() {
    return {
      'allow_speech_input': allowSpeechInput,
      'allow_speech_output': allowSpeechOutput,
      'allow_vision': allowVision,
      'allow_memory': allowMemory,
      'privacy_mode': privacyMode,
      'keep_awake': keepAwake,
    };
  }
}

import 'voice_audio_gate_config.dart';
import 'voice_debug_snapshot.dart';
import 'voice_wake_config.dart';

enum VoiceDebugSampleLabel {
  normalWake,
  falseWake,
  missedWake,
  ignoredCorrectly,
  normalBargeIn,
  falseBargeIn,
}

class VoiceDebugSample {
  VoiceDebugSample({
    required this.createdAt,
    required this.label,
    required this.rawText,
    required this.normalizedText,
    required this.sttFlags,
    required this.wakeWord,
    required this.matchType,
    required this.wakeScore,
    required this.command,
    required this.durationMs,
    required this.speechDurationMs,
    required this.avgRms,
    required this.maxRms,
    required this.speechLikeRatio,
    required this.gateReason,
    required this.gateFlags,
    required this.recordReason,
    required this.bargeInDetected,
    required this.bargeInAvgRms,
    required this.bargeInMaxRms,
    required this.bargeInSpeechLikeRatio,
    required this.bargeInReason,
    required this.voiceWakeConfig,
    required this.audioGateConfig,
  });

  factory VoiceDebugSample.fromSnapshot({
    required VoiceDebugSampleLabel label,
    required VoiceDebugSnapshot snapshot,
    required VoiceWakeConfig voiceWakeConfig,
    required VoiceAudioGateConfig audioGateConfig,
  }) {
    return VoiceDebugSample(
      createdAt: DateTime.now(),
      label: label,
      rawText: snapshot.rawText,
      normalizedText: snapshot.normalizedText,
      sttFlags: snapshot.sttFlags,
      wakeWord: snapshot.wakeWord,
      matchType: snapshot.matchType,
      wakeScore: snapshot.wakeScore,
      command: snapshot.command,
      durationMs: snapshot.durationMs,
      speechDurationMs: snapshot.speechDurationMs,
      avgRms: snapshot.avgRms,
      maxRms: snapshot.maxRms,
      speechLikeRatio: snapshot.speechLikeRatio,
      gateReason: snapshot.gateReason,
      gateFlags: snapshot.gateFlags,
      recordReason: snapshot.recordReason,
      bargeInDetected: snapshot.bargeInDetected,
      bargeInAvgRms: snapshot.bargeInAvgRms,
      bargeInMaxRms: snapshot.bargeInMaxRms,
      bargeInSpeechLikeRatio: snapshot.bargeInSpeechLikeRatio,
      bargeInReason: snapshot.bargeInReason,
      voiceWakeConfig: voiceWakeConfig,
      audioGateConfig: audioGateConfig,
    );
  }

  factory VoiceDebugSample.fromJson(Map<String, Object?> json) {
    return VoiceDebugSample(
      createdAt:
          DateTime.tryParse(_stringValue(json['createdAt'])) ?? DateTime(1970),
      label: VoiceDebugSampleLabel.values.firstWhere(
        (label) => label.name == json['label'],
        orElse: () => VoiceDebugSampleLabel.ignoredCorrectly,
      ),
      rawText: _stringValue(json['rawText']),
      normalizedText: _stringValue(json['normalizedText']),
      sttFlags: _stringList(json['sttFlags']),
      wakeWord: _stringValue(json['wakeWord']),
      matchType: _stringValue(json['matchType']),
      wakeScore: _doubleValue(json['wakeScore']),
      command: _stringValue(json['command']),
      durationMs: _intValue(json['durationMs']),
      speechDurationMs: _intValue(json['speechDurationMs']),
      avgRms: _doubleValue(json['avgRms']),
      maxRms: _doubleValue(json['maxRms']),
      speechLikeRatio: _doubleValue(json['speechLikeRatio']),
      gateReason: _stringValue(json['gateReason']),
      gateFlags: _stringList(json['gateFlags']),
      recordReason: _stringValue(json['recordReason']),
      bargeInDetected: json['bargeInDetected'] == true,
      bargeInAvgRms: _doubleValue(json['bargeInAvgRms']),
      bargeInMaxRms: _doubleValue(json['bargeInMaxRms']),
      bargeInSpeechLikeRatio: _doubleValue(json['bargeInSpeechLikeRatio']),
      bargeInReason: _stringValue(json['bargeInReason']),
      voiceWakeConfig: VoiceWakeConfig.fromJson(json['voiceWakeConfig']),
      audioGateConfig: VoiceAudioGateConfig.fromJson(json['audioGateConfig']),
    );
  }

  final DateTime createdAt;
  final VoiceDebugSampleLabel label;
  final String rawText;
  final String normalizedText;
  final List<String> sttFlags;
  final String wakeWord;
  final String matchType;
  final double wakeScore;
  final String command;
  final int durationMs;
  final int speechDurationMs;
  final double avgRms;
  final double maxRms;
  final double speechLikeRatio;
  final String gateReason;
  final List<String> gateFlags;
  final String recordReason;
  final bool bargeInDetected;
  final double bargeInAvgRms;
  final double bargeInMaxRms;
  final double bargeInSpeechLikeRatio;
  final String bargeInReason;
  final VoiceWakeConfig voiceWakeConfig;
  final VoiceAudioGateConfig audioGateConfig;

  Map<String, Object> toJson() {
    return {
      'createdAt': createdAt.toIso8601String(),
      'label': label.name,
      'rawText': rawText,
      'normalizedText': normalizedText,
      'sttFlags': sttFlags,
      'wakeWord': wakeWord,
      'matchType': matchType,
      'wakeScore': wakeScore,
      'command': command,
      'durationMs': durationMs,
      'speechDurationMs': speechDurationMs,
      'avgRms': avgRms,
      'maxRms': maxRms,
      'speechLikeRatio': speechLikeRatio,
      'gateReason': gateReason,
      'gateFlags': gateFlags,
      'recordReason': recordReason,
      'bargeInDetected': bargeInDetected,
      'bargeInAvgRms': bargeInAvgRms,
      'bargeInMaxRms': bargeInMaxRms,
      'bargeInSpeechLikeRatio': bargeInSpeechLikeRatio,
      'bargeInReason': bargeInReason,
      'voiceWakeConfig': voiceWakeConfig.toJson(),
      'audioGateConfig': audioGateConfig.toJson(),
    };
  }
}

String _stringValue(Object? value) => value is String ? value : '';

int _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return 0;
}

double _doubleValue(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return 0;
}

List<String> _stringList(Object? value) {
  if (value is List) {
    return value.whereType<String>().toList(growable: false);
  }
  return const [];
}

import 'voice_state.dart';

class VoiceDebugSnapshot {
  VoiceDebugSnapshot({
    this.voiceState = VoiceState.idle,
    this.durationMs = 0,
    this.speechDurationMs = 0,
    this.avgRms = 0,
    this.maxRms = 0,
    this.speechLikeRatio = 0,
    this.recordReason = '',
    this.callStt = false,
    this.gateReason = '',
    this.gateFlags = const [],
    this.rawText = '',
    this.normalizedText = '',
    this.sttFlags = const [],
    this.wakeWord = '',
    this.matchType = '',
    this.wakeScore = 0,
    this.command = '',
    this.wakeIgnoredReason = '',
    this.wakeCooldownActive = false,
    this.ttsCooldownActive = false,
    this.bargeInDetected = false,
    this.bargeInAvgRms = 0,
    this.bargeInMaxRms = 0,
    this.bargeInSpeechLikeRatio = 0,
    this.bargeInReason = '',
    this.lifecycleState = '',
    this.lifecycleReason = '',
    this.permissionStatus = '',
    this.recordingInProgress = false,
    this.runtimeWarning = '',
    this.gatewayOk = false,
    this.sttOk = false,
    this.llmOk = false,
    this.ttsOk = false,
    this.gatewayHealthReason = '',
    this.voiceProfile = 'balanced',
    this.isCustomVoiceProfile = false,
    this.profileSource = 'preset',
    this.wakeDetectorType = 'stt',
    this.wakeDetectorStatus = 'ready',
    DateTime? gatewayCheckedAt,
    DateTime? updatedAt,
  }) : gatewayCheckedAt =
           gatewayCheckedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
       updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final VoiceState voiceState;
  final int durationMs;
  final int speechDurationMs;
  final double avgRms;
  final double maxRms;
  final double speechLikeRatio;
  final String recordReason;
  final bool callStt;
  final String gateReason;
  final List<String> gateFlags;
  final String rawText;
  final String normalizedText;
  final List<String> sttFlags;
  final String wakeWord;
  final String matchType;
  final double wakeScore;
  final String command;
  final String wakeIgnoredReason;
  final bool wakeCooldownActive;
  final bool ttsCooldownActive;
  final bool bargeInDetected;
  final double bargeInAvgRms;
  final double bargeInMaxRms;
  final double bargeInSpeechLikeRatio;
  final String bargeInReason;
  final String lifecycleState;
  final String lifecycleReason;
  final String permissionStatus;
  final bool recordingInProgress;
  final String runtimeWarning;
  final bool gatewayOk;
  final bool sttOk;
  final bool llmOk;
  final bool ttsOk;
  final String gatewayHealthReason;
  final String voiceProfile;
  final bool isCustomVoiceProfile;
  final String profileSource;
  final String wakeDetectorType;
  final String wakeDetectorStatus;
  final DateTime gatewayCheckedAt;
  final DateTime updatedAt;

  VoiceDebugSnapshot copyWith({
    VoiceState? voiceState,
    int? durationMs,
    int? speechDurationMs,
    double? avgRms,
    double? maxRms,
    double? speechLikeRatio,
    String? recordReason,
    bool? callStt,
    String? gateReason,
    List<String>? gateFlags,
    String? rawText,
    String? normalizedText,
    List<String>? sttFlags,
    String? wakeWord,
    String? matchType,
    double? wakeScore,
    String? command,
    String? wakeIgnoredReason,
    bool? wakeCooldownActive,
    bool? ttsCooldownActive,
    bool? bargeInDetected,
    double? bargeInAvgRms,
    double? bargeInMaxRms,
    double? bargeInSpeechLikeRatio,
    String? bargeInReason,
    String? lifecycleState,
    String? lifecycleReason,
    String? permissionStatus,
    bool? recordingInProgress,
    String? runtimeWarning,
    bool? gatewayOk,
    bool? sttOk,
    bool? llmOk,
    bool? ttsOk,
    String? gatewayHealthReason,
    String? voiceProfile,
    bool? isCustomVoiceProfile,
    String? profileSource,
    String? wakeDetectorType,
    String? wakeDetectorStatus,
    DateTime? gatewayCheckedAt,
    DateTime? updatedAt,
  }) {
    return VoiceDebugSnapshot(
      voiceState: voiceState ?? this.voiceState,
      durationMs: durationMs ?? this.durationMs,
      speechDurationMs: speechDurationMs ?? this.speechDurationMs,
      avgRms: avgRms ?? this.avgRms,
      maxRms: maxRms ?? this.maxRms,
      speechLikeRatio: speechLikeRatio ?? this.speechLikeRatio,
      recordReason: recordReason ?? this.recordReason,
      callStt: callStt ?? this.callStt,
      gateReason: gateReason ?? this.gateReason,
      gateFlags: gateFlags ?? this.gateFlags,
      rawText: rawText ?? this.rawText,
      normalizedText: normalizedText ?? this.normalizedText,
      sttFlags: sttFlags ?? this.sttFlags,
      wakeWord: wakeWord ?? this.wakeWord,
      matchType: matchType ?? this.matchType,
      wakeScore: wakeScore ?? this.wakeScore,
      command: command ?? this.command,
      wakeIgnoredReason: wakeIgnoredReason ?? this.wakeIgnoredReason,
      wakeCooldownActive: wakeCooldownActive ?? this.wakeCooldownActive,
      ttsCooldownActive: ttsCooldownActive ?? this.ttsCooldownActive,
      bargeInDetected: bargeInDetected ?? this.bargeInDetected,
      bargeInAvgRms: bargeInAvgRms ?? this.bargeInAvgRms,
      bargeInMaxRms: bargeInMaxRms ?? this.bargeInMaxRms,
      bargeInSpeechLikeRatio:
          bargeInSpeechLikeRatio ?? this.bargeInSpeechLikeRatio,
      bargeInReason: bargeInReason ?? this.bargeInReason,
      lifecycleState: lifecycleState ?? this.lifecycleState,
      lifecycleReason: lifecycleReason ?? this.lifecycleReason,
      permissionStatus: permissionStatus ?? this.permissionStatus,
      recordingInProgress: recordingInProgress ?? this.recordingInProgress,
      runtimeWarning: runtimeWarning ?? this.runtimeWarning,
      gatewayOk: gatewayOk ?? this.gatewayOk,
      sttOk: sttOk ?? this.sttOk,
      llmOk: llmOk ?? this.llmOk,
      ttsOk: ttsOk ?? this.ttsOk,
      gatewayHealthReason: gatewayHealthReason ?? this.gatewayHealthReason,
      voiceProfile: voiceProfile ?? this.voiceProfile,
      isCustomVoiceProfile: isCustomVoiceProfile ?? this.isCustomVoiceProfile,
      profileSource: profileSource ?? this.profileSource,
      wakeDetectorType: wakeDetectorType ?? this.wakeDetectorType,
      wakeDetectorStatus: wakeDetectorStatus ?? this.wakeDetectorStatus,
      gatewayCheckedAt: gatewayCheckedAt ?? this.gatewayCheckedAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}

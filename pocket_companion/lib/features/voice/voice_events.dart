import 'wake_word_matcher.dart';
import 'voice_state.dart';

sealed class VoiceEvent {
  const VoiceEvent();
}

class VoiceStateChanged extends VoiceEvent {
  const VoiceStateChanged(this.state);

  final VoiceState state;
}

class WakeDetected extends VoiceEvent {
  const WakeDetected({
    required this.persona,
    required this.wakeWord,
    required this.command,
    required this.score,
    required this.matchType,
  });

  final String persona;
  final String wakeWord;
  final String command;
  final double score;
  final WakeMatchType matchType;
}

class WakeOnlyDetected extends VoiceEvent {
  const WakeOnlyDetected({required this.persona});

  final String persona;
}

class WakeIgnored extends VoiceEvent {
  const WakeIgnored({
    required this.reason,
    required this.text,
    this.score = 0,
    this.flags = const [],
  });

  final String reason;
  final String text;
  final double score;
  final List<String> flags;
}

class UserUtteranceDetected extends VoiceEvent {
  const UserUtteranceDetected({required this.text, this.flags = const []});

  final String text;
  final List<String> flags;
}

class BargeInDetected extends VoiceEvent {
  const BargeInDetected({
    required this.avgRms,
    required this.maxRms,
    required this.speechLikeRatio,
    required this.reason,
  });

  final double avgRms;
  final double maxRms;
  final double speechLikeRatio;
  final String reason;
}

class BargeInIgnored extends VoiceEvent {
  const BargeInIgnored({
    required this.avgRms,
    required this.maxRms,
    required this.speechLikeRatio,
    required this.reason,
  });

  final double avgRms;
  final double maxRms;
  final double speechLikeRatio;
  final String reason;
}

class VoiceLogEvent extends VoiceEvent {
  const VoiceLogEvent(this.message);

  final String message;
}

class VoiceError extends VoiceEvent {
  const VoiceError(this.error);

  final Object error;
}

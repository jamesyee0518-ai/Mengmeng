import 'wake_detector_type.dart';

abstract class WakeDetector {
  WakeDetectorType get type;
  Stream<WakeDetectorEvent> get events;
  Future<void> start();
  Future<void> stop();
  Future<void> detectOnce();
  Future<void> dispose();
}

sealed class WakeDetectorEvent {
  const WakeDetectorEvent();
}

class WakeDetectorDetected extends WakeDetectorEvent {
  const WakeDetectorDetected({
    required this.persona,
    required this.wakeWord,
    required this.command,
    required this.score,
    required this.matchType,
    this.rawText,
    this.normalizedText,
    this.flags = const [],
  });

  final String persona;
  final String wakeWord;
  final String command;
  final double score;
  final String matchType;
  final String? rawText;
  final String? normalizedText;
  final List<String> flags;
}

class WakeDetectorIgnored extends WakeDetectorEvent {
  const WakeDetectorIgnored({
    required this.reason,
    this.rawText,
    this.normalizedText,
    this.score,
    this.flags = const [],
  });

  final String reason;
  final String? rawText;
  final String? normalizedText;
  final double? score;
  final List<String> flags;
}

class WakeDetectorError extends WakeDetectorEvent {
  const WakeDetectorError({required this.reason, this.error});

  final String reason;
  final Object? error;
}

class WakeDetectorLog extends WakeDetectorEvent {
  const WakeDetectorLog(this.message);

  final String message;
}

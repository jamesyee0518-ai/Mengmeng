import 'dart:convert';

import '../face/expression_state.dart';

class RobotResponse {
  const RobotResponse({
    required this.text,
    required this.emotion,
    required this.expression,
    required this.eyeAction,
    required this.mouthAction,
    required this.voice,
    required this.haptic,
    required this.shouldSpeak,
    required this.shouldRemember,
    required this.memoryUpdate,
    required this.robotState,
    required this.modelProvider,
    required this.modelError,
    required this.isFallback,
    required this.fallbackReason,
  });

  factory RobotResponse.fromJsonText(String raw) {
    try {
      final decoded = jsonDecode(_extractJson(raw));
      if (decoded is! Map<String, dynamic>) {
        return RobotResponse.fallback(reason: 'invalid_json_root');
      }
      return RobotResponse.fromMap(decoded);
    } catch (_) {
      return RobotResponse.fallback(reason: 'json_parse_failed');
    }
  }

  factory RobotResponse.fromMap(Map<String, dynamic> map) {
    return RobotResponse(
      text: _string(map['text'], '我刚刚有点没组织好语言，可以再说一遍吗？'),
      emotion: _string(map['emotion'], 'confused'),
      expression: _expression(_string(map['expression'], 'confused')),
      eyeAction: _string(map['eye_action'], 'blink'),
      mouthAction: _string(map['mouth_action'], 'small_wavy'),
      voice: RobotVoice.fromMap(map['voice']),
      haptic: _haptic(_string(map['haptic'], 'none')),
      shouldSpeak: _bool(map['should_speak'], true),
      shouldRemember: _bool(map['should_remember'], false),
      memoryUpdate: map['memory_update'],
      robotState: RobotStateSnapshot.tryParse(map['robot_state']),
      modelProvider: _string(map['model_provider'], 'rules'),
      modelError: map['model_error'] is String
          ? map['model_error'] as String
          : '',
      isFallback: false,
      fallbackReason: '',
    );
  }

  factory RobotResponse.fallback({String reason = 'unknown'}) {
    return RobotResponse(
      text: '我刚刚有点没组织好语言，可以再说一遍吗？',
      emotion: 'confused',
      expression: RobotExpression.confused,
      eyeAction: 'blink',
      mouthAction: 'small_wavy',
      voice: const RobotVoice(
        style: 'gentle',
        speed: 0.9,
        pitch: 1.0,
        volume: 0.7,
      ),
      haptic: HapticCue.none,
      shouldSpeak: true,
      shouldRemember: false,
      memoryUpdate: null,
      robotState: null,
      modelProvider: 'fallback',
      modelError: '',
      isFallback: true,
      fallbackReason: reason,
    );
  }

  final String text;
  final String emotion;
  final RobotExpression expression;
  final String eyeAction;
  final String mouthAction;
  final RobotVoice voice;
  final HapticCue haptic;
  final bool shouldSpeak;
  final bool shouldRemember;
  final Object? memoryUpdate;
  final RobotStateSnapshot? robotState;
  final String modelProvider;
  final String modelError;
  final bool isFallback;
  final String fallbackReason;

  static String _extractJson(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start >= 0 && end >= start) {
      return raw.substring(start, end + 1);
    }
    return raw;
  }

  static String _string(Object? value, String fallback) {
    return value is String && value.trim().isNotEmpty ? value : fallback;
  }

  static bool _bool(Object? value, bool fallback) {
    return switch (value) {
      bool actual => actual,
      String actual => actual.toLowerCase() == 'true',
      _ => fallback,
    };
  }

  static RobotExpression _expression(String value) {
    return switch (value) {
      'happy' => RobotExpression.happy,
      'listening' => RobotExpression.listening,
      'thinking' => RobotExpression.thinking,
      'speaking' => RobotExpression.speaking,
      'confused' => RobotExpression.confused,
      'caring' => RobotExpression.caring,
      'sleepy' => RobotExpression.sleepy,
      'dizzy' => RobotExpression.dizzy,
      'annoyed' => RobotExpression.annoyed,
      'charging' => RobotExpression.charging,
      'low_battery' || 'lowBattery' => RobotExpression.lowBattery,
      'sleeping' => RobotExpression.sleeping,
      'surprised' => RobotExpression.surprised,
      'focus' => RobotExpression.focus,
      'neutral' => RobotExpression.neutral,
      _ => RobotExpression.confused,
    };
  }

  static HapticCue _haptic(String value) {
    return switch (value) {
      'soft_tick' || 'softTick' => HapticCue.softTick,
      'soft_pulse' || 'softPulse' => HapticCue.softPulse,
      'dizzy_buzz' || 'dizzyBuzz' => HapticCue.dizzyBuzz,
      'alert_tick' || 'alertTick' => HapticCue.alertTick,
      _ => HapticCue.none,
    };
  }
}

class RobotStateSnapshot {
  const RobotStateSnapshot({
    required this.mood,
    required this.energy,
    required this.trust,
    required this.attention,
    required this.curiosity,
    required this.sleepiness,
    required this.lastInteractionAt,
  });

  static RobotStateSnapshot? tryParse(Object? value) {
    if (value is! Map<String, dynamic>) {
      return null;
    }
    return RobotStateSnapshot(
      mood: RobotResponse._string(value['mood'], 'neutral'),
      energy: _int(value['energy'], 72),
      trust: _int(value['trust'], 35),
      attention: _int(value['attention'], 60),
      curiosity: _int(value['curiosity'], 50),
      sleepiness: _int(value['sleepiness'], 20),
      lastInteractionAt: RobotResponse._string(
        value['last_interaction_at'],
        '',
      ),
    );
  }

  final String mood;
  final int energy;
  final int trust;
  final int attention;
  final int curiosity;
  final int sleepiness;
  final String lastInteractionAt;

  static int _int(Object? value, int fallback) {
    return switch (value) {
      int actual => actual,
      num actual => actual.round(),
      String actual => int.tryParse(actual) ?? fallback,
      _ => fallback,
    };
  }
}

class RobotVoice {
  const RobotVoice({
    required this.style,
    required this.speed,
    required this.pitch,
    required this.volume,
  });

  factory RobotVoice.fromMap(Object? value) {
    if (value is! Map<String, dynamic>) {
      return const RobotVoice(
        style: 'gentle',
        speed: 0.9,
        pitch: 1.0,
        volume: 0.7,
      );
    }
    return RobotVoice(
      style: RobotResponse._string(value['style'], 'gentle'),
      speed: _number(value['speed'], 0.9),
      pitch: _number(value['pitch'], 1.0),
      volume: _number(value['volume'], 0.7),
    );
  }

  final String style;
  final double speed;
  final double pitch;
  final double volume;

  static double _number(Object? value, double fallback) {
    return switch (value) {
      num actual => actual.toDouble(),
      String actual => double.tryParse(actual) ?? fallback,
      _ => fallback,
    };
  }
}

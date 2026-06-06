import 'package:flutter/foundation.dart';

enum RobotExpression {
  neutral,
  happy,
  listening,
  thinking,
  speaking,
  confused,
  caring,
  sleepy,
  dizzy,
  annoyed,
  charging,
  lowBattery,
  sleeping,
  surprised,
  focus,
}

enum HapticCue { none, softTick, softPulse, dizzyBuzz, alertTick }

enum FaceRole { femaleSoft, femaleLively, maleCalm }

@immutable
class ExpressionState {
  const ExpressionState({
    required this.expression,
    required this.role,
    required this.label,
    required this.eyeAction,
    required this.mouthAction,
    required this.haptic,
    required this.energy,
    required this.isAwake,
    required this.isSpeaking,
    required this.updatedAt,
  });

  factory ExpressionState.initial() {
    return ExpressionState(
      expression: RobotExpression.neutral,
      role: FaceRole.femaleLively,
      label: '待机',
      eyeAction: 'soft_blink',
      mouthAction: 'rest',
      haptic: HapticCue.none,
      energy: 72,
      isAwake: true,
      isSpeaking: false,
      updatedAt: DateTime.now(),
    );
  }

  final RobotExpression expression;
  final FaceRole role;
  final String label;
  final String eyeAction;
  final String mouthAction;
  final HapticCue haptic;
  final int energy;
  final bool isAwake;
  final bool isSpeaking;
  final DateTime updatedAt;

  ExpressionState copyWith({
    RobotExpression? expression,
    FaceRole? role,
    String? label,
    String? eyeAction,
    String? mouthAction,
    HapticCue? haptic,
    int? energy,
    bool? isAwake,
    bool? isSpeaking,
    DateTime? updatedAt,
  }) {
    return ExpressionState(
      expression: expression ?? this.expression,
      role: role ?? this.role,
      label: label ?? this.label,
      eyeAction: eyeAction ?? this.eyeAction,
      mouthAction: mouthAction ?? this.mouthAction,
      haptic: haptic ?? this.haptic,
      energy: energy ?? this.energy,
      isAwake: isAwake ?? this.isAwake,
      isSpeaking: isSpeaking ?? this.isSpeaking,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

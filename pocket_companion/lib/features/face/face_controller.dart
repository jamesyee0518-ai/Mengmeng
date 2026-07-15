import 'package:flutter/foundation.dart';

import '../chat/robot_response.dart';
import 'expression_state.dart';

class FaceController extends ChangeNotifier {
  ExpressionState _state = ExpressionState.initial();

  ExpressionState get state => _state;

  void setRole(FaceRole role) {
    _state = _state.copyWith(role: role, updatedAt: DateTime.now());
    notifyListeners();
  }

  void applyRobotResponse(RobotResponse response) {
    _set(
      response.expression,
      label: response.text,
      eyeAction: response.eyeAction,
      mouthAction: response.mouthAction,
      haptic: response.haptic,
      isAwake: response.expression != RobotExpression.sleeping,
      isSpeaking: false,
      energy: response.robotState?.energy,
    );
  }

  void beginSpeaking() {
    _state = _state.copyWith(
      isSpeaking: true,
      mouthAction: 'rms_speaking',
      updatedAt: DateTime.now(),
    );
    notifyListeners();
  }

  void endSpeaking() {
    _state = _state.copyWith(
      isSpeaking: false,
      mouthAction: 'rest',
      updatedAt: DateTime.now(),
    );
    notifyListeners();
  }

  void tap() {
    _set(
      RobotExpression.happy,
      label: '被轻触',
      eyeAction: 'blink',
      mouthAction: 'smile',
      haptic: HapticCue.softTick,
    );
  }

  void doubleTap() {
    _set(
      RobotExpression.listening,
      label: '唤醒倾听',
      eyeAction: 'wide_focus',
      mouthAction: 'small_open',
      haptic: HapticCue.softPulse,
    );
  }

  void longPress() {
    _set(
      RobotExpression.thinking,
      label: '思考中',
      eyeAction: 'look_up',
      mouthAction: 'flat',
      haptic: HapticCue.softPulse,
    );
  }

  void thinking({String label = '思考中'}) {
    _set(
      RobotExpression.thinking,
      label: label,
      eyeAction: 'look_up',
      mouthAction: 'thinking_dots',
      haptic: HapticCue.softPulse,
    );
  }

  void shake() {
    _set(
      RobotExpression.dizzy,
      label: '有点晕',
      eyeAction: 'spiral',
      mouthAction: 'wavy',
      haptic: HapticCue.dizzyBuzz,
    );
  }

  void charge() {
    _set(
      RobotExpression.charging,
      label: '补充能量',
      eyeAction: 'relaxed',
      mouthAction: 'soft_smile',
      haptic: HapticCue.softPulse,
      energy: 88,
    );
  }

  void lowBattery() {
    _set(
      RobotExpression.lowBattery,
      label: '低电量',
      eyeAction: 'droopy',
      mouthAction: 'small_frown',
      haptic: HapticCue.alertTick,
      energy: 14,
    );
  }

  void flipDown() {
    _set(
      RobotExpression.sleeping,
      label: '倒扣休眠',
      eyeAction: 'closed',
      mouthAction: 'rest',
      haptic: HapticCue.none,
      isAwake: false,
    );
  }

  void speak() {
    _set(
      RobotExpression.speaking,
      label: '说话中',
      eyeAction: 'focused',
      mouthAction: 'rms_speaking',
      haptic: HapticCue.none,
      isSpeaking: true,
    );
  }

  void reset() {
    _state = ExpressionState.initial();
    notifyListeners();
  }

  void _set(
    RobotExpression expression, {
    required String label,
    required String eyeAction,
    required String mouthAction,
    required HapticCue haptic,
    int? energy,
    bool isAwake = true,
    bool isSpeaking = false,
  }) {
    _state = _state.copyWith(
      expression: expression,
      label: label,
      eyeAction: eyeAction,
      mouthAction: mouthAction,
      haptic: haptic,
      energy: energy,
      isAwake: isAwake,
      isSpeaking: isSpeaking,
      updatedAt: DateTime.now(),
    );
    notifyListeners();
  }
}

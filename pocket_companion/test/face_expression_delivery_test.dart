import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_companion/features/chat/robot_response.dart';
import 'package:pocket_companion/features/face/face_controller.dart';
import 'package:pocket_companion/features/face/expression_state.dart';

void main() {
  test('gateway expression stays active during speech animation', () {
    final controller = FaceController();
    final response = RobotResponse.fromMap({
      'text': '我在呀，大大。',
      'expression': 'caring',
      'eye_action': 'slow_blink',
      'mouth_action': 'soft_smile',
      'should_speak': true,
    });
    controller.applyRobotResponse(response);
    expect(controller.state.expression, RobotExpression.caring);
    expect(controller.state.mouthAction, 'soft_smile');
    expect(controller.state.label, '我在呀，大大。');
    controller.beginSpeaking();
    expect(controller.state.expression, RobotExpression.caring);
    expect(controller.state.eyeAction, 'slow_blink');
    expect(controller.state.isSpeaking, isTrue);
    controller.endSpeaking();
    expect(controller.state.expression, RobotExpression.caring);
    expect(controller.state.isSpeaking, isFalse);
    controller.dispose();
  });
}

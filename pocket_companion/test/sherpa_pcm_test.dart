import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_companion/features/voice/sherpa_onnx_wake_detector.dart';

void main() {
  test('decodes PCM from an EventChannel payload at odd byte offset', () {
    final message = Uint8List.fromList([9, 9, 9, 9, 9, 0, 128, 0, 0, 255, 127]);
    final payload = Uint8List.sublistView(message, 5);
    expect(payload.offsetInBytes, 5);
    expect(SherpaOnnxWakeDetector.pcm16Samples(payload),
      [-1.0, 0.0, 32767 / 32768]);
  });

  test('empty and incomplete samples do not read past the payload', () {
    expect(SherpaOnnxWakeDetector.pcm16Samples(Uint8List(0)), isEmpty);
    expect(SherpaOnnxWakeDetector.pcm16Samples(Uint8List.fromList([0, 64, 255])),
      [0.5]);
  });
}

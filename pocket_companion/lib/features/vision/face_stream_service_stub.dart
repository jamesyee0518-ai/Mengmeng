import 'dart:async';

import 'face_observation.dart';

/// 非 Android 平台的空实现。
class FaceStreamService {
  final bool isSupported = false;

  bool get isRunning => false;

  FaceObservation? get latest => null;

  Stream<FaceObservation> get observations => const Stream.empty();

  Future<String?> start() async => '当前平台不支持本地人脸流检测';

  Future<void> release() async {}

  Future<void> dispose() async {}
}

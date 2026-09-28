import 'package:flutter/foundation.dart';

/// 一帧本地人脸检测结果（全部为端侧计算，不上传图像）。
///
/// centerX/centerY 为最大人脸框中心在画面中的归一化位置（0..1），
/// areaRatio 为人脸框面积占画面比例（用于距离粗估）。
@immutable
class FaceObservation {
  const FaceObservation({
    required this.timestamp,
    required this.detected,
    required this.faceCount,
    this.centerX = 0.5,
    this.centerY = 0.5,
    this.areaRatio = 0,
  });

  final DateTime timestamp;
  final bool detected;
  final int faceCount;
  final double centerX;
  final double centerY;
  final double areaRatio;

  /// 水平偏差（-0.5..0.5），供 FollowController 使用。
  double get offsetX => centerX - 0.5;

  /// 垂直偏差（-0.5..0.5）。
  double get offsetY => centerY - 0.5;
}

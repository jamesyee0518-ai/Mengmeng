import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'face_observation.dart';

/// 前置摄像头帧流 + ML Kit 端侧人脸检测。
///
/// 检测节流到约 6fps（[minIntervalMs]），全程本地计算，不保存、不上传图像。
/// 摄像头被本服务独占；需要临时让出相机（如拍照问答）时先 [release] 再 [start]。
class FaceStreamService {
  FaceStreamService() {
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        minFaceSize: 0.15,
        enableContours: false,
        enableClassification: false,
        enableLandmarks: false,
        enableTracking: false,
      ),
    );
  }

  static const int minIntervalMs = 160;

  final bool isSupported = Platform.isAndroid;

  final StreamController<FaceObservation> _observationsController =
      StreamController<FaceObservation>.broadcast();

  CameraController? _camera;
  late final FaceDetector _detector;
  InputImageRotation _rotation = InputImageRotation.rotation0deg;
  int _lastProcessAtMs = 0;
  bool _processing = false;
  bool _running = false;
  FaceObservation? _latest;

  bool get isRunning => _running;

  FaceObservation? get latest => _latest;

  Stream<FaceObservation> get observations => _observationsController.stream;

  /// 启动帧流。返回 null 表示成功，否则返回错误说明。
  Future<String?> start() async {
    if (!isSupported) {
      return '当前平台不支持本地人脸流检测';
    }
    if (_running) {
      return null;
    }
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        return '没有可用相机';
      }
      final camera = cameras.firstWhere(
        (item) => item.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _rotation = _rotationForSensorOrientation(camera.sensorOrientation);
      final controller = CameraController(
        camera,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await controller.initialize();
      await _camera?.dispose();
      _camera = controller;
      _running = true;
      await controller.startImageStream(_onFrame);
      return null;
    } catch (error) {
      _running = false;
      return '相机启动失败: $error';
    }
  }

  /// 释放相机（帧流停止，检测结果流保持可复用）。
  Future<void> release() async {
    _running = false;
    final camera = _camera;
    _camera = null;
    if (camera == null) {
      return;
    }
    try {
      await camera.stopImageStream();
    } catch (_) {}
    await camera.dispose();
  }

  Future<void> dispose() async {
    await release();
    await _detector.close();
    await _observationsController.close();
  }

  Future<void> _onFrame(CameraImage image) async {
    if (!_running || _processing) {
      return;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastProcessAtMs < minIntervalMs) {
      return;
    }
    _lastProcessAtMs = nowMs;
    _processing = true;
    try {
      final input = _toInputImage(image);
      if (input == null) {
        return;
      }
      final faces = await _detector.processImage(input);
      _emit(image, faces, DateTime.now());
    } catch (_) {
      // 单帧失败直接丢弃，等待下一帧。
    } finally {
      _processing = false;
    }
  }

  InputImage? _toInputImage(CameraImage image) {
    // imageFormatGroup.nv21 下 Android 返回 Y 平面 + VU 交错平面，
    // 顺序拼接即为 NV21 缓冲。
    if (image.planes.length < 2) {
      return null;
    }
    final builder = BytesBuilder(copy: false)
      ..add(image.planes[0].bytes)
      ..add(image.planes[1].bytes);
    return InputImage.fromBytes(
      bytes: builder.takeBytes(),
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: _rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  void _emit(CameraImage image, List<Face> faces, DateTime timestamp) {
    Face? largest;
    var largestArea = 0.0;
    for (final face in faces) {
      final box = face.boundingBox;
      final area = box.width * box.height;
      if (area > largestArea) {
        largestArea = area;
        largest = face;
      }
    }
    // 旋转 90/270 时检测坐标系宽高与原始帧互换。
    final rotated = _rotation == InputImageRotation.rotation90deg ||
        _rotation == InputImageRotation.rotation270deg;
    final frameWidth = (rotated ? image.height : image.width).toDouble();
    final frameHeight = (rotated ? image.width : image.height).toDouble();
    FaceObservation observation;
    if (largest == null || frameWidth <= 0 || frameHeight <= 0) {
      observation = FaceObservation(
        timestamp: timestamp,
        detected: false,
        faceCount: faces.length,
      );
    } else {
      final box = largest.boundingBox;
      observation = FaceObservation(
        timestamp: timestamp,
        detected: true,
        faceCount: faces.length,
        centerX: (box.left + box.width / 2) / frameWidth,
        centerY: (box.top + box.height / 2) / frameHeight,
        areaRatio: (box.width * box.height) / (frameWidth * frameHeight),
      );
    }
    _latest = observation;
    if (!_observationsController.isClosed) {
      _observationsController.add(observation);
    }
  }

  static InputImageRotation _rotationForSensorOrientation(int degrees) {
    return switch (degrees) {
      90 => InputImageRotation.rotation90deg,
      180 => InputImageRotation.rotation180deg,
      270 => InputImageRotation.rotation270deg,
      _ => InputImageRotation.rotation0deg,
    };
  }
}

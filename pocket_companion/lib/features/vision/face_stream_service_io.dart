import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
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
  Future<void> _operations = Future<void>.value();
  int _generation = 0;
  Completer<void>? _processingDone;
  int _lastProcessAtMs = 0;
  int _lastDiagnosticAtMs = 0;
  bool _processing = false;
  bool _running = false;
  FaceObservation? _latest;

  bool get isRunning => _running;

  FaceObservation? get latest => _latest;

  Stream<FaceObservation> get observations => _observationsController.stream;

  /// 启动帧流。返回 null 表示成功，否则返回错误说明。
  Future<String?> start() {
    final generation = _generation;
    final operation = _operations.then((_) => _start(generation));
    _operations = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  Future<String?> _start(int generation) async {
    if (generation != _generation) return '检测启动已取消';
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
      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      _camera = controller;
      await controller.initialize();
      if (generation != _generation) return '检测启动已取消';
      _latest = null;
      _lastProcessAtMs = 0;
      _running = true;
      await controller.startImageStream(_onFrame);
      return null;
    } catch (error) {
      _running = false;
      await _camera?.dispose();
      _camera = null;
      return '相机启动失败: $error';
    }
  }

  /// 释放相机（帧流停止，检测结果流保持可复用）。
  Future<void> release() {
    _generation++;
    _running = false;
    _latest = null;
    final operation = _operations.then((_) => _release());
    _operations = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  Future<void> _release() async {
    final camera = _camera;
    _camera = null;
    if (camera == null) {
      return;
    }
    try {
      await camera.stopImageStream();
    } catch (_) {}
    await camera.dispose();
    await _processingDone?.future;
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
    _processingDone = Completer<void>();
    final generation = _generation;
    final camera = _camera!;
    final rotation = rotationForCamera(
      camera.description.sensorOrientation,
      camera.description.lensDirection,
      camera.value.deviceOrientation,
    );
    try {
      final logFrame = nowMs - _lastDiagnosticAtMs >= 3000;
      if (logFrame) {
        _lastDiagnosticAtMs = nowMs;
        debugPrint(
          '[face-stream] ${image.width}x${image.height} '
          'rotation=${rotation.rawValue} orientation=${camera.value.deviceOrientation.name} '
          'format=${image.format.group.name} planes=${image.planes.length} '
          'bytes=${image.planes.map((p) => p.bytes.length).join(",")}',
        );
      }
      final input = inputImageFromCameraImage(image, rotation);
      if (input == null) {
        if (logFrame) debugPrint("[face-stream] unsupported frame layout");
        return;
      }
      final faces = await _detector.processImage(input);
      if (_running && generation == _generation) {
        _emit(image, faces, DateTime.now(), rotation);
      }
    } catch (error) {
      debugPrint("[face-stream] detection failed: $error");
    } finally {
      _processing = false;
      _processingDone?.complete();
      _processingDone = null;
    }
  }

  @visibleForTesting
  static InputImage? inputImageFromCameraImage(
    CameraImage image,
    InputImageRotation rotation,
  ) {
    // CameraX 已将 YUV 平面转换为单个紧密排列的 NV21 缓冲。
    if (image.format.group != ImageFormatGroup.nv21 ||
        image.planes.length != 1 ||
        image.width <= 0 ||
        image.height <= 0) {
      return null;
    }
    final plane = image.planes.single;
    if (plane.bytesPerRow != image.width ||
        plane.bytes.length != image.width * image.height * 3 ~/ 2) {
      return null;
    }
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  void _emit(
    CameraImage image,
    List<Face> faces,
    DateTime timestamp,
    InputImageRotation rotation,
  ) {
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
    final rotated =
        rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg;
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

  @visibleForTesting
  static InputImageRotation rotationForCamera(
    int sensorOrientation,
    CameraLensDirection lens,
    DeviceOrientation orientation,
  ) {
    final compensation = switch (orientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };
    final degrees =
        (sensorOrientation +
            (lens == CameraLensDirection.front ? compensation : -compensation) +
            360) %
        360;
    return switch (degrees) {
      90 => InputImageRotation.rotation90deg,
      180 => InputImageRotation.rotation180deg,
      270 => InputImageRotation.rotation270deg,
      _ => InputImageRotation.rotation0deg,
    };
  }
}

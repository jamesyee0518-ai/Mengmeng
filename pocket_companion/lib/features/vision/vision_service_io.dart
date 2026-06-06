import 'package:camera/camera.dart';

import 'vision_check_result.dart';

class VisionService {
  CameraController? _controller;

  Future<VisionCheckResult> checkOnce() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        return const VisionCheckResult(ok: false, label: '没有相机');
      }

      final camera = cameras.firstWhere(
        (item) => item.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.low,
        enableAudio: false,
      );
      await controller.initialize();
      await _controller?.dispose();
      _controller = controller;
      final image = await controller.takePicture();
      final imageBytes = await image.readAsBytes();

      final direction = switch (camera.lensDirection) {
        CameraLensDirection.front => '前置',
        CameraLensDirection.back => '后置',
        CameraLensDirection.external => '外置',
      };
      return VisionCheckResult(
        ok: true,
        label: '$direction相机已拍照',
        detail: camera.name,
        imageBytes: imageBytes,
      );
    } catch (error) {
      return VisionCheckResult(ok: false, label: '看不到', detail: '$error');
    }
  }

  Future<void> stop() async {
    await _controller?.dispose();
    _controller = null;
  }
}

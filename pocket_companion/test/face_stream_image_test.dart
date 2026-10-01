import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:pocket_companion/features/vision/face_stream_service_io.dart';

void main() {
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  CameraImage frame({int format = 17, int planes = 1, int bytes = 12}) {
    // Use a platform payload fixture without starting the native camera.
    // ignore: deprecated_member_use
    return CameraImage.fromPlatformData({
      'format': format,
      'width': 4,
      'height': 2,
      'planes': List.generate(
        planes,
        (_) => {
          'bytes': Uint8List.fromList(List.generate(bytes, (i) => i)),
          'bytesPerRow': 4,
          'bytesPerPixel': 1,
        },
      ),
    });
  }

  test('front camera rotation follows all device orientations', () {
    final expected = [270, 0, 90, 180];
    final orientations = [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeRight,
    ];
    for (var i = 0; i < orientations.length; i++) {
      expect(
        FaceStreamService.rotationForCamera(
          270,
          CameraLensDirection.front,
          orientations[i],
        ).rawValue,
        expected[i],
      );
    }
    expect(
      FaceStreamService.rotationForCamera(
        90,
        CameraLensDirection.back,
        DeviceOrientation.landscapeLeft,
      ),
      InputImageRotation.rotation0deg,
    );
  });

  test('CameraX single-plane NV21 reaches ML Kit unchanged', () {
    final image = frame();
    final input = FaceStreamService.inputImageFromCameraImage(
      image,
      InputImageRotation.rotation270deg,
    );

    expect(input, isNotNull);
    expect(input!.bytes, same(image.planes.single.bytes));
    expect(input.metadata!.size.width, 4);
    expect(input.metadata!.size.height, 2);
    expect(input.metadata!.rotation, InputImageRotation.rotation270deg);
    expect(input.metadata!.format, InputImageFormat.nv21);
    expect(input.metadata!.bytesPerRow, 4);
  });

  test('rejects planar YUV420 instead of mislabelling it as NV21', () {
    expect(
      FaceStreamService.inputImageFromCameraImage(
        frame(format: 35, planes: 3),
        InputImageRotation.rotation0deg,
      ),
      isNull,
    );
  });

  test('rejects missing planes and incomplete NV21 data', () {
    for (final image in [frame(planes: 0), frame(bytes: 8)]) {
      expect(
        FaceStreamService.inputImageFromCameraImage(
          image,
          InputImageRotation.rotation90deg,
        ),
        isNull,
      );
    }
  });
}

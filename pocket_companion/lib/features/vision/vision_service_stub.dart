import 'vision_check_result.dart';

class VisionService {
  Future<VisionCheckResult> checkOnce() async {
    return const VisionCheckResult(ok: false, label: '看不可用');
  }

  Future<void> stop() async {}
}

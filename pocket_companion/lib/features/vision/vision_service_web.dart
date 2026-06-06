import 'vision_check_result.dart';

class VisionService {
  Future<VisionCheckResult> checkOnce() async {
    return const VisionCheckResult(ok: false, label: '网页端暂不看');
  }

  Future<void> stop() async {}
}

import 'dart:async';

import 'wake_detector.dart';
import 'wake_detector_type.dart';

class NativeWakeDetectorStub implements WakeDetector {
  NativeWakeDetectorStub(this.detectorType);

  final WakeDetectorType detectorType;
  final StreamController<WakeDetectorEvent> _events =
      StreamController<WakeDetectorEvent>.broadcast();
  bool _disposed = false;

  @override
  WakeDetectorType get type => detectorType;

  @override
  Stream<WakeDetectorEvent> get events => _events.stream;

  @override
  Future<void> start() async {
    _emit(WakeDetectorLog('${detectorType.name} wake detector stub started'));
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> detectOnce() async {
    _emit(WakeDetectorError(reason: '${detectorType.name}_not_implemented'));
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _events.close();
  }

  void _emit(WakeDetectorEvent event) {
    if (!_disposed && !_events.isClosed) {
      _events.add(event);
    }
  }
}

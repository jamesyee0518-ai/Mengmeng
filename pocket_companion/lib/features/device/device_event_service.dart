import 'dart:async';
import 'dart:math' as math;

import 'package:battery_plus/battery_plus.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'device_event.dart';

class DeviceEventService {
  DeviceEventService({
    Battery? battery,
    Duration shakeCooldown = const Duration(seconds: 2),
    Duration sampleInterval = const Duration(milliseconds: 180),
    double shakeThreshold = 22,
  }) : _battery = battery ?? Battery(),
       _shakeCooldown = shakeCooldown,
       _sampleInterval = sampleInterval,
       _shakeThreshold = shakeThreshold;

  final StreamController<DeviceEvent> _controller =
      StreamController<DeviceEvent>.broadcast();
  final StreamController<DeviceSensorSample> _sensorController =
      StreamController<DeviceSensorSample>.broadcast();
  final Battery _battery;
  final Duration _shakeCooldown;
  final Duration _sampleInterval;
  final double _shakeThreshold;
  StreamSubscription<BatteryState>? _batterySubscription;
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  DateTime? _lastShakeAt;
  DateTime? _lastSampleAt;
  BatteryState? _lastBatteryState;
  bool _isStarted = false;

  Stream<DeviceEvent> get events => _controller.stream;
  Stream<DeviceSensorSample> get sensorSamples => _sensorController.stream;

  static String shakeLevelForForce(double force) {
    final level = DeviceSensorSample.levelForForce(force);
    return level == 'calm' ? 'light' : level;
  }

  Future<void> start({bool keepAwake = true}) async {
    if (_isStarted) {
      return;
    }
    _isStarted = true;
    await setKeepAwake(keepAwake);
    await _checkInitialBatteryState();
    _batterySubscription = _battery.onBatteryStateChanged.listen(
      _handleBatteryState,
    );
    _accelerometerSubscription = accelerometerEventStream().listen(
      _handleAccelerometerEvent,
    );
  }

  Future<void> stop() async {
    await _batterySubscription?.cancel();
    await _accelerometerSubscription?.cancel();
    _batterySubscription = null;
    _accelerometerSubscription = null;
    _isStarted = false;
    await setKeepAwake(false);
  }

  Future<void> setKeepAwake(bool enabled) async {
    try {
      await WakelockPlus.toggle(enable: enabled);
    } catch (_) {
      // Some desktop/web targets may not support wakelock at runtime.
    }
  }

  void emitSimulated(String type, {double? intensity, String? intensityLevel}) {
    if (_controller.isClosed) {
      return;
    }
    _controller.add(
      DeviceEvent.simulated(
        type,
        intensity: intensity,
        intensityLevel: intensityLevel,
      ),
    );
  }

  void emitSimulatedSensorSample(double force) {
    _emitSensorSample(
      DeviceSensorSample.accelerometer(force: force, x: force, y: 0, z: 0),
    );
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
    await _sensorController.close();
  }

  Future<void> _checkInitialBatteryState() async {
    try {
      final state = await _battery.batteryState;
      _handleBatteryState(state);
      final level = await _battery.batteryLevel;
      if (level <= 20) {
        _emitHardware('low_battery');
      }
    } catch (_) {
      // Battery API is not available on every target.
    }
  }

  void _handleBatteryState(BatteryState state) {
    if (_lastBatteryState == state) {
      return;
    }
    _lastBatteryState = state;
    switch (state) {
      case BatteryState.charging:
      case BatteryState.full:
        _emitHardware('charging');
      case BatteryState.discharging:
        break;
      case BatteryState.unknown:
        break;
      case BatteryState.connectedNotCharging:
        break;
    }
  }

  void _handleAccelerometerEvent(AccelerometerEvent event) {
    final force = math.sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );
    _throttledSensorSample(force, event.x, event.y, event.z);
    if (force < _shakeThreshold) {
      return;
    }
    final now = DateTime.now();
    final lastShakeAt = _lastShakeAt;
    if (lastShakeAt != null && now.difference(lastShakeAt) < _shakeCooldown) {
      return;
    }
    _lastShakeAt = now;
    _emitHardware(
      'shake',
      intensity: force,
      intensityLevel: shakeLevelForForce(force),
      x: event.x,
      y: event.y,
      z: event.z,
    );
  }

  void _throttledSensorSample(double force, double x, double y, double z) {
    final now = DateTime.now();
    final lastSampleAt = _lastSampleAt;
    if (lastSampleAt != null &&
        now.difference(lastSampleAt) < _sampleInterval) {
      return;
    }
    _lastSampleAt = now;
    _emitSensorSample(
      DeviceSensorSample.accelerometer(force: force, x: x, y: y, z: z),
    );
  }

  void _emitSensorSample(DeviceSensorSample sample) {
    if (_sensorController.isClosed) {
      return;
    }
    _sensorController.add(sample);
  }

  void _emitHardware(
    String type, {
    double? intensity,
    String? intensityLevel,
    double? x,
    double? y,
    double? z,
  }) {
    if (_controller.isClosed) {
      return;
    }
    _controller.add(
      DeviceEvent.hardware(
        type,
        intensity: intensity,
        intensityLevel: intensityLevel,
        x: x,
        y: y,
        z: z,
      ),
    );
  }
}

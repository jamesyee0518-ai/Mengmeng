import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import 'gimbal_models.dart';

/// Android 原生 DjiGimbalPlugin 的桥接实现。
/// 通道：pocket_companion/dji_gimbal（方法）、pocket_companion/dji_gimbal_state（事件）。
class GimbalService {
  GimbalService() {
    if (!isSupported) {
      return;
    }
    _events = _eventChannel.receiveBroadcastStream().listen(
      _handleEvent,
      onError: (Object error) {
        _errorsController.add('$error');
      },
    );
  }

  static const MethodChannel _methodChannel = MethodChannel(
    'pocket_companion/dji_gimbal',
  );
  static const EventChannel _eventChannel = EventChannel(
    'pocket_companion/dji_gimbal_state',
  );

  final StreamController<GimbalDeviceState> _deviceStatesController =
      StreamController<GimbalDeviceState>.broadcast();
  final StreamController<GimbalAttitude> _attitudesController =
      StreamController<GimbalAttitude>.broadcast();
  final StreamController<String> _errorsController =
      StreamController<String>.broadcast();

  StreamSubscription<dynamic>? _events;
  GimbalDeviceState _deviceState = const GimbalDeviceState(
    phase: GimbalPhase.idle,
  );

  /// 仅 Android 原生层实现了 DJI 桥接。
  final bool isSupported = Platform.isAndroid;

  GimbalDeviceState get deviceState => _deviceState;

  Stream<GimbalDeviceState> get deviceStates => _deviceStatesController.stream;

  Stream<GimbalAttitude> get attitudes => _attitudesController.stream;

  Stream<String> get errors => _errorsController.stream;

  Future<GimbalDeviceState> register() async {
    if (!isSupported) {
      return _deviceState;
    }
    return _invokeStatus('register');
  }

  Future<GimbalDeviceState> connectBluetooth() async {
    if (!isSupported) {
      return _deviceState;
    }
    return _invokeStatus('connectBluetooth');
  }

  Future<void> setVelocity({
    required double yawDps,
    required double pitchDps,
  }) {
    if (!isSupported) {
      return Future.value();
    }
    return _methodChannel.invokeMethod<void>('setVelocity', {
      'yawDps': yawDps,
      'pitchDps': pitchDps,
    });
  }

  Future<void> stop() => isSupported
      ? _methodChannel.invokeMethod<void>('stop')
      : Future.value();

  Future<void> rotateTo({
    required double yawDeg,
    required double pitchDeg,
    int durationMs = 800,
  }) {
    if (!isSupported) {
      return Future.value();
    }
    return _methodChannel.invokeMethod<void>('rotateTo', {
      'yawDeg': yawDeg,
      'pitchDeg': pitchDeg,
      'durationMs': durationMs,
    });
  }

  Future<void> center() => isSupported
      ? _methodChannel.invokeMethod<void>('center')
      : Future.value();

  Future<void> dispose() async {
    await _events?.cancel();
    _events = null;
    await _deviceStatesController.close();
    await _attitudesController.close();
    await _errorsController.close();
  }

  Future<GimbalDeviceState> _invokeStatus(String method) async {
    try {
      final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        method,
      );
      final state = _parseState(result);
      _deviceState = state;
      _deviceStatesController.add(state);
      return state;
    } on PlatformException catch (error) {
      _errorsController.add('${error.code}: ${error.message}');
      rethrow;
    }
  }

  static GimbalDeviceState _parseState(Map<dynamic, dynamic>? result) {
    if (result == null) {
      return const GimbalDeviceState(phase: GimbalPhase.idle);
    }
    return GimbalDeviceState(
      phase: GimbalPhase.fromName(result['phase'] as String?),
      model: (result['model'] as String?) ?? '',
      hasGimbal: result['hasGimbal'] == true,
    );
  }

  void _handleEvent(dynamic event) {
    if (event is! Map) {
      return;
    }
    switch (event['type']) {
      case 'phase':
        final state = GimbalDeviceState(
          phase: GimbalPhase.fromName(event['phase'] as String?),
          model: (event['model'] as String?) ?? '',
          hasGimbal: event['hasGimbal'] == true,
        );
        _deviceState = state;
        _deviceStatesController.add(state);
      case 'attitude':
        _attitudesController.add(
          GimbalAttitude(
            pitchDeg: _asDouble(event['pitch']),
            yawDeg: _asDouble(event['yaw']),
            rollDeg: _asDouble(event['roll']),
            timestamp: DateTime.now(),
          ),
        );
      case 'error':
        _errorsController.add((event['message'] as String?) ?? '未知错误');
    }
  }

  static double _asDouble(Object? value) {
    return value is num ? value.toDouble() : 0;
  }
}

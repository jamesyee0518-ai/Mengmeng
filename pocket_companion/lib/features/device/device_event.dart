import 'package:flutter/foundation.dart';

@immutable
class DeviceEvent {
  const DeviceEvent({
    required this.type,
    required this.source,
    required this.createdAt,
    this.intensity,
    this.intensityLevel,
    this.x,
    this.y,
    this.z,
  });

  factory DeviceEvent.simulated(
    String type, {
    double? intensity,
    String? intensityLevel,
  }) {
    return DeviceEvent(
      type: type,
      source: 'simulated',
      createdAt: DateTime.now(),
      intensity: intensity,
      intensityLevel: intensityLevel,
    );
  }

  factory DeviceEvent.hardware(
    String type, {
    double? intensity,
    String? intensityLevel,
    double? x,
    double? y,
    double? z,
  }) {
    return DeviceEvent(
      type: type,
      source: 'hardware',
      createdAt: DateTime.now(),
      intensity: intensity,
      intensityLevel: intensityLevel,
      x: x,
      y: y,
      z: z,
    );
  }

  final String type;
  final String source;
  final DateTime createdAt;
  final double? intensity;
  final String? intensityLevel;
  final double? x;
  final double? y;
  final double? z;

  String get label {
    final level = intensityLevel;
    final value = intensity;
    if (level == null && value == null) {
      return '$source:$type';
    }
    final valueText = value == null ? '' : ' ${value.toStringAsFixed(1)}';
    return '$source:$type ${level ?? ''}$valueText'.trim();
  }

  Map<String, Object?> toGatewayPayload() {
    final payload = <String, Object?>{
      'type': type,
      'source': source,
      'intensity': intensity,
      'intensity_level': intensityLevel,
      'x': x,
      'y': y,
      'z': z,
    };
    payload.removeWhere((_, value) => value == null);
    return payload;
  }
}

@immutable
class DeviceSensorSample {
  const DeviceSensorSample({
    required this.force,
    required this.level,
    required this.x,
    required this.y,
    required this.z,
    required this.createdAt,
  });

  factory DeviceSensorSample.accelerometer({
    required double force,
    required double x,
    required double y,
    required double z,
  }) {
    return DeviceSensorSample(
      force: force,
      level: DeviceSensorSample.levelForForce(force),
      x: x,
      y: y,
      z: z,
      createdAt: DateTime.now(),
    );
  }

  final double force;
  final String level;
  final double x;
  final double y;
  final double z;
  final DateTime createdAt;

  static String levelForForce(double force) {
    if (force >= 42) {
      return 'extreme';
    }
    if (force >= 32) {
      return 'strong';
    }
    if (force >= 22) {
      return 'medium';
    }
    if (force >= 12) {
      return 'light';
    }
    return 'calm';
  }

  String get label => '$level ${force.toStringAsFixed(1)}';
}

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_companion/features/device/device_event.dart';
import 'package:pocket_companion/features/device/device_event_service.dart';

void main() {
  test('emits simulated device events', () async {
    final service = DeviceEventService();
    addTearDown(service.dispose);

    final nextEvent = service.events.first;
    service.emitSimulated('shake');

    final event = await nextEvent;
    expect(event.type, 'shake');
    expect(event.source, 'simulated');
    expect(event.label, 'simulated:shake');
  });

  test('classifies shake force levels', () {
    expect(DeviceSensorSample.levelForForce(9.8), 'calm');
    expect(DeviceSensorSample.levelForForce(12), 'light');
    expect(DeviceSensorSample.levelForForce(22), 'medium');
    expect(DeviceSensorSample.levelForForce(32), 'strong');
    expect(DeviceSensorSample.levelForForce(42), 'extreme');

    expect(DeviceEventService.shakeLevelForForce(10), 'light');
    expect(DeviceEventService.shakeLevelForForce(24), 'medium');
    expect(DeviceEventService.shakeLevelForForce(32), 'strong');
    expect(DeviceEventService.shakeLevelForForce(42), 'extreme');
  });

  test('emits simulated sensor samples', () async {
    final service = DeviceEventService();
    addTearDown(service.dispose);

    final nextSample = service.sensorSamples.first;
    service.emitSimulatedSensorSample(28);

    final sample = await nextSample;
    expect(sample.force, 28);
    expect(sample.level, 'medium');
    expect(sample.label, 'medium 28.0');
  });
}

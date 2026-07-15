import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_companion/core/network/gateway_health.dart';

void main() {
  test('GatewayHealth.fromJson parses healthy response', () {
    final health = GatewayHealth.fromJson({
      'ok': true,
      'gateway': {'ok': true, 'version': 'dev', 'uptimeSec': 12},
      'stt': {
        'ok': true,
        'engine': 'whisper-cli',
        'ffmpeg': true,
        'whisperCli': true,
        'modelPathExists': true,
        'reason': null,
      },
      'llm': {
        'ok': true,
        'provider': 'rules',
        'model': 'rules',
        'reachable': true,
        'reason': null,
      },
      'tts': {'ok': true, 'provider': 'system', 'reason': null},
      'timestamp': '2026-06-07T00:00:00Z',
    });

    expect(health.ok, isTrue);
    expect(health.gateway.ok, isTrue);
    expect(health.stt.ffmpeg, isTrue);
    expect(health.llm.provider, 'rules');
    expect(health.reason, isEmpty);
  });

  test('component unavailable keeps reason', () {
    final health = GatewayHealth.fromJson({
      'ok': false,
      'gateway': {'ok': true},
      'stt': {'ok': false, 'reason': 'ffmpeg_unavailable'},
      'llm': {'ok': true},
      'tts': {'ok': true},
    });

    expect(health.ok, isFalse);
    expect(health.stt.ok, isFalse);
    expect(health.reason, 'ffmpeg_unavailable');
  });
}

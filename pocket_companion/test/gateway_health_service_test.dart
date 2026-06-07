import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_companion/core/network/gateway_health_service.dart';
import 'package:pocket_companion/core/network/robot_http_transport.dart';

void main() {
  test('checkHealth returns parsed health', () async {
    final service = GatewayHealthService(
      transport: _HealthTransport(
        body:
            '{"ok":true,"gateway":{"ok":true},"stt":{"ok":true},'
            '"llm":{"ok":true},"tts":{"ok":true}}',
      ),
    );

    final health = await service.checkHealth();

    expect(health.ok, isTrue);
    expect(health.checkedAt.millisecondsSinceEpoch, greaterThan(0));
  });

  test('checkHealth timeout returns ok false', () async {
    final service = GatewayHealthService(
      transport: _HealthTransport(timeout: true),
    );

    final health = await service.checkHealth(
      timeout: const Duration(milliseconds: 1),
    );

    expect(health.ok, isFalse);
    expect(health.reason, 'gateway_timeout');
  });
}

class _HealthTransport implements RobotHttpTransport {
  const _HealthTransport({this.body = '{}', this.timeout = false});

  final String body;
  final bool timeout;

  @override
  Future<RobotHttpResponse> get(
    Uri uri, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (this.timeout) {
      throw TimeoutException('slow');
    }
    return RobotHttpResponse(statusCode: 200, body: body);
  }

  @override
  Future<RobotHttpResponse> postJson(
    Uri uri,
    String body, {
    Duration timeout = const Duration(seconds: 3),
  }) {
    throw UnimplementedError();
  }
}

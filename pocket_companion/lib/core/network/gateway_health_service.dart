import 'dart:async';
import 'dart:convert';

import 'gateway_health.dart';
import 'robot_http_transport.dart';

class GatewayHealthService {
  GatewayHealthService({
    this.baseUrl = const String.fromEnvironment(
      'AI_GATEWAY_BASE_URL',
      defaultValue: 'http://192.168.1.111:8787',
    ),
    RobotHttpTransport? transport,
  }) : _transport = transport ?? RobotHttpTransport();

  final String baseUrl;
  final RobotHttpTransport _transport;

  Future<GatewayHealth> checkHealth({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final checkedAt = DateTime.now();
    try {
      final response = await _transport.get(_uri('/health'), timeout: timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return GatewayHealth.unavailable(
          reason: 'gateway_unavailable',
          checkedAt: checkedAt,
        );
      }
      return GatewayHealth.fromJson(
        jsonDecode(response.body),
        checkedAt: checkedAt,
      );
    } on TimeoutException {
      return GatewayHealth.unavailable(
        reason: 'gateway_timeout',
        checkedAt: checkedAt,
      );
    } catch (_) {
      return GatewayHealth.unavailable(
        reason: 'health_check_failed',
        checkedAt: checkedAt,
      );
    }
  }

  Uri _uri(String path) => Uri.parse('$baseUrl$path');
}

import 'gateway_config.dart';
import 'dart:async';
import 'dart:convert';

import 'gateway_health.dart';
import 'robot_http_transport.dart';

class GatewayHealthService {
  GatewayHealthService({
    this.baseUrl = defaultGatewayBaseUrl,
    RobotHttpTransport? transport,
  }) : _transport = transport ?? RobotHttpTransport();

  final String baseUrl;
  final RobotHttpTransport _transport;

  Future<GatewayHealth> checkHealth({
    Duration timeout = gatewayHealthTimeout,
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

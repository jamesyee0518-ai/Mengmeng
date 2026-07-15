import 'dart:async';

class RobotHttpResponse {
  const RobotHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

class RobotHttpTransport {
  Future<RobotHttpResponse> get(
    Uri uri, {
    Duration timeout = const Duration(seconds: 3),
  }) {
    throw UnsupportedError('HTTP transport is not available on this platform.');
  }

  Future<RobotHttpResponse> postJson(
    Uri uri,
    String body, {
    Duration timeout = const Duration(seconds: 3),
  }) {
    throw UnsupportedError('HTTP transport is not available on this platform.');
  }
}

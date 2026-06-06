import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_companion/core/network/ai_gateway_client.dart';
import 'package:pocket_companion/core/network/robot_http_transport.dart';

void main() {
  test('marks invalid json response as fallback', () async {
    final client = AiGatewayClient(transport: _FakeTransport(body: 'not json'));

    final response = await client.chat('hello');

    expect(response.isFallback, isTrue);
    expect(response.fallbackReason, 'json_parse_failed');
  });

  test('marks http errors as fallback', () async {
    final client = AiGatewayClient(
      transport: _FakeTransport(statusCode: 500, body: '{}'),
    );

    final response = await client.event('tap');

    expect(response.isFallback, isTrue);
    expect(response.fallbackReason, 'http_500');
  });
}

class _FakeTransport implements RobotHttpTransport {
  const _FakeTransport({this.statusCode = 200, required this.body});

  final int statusCode;
  final String body;

  @override
  Future<RobotHttpResponse> get(
    Uri uri, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    return RobotHttpResponse(statusCode: statusCode, body: body);
  }

  @override
  Future<RobotHttpResponse> postJson(
    Uri uri,
    String body, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    return RobotHttpResponse(statusCode: statusCode, body: this.body);
  }
}

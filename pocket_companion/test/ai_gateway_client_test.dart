import 'dart:convert';
import 'package:pocket_companion/features/chat/conversation_context.dart';
import 'package:pocket_companion/features/settings/companion_settings.dart';
import 'package:pocket_companion/core/network/gateway_health_service.dart';
import 'package:pocket_companion/features/voice/speech_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_companion/core/network/ai_gateway_client.dart';
import 'package:pocket_companion/core/network/robot_http_transport.dart';

void main() {
  test('chat, health and speech share their default gateway', () {
    final chat = AiGatewayClient();
    expect(GatewayHealthService().baseUrl, chat.baseUrl);
    expect(SpeechService().baseUrl, chat.baseUrl);
    expect(
      SpeechService(baseUrl: 'https://example.test/gw').baseUrl,
      'https://example.test/gw',
    );
  });
  test('text and vision carry context, privacy removes it', () async {
    final transport = _FakeTransport(body: '{}');
    final client = AiGatewayClient(transport: transport);
    final context = ConversationContext(
      sessionId: 'a',
      persona: 'mengmeng',
      history: [
        {'role': 'user', 'content': '我叫小明'},
        {'role': 'assistant', 'content': '你好'},
      ],
    );
    await client.chat('我叫什么', context: context);
    expect(jsonDecode(transport.lastBody!)['context'], context.toJson());
    await client.chatWithVision('看一下', [1, 2], context: context);
    expect(jsonDecode(transport.lastBody!)['context'], context.toJson());
    final privacy = CompanionSettings.initial().copyWith(privacyMode: true);
    await client.chat('hi', context: context, settings: privacy);
    expect(jsonDecode(transport.lastBody!).containsKey('context'), isFalse);
    await client.chatWithVision('hi', [1], context: context, settings: privacy);
    expect(jsonDecode(transport.lastBody!).containsKey('context'), isFalse);
  });

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
  _FakeTransport({this.statusCode = 200, required this.body});

  String? lastBody;
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
    lastBody = body;
    return RobotHttpResponse(statusCode: statusCode, body: this.body);
  }
}

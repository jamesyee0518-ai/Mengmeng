import 'dart:async';
import 'dart:convert';

import '../../features/chat/robot_response.dart';
import '../../features/device/device_event.dart';
import '../../features/settings/companion_settings.dart';
import 'robot_http_transport.dart';

class AiGatewayClient {
  static const Duration modelResponseTimeout = Duration(seconds: 75);

  AiGatewayClient({
    this.baseUrl = const String.fromEnvironment(
      'AI_GATEWAY_BASE_URL',
      defaultValue: 'http://192.168.1.111:8787',
    ),
    RobotHttpTransport? transport,
  }) : _transport = transport ?? RobotHttpTransport();

  final String baseUrl;
  final RobotHttpTransport _transport;

  String get debugBaseUrl => baseUrl;

  Future<bool> health() async {
    try {
      final response = await _transport.get(_uri('/health'));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<RobotResponse> chat(
    String text, {
    CompanionSettings? settings,
    String? persona,
  }) async {
    return _postRobotResponse('/chat', {
      'text': text,
      if (persona != null) 'persona': persona,
      if (settings != null) 'settings': settings.toGatewayPayload(),
    });
  }

  Future<RobotResponse> vision(
    List<int> imageBytes, {
    String prompt = '请用一句中文描述你看到了什么。',
    CompanionSettings? settings,
    String? persona,
  }) async {
    return _postRobotResponse('/vision', {
      'image_base64': base64Encode(imageBytes),
      'prompt': prompt,
      if (persona != null) 'persona': persona,
      if (settings != null) 'settings': settings.toGatewayPayload(),
    });
  }

  Future<RobotResponse> event(
    String type, {
    CompanionSettings? settings,
    DeviceEvent? deviceEvent,
    String? persona,
    String? source,
  }) async {
    return _postRobotResponse('/event', {
      'type': type,
      if (source != null) 'source': source,
      if (persona != null) 'persona': persona,
      if (deviceEvent != null) ...deviceEvent.toGatewayPayload(),
      if (settings != null) 'settings': settings.toGatewayPayload(),
    });
  }

  Future<RobotResponse> _postRobotResponse(
    String path,
    Map<String, Object?> payload,
  ) async {
    try {
      final response = await _transport.postJson(
        _uri(path),
        jsonEncode(payload),
        timeout: modelResponseTimeout,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return RobotResponse.fallback(reason: 'http_${response.statusCode}');
      }
      return RobotResponse.fromJsonText(response.body);
    } on TimeoutException {
      return RobotResponse.fallback(reason: 'gateway_timeout');
    } catch (_) {
      return RobotResponse.fallback(reason: 'gateway_unreachable');
    }
  }

  Uri _uri(String path) {
    return Uri.parse('$baseUrl$path');
  }
}

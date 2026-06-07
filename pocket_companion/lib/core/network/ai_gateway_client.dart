import 'dart:async';
import 'dart:convert';

import '../../features/chat/robot_response.dart';
import '../../features/device/device_event.dart';
import '../../features/settings/companion_settings.dart';
import 'robot_http_transport.dart';

class AiGatewayClient {
  static const Duration healthTimeout = Duration(seconds: 2);
  static const Duration chatTimeout = Duration(seconds: 90);
  static const Duration visionTimeout = Duration(seconds: 120);

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
      final response = await _transport.get(
        _uri('/health'),
        timeout: healthTimeout,
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> diagnostics() async {
    try {
      final response = await _transport.get(
        _uri('/diagnostics'),
        timeout: const Duration(seconds: 8),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<RobotResponse> chat(
    String text, {
    CompanionSettings? settings,
    String? persona,
  }) async {
    final payload = <String, Object?>{'text': text};
    if (persona != null) {
      payload['persona'] = persona;
    }
    if (settings != null) {
      payload['settings'] = settings.toGatewayPayload();
    }
    return _postRobotResponse('/chat', payload, timeout: chatTimeout);
  }

  Future<RobotResponse> vision(
    List<int> imageBytes, {
    String prompt = '请用一句中文描述你看到了什么。',
    CompanionSettings? settings,
    String? persona,
  }) async {
    final payload = <String, Object?>{
      'image_base64': base64Encode(imageBytes),
      'prompt': prompt,
    };
    if (persona != null) {
      payload['persona'] = persona;
    }
    if (settings != null) {
      payload['settings'] = settings.toGatewayPayload();
    }
    return _postRobotResponse('/vision', payload, timeout: visionTimeout);
  }

  /// 语音+视觉合并：文本对话中附带图片，由Gateway决定是否使用视觉内容
  Future<RobotResponse> chatWithVision(
    String text,
    List<int> imageBytes, {
    String mimeType = 'image/jpeg',
    CompanionSettings? settings,
    String? persona,
  }) async {
    final payload = <String, Object?>{
      'text': text,
      'image_base64': base64Encode(imageBytes),
      'mime_type': mimeType,
    };
    if (persona != null) {
      payload['persona'] = persona;
    }
    if (settings != null) {
      payload['settings'] = settings.toGatewayPayload();
    }
    return _postRobotResponse('/chat/vision', payload, timeout: visionTimeout);
  }

  Future<RobotResponse> event(
    String type, {
    CompanionSettings? settings,
    DeviceEvent? deviceEvent,
    String? persona,
    String? source,
  }) async {
    final payload = <String, Object?>{'type': type};
    if (source != null) {
      payload['source'] = source;
    }
    if (persona != null) {
      payload['persona'] = persona;
    }
    if (deviceEvent != null) {
      payload.addAll(deviceEvent.toGatewayPayload());
    }
    if (settings != null) {
      payload['settings'] = settings.toGatewayPayload();
    }
    return _postRobotResponse('/event', payload);
  }

  Future<RobotResponse> _postRobotResponse(
    String path,
    Map<String, Object?> payload, {
    Duration timeout = chatTimeout,
  }) async {
    try {
      final response = await _transport.postJson(
        _uri(path),
        jsonEncode(payload),
        timeout: timeout,
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

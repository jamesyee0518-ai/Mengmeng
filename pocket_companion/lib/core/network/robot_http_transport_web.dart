// ignore_for_file: avoid_web_libraries_in_flutter
// ignore: deprecated_member_use
import 'dart:html' as html;

class RobotHttpResponse {
  const RobotHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

class RobotHttpTransport {
  Future<RobotHttpResponse> get(
    Uri uri, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final request = await html.HttpRequest.request(
      uri.toString(),
      method: 'GET',
      requestHeaders: const {'accept': 'application/json'},
    ).timeout(timeout);
    return RobotHttpResponse(
      statusCode: request.status ?? 0,
      body: request.responseText ?? '',
    );
  }

  Future<RobotHttpResponse> postJson(
    Uri uri,
    String body, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final request = await html.HttpRequest.request(
      uri.toString(),
      method: 'POST',
      sendData: body,
      requestHeaders: const {
        'accept': 'application/json',
        'content-type': 'application/json',
      },
    ).timeout(timeout);
    return RobotHttpResponse(
      statusCode: request.status ?? 0,
      body: request.responseText ?? '',
    );
  }
}

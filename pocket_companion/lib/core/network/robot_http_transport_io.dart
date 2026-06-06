import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      return RobotHttpResponse(
        statusCode: response.statusCode,
        body: await utf8.decodeStream(response).timeout(timeout),
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<RobotHttpResponse> postJson(
    Uri uri,
    String body, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(uri).timeout(timeout);
      final bytes = utf8.encode(body);
      request.headers.contentType = ContentType.json;
      request.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close().timeout(timeout);
      return RobotHttpResponse(
        statusCode: response.statusCode,
        body: await utf8.decodeStream(response).timeout(timeout),
      );
    } finally {
      client.close(force: true);
    }
  }
}

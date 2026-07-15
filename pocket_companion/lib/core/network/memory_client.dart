import 'dart:convert';

import '../../features/memory/memory_item.dart';
import 'robot_http_transport.dart';

class MemoryClient {
  MemoryClient({
    this.baseUrl = 'http://127.0.0.1:8787',
    RobotHttpTransport? transport,
  }) : _transport = transport ?? RobotHttpTransport();

  final String baseUrl;
  final RobotHttpTransport _transport;

  Future<List<MemoryItem>> query({String? keyword}) async {
    final response = await _transport.postJson(
      _uri('/memory/query'),
      jsonEncode({'keyword': ?keyword}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const [];
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return const [];
    }
    final items = decoded['items'];
    if (items is! List) {
      return const [];
    }
    return [
      for (final item in items)
        if (item is Map<String, dynamic>) MemoryItem.fromMap(item),
    ];
  }

  Future<int> delete({String? id}) async {
    final response = await _transport.postJson(
      _uri('/memory/delete'),
      jsonEncode({'id': ?id}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return 0;
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return 0;
    }
    final deleted = decoded['deleted'];
    return deleted is num ? deleted.toInt() : 0;
  }

  Uri _uri(String path) {
    return Uri.parse('$baseUrl$path');
  }
}

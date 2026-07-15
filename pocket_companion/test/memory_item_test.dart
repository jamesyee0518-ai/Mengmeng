import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_companion/features/memory/memory_item.dart';

void main() {
  test('parses memory item from gateway map', () {
    final item = MemoryItem.fromMap({
      'id': 'm1',
      'type': 'emotional_signal',
      'content': '今天有点累',
      'source': 'chat',
      'created_at': '2026-06-06T00:00:00Z',
    });

    expect(item.id, 'm1');
    expect(item.type, 'emotional_signal');
    expect(item.content, '今天有点累');
    expect(item.source, 'chat');
  });
}

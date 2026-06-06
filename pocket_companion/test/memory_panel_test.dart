import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_companion/core/network/memory_client.dart';
import 'package:pocket_companion/features/memory/memory_item.dart';
import 'package:pocket_companion/features/memory/memory_panel.dart';

void main() {
  testWidgets('memory panel loads, searches, and clears memories', (
    tester,
  ) async {
    final client = _FakeMemoryClient();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MemoryPanel(client: client)),
      ),
    );
    await tester.pump();

    expect(find.text('今天有点累'), findsOneWidget);
    expect(find.text('开心'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('memorySearchInput')),
      '累',
    );
    await tester.tap(find.byKey(const ValueKey('searchMemory')));
    await tester.pump();

    expect(find.text('今天有点累'), findsOneWidget);
    expect(find.text('开心'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('clearMemory')));
    await tester.pump();

    expect(find.byKey(const ValueKey('emptyMemory')), findsOneWidget);
  });
}

class _FakeMemoryClient extends MemoryClient {
  final List<MemoryItem> _items = [
    const MemoryItem(
      id: 'm1',
      type: 'emotional_signal',
      content: '今天有点累',
      source: 'chat',
      createdAt: '2026-06-06T00:00:00Z',
    ),
    const MemoryItem(
      id: 'm2',
      type: 'positive_signal',
      content: '开心',
      source: 'chat',
      createdAt: '2026-06-06T00:01:00Z',
    ),
  ];

  @override
  Future<List<MemoryItem>> query({String? keyword}) async {
    final normalized = keyword?.trim();
    if (normalized == null || normalized.isEmpty) {
      return List.of(_items);
    }
    return [
      for (final item in _items)
        if (item.content.contains(normalized)) item,
    ];
  }

  @override
  Future<int> delete({String? id}) async {
    final count = _items.length;
    _items.clear();
    return count;
  }
}

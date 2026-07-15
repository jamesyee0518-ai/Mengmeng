import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_companion/core/logging/debug_log_store.dart';
import 'package:pocket_companion/features/logs/debug_log_panel.dart';

void main() {
  test('debug log store keeps newest entries first', () {
    final store = DebugLogStore()
      ..info('chat', 'one')
      ..warning('tts', 'two');

    expect(store.entries.first.category, 'tts');
    expect(store.entries.last.category, 'chat');
  });

  testWidgets('debug log panel renders and clears entries', (tester) async {
    final store = DebugLogStore()..info('chat', 'send text');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DebugLogPanel(store: store)),
      ),
    );

    expect(find.text('chat · send text'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('clearLogs')));
    await tester.pump();

    expect(find.byKey(const ValueKey('emptyLogs')), findsOneWidget);
  });
}

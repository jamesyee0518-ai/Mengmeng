import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/logging/debug_log_entry.dart';
import '../../core/logging/debug_log_store.dart';

class DebugLogPanel extends StatelessWidget {
  const DebugLogPanel({super.key, required this.store});

  final DebugLogStore store;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long, size: 20),
                const SizedBox(width: 8),
                Text('日志', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Tooltip(
                  message: '复制日志',
                  child: IconButton(
                    key: const ValueKey('copyLogs'),
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: store.exportText()),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('日志已复制')),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy),
                  ),
                ),
                Tooltip(
                  message: '清空日志',
                  child: IconButton(
                    key: const ValueKey('clearLogs'),
                    onPressed: store.clear,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListenableBuilder(
                listenable: store,
                builder: (context, _) {
                  final entries = store.entries;
                  if (entries.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('暂无日志', key: ValueKey('emptyLogs')),
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      return _LogTile(entry: entries[index]);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry});

  final DebugLogEntry entry;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey('log_${entry.id}'),
      dense: true,
      leading: Icon(_icon, color: _color),
      title: Text('${entry.category} · ${entry.message}'),
      subtitle: Text(_timeText(entry.createdAt)),
    );
  }

  IconData get _icon {
    return switch (entry.level) {
      DebugLogLevel.info => Icons.info_outline,
      DebugLogLevel.warning => Icons.warning_amber,
      DebugLogLevel.error => Icons.error_outline,
    };
  }

  Color get _color {
    return switch (entry.level) {
      DebugLogLevel.info => const Color(0xFF74D8FF),
      DebugLogLevel.warning => const Color(0xFFFFC857),
      DebugLogLevel.error => const Color(0xFFFF6B6B),
    };
  }

  String _timeText(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    final second = time.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }
}

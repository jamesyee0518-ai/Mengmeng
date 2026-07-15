import 'package:flutter/foundation.dart';

import 'debug_log_entry.dart';

class DebugLogStore extends ChangeNotifier {
  final List<DebugLogEntry> _entries = [];
  int _nextId = 1;

  List<DebugLogEntry> get entries => List.unmodifiable(_entries.reversed);

  void info(String category, String message) {
    add(DebugLogLevel.info, category, message);
  }

  void warning(String category, String message) {
    add(DebugLogLevel.warning, category, message);
  }

  void error(String category, String message) {
    add(DebugLogLevel.error, category, message);
  }

  void add(DebugLogLevel level, String category, String message) {
    _entries.add(
      DebugLogEntry(
        id: _nextId++,
        level: level,
        category: category,
        message: message,
        createdAt: DateTime.now(),
      ),
    );
    if (_entries.length > 300) {
      _entries.removeRange(0, _entries.length - 300);
    }
    notifyListeners();
  }

  String exportText() {
    return _entries.map((entry) {
      final time = entry.createdAt.toIso8601String();
      return '[$time] ${entry.level.name} ${entry.category}: ${entry.message}';
    }).join('\n');
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }
}

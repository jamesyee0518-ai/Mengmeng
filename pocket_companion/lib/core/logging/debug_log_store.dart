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
    if (_entries.length > 120) {
      _entries.removeRange(0, _entries.length - 120);
    }
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }
}

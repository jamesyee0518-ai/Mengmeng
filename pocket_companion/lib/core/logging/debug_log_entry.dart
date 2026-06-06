enum DebugLogLevel { info, warning, error }

class DebugLogEntry {
  const DebugLogEntry({
    required this.id,
    required this.level,
    required this.category,
    required this.message,
    required this.createdAt,
  });

  final int id;
  final DebugLogLevel level;
  final String category;
  final String message;
  final DateTime createdAt;
}

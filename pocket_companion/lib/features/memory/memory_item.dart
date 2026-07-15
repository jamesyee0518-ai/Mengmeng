class MemoryItem {
  const MemoryItem({
    required this.id,
    required this.type,
    required this.content,
    required this.source,
    required this.createdAt,
  });

  factory MemoryItem.fromMap(Map<String, dynamic> map) {
    return MemoryItem(
      id: _string(map['id']),
      type: _string(map['type']),
      content: _string(map['content']),
      source: _string(map['source']),
      createdAt: _string(map['created_at']),
    );
  }

  final String id;
  final String type;
  final String content;
  final String source;
  final String createdAt;

  static String _string(Object? value) {
    return value is String ? value : '';
  }
}

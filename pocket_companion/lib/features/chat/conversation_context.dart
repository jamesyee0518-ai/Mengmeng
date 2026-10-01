/// Ephemeral history. This is never written to long-term memory or disk.
class ConversationContext {
  ConversationContext({
    required this.sessionId,
    required this.persona,
    required List<Map<String, String>> history,
  }) : history = List.unmodifiable(
         history.map((item) => Map<String, String>.unmodifiable(item)),
       );

  final String sessionId;
  final String persona;
  final List<Map<String, String>> history;

  Map<String, Object> toJson() => {
    'session_id': sessionId,
    'persona': persona,
    'history': history,
  };
}

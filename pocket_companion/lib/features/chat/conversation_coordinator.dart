import 'dart:math';
import 'package:flutter/foundation.dart';
import 'conversation_context.dart';
import 'robot_response.dart';

enum ConversationPhase { idle, requesting, delivering }

enum TurnResult { completed, busy, dropped, cancelled, failed }

/// Owns turn ordering, transient history and cancellation through playback.
/// There is deliberately no queue: automatic events become stale quickly.
class ConversationCoordinator extends ChangeNotifier {
  static const maxTurns = 6;
  static const maxCharacters = 12000;
  static const maxMessageCharacters = 2000;

  String _persona = 'mengmeng';
  String _sessionId = _newId();
  final List<List<Map<String, String>>> _turns = [];
  int _generation = 0;
  bool _disposed = false;
  ConversationPhase _phase = ConversationPhase.idle;
  Object? _lastError;

  ConversationPhase get phase => _phase;
  bool get isBusy => _phase != ConversationPhase.idle;
  Object? get lastError => _lastError;
  ConversationContext get context => ConversationContext(
    sessionId: _sessionId,
    persona: _persona,
    history: _turns.expand((turn) => turn).toList(),
  );

  static String _newId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  void cancel({bool clearHistory = false}) {
    _generation++;
    _phase = ConversationPhase.idle;
    _lastError = null;
    if (clearHistory) {
      _turns.clear();
      _sessionId = _newId();
    }
    if (!_disposed) notifyListeners();
  }

  void newSession({String? persona}) {
    _persona = persona ?? _persona;
    cancel(clearHistory: true);
  }

  Future<TurnResult> run({
    required String persona,
    required Future<RobotResponse> Function(
      ConversationContext context,
      bool Function() isCurrent,
    )
    request,
    required Future<void> Function(
      RobotResponse response,
      bool Function() isCurrent,
    )
    deliver,
    String? userText,
    bool automatic = false,
    bool useContext = true,
  }) async {
    if (_disposed) return TurnResult.cancelled;
    if (isBusy) return automatic ? TurnResult.dropped : TurnResult.busy;
    if (persona != _persona) newSession(persona: persona);
    final generation = ++_generation;
    final snapshot = useContext
        ? context
        : ConversationContext(
            sessionId: _sessionId,
            persona: _persona,
            history: [],
          );
    bool current() => !_disposed && generation == _generation;
    _lastError = null;
    _phase = ConversationPhase.requesting;
    notifyListeners();
    try {
      final response = await request(snapshot, current);
      if (!current()) return TurnResult.cancelled;
      _phase = ConversationPhase.delivering;
      notifyListeners();
      await deliver(response, current);
      if (!current()) return TurnResult.cancelled;
      if (useContext &&
          !automatic &&
          userText != null &&
          userText.trim().isNotEmpty &&
          response.text.trim().isNotEmpty &&
          !response.isFallback &&
          response.modelError.isEmpty &&
          response.modelProvider != 'rules') {
        _remember(userText, response.text);
      }
      return TurnResult.completed;
    } catch (error) {
      if (!current()) return TurnResult.cancelled;
      _lastError = error;
      return TurnResult.failed;
    } finally {
      if (current()) {
        _phase = ConversationPhase.idle;
        notifyListeners();
      }
    }
  }

  void _remember(String user, String assistant) {
    String clip(String value) {
      final text = value.trim();
      return text.length <= maxMessageCharacters
          ? text
          : text.substring(0, maxMessageCharacters);
    }

    _turns.add([
      {'role': 'user', 'content': clip(user)},
      {'role': 'assistant', 'content': clip(assistant)},
    ]);
    int characters() => _turns
        .expand((turn) => turn)
        .fold(0, (sum, message) => sum + message['content']!.length);
    while (_turns.length > maxTurns || characters() > maxCharacters) {
      _turns.removeAt(0);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _turns.clear();
    super.dispose();
  }
}

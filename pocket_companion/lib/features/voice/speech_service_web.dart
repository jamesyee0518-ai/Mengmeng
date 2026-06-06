import 'dart:async';

class SpeechService {
  Timer? _timer;
  Completer<String?>? _activeCompleter;

  Future<String?> listenOnce({Duration listenFor = const Duration(seconds: 5)}) {
    _timer?.cancel();
    _activeCompleter?.complete(null);
    final completer = Completer<String?>();
    _activeCompleter = completer;
    _timer = Timer(const Duration(milliseconds: 800), () {
      if (!completer.isCompleted) {
        completer.complete('今天有点累');
      }
    });
    return completer.future;
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    if (_activeCompleter?.isCompleted == false) {
      _activeCompleter?.complete(null);
    }
    _activeCompleter = null;
  }
}

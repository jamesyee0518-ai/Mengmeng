// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';

// ignore: deprecated_member_use
import 'dart:html' as html;

class TtsService {
  Completer<void>? _activeCompleter;

  Future<void> speak(
    String text, {
    String style = 'warm',
    double speed = 0.95,
    double pitch = 1.0,
    double volume = 0.75,
  }) async {
    await stop();
    final synth = html.window.speechSynthesis;
    if (synth == null || text.trim().isEmpty) {
      return;
    }

    final utterance = html.SpeechSynthesisUtterance(text)
      ..rate = speed.clamp(0.5, 1.5)
      ..pitch = pitch.clamp(0.5, 1.6)
      ..volume = volume.clamp(0.0, 1.0)
      ..lang = 'zh-CN';

    final completer = Completer<void>();
    _activeCompleter = completer;
    utterance.onEnd.listen((_) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    utterance.onError.listen((_) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    synth.speak(utterance);
    await completer.future;
  }

  Future<void> stop() async {
    html.window.speechSynthesis?.cancel();
    if (_activeCompleter?.isCompleted == false) {
      _activeCompleter?.complete();
    }
    _activeCompleter = null;
  }
}

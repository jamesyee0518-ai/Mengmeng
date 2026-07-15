import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  TtsService({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  Completer<void>? _activeCompleter;

  Future<void> speak(
    String text, {
    String style = 'warm',
    double speed = 0.95,
    double pitch = 1.0,
    double volume = 0.75,
  }) async {
    await stop();
    if (text.trim().isEmpty) {
      return;
    }

    final completer = Completer<void>();
    _activeCompleter = completer;
    _tts.setCompletionHandler(() {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    _tts.setErrorHandler((_) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    _tts.setCancelHandler(() {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    await _tts.setLanguage('zh-CN');
    await _applyVoiceStyle(style);
    await _tts.setSpeechRate(speed.clamp(0.4, 1.0));
    await _tts.setPitch(pitch.clamp(0.5, 1.5));
    await _tts.setVolume(volume.clamp(0.0, 1.0));
    await _tts.awaitSpeakCompletion(true);
    await _tts.speak(text);
    await completer.future.timeout(
      Duration(milliseconds: 900 + text.runes.length * 130),
      onTimeout: () {},
    );
  }

  Future<void> _applyVoiceStyle(String style) async {
    try {
      final voices = await _tts.getVoices;
      if (voices is! List) {
        return;
      }
      final voiceList = voices.cast<Object?>();
      final target = style == 'male'
          ? _findVoice(voiceList, ['male', '男'])
          : style == 'female'
          ? _findVoice(voiceList, ['female', '女'])
          : null;
      if (target != null) {
        await _tts.setVoice(target);
      }
    } catch (_) {}
  }

  Map<String, String>? _findVoice(List<Object?> voices, List<String> markers) {
    for (final voice in voices) {
      if (voice is! Map) {
        continue;
      }
      final normalized = voice.entries
          .map((entry) => '${entry.key}:${entry.value}')
          .join(' ')
          .toLowerCase();
      final isChinese =
          normalized.contains('zh') || normalized.contains('chinese');
      final matches = markers.any(
        (marker) => normalized.contains(marker.toLowerCase()),
      );
      if (isChinese && matches) {
        return voice.map(
          (key, value) => MapEntry('$key', '$value'),
        );
      }
    }
    return null;
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
    if (_activeCompleter?.isCompleted == false) {
      _activeCompleter?.complete();
    }
    _activeCompleter = null;
  }
}

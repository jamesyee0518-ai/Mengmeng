import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// TTS：网络合成优先（网关 /tts -> 语音服务器 edge-tts，音色远好于系统 TTS），
/// 网络不可用时自动回退手机系统合成（flutter_tts）。
class TtsService {
  TtsService({FlutterTts? tts, String? networkBaseUrl})
    : _tts = tts ?? FlutterTts(),
      _networkBaseUrl = networkBaseUrl;

  final FlutterTts _tts;
  final String? _networkBaseUrl;
  final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);

  AudioPlayer? _netPlayer;
  StreamSubscription<void>? _netCompleteSub;
  Completer<void>? _activeCompleter;

  Future<void> speak(
    String text, {
    String style = 'warm',
    double speed = 0.95,
    double pitch = 1.0,
    double volume = 0.75,
    String persona = 'mengmeng',
  }) async {
    await stop();
    if (text.trim().isEmpty) {
      return;
    }
    if (_networkBaseUrl != null) {
      final spoken = await _speakViaNetwork(
        text,
        style: style,
        speed: speed,
        persona: persona,
      );
      if (spoken) {
        return;
      }
    }
    await _speakViaSystem(
      text,
      style: style,
      speed: speed,
      pitch: pitch,
      volume: volume,
    );
  }

  // ------------------------------------------------------------ 网络合成

  Future<bool> _speakViaNetwork(
    String text, {
    required String style,
    required double speed,
    required String persona,
  }) async {
    try {
      final uri = Uri.parse('$_networkBaseUrl/tts');
      final request = await _httpClient
          .postUrl(uri)
          .timeout(const Duration(seconds: 8));
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'text': text,
          'style': style,
          'persona': persona,
          'speed': speed,
        }),
      );
      final response = await request
          .close()
          .timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) {
        return false;
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      final bytes = Uint8List.fromList(builder.takeBytes());
      if (bytes.isEmpty) {
        return false;
      }
      return _playNetworkAudio(bytes);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _playNetworkAudio(Uint8List bytes) async {
    final player = _netPlayer ??= AudioPlayer();
    final completer = Completer<void>();
    _activeCompleter = completer;
    await _netCompleteSub?.cancel();
    _netCompleteSub = player.onPlayerComplete.listen((_) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    try {
      await player.play(BytesSource(bytes));
    } catch (_) {
      return false;
    }
    // mp3 24kbps 估算：字节*8/24 毫秒，留 3 秒余量，上限 90 秒
    final estimatedMs = 3000 + (bytes.lengthInBytes * 8 / 24).round();
    await completer.future.timeout(
      Duration(milliseconds: estimatedMs.clamp(3000, 90000)),
      onTimeout: () {},
    );
    return true;
  }

  // ------------------------------------------------------------ 系统合成

  Future<void> _speakViaSystem(
    String text, {
    required String style,
    required double speed,
    required double pitch,
    required double volume,
  }) async {
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
      await _netPlayer?.stop();
    } catch (_) {}
    try {
      await _tts.stop();
    } catch (_) {}
    if (_activeCompleter?.isCompleted == false) {
      _activeCompleter?.complete();
    }
    _activeCompleter = null;
  }
}

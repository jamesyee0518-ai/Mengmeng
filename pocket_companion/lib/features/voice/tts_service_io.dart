import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'tts_chunks.dart';

/// TTS：网络合成优先（网关 /tts -> 语音服务器 edge-tts，音色远好于系统 TTS），
/// 网络不可用时自动回退手机系统合成（flutter_tts）。
class TtsService {
  TtsService({
    FlutterTts? tts,
    String? networkBaseUrl,
    @visibleForTesting AudioPlayer? player,
    @visibleForTesting Future<Uint8List?> Function(String)? synthesize,
  }) : _tts = tts ?? FlutterTts(),
       _networkBaseUrl = networkBaseUrl,
       _netPlayer = player,
       _synthesize = synthesize;

  final FlutterTts _tts;
  final Future<Uint8List?> Function(String)? _synthesize;
  int _generation = 0;
  Future<void> _playerOperations = Future<void>.value();

  Future<void> _playerOperation(Future<void> Function() action) {
    final operation = _playerOperations.then((_) => action());
    _playerOperations = operation.catchError((Object _) {});
    return operation;
  }

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
    final generation = ++_generation;
    await _stopPlayback();
    for (final chunk in ttsChunks(text)) {
      if (generation != _generation) return;
      var spoken = false;
      if (_networkBaseUrl != null || _synthesize != null) {
        final bytes = _synthesize != null
            ? await _synthesize(chunk)
            : await _synthesizeNetwork(
                chunk,
                style: style,
                speed: speed,
                persona: persona,
              );
        if (generation != _generation) return;
        if (bytes != null && bytes.isNotEmpty) {
          spoken = await _playNetworkAudio(bytes, generation, volume);
        }
      }
      if (generation != _generation) return;
      if (!spoken) {
        await _speakViaSystem(
          chunk,
          style: style,
          speed: speed,
          pitch: pitch,
          volume: volume,
          generation: generation,
        );
      }
    }
  }

  // ------------------------------------------------------------ 网络合成

  Future<Uint8List?> _synthesizeNetwork(
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
      final response = await request.close().timeout(
        const Duration(seconds: 25),
      );
      if (response.statusCode != 200) {
        return null;
      }
      final builder = BytesBuilder(copy: false);
      await response.forEach(builder.add).timeout(const Duration(seconds: 30));
      final bytes = Uint8List.fromList(builder.takeBytes());
      if (bytes.isEmpty) {
        return null;
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _playNetworkAudio(
    Uint8List bytes,
    int generation,
    double volume,
  ) async {
    if (generation != _generation) return true;
    final player = _netPlayer ??= AudioPlayer();
    final completer = Completer<void>();
    _activeCompleter = completer;
    await _netCompleteSub?.cancel();
    if (generation != _generation) return true;
    final subscription = player.onPlayerComplete.listen(
      (_) {
        if (!completer.isCompleted) completer.complete();
      },
      onError: (Object error, StackTrace stack) {
        if (!completer.isCompleted) completer.completeError(error, stack);
      },
    );
    _netCompleteSub = subscription;
    // Install the handler before play; timeout is an explicit failure, never
    // a successful completion that reopens the microphone over ongoing audio.
    final finished = completer.future.timeout(const Duration(minutes: 3));
    final completionError = <Object>[];
    final observed = finished.catchError((Object error) {
      completionError.add(error);
    });
    try {
      await _playerOperation(() async {
        if (generation == _generation) {
          await player.play(BytesSource(bytes), volume: volume.clamp(0.0, 1.0));
        }
      });
      if (generation != _generation) return true;
      await observed;
      if (completionError.isNotEmpty) throw completionError.first;
      return true;
    } finally {
      if (!completer.isCompleted) completer.complete();
      await subscription.cancel();
      if (identical(_netCompleteSub, subscription)) _netCompleteSub = null;
      if (generation == _generation) {
        await _playerOperation(() async {
          if (generation == _generation) await player.stop();
        });
        if (identical(_activeCompleter, completer)) _activeCompleter = null;
      }
    }
  }

  // ------------------------------------------------------------ 系统合成

  Future<void> _speakViaSystem(
    String text, {
    required String style,
    required double speed,
    required double pitch,
    required double volume,
    required int generation,
  }) async {
    final completer = Completer<void>();
    _activeCompleter = completer;
    Object? playbackError;
    _tts.setCompletionHandler(() {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    _tts.setErrorHandler((error) {
      playbackError = error;
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    _tts.setCancelHandler(() {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    if (generation != _generation) return;
    await _tts.setLanguage('zh-CN');
    await _applyVoiceStyle(style);
    await _tts.setSpeechRate(speed.clamp(0.4, 1.0));
    await _tts.setPitch(pitch.clamp(0.5, 1.5));
    await _tts.setVolume(volume.clamp(0.0, 1.0));
    await _tts.awaitSpeakCompletion(true);
    if (generation != _generation) return;
    try {
      await _tts.speak(text).timeout(const Duration(minutes: 3));
      if (generation != _generation) return;
      await completer.future.timeout(const Duration(minutes: 3));
      if (playbackError != null) throw StateError('系统播报失败：$playbackError');
    } finally {
      if (generation == _generation) {
        await _tts.stop();
        if (identical(_activeCompleter, completer)) _activeCompleter = null;
      }
    }
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
        return voice.map((key, value) => MapEntry('$key', '$value'));
      }
    }
    return null;
  }

  Future<void> stop() async {
    _generation++;
    await _stopPlayback();
  }

  Future<void> _stopPlayback() async {
    final active = _activeCompleter;
    _activeCompleter = null;
    if (active != null && !active.isCompleted) active.complete();
    try {
      await _playerOperation(() async {
        await _netPlayer?.stop();
      });
    } catch (_) {}
    try {
      await _tts.stop();
    } catch (_) {}
  }
}

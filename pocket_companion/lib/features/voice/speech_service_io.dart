import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class SpeechService {
  SpeechService({stt.SpeechToText? speech})
    : _speech = speech ?? stt.SpeechToText();

  static const MethodChannel _capabilities = MethodChannel(
    'pocket_companion/device_capabilities',
  );
  static const String _gatewayBaseUrl = String.fromEnvironment(
    'AI_GATEWAY_BASE_URL',
    defaultValue: 'http://192.168.1.111:8787',
  );

  final stt.SpeechToText _speech;
  Completer<String?>? _activeCompleter;
  String _lastWords = '';
  bool _isInitialized = false;

  Future<String?> listenOnce({Duration listenFor = const Duration(seconds: 5)}) async {
    if (Platform.isAndroid) {
      return _listenWithWhisperGateway(listenFor: listenFor);
    }
    await stop();
    final completer = Completer<String?>();
    _activeCompleter = completer;
    _lastWords = '';

    try {
      if (!await _canUseSpeechRecognition()) {
        return null;
      }
      _isInitialized =
          _isInitialized ||
          await _speech.initialize(
            onError: (error) {
              if (!completer.isCompleted) {
                completer.complete(_lastWords.isEmpty ? null : _lastWords);
              }
            },
            onStatus: (status) {
              if ((status == 'done' || status == 'notListening') &&
                  !completer.isCompleted) {
                completer.complete(_lastWords.isEmpty ? null : _lastWords);
              }
            },
          );
      if (!_isInitialized) {
        return null;
      }

      await _speech.listen(
        onResult: (result) {
          _lastWords = result.recognizedWords;
          if (result.finalResult && !completer.isCompleted) {
            completer.complete(_lastWords);
          }
        },
        listenOptions: stt.SpeechListenOptions(
          listenFor: listenFor,
          pauseFor: const Duration(seconds: 2),
          partialResults: false,
          cancelOnError: true,
        ),
      );

      return completer.future.timeout(
        const Duration(seconds: 9),
        onTimeout: () => _lastWords.isEmpty ? null : _lastWords,
      );
    } catch (_) {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
      return completer.future;
    }
  }

  Future<String?> _listenWithWhisperGateway({
    Duration listenFor = const Duration(seconds: 5),
  }) async {
    try {
      final path = await _capabilities.invokeMethod<String>('recordAudioClip', {
        'durationMs': listenFor.inMilliseconds,
      });
      if (path == null || path.isEmpty) {
        return null;
      }
      final file = File(path);
      if (!await file.exists()) {
        return null;
      }
      final bytes = await file.readAsBytes();
      unawaited(file.delete().catchError((_) => file));
      final client = HttpClient();
      try {
        final uri = Uri.parse('$_gatewayBaseUrl/stt');
        final request = await client
            .postUrl(uri)
            .timeout(const Duration(seconds: 5));
        request.headers.contentType = ContentType.binary;
        request.headers.set('x-audio-format', 'm4a');
        request.headers.set('content-length', bytes.length.toString());
        request.add(bytes);
        final response = await request.close().timeout(
          const Duration(seconds: 75),
        );
        final body = await utf8
            .decodeStream(response)
            .timeout(const Duration(seconds: 75));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          return null;
        }
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          final text = decoded['text'];
          return text is String && text.trim().isNotEmpty ? text.trim() : null;
        }
        return null;
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      return null;
    }
  }

  Future<bool> _canUseSpeechRecognition() async {
    if (!Platform.isAndroid) {
      return true;
    }
    try {
      final status = await _capabilities.invokeMapMethod<String, Object?>(
        'speechRecognitionStatus',
      );
      return status?['available'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    try {
      await _speech.stop();
    } catch (_) {}
    if (_activeCompleter?.isCompleted == false) {
      try {
        _activeCompleter?.complete(_lastWords.isEmpty ? null : _lastWords);
      } catch (_) {}
    }
    _activeCompleter = null;
  }
}

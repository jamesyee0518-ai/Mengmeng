import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'audio_clip_result.dart';
import 'barge_in_config.dart';
import 'barge_in_result.dart';
import 'voice_audio_gate.dart';
import 'voice_audio_gate_config.dart';
import 'voice_debug_snapshot.dart';

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
  VoiceAudioGateConfig _audioGateConfig = const VoiceAudioGateConfig();
  Completer<String?>? _activeCompleter;
  String _lastWords = '';
  bool _isInitialized = false;
  VoiceDebugSnapshot _latestDebugSnapshot = VoiceDebugSnapshot();

  VoiceDebugSnapshot get latestDebugSnapshot => _latestDebugSnapshot;
  VoiceAudioGateConfig get audioGateConfig => _audioGateConfig;

  void updateAudioGateConfig(VoiceAudioGateConfig config) {
    _audioGateConfig = config;
  }

  Future<String> microphonePermissionStatus() async {
    if (!Platform.isAndroid) {
      return 'granted';
    }
    try {
      final status = await _capabilities.invokeMapMethod<String, Object?>(
        'microphonePermissionStatus',
      );
      final permissionStatus = _stringFromJson(status?['status']).isEmpty
          ? 'unknown'
          : _stringFromJson(status?['status']);
      _latestDebugSnapshot = _latestDebugSnapshot.copyWith(
        permissionStatus: permissionStatus,
        runtimeWarning: permissionStatus == 'denied' ? 'permissionDenied' : '',
      );
      return permissionStatus;
    } catch (_) {
      _latestDebugSnapshot = _latestDebugSnapshot.copyWith(
        permissionStatus: 'unknown',
      );
      return 'unknown';
    }
  }

  Future<String?> listenOnce({
    Duration listenFor = const Duration(seconds: 5),
  }) async {
    if (Platform.isAndroid) {
      return _recordAndTranscribe(
        method: 'recordAudioClip',
        arguments: {'durationMs': listenFor.inMilliseconds},
      );
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

  Future<String?> listenForUtterance({
    Duration maxDuration = const Duration(seconds: 12),
    Duration silenceTimeout = const Duration(milliseconds: 1200),
    Duration startTimeout = const Duration(seconds: 3),
  }) async {
    if (!Platform.isAndroid) {
      return listenOnce(listenFor: maxDuration);
    }
    return _recordAndTranscribe(
      method: 'recordUntilSilence',
      arguments: {
        'maxDurationMs': maxDuration.inMilliseconds,
        'silenceTimeoutMs': silenceTimeout.inMilliseconds,
        'minSpeechMs': 400,
        'startTimeoutMs': startTimeout.inMilliseconds,
      },
    );
  }

  Future<BargeInResult> listenForBargeIn(BargeInConfig config) async {
    if (!config.enabled || !Platform.isAndroid) {
      return const BargeInResult(
        detected: false,
        durationMs: 0,
        speechDurationMs: 0,
        avgRms: 0,
        maxRms: 0,
        speechLikeRatio: 0,
        reason: 'disabled',
      );
    }
    try {
      final rawResult = await _capabilities
          .invokeMethod<Object>('detectBargeIn', {
            'maxDurationMs': config.maxDuration.inMilliseconds,
            'minSpeechMs': config.minSpeechDuration.inMilliseconds,
            'minAvgRms': config.minAvgRms,
            'minMaxRms': config.minMaxRms,
            'minSpeechLikeRatio': config.minSpeechLikeRatio,
          });
      final bargeIn = BargeInResult.fromJson(rawResult);
      _latestDebugSnapshot = _latestDebugSnapshot.copyWith(
        bargeInDetected: bargeIn.detected,
        bargeInAvgRms: bargeIn.avgRms,
        bargeInMaxRms: bargeIn.maxRms,
        bargeInSpeechLikeRatio: bargeIn.speechLikeRatio,
        bargeInReason: bargeIn.reason,
      );
      _logBargeIn(bargeIn);
      return bargeIn;
    } catch (error) {
      // ignore: avoid_print
      print('[speech] barge-in failed: $error');
      return const BargeInResult(
        detected: false,
        durationMs: 0,
        speechDurationMs: 0,
        avgRms: 0,
        maxRms: 0,
        speechLikeRatio: 0,
        reason: 'error',
      );
    }
  }

  Future<String?> _recordAndTranscribe({
    required String method,
    required Map<String, Object?> arguments,
  }) async {
    try {
      final rawClip = await _capabilities.invokeMethod<Object>(
        method,
        arguments,
      );
      final clip = AudioClipResult.fromPlatformResult(rawClip);
      _latestDebugSnapshot = _latestDebugSnapshot.copyWith(
        durationMs: clip.durationMs,
        speechDurationMs: clip.speechDurationMs,
        avgRms: clip.avgRms,
        maxRms: clip.maxRms,
        speechLikeRatio: clip.speechLikeRatio,
        recordReason: clip.reason,
        callStt: false,
        gateReason: '',
        gateFlags: const [],
        rawText: '',
        normalizedText: '',
        sttFlags: const [],
        recordingInProgress: clip.reason == 'recording_in_progress',
        runtimeWarning: clip.reason == 'recording_in_progress'
            ? 'recording_in_progress'
            : '',
      );
      _logAudioClip(method, clip);
      final gate = VoiceAudioGate(config: _audioGateConfig).evaluate(clip);
      _latestDebugSnapshot = _latestDebugSnapshot.copyWith(
        callStt: gate.shouldSendToStt,
        gateReason: gate.reason,
        gateFlags: gate.flags,
      );
      if (!gate.shouldSendToStt) {
        _logAudioGate(gate, callStt: false);
        if (clip.path.isNotEmpty) {
          unawaited(
            File(clip.path).delete().catchError((_) => File(clip.path)),
          );
        }
        return null;
      }
      _logAudioGate(gate, callStt: true);
      final path = clip.path;
      if (path.isEmpty) {
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
          const Duration(seconds: 40),
        );
        final body = await utf8
            .decodeStream(response)
            .timeout(const Duration(seconds: 40));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          return null;
        }
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          _latestDebugSnapshot = _latestDebugSnapshot.copyWith(
            rawText: _stringFromJson(decoded['raw_text']),
            normalizedText: _stringFromJson(decoded['normalized_text']),
            sttFlags: _stringListFromJson(decoded['flags']),
          );
          final text = decoded['text'];
          return text is String && text.trim().isNotEmpty ? text.trim() : null;
        }
        return null;
      } finally {
        client.close(force: true);
      }
    } on PlatformException catch (error) {
      final warning = error.code == 'record_audio_denied'
          ? 'permissionDenied'
          : error.code;
      _latestDebugSnapshot = _latestDebugSnapshot.copyWith(
        permissionStatus: error.code == 'record_audio_denied' ? 'denied' : '',
        runtimeWarning: warning,
        callStt: false,
      );
      return null;
    } catch (_) {
      return null;
    }
  }

  String _stringFromJson(Object? value) => value is String ? value : '';

  List<String> _stringListFromJson(Object? value) {
    if (value is List) {
      return value.whereType<String>().toList(growable: false);
    }
    return const [];
  }

  void _logAudioClip(String method, AudioClipResult clip) {
    // ignore: avoid_print
    print(
      '[speech] $method durationMs=${clip.durationMs} '
      'speechDurationMs=${clip.speechDurationMs} '
      'avgRms=${clip.avgRms.toStringAsFixed(1)} '
      'maxRms=${clip.maxRms.toStringAsFixed(1)} '
      'speechLikeRatio=${clip.speechLikeRatio.toStringAsFixed(3)} '
      'hasSpeechLikeAudio=${clip.hasSpeechLikeAudio} reason=${clip.reason}',
    );
  }

  void _logAudioGate(VoiceAudioGateDecision gate, {required bool callStt}) {
    // ignore: avoid_print
    print(
      '[speech] audio gate callStt=$callStt reason=${gate.reason} '
      'flags=${gate.flags.join(",")}',
    );
  }

  void _logBargeIn(BargeInResult result) {
    // ignore: avoid_print
    print(
      '[speech] barge-in detected=${result.detected} '
      'durationMs=${result.durationMs} speechDurationMs=${result.speechDurationMs} '
      'avgRms=${result.avgRms.toStringAsFixed(1)} '
      'maxRms=${result.maxRms.toStringAsFixed(1)} '
      'speechLikeRatio=${result.speechLikeRatio.toStringAsFixed(3)} '
      'reason=${result.reason}',
    );
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
    if (Platform.isAndroid) {
      try {
        await _capabilities.invokeMethod<bool>('cancelRecording');
      } catch (_) {}
    }
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

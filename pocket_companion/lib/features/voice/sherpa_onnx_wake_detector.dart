import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'wake_detector.dart';
import 'wake_detector_type.dart';

class SherpaOnnxWakeDetector implements WakeDetector {
  SherpaOnnxWakeDetector({
    WakeDetector? fallback,
    MethodChannel? controlChannel,
    EventChannel? audioChannel,
    @visibleForTesting Future<void> Function()? initialize,
    @visibleForTesting sherpa.KeywordSpotter? spotter,
    @visibleForTesting sherpa.OnlineStream? stream,
  }) : _control = controlChannel ?? const MethodChannel(_controlChannelName),
       _audio = audioChannel ?? const EventChannel(_audioChannelName),
       _fallback = fallback,
       _initializeOverride = initialize,
       _spotter = spotter,
       _stream = stream;

  static const _controlChannelName = 'pocket_companion/sherpa_wake_control';
  static const _audioChannelName = 'pocket_companion/sherpa_wake_audio';
  static const _assetRoot = 'assets/models/sherpa_onnx_kws';

  final MethodChannel _control;
  final EventChannel _audio;
  final WakeDetector? _fallback;
  final Future<void> Function()? _initializeOverride;
  int _generation = 0;
  Future<void>? _starting;
  Future<void>? _recovering;
  final _events = StreamController<WakeDetectorEvent>.broadcast();
  sherpa.KeywordSpotter? _spotter;
  sherpa.OnlineStream? _stream;
  StreamSubscription<Object?>? _audioSubscription;
  bool _initialized = false;
  bool _nativeStarted = false;
  bool _disposed = false;
  bool _usingFallback = false;
  Timer? _audioWatchdog;
  int _framesSinceCheck = 0;
  int _missingAudioChecks = 0;
  int _audioSamples = 0;
  double _audioSquares = 0;
  double _audioPeak = 0;
  StreamSubscription<WakeDetectorEvent>? _fallbackSubscription;

  @override
  WakeDetectorType get type => WakeDetectorType.sherpaOnnx;

  bool get usingFallback => _usingFallback;

  @override
  Stream<WakeDetectorEvent> get events => _events.stream;

  @override
  Future<void> start() async {
    if (_disposed || _audioSubscription != null || _usingFallback) return;
    if (_starting != null) return _starting;
    final generation = _generation;
    final pending = _start(generation);
    _starting = pending;
    try {
      await pending;
    } finally {
      if (identical(_starting, pending)) _starting = null;
    }
  }

  Future<void> _start(int generation) async {
    try {
      await (_initializeOverride ?? _initialize)();
      if (_disposed || generation != _generation) return;
      // Subscribe first so a native startup error cannot disappear without a sink.
      _audioSubscription = _audio.receiveBroadcastStream().listen(
        (event) {
          if (_disposed || generation != _generation) return;
          try {
            _consumeAudio(event);
          } catch (error) {
            _recover(error, generation);
          }
        },
        onError: (Object error) => _recover(error, generation),
        onDone: () => _recover(StateError('audio stream closed'), generation),
      );
      _nativeStarted = true;
      final status = await _control.invokeMapMethod<String, Object?>('start');
      if (_disposed || generation != _generation) return;
      if (status?['started'] != true) {
        throw StateError('sherpa audio did not start: ${status?['reason']}');
      }
      _framesSinceCheck = 0;
      _missingAudioChecks = 0;
      _audioWatchdog = Timer.periodic(const Duration(seconds: 2), (_) {
        _missingAudioChecks = _framesSinceCheck == 0
            ? _missingAudioChecks + 1
            : 0;
        _framesSinceCheck = 0;
        if (_missingAudioChecks >= 3) {
          unawaited(
            _recover(StateError('wake audio stream stalled'), generation),
          );
        }
      });
      _emit(const WakeDetectorLog('sherpaOnnx local wake detector started'));
    } catch (error) {
      await _recover(error, generation);
    }
  }

  Future<void> _recover(Object error, int generation) async {
    if (_disposed || generation != _generation) return;
    if (_recovering != null) return _recovering;
    final pending = _activateFallback(error, generation);
    _recovering = pending;
    try {
      await pending;
    } finally {
      if (identical(_recovering, pending)) _recovering = null;
    }
  }

  Future<void> _activateFallback(Object error, int generation) async {
    _emit(WakeDetectorError(reason: 'sherpa_audio_unavailable', error: error));
    await _stopNative();
    if (_disposed || generation != _generation) return;
    if (_fallback == null) return;
    _usingFallback = true;
    _fallbackSubscription ??= _fallback.events.listen(_emit);
    await _fallback.start();
    if (_disposed || generation != _generation) {
      await _fallback.stop();
      return;
    }
    _emit(const WakeDetectorLog('sherpa unavailable; using STT wake fallback'));
  }

  @override
  Future<void> detectOnce() async {
    if (_disposed) return;
    final generation = _generation;
    if (_recovering != null) await _recovering;
    if (_disposed || generation != _generation) return;
    if (!_usingFallback && _audioSubscription == null) await start();
    if (_disposed || generation != _generation) return;
    if (_usingFallback) await _fallback!.detectOnce();
  }

  Future<void> _stopNative() async {
    _audioWatchdog?.cancel();
    _audioWatchdog = null;
    _audioSamples = 0;
    _audioSquares = 0;
    _audioPeak = 0;
    final subscription = _audioSubscription;
    _audioSubscription = null;
    await subscription?.cancel();
    if (_nativeStarted) {
      _nativeStarted = false;
      try {
        await _control.invokeMethod<void>('stop');
      } on MissingPluginException {
        // Non-Android platforms safely remain unavailable.
      }
    }
    if (_stream != null && _spotter != null) _spotter!.reset(_stream!);
  }

  @override
  Future<void> stop() async {
    _generation++;
    await _stopNative();
    if (_usingFallback) await _fallback?.stop();
    _usingFallback = false;
  }

  Future<void> _initialize() async {
    if (_initialized) return;
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'Sherpa wake detection currently requires Android',
      );
    }
    final root = Directory(
      '${(await getApplicationSupportDirectory()).path}/sherpa_kws',
    );
    await root.create(recursive: true);
    for (final name in const [
      'encoder.onnx',
      'decoder.onnx',
      'joiner.onnx',
      'tokens.txt',
      'keywords.txt',
    ]) {
      final file = File('${root.path}/$name');
      // Refresh the small keyword list on upgrades; model weights stay cached.
      if (name == 'keywords.txt' ||
          !await file.exists() ||
          await file.length() == 0) {
        final data = await rootBundle.load('$_assetRoot/$name');
        await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      }
    }
    sherpa.initBindings();
    _spotter = sherpa.KeywordSpotter(
      sherpa.KeywordSpotterConfig(
        feat: const sherpa.FeatureConfig(sampleRate: 16000, featureDim: 80),
        model: sherpa.OnlineModelConfig(
          transducer: sherpa.OnlineTransducerModelConfig(
            encoder: '${root.path}/encoder.onnx',
            decoder: '${root.path}/decoder.onnx',
            joiner: '${root.path}/joiner.onnx',
          ),
          tokens: '${root.path}/tokens.txt',
          numThreads: 2,
          provider: 'cpu',
          modelType: 'zipformer2',
          debug: false,
        ),
        keywordsFile: '${root.path}/keywords.txt',
      ),
    );
    _stream = _spotter!.createStream();
    _initialized = true;
  }

  @visibleForTesting
  static Float32List pcm16Samples(Uint8List bytes) {
    // EventChannel byte payloads can begin at an odd offset in the message.
    final data = ByteData.sublistView(bytes);
    final samples = Float32List(bytes.length ~/ 2);
    for (var i = 0; i < samples.length; i++) {
      samples[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return samples;
  }

  void _consumeAudio(Object? event) {
    if (event is! Uint8List || _stream == null || _spotter == null) return;
    final samples = pcm16Samples(event);
    if (samples.isEmpty) return;
    _framesSinceCheck++;
    for (final sample in samples) {
      final pcm = sample * 32768;
      _audioSquares += pcm * pcm;
      _audioPeak = math.max(_audioPeak, pcm.abs());
    }
    _audioSamples += samples.length;
    if (_audioSamples >= 16000) {
      _emit(
        WakeDetectorAudio(
          durationMs: _audioSamples * 1000 ~/ 16000,
          avgRms: math.sqrt(_audioSquares / _audioSamples),
          maxRms: _audioPeak,
        ),
      );
      _audioSamples = 0;
      _audioSquares = 0;
      _audioPeak = 0;
    }
    _stream!.acceptWaveform(samples: samples, sampleRate: 16000);
    while (_spotter!.isReady(_stream!)) {
      _spotter!.decode(_stream!);
      final keyword = _spotter!.getResult(_stream!).keyword.trim();
      if (keyword.isNotEmpty) {
        _emitKeyword(keyword);
        _spotter!.reset(_stream!);
        return;
      }
    }
  }

  void _emitKeyword(String keyword) {
    _emit(
      WakeDetectorDetected(
        persona: keyword == '小远'
            ? 'xiaoyuan'
            : keyword == '群群老师'
            ? 'qunqun_teacher'
            : 'mengmeng',
        wakeWord: keyword,
        command: '',
        score: 1,
        matchType: 'sherpa_onnx',
        rawText: keyword,
        normalizedText: keyword,
        flags: const ['local_kws'],
      ),
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    await _starting;
    await _recovering;
    await _fallbackSubscription?.cancel();
    await _fallback?.dispose();
    _stream?.free();
    _spotter?.free();
    await _events.close();
  }

  void _emit(WakeDetectorEvent event) {
    if (!_disposed && !_events.isClosed) _events.add(event);
  }
}

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'wake_detector.dart';
import 'wake_detector_type.dart';

class SherpaOnnxWakeDetector implements WakeDetector {
  SherpaOnnxWakeDetector({
    WakeDetector? fallback,
    MethodChannel? controlChannel,
    EventChannel? audioChannel,
  }) : _control = controlChannel ?? const MethodChannel(_controlChannelName),
       _audio = audioChannel ?? const EventChannel(_audioChannelName),
       _fallback = fallback;

  static const _controlChannelName = 'pocket_companion/sherpa_wake_control';
  static const _audioChannelName = 'pocket_companion/sherpa_wake_audio';
  static const _assetRoot = 'assets/models/sherpa_onnx_kws';

  final MethodChannel _control;
  final EventChannel _audio;
  final WakeDetector? _fallback;
  final _events = StreamController<WakeDetectorEvent>.broadcast();
  sherpa.KeywordSpotter? _spotter;
  sherpa.OnlineStream? _stream;
  StreamSubscription<Object?>? _audioSubscription;
  bool _initialized = false;
  bool _disposed = false;
  bool _usingFallback = false;
  StreamSubscription<WakeDetectorEvent>? _fallbackSubscription;

  @override
  WakeDetectorType get type => WakeDetectorType.sherpaOnnx;

  @override
  Stream<WakeDetectorEvent> get events => _events.stream;

  @override
  Future<void> start() async {
    if (_disposed || _audioSubscription != null) return;
    try {
      await _initialize();
      await _control.invokeMethod<void>('start');
      _audioSubscription = _audio.receiveBroadcastStream().listen(
        _consumeAudio,
        onError: (Object error) => _emit(
          WakeDetectorError(reason: 'sherpa_audio_stream_error', error: error),
        ),
      );
      _emit(const WakeDetectorLog('sherpaOnnx local wake detector started'));
    } catch (error) {
      await stop();
      _emit(WakeDetectorError(reason: 'sherpa_init_failed', error: error));
      if (_fallback != null) {
        _usingFallback = true;
        _fallbackSubscription ??= _fallback.events.listen(_emit);
        await _fallback.start();
        _emit(
          const WakeDetectorLog('sherpa unavailable; using STT wake fallback'),
        );
      }
    }
  }

  @override
  Future<void> detectOnce() async {
    if (_usingFallback) {
      await _fallback!.detectOnce();
      return;
    }
    if (!_initialized) await start();
    if (_usingFallback) await _fallback!.detectOnce();
  }

  @override
  Future<void> stop() async {
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    try {
      await _control.invokeMethod<void>('stop');
    } on MissingPluginException {
      // Non-Android platforms safely remain unavailable.
    }
    if (_usingFallback) await _fallback?.stop();
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
      if (!await file.exists() || await file.length() == 0) {
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

  void _consumeAudio(Object? event) {
    if (event is! Uint8List || _stream == null || _spotter == null) return;
    final pcm = Int16List.view(
      event.buffer,
      event.offsetInBytes,
      event.lengthInBytes ~/ 2,
    );
    final samples = Float32List(pcm.length);
    for (var i = 0; i < pcm.length; i++) {
      samples[i] = pcm[i] / 32768.0;
    }
    _stream!.acceptWaveform(samples: samples, sampleRate: 16000);
    while (_spotter!.isReady(_stream!)) {
      _spotter!.decode(_stream!);
    }
    final keyword = _spotter!.getResult(_stream!).keyword.trim();
    if (keyword.isEmpty) return;
    _emit(
      WakeDetectorDetected(
        persona: keyword == '小远'
            ? 'xiaoyuan'
            : keyword == '群群老师'
            ? 'qunqun'
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
    _spotter!.reset(_stream!);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
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

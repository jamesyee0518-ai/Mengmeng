import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'voice_debug_sample.dart';
import 'voice_debug_sample_summary.dart';

abstract class VoiceDebugSampleStore {
  Future<void> add(VoiceDebugSample sample);
  Future<List<VoiceDebugSample>> listRecent({int limit = 20});
  Future<VoiceDebugSampleSummary> summarize();
  Future<void> clear();
  Future<String?> exportPath();

  Future<void> append(VoiceDebugSample sample) => add(sample);
}

class MemoryVoiceDebugSampleStore implements VoiceDebugSampleStore {
  final List<VoiceDebugSample> _samples = [];

  List<VoiceDebugSample> get samples => List.unmodifiable(_samples);

  @override
  Future<void> add(VoiceDebugSample sample) async {
    _samples.add(sample);
  }

  @override
  Future<void> append(VoiceDebugSample sample) => add(sample);

  @override
  Future<List<VoiceDebugSample>> listRecent({int limit = 20}) async {
    final start = (_samples.length - limit).clamp(0, _samples.length);
    return _samples.sublist(start).reversed.toList(growable: false);
  }

  @override
  Future<VoiceDebugSampleSummary> summarize() async {
    return VoiceDebugSampleSummary.fromSamples(_samples);
  }

  @override
  Future<void> clear() async {
    _samples.clear();
  }

  @override
  Future<String?> exportPath() async => null;
}

class JsonlVoiceDebugSampleStore implements VoiceDebugSampleStore {
  JsonlVoiceDebugSampleStore._(this._file);

  factory JsonlVoiceDebugSampleStore.file(File file) {
    return JsonlVoiceDebugSampleStore._(file);
  }

  static Future<JsonlVoiceDebugSampleStore> create() async {
    final directory = await getApplicationDocumentsDirectory();
    return JsonlVoiceDebugSampleStore._(
      File('${directory.path}/voice_debug_samples.jsonl'),
    );
  }

  final File _file;

  @override
  Future<void> add(VoiceDebugSample sample) async {
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(
        '${jsonEncode(sample.toJson())}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (error) {
      // Debug sample capture must never break the voice flow.
      // ignore: avoid_print
      print('[speech] voice debug sample write failed: $error');
    }
  }

  @override
  Future<void> append(VoiceDebugSample sample) => add(sample);

  @override
  Future<List<VoiceDebugSample>> listRecent({int limit = 20}) async {
    final samples = await _readAll();
    final start = (samples.length - limit).clamp(0, samples.length);
    return samples.sublist(start).reversed.toList(growable: false);
  }

  @override
  Future<VoiceDebugSampleSummary> summarize() async {
    return VoiceDebugSampleSummary.fromSamples(await _readAll());
  }

  @override
  Future<void> clear() async {
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString('', flush: true);
    } catch (error) {
      // ignore: avoid_print
      print('[speech] voice debug sample clear failed: $error');
    }
  }

  @override
  Future<String?> exportPath() async => _file.path;

  Future<List<VoiceDebugSample>> _readAll() async {
    if (!await _file.exists()) {
      return const [];
    }
    final lines = await _file.readAsLines();
    final samples = <VoiceDebugSample>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, Object?>) {
          samples.add(VoiceDebugSample.fromJson(decoded));
        } else if (decoded is Map) {
          samples.add(
            VoiceDebugSample.fromJson(Map<String, Object?>.from(decoded)),
          );
        }
      } catch (_) {
        continue;
      }
    }
    return samples;
  }
}

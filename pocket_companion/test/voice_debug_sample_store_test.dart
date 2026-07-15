import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_companion/features/voice/voice_debug_sample.dart';
import 'package:pocket_companion/features/voice/voice_debug_sample_store.dart';

import 'voice_debug_sample_test.dart' as fixture;

void main() {
  test('Memory store add listRecent and clear work', () async {
    final store = MemoryVoiceDebugSampleStore();
    await store.add(fixture.sample(VoiceDebugSampleLabel.normalWake));
    await store.add(fixture.sample(VoiceDebugSampleLabel.falseWake));

    final recent = await store.listRecent(limit: 1);
    expect(recent, hasLength(1));
    expect(recent.single.label, VoiceDebugSampleLabel.falseWake);

    await store.clear();
    expect(await store.listRecent(), isEmpty);
  });

  test('Jsonl store writes and reads samples', () async {
    final store = JsonlVoiceDebugSampleStore.file(await _tempFile());
    await store.add(fixture.sample(VoiceDebugSampleLabel.normalWake));

    final recent = await store.listRecent();

    expect(recent, hasLength(1));
    expect(recent.single.label, VoiceDebugSampleLabel.normalWake);
    expect(recent.single.normalizedText, '萌萌帮我看');
  });

  test('Jsonl store listRecent limit works', () async {
    final store = JsonlVoiceDebugSampleStore.file(await _tempFile());
    await store.add(fixture.sample(VoiceDebugSampleLabel.normalWake));
    await store.add(fixture.sample(VoiceDebugSampleLabel.falseWake));
    await store.add(fixture.sample(VoiceDebugSampleLabel.missedWake));

    final recent = await store.listRecent(limit: 2);

    expect(recent, hasLength(2));
    expect(recent.first.label, VoiceDebugSampleLabel.missedWake);
    expect(recent.last.label, VoiceDebugSampleLabel.falseWake);
  });

  test('Jsonl store skips bad JSON lines', () async {
    final file = await _tempFile();
    final store = JsonlVoiceDebugSampleStore.file(file);
    await file.writeAsString('bad json\n');
    await store.add(fixture.sample(VoiceDebugSampleLabel.ignoredCorrectly));

    final recent = await store.listRecent();

    expect(recent, hasLength(1));
    expect(recent.single.label, VoiceDebugSampleLabel.ignoredCorrectly);
  });

  test('Jsonl summarize exportPath and clear work', () async {
    final file = await _tempFile();
    final store = JsonlVoiceDebugSampleStore.file(file);
    await store.add(fixture.sample(VoiceDebugSampleLabel.normalWake));
    await store.add(fixture.sample(VoiceDebugSampleLabel.falseWake));
    await store.add(fixture.sample(VoiceDebugSampleLabel.missedWake));
    await store.add(fixture.sample(VoiceDebugSampleLabel.ignoredCorrectly));

    final summary = await store.summarize();
    expect(summary.total, 4);
    expect(summary.normalWakeCount, 1);
    expect(summary.falseWakeCount, 1);
    expect(summary.missedWakeCount, 1);
    expect(summary.ignoredCorrectlyCount, 1);
    expect(await store.exportPath(), isNotEmpty);

    await store.clear();
    expect(await store.listRecent(), isEmpty);
  });

  test('Jsonl store preserves barge-in labels', () async {
    final store = JsonlVoiceDebugSampleStore.file(await _tempFile());
    await store.add(fixture.sample(VoiceDebugSampleLabel.normalBargeIn));
    await store.add(fixture.sample(VoiceDebugSampleLabel.falseBargeIn));

    final recent = await store.listRecent();
    final summary = await store.summarize();

    expect(recent.first.label, VoiceDebugSampleLabel.falseBargeIn);
    expect(recent.last.label, VoiceDebugSampleLabel.normalBargeIn);
    expect(summary.normalBargeInCount, 1);
    expect(summary.falseBargeInCount, 1);
  });
}

Future<File> _tempFile() async {
  final dir = await Directory.systemTemp.createTemp(
    'voice_debug_samples_test_',
  );
  return File('${dir.path}/voice_debug_samples.jsonl');
}

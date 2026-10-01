import 'dart:async';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_companion/features/voice/tts_service_io.dart';
import 'package:pocket_companion/features/voice/tts_chunks.dart';

class Player implements AudioPlayer {
  final completion = StreamController<void>.broadcast();
  int plays = 0;
  @override
  Stream<void> get onPlayerComplete => completion.stream;
  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async {
    plays++;
  }

  @override
  Future<void> stop() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SystemTts implements FlutterTts {
  @override
  Future<dynamic> stop() async => 1;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('chunks preserve long text, punctuation and Unicode', () {
    final text = "${'你好🐳。' * 180}最后一句。";
    final chunks = ttsChunks(text);
    expect(chunks.join(), text);
    expect(chunks.every((chunk) => chunk.runes.length <= 300), isTrue);
    expect(chunks.last.endsWith('最后一句。'), isTrue);
  });
  test('waits for real completion and speaks all chunks in order', () async {
    final player = Player();
    final requested = <String>[];
    final tts = TtsService(
      tts: SystemTts(),
      player: player,
      synthesize: (text) async {
        requested.add(text);
        return Uint8List.fromList([1, 2, 3]);
      },
    );
    var done = false;
    final text = '啊' * 650;
    final pending = tts.speak(text).then((_) => done = true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(player.plays, 1);
    expect(done, isFalse);
    for (var i = 0; i < 3; i++) {
      expect(player.plays, i + 1);
      player.completion.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await pending;
    expect(requested.join(), text);
    expect(done, isTrue);
    await player.completion.close();
  });
  test(
    'small audio payload does not end playback on the old estimated timeout',
    () async {
      final player = Player();
      final tts = TtsService(
        tts: SystemTts(),
        player: player,
        synthesize: (_) async => Uint8List.fromList([1]),
      );
      var done = false;
      final pending = tts.speak('慢速长音频').then((_) => done = true);
      await Future<void>.delayed(const Duration(milliseconds: 3200));
      expect(done, isFalse);
      player.completion.add(null);
      await pending;
      await player.completion.close();
    },
  );

  test('stop while synthesis is pending cannot start late playback', () async {
    final player = Player();
    final synthesis = Completer<Uint8List?>();
    final tts = TtsService(
      tts: SystemTts(),
      player: player,
      synthesize: (_) => synthesis.future,
    );
    final pending = tts.speak('你好');
    await Future<void>.delayed(Duration.zero);
    await tts.stop();
    synthesis.complete(Uint8List.fromList([1]));
    await pending;
    expect(player.plays, 0);
    await player.completion.close();
  });
  test('explicit stop cancels remaining speech chunks', () async {
    final player = Player();
    final tts = TtsService(
      tts: SystemTts(),
      player: player,
      synthesize: (_) async => Uint8List.fromList([1]),
    );
    final pending = tts.speak('啊' * 650);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await tts.stop();
    await pending;
    expect(player.plays, 1);
    await player.completion.close();
  });
  test('player failure propagates instead of silently completing', () async {
    final player = Player();
    final tts = TtsService(
      tts: SystemTts(),
      player: player,
      synthesize: (_) async => Uint8List.fromList([1]),
    );
    final pending = tts.speak('你好');
    final result = expectLater(pending, throwsStateError);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    player.completion.addError(StateError('speaker failed'));
    await result;
    await player.completion.close();
  });
}

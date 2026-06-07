import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_companion/features/voice/wake_word_matcher.dart';

void main() {
  const matcher = WakeWordMatcher();

  test('primary wake word wakes directly', () {
    final result = matcher.match('萌萌，你在吗');

    expect(result, isNotNull);
    expect(result!.persona, 'mengmeng');
    expect(result.command, '你在吗');
    expect(result.score, greaterThanOrEqualTo(0.85));
  });

  test('fuzzy wake word alone is ignored', () {
    expect(matcher.match('妹妹'), isNull);
    expect(matcher.match('么么'), isNull);
  });

  test('fuzzy wake word with command can wake', () {
    final result = matcher.match('妹妹帮我看看这个');

    expect(result, isNotNull);
    expect(result!.persona, 'mengmeng');
    expect(result.command, '帮我看看这个');
  });

  test('prompt leak flag suppresses weak wake result', () {
    expect(matcher.match('梦梦', flags: ['prompt_leak_removed']), isNull);
  });
}

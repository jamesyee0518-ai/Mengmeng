import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_companion/features/chat/conversation_coordinator.dart';
import 'package:pocket_companion/features/chat/conversation_context.dart';
import 'package:pocket_companion/features/chat/robot_response.dart';

RobotResponse reply([String text = '记住了']) =>
    RobotResponse.fromMap({'text': text, 'model_provider': 'lmstudio'});

void main() {
  late ConversationCoordinator coordinator;
  setUp(() => coordinator = ConversationCoordinator());
  tearDown(() => coordinator.dispose());
  Future<TurnResult> turn(
    String text, {
    String persona = 'mengmeng',
    bool automatic = false,
    bool useContext = true,
    RobotResponse? response,
  }) => coordinator.run(
    persona: persona,
    userText: text,
    automatic: automatic,
    useContext: useContext,
    request: (_, _) async => response ?? reply(),
    deliver: (_, _) async {},
  );

  test('next request receives complete immutable prior turns', () async {
    await turn('我叫小明');
    ConversationContext? snapshot;
    await coordinator.run(
      persona: 'mengmeng',
      userText: '我叫什么',
      request: (context, _) async {
        snapshot = context;
        return reply('小明');
      },
      deliver: (_, _) async {},
    );
    expect(snapshot!.history.map((m) => m['role']), ['user', 'assistant']);
    expect(snapshot!.history.first['content'], '我叫小明');
    expect(coordinator.context.history.length, 4);
    expect(
      () => snapshot!.history.first['content'] = 'changed',
      throwsUnsupportedError,
    );
    expect(snapshot!.history.length, 2);
  });

  test('clips whole pairs by turn count and character budget', () async {
    for (var i = 0; i < 10; i++) {
      await turn('question $i');
    }
    expect(coordinator.context.history.length, 12);
    expect(coordinator.context.history.first['content'], 'question 4');
    for (var i = 0; i < 4; i++) {
      await turn('问' * 3000, response: reply('答' * 3000));
    }
    expect(coordinator.context.history.length, 6);
    expect(
      coordinator.context.history.every((m) => m['content']!.length == 2000),
      isTrue,
    );
  });

  test('persona and new session clear history and rotate identity', () async {
    await turn('秘密');
    final firstId = coordinator.context.sessionId;
    await turn('你好', persona: 'xiaoyuan');
    expect(coordinator.context.sessionId, isNot(firstId));
    expect(coordinator.context.history.first['content'], '你好');
    coordinator.newSession();
    expect(coordinator.context.history, isEmpty);
  });

  test(
    'automatic, privacy, rules and fallback turns never enter history',
    () async {
      await turn('自动', automatic: true);
      await turn('隐私', useContext: false);
      await turn('失败', response: RobotResponse.fallback());
      await turn('规则', response: RobotResponse.fromMap({'text': '好的'}));
      await turn(
        '错误',
        response: RobotResponse.fromMap({
          'text': '好的',
          'model_provider': 'lmstudio',
          'model_error': 'timeout',
        }),
      );
      expect(coordinator.context.history, isEmpty);
      await turn('正常');
      await coordinator.run(
        persona: 'mengmeng',
        useContext: false,
        request: (context, _) async {
          expect(context.history, isEmpty);
          return reply();
        },
        deliver: (_, _) async {},
      );
      expect(coordinator.context.history.length, 2);
    },
  );

  test(
    'one owner through playback, rejects users and drops automatic events',
    () async {
      final playback = Completer<void>();
      final pending = coordinator.run(
        persona: 'mengmeng',
        userText: 'hi',
        request: (_, _) async => reply(),
        deliver: (_, _) => playback.future,
      );
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.phase, ConversationPhase.delivering);
      expect(await turn('second'), TurnResult.busy);
      expect(await turn('sensor', automatic: true), TurnResult.dropped);
      playback.complete();
      expect(await pending, TurnResult.completed);
      expect(coordinator.isBusy, isFalse);
    },
  );

  test('cancelled request cannot deliver or release a newer request', () async {
    final old = Completer<RobotResponse>();
    final fresh = Completer<RobotResponse>();
    var delivered = false;
    final pending = coordinator.run(
      persona: 'mengmeng',
      userText: 'old',
      request: (_, _) => old.future,
      deliver: (_, _) async {
        delivered = true;
      },
    );
    coordinator.cancel(clearHistory: true);
    final next = coordinator.run(
      persona: 'mengmeng',
      userText: 'new',
      request: (_, _) => fresh.future,
      deliver: (_, _) async {},
    );
    old.complete(reply());
    expect(await pending, TurnResult.cancelled);
    expect(delivered, isFalse);
    expect(coordinator.isBusy, isTrue);
    fresh.complete(reply());
    await next;
    expect(coordinator.context.history.first['content'], 'new');
  });

  test('cancel during playback invalidates continuation and history', () async {
    final playback = Completer<void>();
    bool Function()? isCurrent;
    final pending = coordinator.run(
      persona: 'mengmeng',
      userText: 'old',
      request: (_, _) async => reply(),
      deliver: (_, current) {
        isCurrent = current;
        return playback.future;
      },
    );
    await Future<void>.delayed(Duration.zero);
    coordinator.newSession();
    expect(isCurrent!(), isFalse);
    playback.complete();
    expect(await pending, TurnResult.cancelled);
    expect(coordinator.context.history, isEmpty);
  });

  test(
    'delivery failure releases owner without remembering response',
    () async {
      expect(
        await coordinator.run(
          persona: 'mengmeng',
          userText: 'hi',
          request: (_, _) async => reply(),
          deliver: (_, _) async {
            throw StateError('speaker');
          },
        ),
        TurnResult.failed,
      );
      expect(coordinator.isBusy, isFalse);
      expect(coordinator.lastError, isA<StateError>());
      expect(coordinator.context.history, isEmpty);
      expect(await turn('retry'), TurnResult.completed);
      expect(coordinator.lastError, isNull);
    },
  );
}

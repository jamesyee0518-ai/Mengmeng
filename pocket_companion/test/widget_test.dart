import 'package:pocket_companion/core/logging/debug_log_store.dart';
import 'package:pocket_companion/features/voice/voice_settings_store.dart';
import 'package:pocket_companion/features/chat/conversation_context.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_companion/core/network/ai_gateway_client.dart';
import 'package:pocket_companion/core/network/gateway_health_service.dart';
import 'package:pocket_companion/core/network/robot_http_transport.dart';
import 'package:pocket_companion/features/chat/robot_response.dart';
import 'package:pocket_companion/features/device/device_event.dart';
import 'package:pocket_companion/features/device/device_event_service.dart';
import 'package:pocket_companion/features/face/face_page.dart';
import 'package:pocket_companion/features/settings/companion_settings.dart';
import 'package:pocket_companion/features/vision/vision_check_result.dart';
import 'package:pocket_companion/features/vision/vision_service.dart';
import 'package:pocket_companion/features/voice/speech_service.dart';
import 'package:pocket_companion/features/voice/tts_service.dart';

/// 沉浸式模式：触摸脸区唤出顶部状态条与底部输入区
Future<void> _revealComposer(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('robotFaceArea')));
  // 推进时间冲掉双击识别器的等待定时器，避免测试收尾报 pending timer
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets(
    'default wake resumes after background and diagnostics fit landscape',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(780, 360));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final speech = _FakeSpeechService();
      await tester.pumpWidget(_testApp(speech: speech, autoStartWake: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      final count = speech.listenOnceCalls;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(speech.listenOnceCalls, greaterThan(count));
      await tester.tap(find.byKey(const ValueKey('noticeButton')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('语音诊断'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const ValueKey('voiceDiagnosticsScroll')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byKey(const ValueKey('voiceDiagnosticsScroll')),
        const Offset(0, -250),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets('wake starts by default and manual stop survives resume', (
    tester,
  ) async {
    final speech = _FakeSpeechService();
    await tester.pumpWidget(_testApp(speech: speech, autoStartWake: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(speech.listenOnceCalls, greaterThan(0));
    await _openControls(tester);
    expect(find.text('关闭唤醒'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('toggleWakeListening')));
    await tester.pump();
    final count = speech.listenOnceCalls;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 1));
    expect(speech.listenOnceCalls, count);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'errors stay behind persistent red dot and reading clears unread',
    (tester) async {
      final logs = DebugLogStore();
      await tester.pumpWidget(_testApp(logs: logs));
      await tester.pump();
      logs.warning('speech', '测试错误提示');
      await tester.pump();
      expect(find.text('测试错误提示'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byKey(const ValueKey('unreadNoticeDot')), findsOneWidget);
      expect(find.byKey(const ValueKey('expressionLabel')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('noticeButton')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('测试错误提示'), findsOneWidget);
      expect(find.byKey(const ValueKey('unreadNoticeDot')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'page carries prior turn and clears it after leaving foreground',
    (tester) async {
      final gateway = _ContextGatewayClient();
      await tester.pumpWidget(_testApp(gateway: gateway));
      await _revealComposer(tester);
      Future<void> send(String text) async {
        await tester.enterText(find.byKey(const ValueKey('chatInput')), text);
        await tester.tap(find.byKey(const ValueKey('sendChat')));
        await tester.pump();
        await tester.pump();
      }

      await send('我叫小明');
      await send('我叫什么');
      expect(gateway.contexts[0].history, isEmpty);
      expect(gateway.contexts[1].history.first['content'], '我叫小明');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await send('新的对话');
      expect(gateway.contexts.last.history, isEmpty);
      expect(
        gateway.contexts.last.sessionId,
        isNot(gateway.contexts.first.sessionId),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('backgrounding discards an outstanding reply', (tester) async {
    final gateway = _PendingGatewayClient();
    final tts = _FakeTtsService();
    await tester.pumpWidget(_testApp(gateway: gateway, tts: tts));
    await _revealComposer(tester);
    await tester.enterText(find.byKey(const ValueKey('chatInput')), 'test');
    await tester.tap(find.byKey(const ValueKey('sendChat')));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    gateway.reply.complete(
      RobotResponse.fromMap({
        'text': 'late reply',
        'expression': 'neutral',
        'should_speak': true,
      }),
    );
    await tester.pump();
    await tester.pump();
    expect(tts.spokenTexts, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('revealing controls does not trigger a gateway event', (
    tester,
  ) async {
    final gateway = _PendingGatewayClient();
    await tester.pumpWidget(_testApp(gateway: gateway));
    await _revealComposer(tester);
    expect(gateway.eventCalls, 0);
  });

  testWidgets(
    'open controls unlock all five actions when a request completes',
    (tester) async {
      final gateway = _PendingGatewayClient();
      await tester.pumpWidget(_testApp(gateway: gateway));
      await _revealComposer(tester);
      await tester.enterText(find.byKey(const ValueKey('chatInput')), 'test');
      await tester.tap(find.byKey(const ValueKey('sendChat')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('openControlPanel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final keys = [
        'toggleWakeListening',
        'toggleVoiceConversation',
        'panelListenVoice',
        'panelLook',
        'toggleVisionMonitoring',
      ];
      FilledButton button(String key) => tester.widget<FilledButton>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(FilledButton),
        ),
      );
      for (final key in keys) {
        expect(button(key).onPressed, isNull);
      }
      gateway.reply.complete(
        RobotResponse.fromMap({
          'text': 'done',
          'expression': 'neutral',
          'should_speak': false,
        }),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
      for (final key in keys) {
        expect(button(key).onPressed, isNotNull, reason: key);
      }
      await tester.tap(find.byKey(const ValueKey('toggleVisionMonitoring')));
      await tester.pump();
      await tester.pump();
      expect(find.text('关闭守望'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('toggleVisionMonitoring')));
      await tester.pump();
      await tester.pump();
      expect(find.text('视觉守望'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 11));
    },
  );

  testWidgets('FacePage smoke builds robot shell', (tester) async {
    await tester.pumpWidget(_testApp());

    expect(find.bySemanticsLabel('robot face neutral'), findsOneWidget);
    // 顶部状态条与底部输入区默认都隐藏，触摸脸区后一起出现
    expect(find.byKey(const ValueKey('openControlPanel')), findsNothing);
    expect(find.byKey(const ValueKey('chatInput')), findsNothing);
    await _revealComposer(tester);
    expect(find.byKey(const ValueKey('openControlPanel')), findsOneWidget);
    expect(find.byKey(const ValueKey('chatInput')), findsOneWidget);
    expect(find.byKey(const ValueKey('listenVoice')), findsOneWidget);
    expect(find.byKey(const ValueKey('sendChat')), findsOneWidget);
  });

  testWidgets('control panel exposes stable action keys', (tester) async {
    await tester.pumpWidget(_testApp());
    await _openControls(tester);

    expect(
      find.byKey(const ValueKey('toggleVoiceConversation')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('togglePrivacy')), findsOneWidget);
    expect(find.byKey(const ValueKey('openMemory')), findsOneWidget);
    expect(find.byKey(const ValueKey('openLogs')), findsOneWidget);
    expect(find.byKey(const ValueKey('openDeviceCheck')), findsOneWidget);
    expect(find.byKey(const ValueKey('toggleVoiceDebugPanel')), findsOneWidget);
    expect(find.byKey(const ValueKey('debugShakeButton')), findsOneWidget);
  });

  testWidgets('debug shake button can be tapped by stable key', (tester) async {
    await tester.pumpWidget(_testApp());
    await _openControls(tester);

    await tester.tap(find.byKey(const ValueKey('debugShakeButton')));
    await tester.pump();

    expect(find.byKey(const ValueKey('debugShakeButton')), findsOneWidget);
  });

  testWidgets('chat can start and stop speaking', (tester) async {
    await tester.pumpWidget(_testApp());
    await _revealComposer(tester);

    await tester.enterText(find.byKey(const ValueKey('chatInput')), 'hello');
    await tester.tap(find.byKey(const ValueKey('sendChat')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byKey(const ValueKey('stopSpeaking')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('stopSpeaking')));
    await tester.pump();

    expect(find.byKey(const ValueKey('stopSpeaking')), findsNothing);
  });

  testWidgets('privacy disables composer voice input', (tester) async {
    await tester.pumpWidget(_testApp());
    await _revealComposer(tester);
    await _openControls(tester);

    await tester.tap(find.byKey(const ValueKey('togglePrivacy')));
    await tester.pump();

    final listenButton = tester.widget<IconButton>(
      find.byKey(const ValueKey('listenVoice')),
    );
    expect(listenButton.onPressed, isNull);
  });

  testWidgets('device check panel opens from stable key', (tester) async {
    await tester.pumpWidget(_testApp());
    await _openControls(tester);

    await tester.tap(find.byKey(const ValueKey('openDeviceCheck')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('checkVision')), findsOneWidget);
    expect(find.byKey(const ValueKey('checkSpeech')), findsOneWidget);
    expect(find.byKey(const ValueKey('checkLightImpact')), findsOneWidget);
  });

  testWidgets('gateway unavailable does not block wake startup', (
    tester,
  ) async {
    final speech = _FakeSpeechService();
    await tester.pumpWidget(
      _testApp(
        speech: speech,
        gatewayHealthService: GatewayHealthService(
          transport: const _HealthTransport(
            body:
                '{"ok":false,"gateway":{"ok":false,"reason":"gateway_unavailable"},'
                '"stt":{"ok":true},"llm":{"ok":true},"tts":{"ok":true}}',
          ),
        ),
      ),
    );
    await _openControls(tester);

    await tester.tap(find.byKey(const ValueKey('toggleWakeListening')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(speech.listenOnceCalls, greaterThan(0));
    expect(find.byType(SnackBar), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('stt health does not block wake startup', (tester) async {
    final speech = _FakeSpeechService();
    await tester.pumpWidget(
      _testApp(
        speech: speech,
        gatewayHealthService: GatewayHealthService(
          transport: const _HealthTransport(
            body:
                '{"ok":false,"gateway":{"ok":true},'
                '"stt":{"ok":false,"reason":"stt_unavailable"},'
                '"llm":{"ok":true},"tts":{"ok":true}}',
          ),
        ),
      ),
    );
    await _openControls(tester);

    await tester.tap(find.byKey(const ValueKey('toggleWakeListening')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(speech.listenOnceCalls, greaterThan(0));
    expect(find.byType(SnackBar), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}

Future<void> _openControls(WidgetTester tester) async {
  await _revealComposer(tester);
  await tester.tap(find.byKey(const ValueKey('openControlPanel')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Widget _testApp({
  AiGatewayClient? gateway,
  DeviceEventService? deviceEvents,
  TtsService? tts,
  SpeechService? speech,
  GatewayHealthService? gatewayHealthService,
  bool autoStartWake = false,
  DebugLogStore? logs,
}) {
  return MaterialApp(
    home: FacePage(
      autoStartWake: autoStartWake,
      logs: logs,
      voiceSettingsStore: MemoryVoiceSettingsStore(),
      gateway: gateway ?? _FakeGatewayClient(),
      tts: tts ?? _FakeTtsService(),
      speech: speech ?? _FakeSpeechService(),
      vision: _FakeVisionService(),
      deviceEvents: deviceEvents,
      gatewayHealthService:
          gatewayHealthService ??
          GatewayHealthService(
            transport: const _HealthTransport(
              body:
                  '{"ok":true,"gateway":{"ok":true},"stt":{"ok":true},'
                  '"llm":{"ok":true},"tts":{"ok":true}}',
            ),
          ),
    ),
  );
}

class _FakeVisionService extends VisionService {
  @override
  Future<VisionCheckResult> checkOnce() async {
    return const VisionCheckResult(ok: true, label: 'camera ok');
  }
}

class _FakeSpeechService extends SpeechService {
  int listenOnceCalls = 0;

  @override
  Future<String?> listenOnce({
    Duration listenFor = const Duration(seconds: 5),
  }) async {
    listenOnceCalls++;
    return '今天有点累';
  }

  @override
  Future<String> microphonePermissionStatus() async => 'granted';
}

class _HealthTransport implements RobotHttpTransport {
  const _HealthTransport({required this.body});

  final String body;

  @override
  Future<RobotHttpResponse> get(
    Uri uri, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    return RobotHttpResponse(statusCode: 200, body: body);
  }

  @override
  Future<RobotHttpResponse> postJson(
    Uri uri,
    String body, {
    Duration timeout = const Duration(seconds: 3),
  }) {
    throw UnimplementedError();
  }
}

class _FakeTtsService extends TtsService {
  Completer<void>? _active;
  final List<String> spokenTexts = [];

  @override
  Future<void> speak(
    String text, {
    String style = 'warm',
    double speed = 0.95,
    double pitch = 1.0,
    double volume = 0.75,
    String persona = 'mengmeng',
  }) {
    spokenTexts.add(text);
    if (style == 'impact') {
      return Future<void>.value();
    }
    _active = Completer<void>();
    return _active!.future;
  }

  @override
  Future<void> stop() async {
    if (_active?.isCompleted == false) {
      _active?.complete();
    }
  }
}

class _FakeGatewayClient extends AiGatewayClient {
  @override
  Future<bool> health() async => true;

  @override
  Future<RobotResponse> event(
    String type, {
    CompanionSettings? settings,
    DeviceEvent? deviceEvent,
    String? persona,
    String? source,
  }) async {
    if (type == 'shake') {
      return RobotResponse.fromMap({
        'text': 'shake',
        'emotion': 'dizzy',
        'expression': 'dizzy',
        'eye_action': 'spiral',
        'mouth_action': 'wavy',
        'haptic': 'dizzy_buzz',
        'should_speak': settings?.allowSpeechOutput ?? false,
        'should_remember': false,
        'robot_state': _robotState('dizzy', 67),
      });
    }
    return RobotResponse.fromMap({
      'text': 'ok',
      'emotion': 'neutral',
      'expression': 'neutral',
      'eye_action': 'soft_blink',
      'mouth_action': 'rest',
      'haptic': 'none',
      'should_speak': settings?.allowSpeechOutput ?? false,
      'should_remember': false,
      'robot_state': _robotState('neutral', 72),
    });
  }

  @override
  Future<RobotResponse> chat(
    String text, {
    CompanionSettings? settings,
    String? persona,
    ConversationContext? context,
  }) async {
    return RobotResponse.fromMap({
      'text': 'chat ok',
      'emotion': 'caring',
      'expression': 'caring',
      'eye_action': 'slow_blink',
      'mouth_action': 'soft_smile',
      'haptic': 'soft_pulse',
      'should_speak': settings?.allowSpeechOutput ?? true,
      'should_remember': settings?.allowMemory ?? false,
      'robot_state': _robotState('caring', 78),
    });
  }
}

Map<String, Object> _robotState(String mood, int energy) {
  return {
    'mood': mood,
    'energy': energy,
    'trust': 36,
    'attention': 70,
    'curiosity': 50,
    'sleepiness': 24,
    'last_interaction_at': '2026-06-06T00:00:00Z',
  };
}

class _PendingGatewayClient extends _FakeGatewayClient {
  final reply = Completer<RobotResponse>();
  int eventCalls = 0;

  @override
  Future<RobotResponse> chat(
    String text, {
    CompanionSettings? settings,
    String? persona,
    ConversationContext? context,
  }) => reply.future;

  @override
  Future<RobotResponse> event(
    String type, {
    CompanionSettings? settings,
    DeviceEvent? deviceEvent,
    String? persona,
    String? source,
  }) {
    eventCalls++;
    return super.event(
      type,
      settings: settings,
      deviceEvent: deviceEvent,
      persona: persona,
      source: source,
    );
  }
}

class _ContextGatewayClient extends _FakeGatewayClient {
  final contexts = <ConversationContext>[];
  @override
  Future<RobotResponse> chat(
    String text, {
    CompanionSettings? settings,
    String? persona,
    ConversationContext? context,
  }) async {
    contexts.add(context!);
    return RobotResponse.fromMap({
      'text': '你好小明',
      'model_provider': 'lmstudio',
      'should_speak': false,
    });
  }
}

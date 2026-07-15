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

void main() {
  testWidgets('FacePage smoke builds robot shell', (tester) async {
    await tester.pumpWidget(_testApp());

    expect(find.bySemanticsLabel('robot face neutral'), findsOneWidget);
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

  testWidgets('gateway unavailable blocks wake listening', (tester) async {
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

    expect(speech.listenOnceCalls, 0);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('stt unavailable blocks wake listening', (tester) async {
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

    expect(speech.listenOnceCalls, 0);
    expect(find.byType(SnackBar), findsOneWidget);
  });
}

Future<void> _openControls(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('openControlPanel')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Widget _testApp({
  DeviceEventService? deviceEvents,
  TtsService? tts,
  SpeechService? speech,
  GatewayHealthService? gatewayHealthService,
}) {
  return MaterialApp(
    home: FacePage(
      gateway: _FakeGatewayClient(),
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

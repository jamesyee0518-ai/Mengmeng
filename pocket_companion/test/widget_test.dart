import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_companion/core/network/ai_gateway_client.dart';
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
  testWidgets('shows the robot face shell', (tester) async {
    await tester.pumpWidget(_testApp());

    expect(find.bySemanticsLabel('robot face neutral'), findsOneWidget);
    expect(find.text('待机'), findsOneWidget);
  });

  testWidgets('debug dock can switch expressions', (tester) async {
    await tester.pumpWidget(_testApp());

    await tester.tap(find.byKey(const ValueKey('debug_摇晃')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('哇，别晃啦，我有点头晕。'), findsOneWidget);
    expect(find.bySemanticsLabel('robot face dizzy'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('debug_复位')));
    await tester.pump();

    expect(find.text('待机'), findsOneWidget);
  });

  testWidgets('chat input applies gateway response', (tester) async {
    await tester.pumpWidget(_testApp());

    await tester.enterText(find.byKey(const ValueKey('chatInput')), '今天有点累');
    await tester.tap(find.byKey(const ValueKey('sendChat')));
    await tester.pump();

    expect(find.text('正在想'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('听起来你今天消耗不少。我可以先安静陪你一会儿。'), findsOneWidget);
    expect(find.bySemanticsLabel('robot face caring'), findsOneWidget);
    expect(find.text('78%'), findsOneWidget);
    expect(find.byKey(const ValueKey('stopSpeaking')), findsOneWidget);
  });

  testWidgets('speaking can be interrupted', (tester) async {
    await tester.pumpWidget(_testApp());

    await tester.enterText(find.byKey(const ValueKey('chatInput')), '今天有点累');
    await tester.tap(find.byKey(const ValueKey('sendChat')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    await tester.tap(find.byKey(const ValueKey('stopSpeaking')));
    await tester.pump();

    expect(find.byKey(const ValueKey('stopSpeaking')), findsNothing);
  });

  testWidgets('voice input sends recognized text to chat', (tester) async {
    await tester.pumpWidget(_testApp());

    await tester.tap(find.byKey(const ValueKey('listenVoice')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('听起来你今天消耗不少。我可以先安静陪你一会儿。'), findsOneWidget);
    expect(find.bySemanticsLabel('robot face caring'), findsOneWidget);
    expect(find.byKey(const ValueKey('stopSpeaking')), findsOneWidget);
  });

  testWidgets('voice conversation starts from composer', (tester) async {
    await tester.pumpWidget(_testApp());

    await tester.tap(find.byKey(const ValueKey('toggleVoiceConversation')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('听起来你今天消耗不少。我可以先安静陪你一会儿。'), findsOneWidget);
    expect(find.byKey(const ValueKey('stopSpeaking')), findsOneWidget);
  });

  testWidgets('privacy mode disables listening and speech output', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp());

    await tester.tap(find.byKey(const ValueKey('togglePrivacy')));
    await tester.pump();

    final listenButton = tester.widget<IconButton>(
      find.byKey(const ValueKey('listenVoice')),
    );
    expect(listenButton.onPressed, isNull);

    await tester.enterText(find.byKey(const ValueKey('chatInput')), '今天有点累');
    await tester.tap(find.byKey(const ValueKey('sendChat')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('听起来你今天消耗不少。我可以先安静陪你一会儿。'), findsOneWidget);
    expect(find.byKey(const ValueKey('stopSpeaking')), findsNothing);
  });

  testWidgets('memory entry is available from face page', (tester) async {
    await tester.pumpWidget(_testApp());

    expect(find.byKey(const ValueKey('openMemory')), findsOneWidget);
  });

  testWidgets('log entry is available from face page', (tester) async {
    await tester.pumpWidget(_testApp());

    expect(find.byKey(const ValueKey('openLogs')), findsOneWidget);
  });

  testWidgets('device check panel receives simulated impact events', (
    tester,
  ) async {
    final deviceEvents = DeviceEventService();
    final tts = _FakeTtsService();
    await tester.pumpWidget(_testApp(deviceEvents: deviceEvents, tts: tts));

    await tester.tap(find.byKey(const ValueKey('openDeviceCheck')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('设备自检'), findsOneWidget);
    expect(find.text('未触发'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('checkLightImpact')));
    await tester.pump();

    expect(find.text('light 14.0'), findsNWidgets(2));
    expect(find.text('simulated:shake light 14.0'), findsOneWidget);
    expect(tts.spokenTexts, contains('嗯？'));

    await tester.tap(find.byKey(const ValueKey('checkMediumImpact')));
    await tester.pump();

    expect(find.text('medium 28.0'), findsOneWidget);
    expect(find.text('simulated:shake medium 28.0'), findsOneWidget);
    expect(tts.spokenTexts, contains('哎呀。'));

    await tester.tap(find.byKey(const ValueKey('checkStrongImpact')));
    await tester.pump();

    expect(find.text('strong 34.0'), findsOneWidget);
    expect(find.text('simulated:shake strong 34.0'), findsOneWidget);
    expect(tts.spokenTexts, contains('哇！'));

    await tester.tap(find.byKey(const ValueKey('checkExtremeImpact')));
    await tester.pump();

    expect(find.text('extreme 44.0'), findsNWidgets(2));
    expect(find.text('simulated:shake extreme 44.0'), findsOneWidget);
    expect(tts.spokenTexts, contains('啊！疼。'));
  });

  testWidgets('device check panel tests seeing and listening', (tester) async {
    await tester.pumpWidget(_testApp());

    await tester.tap(find.byKey(const ValueKey('openDeviceCheck')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.byKey(const ValueKey('checkVision')));
    await tester.pump();

    expect(find.text('前置相机已打开'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('checkSpeech')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('今天有点累'), findsOneWidget);
  });
}

Widget _testApp({DeviceEventService? deviceEvents, TtsService? tts}) {
  return MaterialApp(
    home: FacePage(
      gateway: _FakeGatewayClient(),
      tts: tts ?? _FakeTtsService(),
      speech: _FakeSpeechService(),
      vision: _FakeVisionService(),
      deviceEvents: deviceEvents,
    ),
  );
}

class _FakeVisionService extends VisionService {
  @override
  Future<VisionCheckResult> checkOnce() async {
    return const VisionCheckResult(ok: true, label: '前置相机已打开');
  }
}

class _FakeSpeechService extends SpeechService {
  @override
  Future<String?> listenOnce() async => '今天有点累';
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
  }) async {
    if (type == 'shake') {
      return RobotResponse.fromMap({
        'text': '哇，别晃啦，我有点头晕。',
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
      'text': '我收到了。',
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
  Future<RobotResponse> chat(String text, {CompanionSettings? settings}) async {
    return RobotResponse.fromMap({
      'text': '听起来你今天消耗不少。我可以先安静陪你一会儿。',
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

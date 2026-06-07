# Voice Wake-up Progress

## Current Status

As of the current V2.0-alpha checkpoint, the voice wake-up pipeline has moved from a FacePage-managed loop into a controller-driven voice subsystem.

Completed:

- V1.1: text-level wake-word matching with primary, alias, fuzzy, and similarity scoring.
- V1.2: Android audio RMS metadata, lightweight audio gate, and Gateway `/stt` empty or short-audio fallback.
- V1.2.5: `recordUntilSilence` for conversation recording.
- V1.3: `VoiceWakeController` extracted from `FacePage`.
- V1.4: `VoiceDebugSnapshot` and debug panel.
- V1.4.5: dynamic tuning and debug sample labeling.
- V1.4.6: JSONL sample persistence, recent sample view, summary, export path, and clear action.
- V1.5: simplified high-RMS TTS barge-in.
- V1.6: sample replay analysis and threshold recommendation.
- V1.6.5: stable widget smoke tests and key-based control panel tests.
- V1.7: lifecycle governance, cancellation generation token, microphone permission handling, and native recording mutex.
- V1.7.5: Gateway `/health`, timeout protection, and offline degradation.
- V1.8: runtime voice profiles and persistent settings.
- V2.0-alpha: `WakeDetector` abstraction, default `SttWakeDetector`, and native detector stubs for Sherpa-ONNX and openWakeWord.

Current default monitoring path:

```text
VoiceWakeController
  -> WakeDetector.detectOnce()
  -> SttWakeDetector
  -> SpeechService.listenOnce()
  -> audio gate
  -> Gateway /stt
  -> WakeWordMatcher
  -> WakeDetectorDetected / WakeDetectorIgnored
  -> VoiceWakeController converts to VoiceEvent
```

Compatibility retained:

- Monitoring still defaults to STT fallback.
- Conversation still uses `listenForUtterance` and must not be replaced by local wake detection.
- Barge-in, debug panel, JSONL samples, health check, lifecycle handling, and TTS cooldown remain in place.
- Wake matcher rules are preserved, including fuzzy words not waking alone and prompt-leak flag penalties.

Latest verification:

- `dart analyze`: passed.
- `flutter test`: passed.
- `python3 -m py_compile ai_gateway/main.py`: passed.
- `git diff --check`: passed.

## Next Development Plan

Goal: connect Sherpa-ONNX to monitoring wake-up only. Do not change conversation STT.

1. Implement Dart `SherpaOnnxWakeDetector` and fake native-event unit tests.
   - Add a Dart detector implementation that consumes native wake events.
   - Keep `SttWakeDetector` as fallback.
   - Test detector event mapping with fake native events first.

2. Add Android MethodChannel/EventChannel.
   - Use MethodChannel for init, start, stop, dispose, and status.
   - Use EventChannel for streaming wake events and errors.
   - Preserve recording mutex rules so Sherpa monitoring does not conflict with `recordUntilSilence` or barge-in.

3. Add model file path and initialization.
   - Define Android model asset or external file path handling.
   - Report model path, init status, and errors into `VoiceDebugSnapshot`.
   - Fail safely back to STT if model initialization fails.

4. Run real-device experiments.
   - Test quiet room, noisy room, far-field, TTS playback, and lifecycle transitions.
   - Verify that monitoring local wake does not call Gateway `/stt` unless fallback is explicitly used.
   - Verify conversation still records with `recordUntilSilence` and sends user utterances to STT.

5. Add Debug Panel switching and JSONL fields.
   - Allow selecting STT / Sherpa-ONNX / openWakeWord from the debug panel.
   - Persist selected detector type with voice settings.
   - Record detector type, native score, model status, and fallback reason in JSONL samples.

Non-goals for the next step:

- Do not modify conversation STT.
- Do not train a custom wake-word model.
- Do not save raw audio files.
- Do not remove STT fallback.
- Do not make large UI changes.

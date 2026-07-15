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
- V2.1-alpha: Sherpa-ONNX 1.13.4 Android KWS integration, bundled Mengmeng model, 16 kHz native PCM stream, and automatic STT fallback.

Current Android monitoring path:

```text
VoiceWakeController
  -> SherpaOnnxWakeDetector
  -> Android EventChannel (16 kHz mono PCM)
  -> local sherpa-onnx keyword spotter
  -> Mengmeng / Xiaoyuan / Qunqun teacher
  -> WakeDetectorDetected / WakeDetectorIgnored
  -> VoiceWakeController converts to VoiceEvent
```

If native initialization or model loading fails, monitoring falls back to the existing STT wake path. Conversation recording and conversation STT are unchanged.

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

Goal: complete real-device tuning of Sherpa-ONNX monitoring wake-up. Do not change conversation STT.

1. Run real-device experiments.
   - Test quiet room, noisy room, far-field, TTS playback, and lifecycle transitions.
   - Verify that monitoring local wake does not call Gateway `/stt` unless fallback is explicitly used.
   - Verify conversation still records with `recordUntilSilence` and sends user utterances to STT.

2. Add Debug Panel switching and JSONL fields.
   - Allow selecting STT / Sherpa-ONNX / openWakeWord from the debug panel.
   - Persist selected detector type with voice settings.
   - Record detector type, native score, model status, and fallback reason in JSONL samples.

Non-goals for the next step:

- Do not modify conversation STT.
- Do not train a custom wake-word model.
- Do not save raw audio files.
- Do not remove STT fallback.
- Do not make large UI changes.

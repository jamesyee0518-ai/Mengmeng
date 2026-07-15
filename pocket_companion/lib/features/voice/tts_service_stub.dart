class TtsService {
  Future<void> speak(
    String text, {
    String style = 'warm',
    double speed = 0.95,
    double pitch = 1.0,
    double volume = 0.75,
  }) {
    throw UnsupportedError('TTS is not available on this platform.');
  }

  Future<void> stop() async {}
}

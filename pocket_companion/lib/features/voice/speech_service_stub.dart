class SpeechService {
  Future<String?> listenOnce({Duration listenFor = const Duration(seconds: 5)}) {
    throw UnsupportedError(
      'Speech recognition is not available on this platform.',
    );
  }

  Future<void> stop() async {}
}

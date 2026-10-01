enum VoiceState {
  idle,
  monitoring,
  wakeCandidate,
  awakened,
  conversation,
  recording,
  transcribing,
  thinking,
  speaking,
  bargeInListening,
  error,
}

/// User-visible session mode, independent of recording and playback phases.
enum VoiceMode { off, wake, conversation }

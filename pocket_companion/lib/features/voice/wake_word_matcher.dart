enum WakeMatchType { primary, alias, fuzzy, levenshtein }

class WakeCommand {
  const WakeCommand({
    required this.persona,
    required this.wakeWord,
    required this.command,
    required this.score,
    required this.type,
    required this.requiresConfirmation,
  });

  final String persona;
  final String wakeWord;
  final String command;
  final double score;
  final WakeMatchType type;
  final bool requiresConfirmation;

  bool get canWakeDirectly =>
      score >= 0.85 ||
      (score >= 0.70 && command.isNotEmpty && !requiresConfirmation);
}

class WakeWordProfile {
  const WakeWordProfile({
    required this.persona,
    required this.primaryWords,
    required this.aliasWords,
    required this.fuzzyWords,
  });

  final String persona;
  final List<String> primaryWords;
  final List<String> aliasWords;
  final List<String> fuzzyWords;
}

class WakeWordMatcher {
  const WakeWordMatcher();

  WakeCommand? match(String text, {Iterable<String> flags = const []}) {
    final normalized = normalize(text);
    if (normalized.isEmpty) {
      return null;
    }

    WakeCommand? best;
    for (final profile in _profiles) {
      best = _better(
        best,
        _matchWords(
          normalized,
          profile: profile,
          words: profile.primaryWords,
          type: WakeMatchType.primary,
          baseScore: 1.0,
          flags: flags,
        ),
      );
      best = _better(
        best,
        _matchWords(
          normalized,
          profile: profile,
          words: profile.aliasWords,
          type: WakeMatchType.alias,
          baseScore: 0.85,
          flags: flags,
        ),
      );
      best = _better(
        best,
        _matchWords(
          normalized,
          profile: profile,
          words: profile.fuzzyWords,
          type: WakeMatchType.fuzzy,
          baseScore: 0.68,
          flags: flags,
        ),
      );
    }

    if (best == null && normalized.length <= 8) {
      best = _matchBySimilarity(normalized, flags: flags);
    }

    if (best == null || !best.canWakeDirectly) {
      return null;
    }
    return best;
  }

  WakeCommand? _matchWords(
    String normalized, {
    required WakeWordProfile profile,
    required List<String> words,
    required WakeMatchType type,
    required double baseScore,
    required Iterable<String> flags,
  }) {
    WakeCommand? best;
    for (final word in words) {
      final alias = normalize(word);
      final index = normalized.indexOf(alias);
      if (index < 0) {
        continue;
      }
      final command = cleanCommand(normalized.replaceFirst(alias, ''));
      final requiresConfirmation =
          type == WakeMatchType.fuzzy && command.isEmpty;
      var score = baseScore;
      if (index == 0) {
        score += 0.10;
      }
      if (command.isNotEmpty) {
        score += 0.10;
      }
      if (normalized.length >= 3 && normalized.length <= 20) {
        score += 0.05;
      }
      if (type == WakeMatchType.fuzzy) {
        score -= 0.15;
      }
      if (normalized.length <= 2 && command.isEmpty) {
        score -= 0.20;
      }
      score += _flagPenalty(flags);
      best = _better(
        best,
        WakeCommand(
          persona: profile.persona,
          wakeWord: word,
          command: command,
          score: score.clamp(0.0, 1.0),
          type: type,
          requiresConfirmation: requiresConfirmation,
        ),
      );
    }
    return best;
  }

  WakeCommand? _matchBySimilarity(
    String normalized, {
    required Iterable<String> flags,
  }) {
    WakeWordProfile? bestProfile;
    String? bestWord;
    var bestScore = 0.0;
    for (final profile in _profiles) {
      for (final word in [...profile.primaryWords, ...profile.aliasWords]) {
        final score = _similarity(normalized, normalize(word));
        if (score > bestScore) {
          bestScore = score;
          bestWord = word;
          bestProfile = profile;
        }
      }
    }
    if (bestProfile == null || bestWord == null || bestScore < 0.72) {
      return null;
    }
    final score = (0.50 + bestScore * 0.30 + _flagPenalty(flags)).clamp(
      0.0,
      1.0,
    );
    return WakeCommand(
      persona: bestProfile.persona,
      wakeWord: bestWord,
      command: '',
      score: score,
      type: WakeMatchType.levenshtein,
      requiresConfirmation: score < 0.85,
    );
  }

  double _flagPenalty(Iterable<String> flags) {
    var penalty = 0.0;
    if (flags.contains('prompt_leak_removed')) {
      penalty -= 0.30;
    }
    if (flags.contains('likely_hallucination')) {
      penalty -= 0.30;
    }
    if (flags.contains('short_text')) {
      penalty -= 0.05;
    }
    return penalty;
  }

  WakeCommand? _better(WakeCommand? left, WakeCommand? right) {
    if (right == null) {
      return left;
    }
    if (left == null || right.score > left.score) {
      return right;
    }
    return left;
  }

  static String normalize(String text) {
    return text.trim().replaceAll(
      RegExp(r'[\s，。！？、,.!?~～：:（）()\[\]【】《》"“”‘’]'),
      '',
    );
  }

  static String cleanCommand(String text) {
    final cleaned = normalize(text);
    const noiseCommands = {'同学', '老師', '老师', '啊', '呀', '呢', '喂'};
    return noiseCommands.contains(cleaned) ? '' : cleaned;
  }

  double _similarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) {
      return 0;
    }
    final distance = _levenshtein(a, b);
    final longest = a.length > b.length ? a.length : b.length;
    return 1 - distance / longest;
  }

  int _levenshtein(String a, String b) {
    final left = a.runes.toList();
    final right = b.runes.toList();
    final previous = List<int>.generate(right.length + 1, (index) => index);
    for (var i = 0; i < left.length; i++) {
      var diagonal = previous[0];
      previous[0] = i + 1;
      for (var j = 0; j < right.length; j++) {
        final insert = previous[j + 1] + 1;
        final delete = previous[j] + 1;
        final replace = diagonal + (left[i] == right[j] ? 0 : 1);
        diagonal = previous[j + 1];
        previous[j + 1] = [
          insert,
          delete,
          replace,
        ].reduce((x, y) => x < y ? x : y);
      }
    }
    return previous[right.length];
  }
}

const _profiles = [
  WakeWordProfile(
    persona: 'mengmeng',
    primaryWords: ['萌萌', '萌萌呀', '你好萌萌', '萌萌在吗'],
    aliasWords: ['梦梦', '夢夢', '蒙蒙', '濛濛', '朦朦', '萌妹'],
    fuzzyWords: ['萌', '妹妹', '么么', '农农', '農農'],
  ),
  WakeWordProfile(
    persona: 'xiaoyuan',
    primaryWords: ['小远同学', '小远', '小遠'],
    aliasWords: ['小圆同学', '小園同学', '小圆', '小園', '小袁', '小源', '小元'],
    fuzzyWords: ['小语言'],
  ),
  WakeWordProfile(
    persona: 'qunqun_teacher',
    primaryWords: ['群群老师', '群群老師', '群老师', '群老師', '群群'],
    aliasWords: ['群俊老师', '秦军老师', '秦群老师', '群君老师', '群軍老師'],
    fuzzyWords: [],
  ),
];

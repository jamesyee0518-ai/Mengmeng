/// Keep each request below the speech server's 600-character limit.
/// Preserve all text and prefer sentence boundaries, without splitting Unicode.
List<String> ttsChunks(String text, {int maxCharacters = 300}) {
  if (maxCharacters < 1) throw ArgumentError.value(maxCharacters);
  final runes = text.trim().runes.toList();
  final chunks = <String>[];
  var start = 0;
  const boundaries = '。！？!?；;\n';
  while (start < runes.length) {
    var end = (start + maxCharacters).clamp(0, runes.length);
    if (end < runes.length) {
      for (var i = end - 1; i >= start + maxCharacters ~/ 2; i--) {
        if (boundaries.contains(String.fromCharCode(runes[i]))) {
          end = i + 1;
          break;
        }
      }
    }
    chunks.add(String.fromCharCodes(runes.sublist(start, end)));
    start = end;
  }
  return chunks;
}

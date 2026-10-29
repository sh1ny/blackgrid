/// Source checks that keep raw enum names and internal jargon out of UI text.
library;

/// One offending source line, named by file and 1-based line number.
final class PlainLanguageHit {
  /// Creates a hit at [path]:[line] with the offending [text].
  const PlainLanguageHit(this.path, this.line, this.text);

  /// The file the hit was found in.
  final String path;

  /// The 1-based line number of the hit.
  final int line;

  /// The trimmed source text of the offending line.
  final String text;

  @override
  String toString() => '$path:$line: $text';
}

final _enumName = RegExp(
  r'\b\w*(?:[sS]tatus|[sS]tate|[rR]eason|[cC]ode|[pP]ass|[fF]ir|[sS]ource)'
  r'\??\.name\b',
);

final _keyCall = RegExp(r'\b(?:Value|PageStorage)?Key\s*(?:<[^>]*>)?\s*\(');

const _literal =
    r"'(?:[^'\\\n]|\\.)*'"
    r'|"(?:[^"\\\n]|\\.)*"';

final _debugLabel = RegExp('debugLabel:\\s*(?:$_literal)');

final _literalRun = RegExp('(?:$_literal)(?:\\s*(?:$_literal))*');

final _singleLiteral = RegExp(_literal);

final _bannedStem = RegExp(
  r'canonical|identit|durabl|dpapi|authori[sz]|authority|normali[sz]|gross rub|'
  r'session-only',
  caseSensitive: false,
);

final _m1 = RegExp(r'(?<![A-Za-z0-9_])M1(?![A-Za-z0-9_])');

/// Finds raw status, reason, code, pass, FIR and source `.name` reads.
///
/// Comment lines and the arguments of `Key(`, `ValueKey(` and
/// `PageStorageKey(` are ignored, so `item.name` and keys built from
/// `mode.name` do not count.
List<PlainLanguageHit> findEnumNameHits(String path, String source) {
  final code = _maskKeyArguments(_blankComments(source));
  return _hitsPerLine(path, source, code, (line) => _enumName.hasMatch(line));
}

/// Finds banned internal terms inside string literals.
///
/// Adjacent literals on a line are joined before matching. Comment lines,
/// literals passed to `Key(`, `ValueKey(` and `PageStorageKey(`, and
/// `debugLabel:` literals are ignored. `M1` matches as a whole word only.
List<PlainLanguageHit> findBannedTermHits(String path, String source) {
  var code = _maskKeyArguments(_blankComments(source));
  code = _mask(code, _debugLabel.allMatches(code).toList());
  return _hitsPerLine(path, source, code, (line) {
    for (final run in _literalRun.allMatches(line)) {
      final joined = _singleLiteral
          .allMatches(run[0]!)
          .map((m) => m[0]!.substring(1, m[0]!.length - 1))
          .join();
      if (_bannedStem.hasMatch(joined) || _m1.hasMatch(joined)) return true;
    }
    return false;
  });
}

List<PlainLanguageHit> _hitsPerLine(
  String path,
  String original,
  String masked,
  bool Function(String line) isHit,
) {
  final originalLines = original.split('\n');
  final maskedLines = masked.split('\n');
  return [
    for (var i = 0; i < maskedLines.length; i++)
      if (isHit(maskedLines[i]))
        PlainLanguageHit(path, i + 1, originalLines[i].trim()),
  ];
}

/// Replaces whole comment lines with empty lines, keeping line numbers.
String _blankComments(String source) => source
    .split('\n')
    .map((line) => line.trimLeft().startsWith('//') ? '' : line)
    .join('\n');

/// Blanks the arguments of every key constructor call, keeping newlines.
String _maskKeyArguments(String code) {
  final spans = <(int, int)>[];
  var from = 0;
  while (true) {
    final match = _keyCall.matchAsPrefix(code, from) ?? _nextKey(code, from);
    if (match == null) break;
    var depth = 1;
    var i = match.end;
    while (i < code.length && depth > 0) {
      final c = code[i];
      if (c == '(') depth++;
      if (c == ')') depth--;
      i++;
    }
    spans.add((match.end, i));
    from = i;
  }
  return _maskSpans(code, spans);
}

Match? _nextKey(String code, int from) =>
    _keyCall.allMatches(code, from).firstOrNull;

String _mask(String code, List<Match> matches) =>
    _maskSpans(code, [for (final m in matches) (m.start, m.end)]);

String _maskSpans(String code, List<(int, int)> spans) {
  if (spans.isEmpty) return code;
  final out = StringBuffer();
  var last = 0;
  for (final (start, end) in spans) {
    out.write(code.substring(last, start));
    out.write(code.substring(start, end).replaceAll(RegExp(r'[^\n]'), ' '));
    last = end;
  }
  out.write(code.substring(last));
  return out.toString();
}

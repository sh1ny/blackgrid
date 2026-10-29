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

final _keyCall = RegExp(r'(?:Value|PageStorage)?Key\s*(?:<[^>]*>)?\s*\(');

final _debugLabel = RegExp(r'debugLabel:\s*');

final _bannedStem = RegExp(
  r'canonical|identit|durabl|dpapi|authori[sz]|authority|normali[sz]|gross rub|'
  r'session-only',
  caseSensitive: false,
);

final _m1 = RegExp(r'(?<![A-Za-z0-9_])M1(?![A-Za-z0-9_])');

final _identStart = RegExp(r'[A-Za-z_]');
final _identChar = RegExp(r'[A-Za-z0-9_]');

/// Finds raw status, reason, code, pass, FIR and source `.name` reads.
///
/// Comment lines and the arguments of `Key(`, `ValueKey(` and
/// `PageStorageKey(` are ignored, so `item.name` and keys built from
/// `mode.name` do not count.
List<PlainLanguageHit> findEnumNameHits(String path, String source) {
  final uncommented = _blankComments(source);
  final code = _maskSpans(uncommented, _keyArgumentSpans(uncommented));
  return _hitsAt(path, source, [
    for (final (i, line) in code.split('\n').indexed)
      if (_enumName.hasMatch(line)) i + 1,
  ]);
}

/// Finds banned internal terms inside string literals.
///
/// A quote- and brace-aware scanner reads the literals: single, double,
/// triple-quoted and raw strings. The code inside an interpolation (`${...}`
/// or `$name`) is removed before matching, while string literals nested in an
/// interpolation are matched on their own. Adjacent literals on a line are
/// joined before matching. Comments, literals passed to `Key(`, `ValueKey(`
/// and `PageStorageKey(`, and `debugLabel:` literals are ignored. `M1`
/// matches as a whole word only.
List<PlainLanguageHit> findBannedTermHits(String path, String source) {
  final code = _blankComments(source);
  final literals = <_Literal>[];
  _scan(code, literals);
  final lines = <int>{};
  _Literal? previous;
  final run = StringBuffer();
  var runLine = 0;
  void flush() {
    final text = run.toString();
    if (_bannedStem.hasMatch(text) || _m1.hasMatch(text)) lines.add(runLine);
    run.clear();
  }

  for (final lit in literals) {
    final joins =
        previous != null &&
        lit.topLevel &&
        previous.topLevel &&
        !code.substring(previous.end, lit.start).contains(RegExp(r'[^ \t]'));
    if (!joins) {
      flush();
      runLine = _lineOf(code, lit.start);
    }
    run.write(lit.text);
    previous = lit;
  }
  flush();
  return _hitsAt(path, source, lines.toList()..sort());
}

/// Keeps only the text of [source] that `legacy_import.dart` shows the player.
///
/// The import dialog shows the literals inside `ImportAccounting(` calls, the
/// `sourceReason` initializer and `FormatException(` messages. Everything else,
/// including the C# fork's input-format keys, is blanked with spaces, so line
/// numbers are kept. Pass the result to [findBannedTermHits].
String scopeLegacyImportSource(String source) {
  final code = _blankComments(source);
  final spans = <(int, int)>[
    for (final m in RegExp(
      r'\b(?:ImportAccounting|FormatException)\s*\(',
    ).allMatches(code))
      (m.start, _closingParen(code, m.end)),
    for (final m in RegExp(r'\bsourceReason\s*=').allMatches(code))
      (m.start, _statementEnd(code, m.end)),
  ];
  final keep = List<bool>.filled(code.length, false);
  for (final (start, end) in spans) {
    for (var i = start; i < end; i++) {
      keep[i] = true;
    }
  }
  final out = StringBuffer();
  for (var i = 0; i < code.length; i++) {
    out.write(keep[i] || code[i] == '\n' ? code[i] : ' ');
  }
  return out.toString();
}

/// One string literal found by the scanner.
final class _Literal {
  const _Literal(this.start, this.end, this.text, {required this.topLevel});

  final int start;
  final int end;

  /// The literal's text with interpolation code removed.
  final String text;

  /// Whether the literal sits outside any interpolation.
  final bool topLevel;
}

List<PlainLanguageHit> _hitsAt(String path, String original, List<int> lines) {
  final originalLines = original.split('\n');
  return [
    for (final line in lines)
      PlainLanguageHit(path, line, originalLines[line - 1].trim()),
  ];
}

int _lineOf(String code, int offset) {
  var line = 1;
  for (var i = 0; i < offset; i++) {
    if (code.codeUnitAt(i) == 0x0A) line++;
  }
  return line;
}

/// Replaces whole comment lines with empty lines, keeping line numbers.
String _blankComments(String source) => source
    .split('\n')
    .map((line) => line.trimLeft().startsWith('//') ? '' : line)
    .join('\n');

/// Walks [code], adding every literal to [sink].
///
/// Skips trailing comments, `Key(` arguments and `debugLabel:` literals.
void _scan(String code, List<_Literal> sink) {
  var i = 0;
  while (i < code.length) {
    final c = code[i];
    final key = _atWordStart(code, i) ? _keyCall.matchAsPrefix(code, i) : null;
    final label = _atWordStart(code, i)
        ? _debugLabel.matchAsPrefix(code, i)
        : null;
    if (c == '/' && code.startsWith('//', i)) {
      while (i < code.length && code[i] != '\n') {
        i++;
      }
    } else if (c == '/' && code.startsWith('/*', i)) {
      final end = code.indexOf('*/', i + 2);
      i = end < 0 ? code.length : end + 2;
    } else if (_isLiteralStart(code, i)) {
      i = _readLiteral(code, i, sink, topLevel: true);
    } else if (key != null) {
      i = _closingParen(code, key.end);
    } else if (label != null) {
      i = label.end;
      if (i < code.length && _isLiteralStart(code, i)) {
        i = _readLiteral(code, i, <_Literal>[], topLevel: true);
      }
    } else {
      i++;
    }
  }
}

bool _atWordStart(String code, int i) =>
    i == 0 || !_identChar.hasMatch(code[i - 1]);

bool _isLiteralStart(String code, int i) {
  final c = code[i];
  if (c == "'" || c == '"') return true;
  return c == 'r' &&
      i + 1 < code.length &&
      (code[i + 1] == "'" || code[i + 1] == '"') &&
      _atWordStart(code, i);
}

/// Reads the literal starting at [start] and returns the offset after it.
int _readLiteral(
  String code,
  int start,
  List<_Literal> sink, {
  required bool topLevel,
}) {
  var i = start;
  final raw = code[i] == 'r';
  if (raw) i++;
  final quote = code[i];
  final triple = code.startsWith(quote * 3, i);
  final delimiter = triple ? quote * 3 : quote;
  i += delimiter.length;
  final text = StringBuffer();
  while (i < code.length) {
    if (code.startsWith(delimiter, i)) {
      i += delimiter.length;
      break;
    }
    final c = code[i];
    final next = i + 1 < code.length ? code[i + 1] : '';
    if (!triple && c == '\n') break;
    if (!raw && c == r'\' && next.isNotEmpty) {
      text.write(next);
      i += 2;
    } else if (!raw && c == r'$' && next == '{') {
      i = _skipInterpolation(code, i + 2, sink);
    } else if (!raw && c == r'$' && _identStart.hasMatch(next)) {
      i += 2;
      while (i < code.length && _identChar.hasMatch(code[i])) {
        i++;
      }
    } else {
      text.write(c);
      i++;
    }
  }
  sink.add(_Literal(start, i, text.toString(), topLevel: topLevel));
  return i;
}

/// Skips an interpolation body after `${` and returns the offset after `}`.
///
/// Literals nested inside are added to [sink] as non-top-level literals.
int _skipInterpolation(String code, int from, List<_Literal> sink) {
  var depth = 1;
  var i = from;
  while (i < code.length && depth > 0) {
    if (_isLiteralStart(code, i)) {
      i = _readLiteral(code, i, sink, topLevel: false);
      continue;
    }
    final c = code[i];
    if (c == '{') depth++;
    if (c == '}') depth--;
    i++;
  }
  return i;
}

/// Returns the offset after the `)` closing a call whose `(` precedes [from].
int _closingParen(String code, int from) {
  var depth = 1;
  var i = from;
  while (i < code.length && depth > 0) {
    if (_isLiteralStart(code, i)) {
      i = _readLiteral(code, i, <_Literal>[], topLevel: true);
      continue;
    }
    final c = code[i];
    if (c == '(') depth++;
    if (c == ')') depth--;
    i++;
  }
  return i;
}

/// Returns the offset after the `;` that ends the statement at [from].
int _statementEnd(String code, int from) {
  var i = from;
  while (i < code.length) {
    if (_isLiteralStart(code, i)) {
      i = _readLiteral(code, i, <_Literal>[], topLevel: true);
      continue;
    }
    i++;
    if (code[i - 1] == ';') break;
  }
  return i;
}

/// Spans of the arguments of every key constructor call.
List<(int, int)> _keyArgumentSpans(String code) {
  final spans = <(int, int)>[];
  var from = 0;
  for (final m in _keyCall.allMatches(code)) {
    if (m.start < from || !_atWordStart(code, m.start)) continue;
    final end = _closingParen(code, m.end);
    spans.add((m.end, end));
    from = end;
  }
  return spans;
}

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

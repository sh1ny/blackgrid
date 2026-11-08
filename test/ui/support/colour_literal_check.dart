/// Source check that keeps colour literals out of the interface code.
library;

/// One colour literal, named by file and 1-based line number.
final class ColourLiteralHit {
  /// Creates a hit at [path]:[line] with the offending [text].
  const ColourLiteralHit(this.path, this.line, this.text);

  /// The file the hit was found in.
  final String path;

  /// The 1-based line number of the hit.
  final int line;

  /// The trimmed source text of the offending line.
  final String text;

  @override
  String toString() => '$path:$line: $text';
}

final _colourLiteral = RegExp(
  r'\bColor\s*\(|Color\.from(?:ARGB|RGBO)?\s*\(|\bColors\.(?!transparent\b)\w+',
);

/// Finds `Color(`, `Color.fromARGB(`, `Color.fromRGBO(`, `Color.from(` and
/// `Colors.name` uses (except `Colors.transparent`) in [source].
///
/// Comments are ignored, and so is text inside string literals. Line numbers
/// are those of [source].
List<ColourLiteralHit> findColourLiteralHits(String path, String source) {
  final code = _blankCommentsAndStrings(source).split('\n');
  final original = source.split('\n');
  return [
    for (final (i, line) in code.indexed)
      if (_colourLiteral.hasMatch(line))
        ColourLiteralHit(path, i + 1, original[i].trim()),
  ];
}

/// Replaces comments and string contents with spaces, keeping line breaks.
String _blankCommentsAndStrings(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    final c = source[i];
    final next = i + 1 < source.length ? source[i + 1] : '';
    if (c == '/' && next == '/') {
      while (i < source.length && source[i] != '\n') {
        out.write(' ');
        i++;
      }
    } else if (c == '/' && next == '*') {
      var depth = 0;
      while (i < source.length) {
        if (source.startsWith('/*', i)) {
          depth++;
          out.write('  ');
          i += 2;
        } else if (source.startsWith('*/', i)) {
          depth--;
          out.write('  ');
          i += 2;
          if (depth == 0) break;
        } else {
          out.write(source[i] == '\n' ? '\n' : ' ');
          i++;
        }
      }
    } else if (c == "'" || c == '"') {
      final raw = i > 0 && source[i - 1] == 'r';
      final triple = source.startsWith(c * 3, i);
      final quote = triple ? c * 3 : c;
      out.write(quote);
      i += quote.length;
      while (i < source.length && !source.startsWith(quote, i)) {
        if (!raw && source[i] == r'\' && i + 1 < source.length) {
          out.write('  ');
          i += 2;
        } else if (!triple && source[i] == '\n') {
          break;
        } else {
          out.write(source[i] == '\n' ? '\n' : ' ');
          i++;
        }
      }
      if (i < source.length && source.startsWith(quote, i)) {
        out.write(quote);
        i += quote.length;
      }
    } else {
      out.write(c);
      i++;
    }
  }
  return out.toString();
}

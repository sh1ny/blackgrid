enum RaidPanelState {
  missing,
  unreadable,
  partial,
  recognized,
  empty,
  ambiguous,
  unavailable,
  error,
}

/// Original saved-image pixel coordinates; right and bottom are exclusive.
final class RaidPanelBox {
  const RaidPanelBox(this.left, this.top, this.right, this.bottom);
  final int left;
  final int top;
  final int right;
  final int bottom;
  int get width => right - left;
  int get height => bottom - top;
  bool contains(RaidPanelBox other) =>
      other.left >= left &&
      other.top >= top &&
      other.right <= right &&
      other.bottom <= bottom;
}

final class RaidPanelEvidence {
  RaidPanelEvidence({
    required this.state,
    List<String> extractNames = const [],
    List<String> transitNames = const [],
    this.rawText = '',
    this.message,
    this.panel,
  }) : extractNames = List.unmodifiable(extractNames),
       transitNames = List.unmodifiable(transitNames);
  final RaidPanelState state;
  final List<String> extractNames;
  final List<String> transitNames;

  /// Merged engine text; the matcher also finds known names directly in it.
  final String rawText;
  final String? message;
  final RaidPanelBox? panel;
}

/// Screenshot-resolution tuning shared with the reference companion.
final class RaidPanelProfile {
  const RaidPanelProfile({
    required this.name,
    required this.panelWidthRatio,
    required this.panelHeightRatio,
    required this.headerHeightRatio,
    required this.headerScanStartRatio,
    required this.greenHitThreshold,
    required this.ocrScaleFactor,
  });

  factory RaidPanelProfile.forSize(int width, int height) {
    final aspect = height > 0 ? width / height : 16 / 9;
    if (aspect >= 2.15) {
      return RaidPanelProfile(
        name: 'Ultrawide',
        panelWidthRatio: 0.36,
        panelHeightRatio: 0.58,
        headerHeightRatio: 0.075,
        headerScanStartRatio: 0.58,
        greenHitThreshold: 0.10,
        ocrScaleFactor: _max(1.35, _ocrScale(height, 1440, 2.4)),
      );
    }
    if (height >= 2160) {
      return const RaidPanelProfile(
        name: '4K',
        panelWidthRatio: 0.52,
        panelHeightRatio: 0.56,
        headerHeightRatio: 0.065,
        headerScanStartRatio: 0.50,
        greenHitThreshold: 0.12,
        ocrScaleFactor: 1.0,
      );
    }
    if (height >= 1440) {
      return const RaidPanelProfile(
        name: '1440p',
        panelWidthRatio: 0.52,
        panelHeightRatio: 0.58,
        headerHeightRatio: 0.07,
        headerScanStartRatio: 0.50,
        greenHitThreshold: 0.12,
        ocrScaleFactor: 1.15,
      );
    }
    return RaidPanelProfile(
      name: '1080p',
      panelWidthRatio: 0.52,
      panelHeightRatio: 0.58,
      headerHeightRatio: 0.08,
      headerScanStartRatio: 0.48,
      greenHitThreshold: 0.12,
      ocrScaleFactor: _ocrScale(height, 1440, 2.5),
    );
  }

  final String name;
  final double panelWidthRatio;
  final double panelHeightRatio;
  final double headerHeightRatio;
  final double headerScanStartRatio;
  final double greenHitThreshold;
  final double ocrScaleFactor;

  static double _max(double a, double b) => a > b ? a : b;
  static double _ocrScale(int height, int reference, double maximum) {
    if (height <= 0 || height >= reference) return 1.0;
    final scale = reference / height;
    return scale < maximum ? scale : maximum;
  }

  /// Green exfil header across the top of the right-hand panel area.
  bool detect(int width, int height, int Function(int x, int y) rgb) {
    final startX = (width * headerScanStartRatio).toInt();
    final headerBottom = _maxInt(24, (height * headerHeightRatio).toInt());
    final step = width >= 3000 ? 5 : 4;
    var hits = 0;
    var samples = 0;
    for (var y = 4; y < headerBottom && y < height; y += 2) {
      for (var x = startX; x < width - 4; x += step) {
        if (_headerGreen(rgb(x, y))) hits++;
        samples++;
      }
    }
    return samples > 0 && hits / samples >= greenHitThreshold;
  }

  /// Last row of panel text/background before a sustained blank run.
  int panelBottom(int width, int height, int Function(int x, int y) rgb) {
    final panelX = _maxInt(0, (width * (1.0 - panelWidthRatio)).toInt());
    final minHeight = _maxInt(1, (height * panelHeightRatio).toInt());
    final scanLimit = _minInt(height, (height * 0.72).toInt());
    var lastTextRow = _maxInt(24, (height * headerHeightRatio).toInt());
    var blankRows = 0;
    final step = _maxInt(2, (width - panelX) ~/ 80);
    for (var y = 0; y < scanLimit; y++) {
      var rowHasText = false;
      for (var x = panelX; x < width - 2; x += step) {
        final color = rgb(x, y);
        if (isLikelyRaidPanelText(color) ||
            _headerGreen(color) ||
            _panelBackground(color)) {
          rowHasText = true;
          break;
        }
      }
      if (rowHasText) {
        lastTextRow = y;
        blankRows = 0;
        continue;
      }
      blankRows++;
      if (blankRows >= 28 && y > minHeight) break;
    }
    return _minInt(height, _maxInt(minHeight, lastTextRow + 28));
  }

  /// Right-anchored top crop of the panel area down to [bottom].
  RaidPanelBox crop(int width, int height, int bottom) {
    final cropWidth = _minInt(
      width,
      _maxInt(1, (width * panelWidthRatio).toInt()),
    );
    final left = _maxInt(0, width - cropWidth);
    return RaidPanelBox(
      left,
      0,
      left + _minInt(cropWidth, width - left),
      _minInt(height, _maxInt(1, bottom)),
    );
  }
}

int _maxInt(int a, int b) => a > b ? a : b;
int _minInt(int a, int b) => a < b ? a : b;

bool _headerGreen(int color) {
  final r = (color >> 16) & 255, g = (color >> 8) & 255, b = color & 255;
  return g >= 150 && r <= 210 && b <= 170 && g >= r + 20 && g >= b + 10;
}

bool _panelBackground(int color) {
  final r = (color >> 16) & 255, g = (color >> 8) & 255, b = color & 255;
  final max = r > g ? (r > b ? r : b) : (g > b ? g : b);
  final min = r < g ? (r < b ? r : b) : (g < b ? g : b);
  return max <= 95 && max - min <= 35;
}

/// Light, green or red panel glyph colour (packed RGB).
bool isLikelyRaidPanelText(int color) {
  final r = (color >> 16) & 255, g = (color >> 8) & 255, b = color & 255;
  final max = r > g ? (r > b ? r : b) : (g > b ? g : b);
  final min = r < g ? (r < b ? r : b) : (g < b ? g : b);
  return (max >= 165 && max - min <= 90) ||
      (g >= 140 && g >= r + 25 && g >= b + 10) ||
      (r >= 145 && r >= g + 25 && r >= b + 20);
}

/// Combines engine text from two recognitions of the same panel.
String mergeRaidOcrText(String primary, String secondary) {
  if (primary.trim().isEmpty) return secondary;
  if (secondary.trim().isEmpty) return primary;
  final a = primary.toLowerCase(), b = secondary.toLowerCase();
  if (a.contains(b)) return primary;
  if (b.contains(a)) return secondary;
  return '$primary\n$secondary';
}

/// Case-insensitive ordered union of trimmed, nonempty lines.
List<String> mergeRaidOcrLines(
  Iterable<String> primary,
  Iterable<String> secondary,
) {
  final merged = <String>[];
  final seen = <String>{};
  for (final line in [...primary, ...secondary]) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || !seen.add(trimmed.toLowerCase())) continue;
    merged.add(trimmed);
  }
  return merged;
}

/// Extract and transit names read from panel text, before current-map matching.
final class RaidPanelNames {
  final extracts = <String>[];
  final transits = <String>[];
  int get count => extracts.length + transits.length;
}

const _exitTag = r'(?:EXFIL|EXI\s*T|EX1T|EXIT|EXFILO|EXITO)';
final _exfilLine = RegExp(
  r'(?:EXFIL|EXIT|EXI\s*T|EX1T|EXFILO|EXITO)\s*0?(\d{1,2})\s*(.+?)(?:\s+\d{1,2}:\d{2}(?::\d{2})?|\s+\?{1,2}:\?{1,2}:\?{1,2})?(?:\s*$|\s+(?:EXFIL|EXIT|TRANSIT))',
  caseSensitive: false,
);
final _transitLine = RegExp(
  r'TRANSIT\s*0?\d{1,2}\s*(.+?)(?:\s+\d{1,2}:\d{2}(?::\d{2})?|\s+\?{1,2}:\?{1,2}:\?{1,2})?(?:\s*$|\s+TRANSIT)',
  caseSensitive: false,
);
final _exfilInline = RegExp(
  '$_exitTag'
  r'\s*0?\d{1,2}\s*(.+?)(?=\s+'
  '$_exitTag'
  r'\s*0?\d|\s+TRANSIT\s*0?\d|$)',
  caseSensitive: false,
);
final _transitInline = RegExp(
  r'TRANSIT\s*0?\d{1,2}\s*(.+?)(?=\s+'
  '$_exitTag'
  r'\s*0?\d|\s+TRANSIT\s*0?\d|$)',
  caseSensitive: false,
);
final _numberedExtract = RegExp(r'^0?(\d{1,2})\s+([A-Za-z].+)$');
final _timerLine = RegExp(r'^\d{1,2}:\d{2}(:\d{2})?$');

/// Reads extract/transit names from the panel's OCR text and lines, accepting
/// the engine's known tag misreads. Current-map matching decides authority.
final class RaidPanelTextParser {
  const RaidPanelTextParser();

  void parse(String text, List<String> lines, RaidPanelNames names) {
    if (text.trim().isEmpty && lines.isEmpty) return;
    final normalizedText = _normalize(text);
    final candidates = lines.isNotEmpty
        ? lines.map(_normalize)
        : normalizedText.split(RegExp(r'[\r\n]+'));
    for (final line in candidates) {
      final trimmed = _clean(line.trim());
      if (trimmed.isEmpty || _ignored(trimmed)) continue;
      final exfil = _exfilLine.firstMatch(trimmed);
      if (exfil != null) {
        _add(names.extracts, _clean(exfil[2]!));
      } else {
        final numbered = _numberedExtract.firstMatch(trimmed);
        if (numbered != null && !_has(trimmed, 'TRANSIT')) {
          _add(names.extracts, _clean(numbered[2]!));
        }
      }
      final transit = _transitLine.firstMatch(trimmed);
      if (transit != null) _add(names.transits, _clean(transit[1]!));
    }
    for (final match in _exfilInline.allMatches(normalizedText)) {
      _add(names.extracts, _clean(match[1]!));
    }
    for (final match in _transitInline.allMatches(normalizedText)) {
      _add(names.transits, _clean(match[1]!));
    }
    _unlabeledExtracts(normalizedText, names);
    _transitSection(normalizedText, names);
  }

  static void _unlabeledExtracts(String text, RaidPanelNames names) {
    final transit = _indexOf(text, 'TRANSIT');
    final section = transit > 0 ? text.substring(0, transit) : text;
    for (final line in section.split(RegExp(r'[\r\n]+'))) {
      final trimmed = _clean(line.trim());
      if (trimmed.isEmpty || _ignored(trimmed)) continue;
      if (_exfilLine.hasMatch(trimmed) || _numberedExtract.hasMatch(trimmed)) {
        continue;
      }
      if (_has(trimmed, 'TRANSIT')) continue;
      if (trimmed.length >= 3 &&
          RegExp(r'^\p{L}', unicode: true).hasMatch(trimmed) &&
          !trimmed.toUpperCase().startsWith('EXFIL') &&
          !trimmed.toUpperCase().startsWith('EXIT')) {
        _add(names.extracts, trimmed);
      }
    }
  }

  static void _transitSection(String text, RaidPanelNames names) {
    final transit = _indexOf(text, 'TRANSIT');
    if (transit < 0) return;
    for (final line in text.substring(transit).split(RegExp(r'[\r\n]+'))) {
      final trimmed = _clean(line.trim());
      if (trimmed.isEmpty || _ignored(trimmed)) continue;
      if (_transitLine.hasMatch(trimmed)) continue;
      final lower = trimmed.toLowerCase();
      if (lower.startsWith('transit to ')) _add(names.transits, trimmed);
      if (lower.contains(' to ') && lower.contains('transit')) {
        _add(names.transits, trimmed);
      }
    }
  }

  static String _normalize(String text) {
    var result = text.replaceAll('’', "'").replaceAll('‘', "'");
    for (final (from, to) in const [
      ('EXI T', 'EXIT'),
      ('EX1T', 'EXIT'),
      ('EXI1', 'EXIT'),
      ('EX IT', 'EXIT'),
      ('EXFILO', 'EXFIL0'),
      ('EXITO', 'EXIT0'),
      ('TRANSI T', 'TRANSIT'),
      ('TRANSI1', 'TRANSIT'),
    ]) {
      result = result.replaceAll(
        RegExp(RegExp.escape(from), caseSensitive: false),
        to,
      );
    }
    return result;
  }

  static bool _ignored(String line) {
    final lower = line.toLowerCase();
    return _timerLine.hasMatch(line) ||
        lower.contains('extraction point') ||
        lower.contains('keycard required') ||
        lower.startsWith('find an') ||
        lower == 'transit' ||
        lower == 'exfil' ||
        lower == 'exit';
  }

  static String _clean(String value) {
    var cleaned = value
        .trim()
        .replaceAll(RegExp(r'^\*+|\*+$'), '')
        .replaceAll(RegExp(r'\s+\d{1,2}:\d{2}(?::\d{2})?.*$'), '')
        .replaceAll(RegExp(r'\s+\?{1,2}:\?{1,2}:\?{1,2}.*$'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ');
    const trim = ' -:.,*|';
    var start = 0, end = cleaned.length;
    while (start < end && trim.contains(cleaned[start])) {
      start++;
    }
    while (end > start && trim.contains(cleaned[end - 1])) {
      end--;
    }
    cleaned = cleaned.substring(start, end);
    return cleaned;
  }

  static bool _has(String text, String token) =>
      text.toUpperCase().contains(token);
  static int _indexOf(String text, String token) =>
      text.toUpperCase().indexOf(token);

  static void _add(List<String> names, String value) {
    if (value.trim().isEmpty) return;
    final lower = value.toLowerCase();
    if (names.any((existing) => existing.toLowerCase() == lower)) return;
    names.add(value);
  }
}

import 'raid_panel_text_parser.dart';

final class RaidExitIdentity {
  RaidExitIdentity({
    required this.id,
    required this.name,
    required this.transit,
    List<String> aliases = const [],
  }) : aliases = List.unmodifiable(aliases);
  final String id;
  final String name;
  final bool transit;
  final List<String> aliases;
}

final class RaidMatchResult {
  RaidMatchResult(this.state, Set<String> ids, this.message)
    : ids = Set.unmodifiable(ids);
  final RaidPanelState state;
  final Set<String> ids;
  final String? message;
}

/// Matches OCR names against the current prepared map's extracts and
/// transits, tolerating OCR noise the same way as the reference companion.
/// A row or raw-text fragment that fits several distinct exits equally well
/// authorizes none of them.
final class RaidExfilMatcher {
  RaidExfilMatcher(List<RaidExitIdentity> identities)
    : _extracts = _exits(identities, transit: false),
      _transits = _exits(identities, transit: true);
  final List<_Exit> _extracts;
  final List<_Exit> _transits;

  static const _similarityThreshold = 0.78;
  static const _wordOverlapThreshold = 0.72;

  RaidMatchResult match(RaidPanelEvidence evidence) {
    if (evidence.state != RaidPanelState.recognized) {
      return RaidMatchResult(evidence.state, {}, evidence.message);
    }
    final matched = <_Exit>{};
    for (final (ocrNames, exits) in [
      (evidence.extractNames, _extracts),
      (evidence.transitNames, _transits),
    ]) {
      for (final ocr in ocrNames) {
        final candidates = [
          for (final exit in exits)
            if (exit.names.any((name) => namesMatch(ocr, name))) exit,
        ];
        if (candidates.isEmpty) continue;
        final best = _bestFor(ocr, candidates);
        if (best == null) {
          return RaidMatchResult(
            RaidPanelState.ambiguous,
            {},
            'Exfil panel row "$ocr" matches more than one current-map exit.',
          );
        }
        matched.add(best);
      }
    }
    final raw = evidence.rawText;
    var rawConflict = false;
    if (raw.trim().isNotEmpty) {
      final transitIndex = raw.toUpperCase().indexOf('TRANSIT');
      final extractSection = transitIndex > 0
          ? raw.substring(0, transitIndex)
          : raw;
      final transitSection = transitIndex >= 0
          ? raw.substring(transitIndex)
          : raw;
      final full = _normalize(raw);
      final extractConflict = _supplementFromRaw(
        _extracts,
        _normalize(extractSection),
        full,
        matched,
      );
      final transitConflict = _supplementFromRaw(
        _transits,
        _normalize(transitSection),
        full,
        matched,
      );
      rawConflict = extractConflict || transitConflict;
    }
    final ids = {for (final exit in matched) ...exit.ids};
    if (ids.isEmpty) {
      return rawConflict
          ? RaidMatchResult(
              RaidPanelState.ambiguous,
              {},
              'Exfil panel text matches more than one current-map exit.',
            )
          : RaidMatchResult(
              RaidPanelState.unreadable,
              {},
              'Exfil panel found, but no current-map extract or transit matched.',
            );
    }
    return RaidMatchResult(RaidPanelState.recognized, ids, evidence.message);
  }

  static bool namesMatch(String ocrName, String dataName) {
    final ocr = _normalize(ocrName), data = _normalize(dataName);
    if (ocr.isEmpty || data.isEmpty) return false;
    if (ocr == data || ocr.contains(data) || data.contains(ocr)) return true;
    if (_wordOverlap(ocr, dataName) >= _wordOverlapThreshold ||
        _wordOverlap(data, ocrName) >= _wordOverlapThreshold) {
      return true;
    }
    return _similarity(ocr, data) >= _similarityThreshold;
  }

  /// Canonical exits keyed by normalized name, so spatial copies of one exit
  /// (several markers sharing its name) are authorized together.
  static List<_Exit> _exits(
    List<RaidExitIdentity> identities, {
    required bool transit,
  }) {
    final byName = <String, _Exit>{};
    for (final identity in identities) {
      if (identity.id.isEmpty || identity.transit != transit) continue;
      final key = _normalize(identity.name);
      final exit = byName.putIfAbsent(
        key.isEmpty ? '#${identity.id}' : key,
        () => _Exit(key),
      );
      exit.ids.add(identity.id);
      for (final name in [identity.name, ...identity.aliases]) {
        if (name.trim().isNotEmpty && !exit.names.contains(name)) {
          exit.names.add(name);
        }
      }
    }
    return List.unmodifiable(byName.values);
  }

  /// The single strongest exit for one parsed row, or null on a tie. An exact
  /// name beats a row containing a whole name, which beats a fuzzy match;
  /// within a tier the longest contained name or the most similar fuzzy name
  /// must be unique.
  static _Exit? _bestFor(String ocrName, List<_Exit> candidates) {
    final ocr = _normalize(ocrName);
    (int, double) score(_Exit exit) {
      var best = (0, 0.0);
      for (final name in exit.names) {
        final data = _normalize(name);
        if (data.isEmpty) continue;
        final (int, double) current = ocr == data
            ? (3, 0)
            : ocr.contains(data)
            ? (2, data.length.toDouble())
            : (1, _similarity(ocr, data));
        if (_compare(current, best) > 0) best = current;
      }
      return best;
    }

    _Exit? winner;
    var top = (-1, 0.0);
    var tied = false;
    for (final exit in candidates) {
      final current = score(exit);
      final order = _compare(current, top);
      if (order > 0) {
        winner = exit;
        top = current;
        tied = false;
      } else if (order == 0) {
        tied = true;
      }
    }
    return tied ? null : winner;
  }

  static int _compare((int, double) left, (int, double) right) {
    if (left.$1 != right.$1) return left.$1.compareTo(right.$1);
    final delta = left.$2 - right.$2;
    return delta.abs() <= 1e-9 ? 0 : delta.sign.toInt();
  }

  /// Adds exits whose names appear in raw engine text the row parser missed.
  /// A whole name in the text is direct evidence. A whole name inside a
  /// longer matched name, or a partial word/base-name hit with no evidence
  /// beyond matched names and other exits' hits, is dropped. Returns whether
  /// any hit was dropped.
  static bool _supplementFromRaw(
    List<_Exit> exits,
    String section,
    String full,
    Set<_Exit> matched,
  ) {
    final whole = <_Exit>{};
    final partial = <_Exit, Set<String>>{};
    for (final exit in exits) {
      if (matched.contains(exit)) continue;
      final evidence = <String>{};
      for (final name in exit.names) {
        final hit = _rawEvidence(name, section, full);
        if (hit == null) continue;
        if (hit.isEmpty) {
          whole.add(exit);
          break;
        }
        evidence.addAll(hit);
      }
      if (!whole.contains(exit) && evidence.isNotEmpty) {
        partial[exit] = evidence;
      }
    }
    final explained = [
      for (final exit in {...matched, ...whole})
        if (exit.key.isNotEmpty) exit.key,
    ];
    var dropped = false;
    final accepted = <_Exit>[];
    for (final exit in whole) {
      if (explained.any(
        (other) => other != exit.key && other.contains(exit.key),
      )) {
        dropped = true;
      } else {
        accepted.add(exit);
      }
    }
    for (final MapEntry(key: exit, value: tokens) in partial.entries) {
      final distinctive = tokens.any(
        (token) =>
            !explained.any((key) => key.contains(token)) &&
            !partial.entries.any(
              (other) => other.key != exit && other.value.contains(token),
            ),
      );
      if (!distinctive) {
        dropped = true;
      } else {
        accepted.add(exit);
      }
    }
    matched.addAll(accepted);
    return dropped;
  }

  /// Null when [dataName] is absent, empty when the whole name appears, and
  /// otherwise the partial words or base name that matched.
  static Set<String>? _rawEvidence(
    String dataName,
    String section,
    String full,
  ) {
    final data = _normalize(dataName);
    if (data.length < 4) return null;
    if (section.contains(data) || full.contains(data)) return const {};
    if (_wordOverlap(section, dataName) >= _wordOverlapThreshold ||
        _wordOverlap(full, dataName) >= _wordOverlapThreshold) {
      return {
        for (final word in _words(dataName))
          if (section.contains(word) || full.contains(word)) word,
      };
    }
    final paren = dataName.indexOf('(');
    for (final candidate in [
      if (paren > 0) dataName.substring(0, paren).trim(),
      dataName.replaceAll(RegExp(r'\([^)]*\)'), '').trim(),
    ]) {
      final normalized = _normalize(candidate);
      if (normalized.length >= 4 &&
          (section.contains(normalized) || full.contains(normalized))) {
        return {normalized};
      }
    }
    return null;
  }

  static List<String> _words(String name) => name
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((word) => word.length >= 3)
      .where((word) => !const {'the', 'and', 'for', 'from'}.contains(word))
      .toList();

  static double _wordOverlap(String normalizedText, String name) {
    final words = _words(name);
    if (words.isEmpty) return 0;
    final hits = words.where((word) => normalizedText.contains(word)).length;
    return hits / words.length;
  }

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static double _similarity(String left, String right) {
    final longest = left.length > right.length ? left.length : right.length;
    if (longest == 0) return 1;
    var previous = List<int>.generate(right.length + 1, (j) => j);
    for (var i = 1; i <= left.length; i++) {
      final current = List<int>.filled(right.length + 1, 0)..[0] = i;
      for (var j = 1; j <= right.length; j++) {
        final cost = left[i - 1] == right[j - 1] ? 0 : 1;
        final best = previous[j] + 1 < current[j - 1] + 1
            ? previous[j] + 1
            : current[j - 1] + 1;
        current[j] = best < previous[j - 1] + cost
            ? best
            : previous[j - 1] + cost;
      }
      previous = current;
    }
    return 1 - previous[right.length] / longest;
  }
}

final class _Exit {
  _Exit(this.key);
  final String key;
  final Set<String> ids = {};
  final List<String> names = [];
}

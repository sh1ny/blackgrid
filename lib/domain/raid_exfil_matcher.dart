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
final class RaidExfilMatcher {
  RaidExfilMatcher(List<RaidExitIdentity> identities)
    : _identities = List.unmodifiable(
        identities.where((identity) => identity.id.isNotEmpty),
      );
  final List<RaidExitIdentity> _identities;

  static const _similarityThreshold = 0.78;
  static const _wordOverlapThreshold = 0.72;

  RaidMatchResult match(RaidPanelEvidence evidence) {
    if (evidence.state != RaidPanelState.recognized) {
      return RaidMatchResult(evidence.state, {}, evidence.message);
    }
    final ids = <String>{};
    final raw = evidence.rawText;
    final upper = raw.toUpperCase();
    final transitIndex = upper.indexOf('TRANSIT');
    final extractSection = transitIndex > 0
        ? raw.substring(0, transitIndex)
        : raw;
    final transitSection = transitIndex >= 0
        ? raw.substring(transitIndex)
        : raw;
    for (final identity in _identities) {
      final names = [
        identity.name,
        ...identity.aliases,
      ].where((name) => name.trim().isNotEmpty).toList();
      final ocrNames = identity.transit
          ? evidence.transitNames
          : evidence.extractNames;
      final matched =
          ocrNames.any((ocr) => names.any((name) => namesMatch(ocr, name))) ||
          (raw.trim().isNotEmpty &&
              names.any(
                (name) => _appearsIn(
                  name,
                  _normalize(
                    identity.transit ? transitSection : extractSection,
                  ),
                  _normalize(raw),
                ),
              ));
      if (matched) ids.add(identity.id);
    }
    if (ids.isEmpty) {
      return RaidMatchResult(
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

  static bool _appearsIn(String dataName, String section, String full) {
    final data = _normalize(dataName);
    if (data.length < 4) return false;
    if (section.contains(data) || full.contains(data)) return true;
    if (_wordOverlap(section, dataName) >= _wordOverlapThreshold ||
        _wordOverlap(full, dataName) >= _wordOverlapThreshold) {
      return true;
    }
    final paren = dataName.indexOf('(');
    for (final candidate in [
      if (paren > 0) dataName.substring(0, paren).trim(),
      dataName.replaceAll(RegExp(r'\([^)]*\)'), '').trim(),
    ]) {
      final normalized = _normalize(candidate);
      if (normalized.length >= 4 &&
          (section.contains(normalized) || full.contains(normalized))) {
        return true;
      }
    }
    return false;
  }

  static double _wordOverlap(String normalizedText, String name) {
    final words = name
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((word) => word.length >= 3)
        .where((word) => !const {'the', 'and', 'for', 'from'}.contains(word))
        .toList();
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

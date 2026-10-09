/// Turns recognised inspection title text into a mode-scoped catalog identity
/// or a typed rejection.
///
/// Everything here is pure, synchronous and free of `dart:ffi` and Flutter,
/// so a [TitleMatchIndex] can be built and queried inside `Isolate.run`.
/// Similarities, margins and gate constants are evaluated in IEEE single
/// precision, which reproduces the reference companion's boundary behaviour.
library;

import 'dart:collection';
import 'dart:typed_data';

import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'catalog.dart';

/// Thresholds of the recognition pipeline, stored as single-precision values.
///
/// The decimal values named on each field are what the reference uses; the
/// stored doubles are those decimals rounded to `float32`.
final class RecognitionGates {
  /// Creates the one gate set; use [recognitionGates].
  const RecognitionGates();

  /// Minimum marker correlation (.82).
  final double markerScore = 0.8199999928474426;

  /// Minimum best-candidate similarity, and minimum confirming confidence
  /// (.55).
  final double similarity = 0.550000011920929;

  /// Minimum normalised title length (3).
  final int minTitleLength = 3;

  /// Margin at which the best candidate stands alone (.05).
  final double margin = 0.05000000074505806;

  /// Margin below which a quantity must also agree (.03).
  final double closeMargin = 0.029999999329447746;

  /// Similarity to a UI-chrome label at which the confirming matcher gives
  /// up (.85).
  final double chromeSimilarity = 0.8500000238418579;

  /// Smallest title quantity that counts as evidence (10).
  final int minQuantity = 10;

  /// Value after which further quantity digits are ignored (100000).
  final int quantityCap = 100000;
}

/// The gate set used by the matcher.
const recognitionGates = RecognitionGates();

/// Why a title was not accepted.
enum TitleRejectReason {
  /// The index holds no items.
  emptyCatalog,

  /// The normalised title is shorter than the minimum length.
  titleTooShort,

  /// The title is a localised search-box label, not an item name.
  uiChrome,

  /// The best similarity is under the similarity gate.
  belowSimilarity,

  /// The best candidate is not clearly better than the runner-up.
  ambiguous,

  /// The index was built for a different game mode than the caller's.
  catalogModeMismatch,
}

/// The confirming matcher's pick for a title.
final class TitleConfirmation {
  /// Creates a confirmation of [id] with [confidence].
  const TitleConfirmation(this.id, this.confidence);

  /// Catalog ID of the picked item.
  final String id;

  /// Single-precision similarity of the title to the item's raw name.
  final double confidence;

  @override
  String toString() => 'TitleConfirmation($id, $confidence)';
}

/// The result of matching one title; either [TitleAccepted] or
/// [TitleRejected].
sealed class TitleMatch {
  const TitleMatch({
    required this.normalisedTitle,
    required this.bestId,
    required this.bestScore,
    required this.runnerUpId,
    required this.runnerUpScore,
    required this.margin,
    required this.confirmedBy,
    required this.mode,
    required this.revision,
  });

  /// The title after [normaliseTitle].
  final String normalisedTitle;

  /// ID of the best candidate, or null when nothing was scored.
  final String? bestId;

  /// Single-precision similarity of the best candidate (0 when none).
  final double bestScore;

  /// ID of the runner-up, or null when there was none.
  final String? runnerUpId;

  /// Single-precision similarity of the runner-up (0 when none).
  final double runnerUpScore;

  /// Single-precision difference between [bestScore] and [runnerUpScore].
  final double margin;

  /// The confirming matcher's pick, if it picked one.
  final TitleConfirmation? confirmedBy;

  /// Game mode of the index that produced this result.
  final GameMode mode;

  /// Catalog revision of the index that produced this result.
  final String revision;
}

/// A title accepted as catalog item [bestId].
final class TitleAccepted extends TitleMatch {
  /// Creates an acceptance of [bestId].
  const TitleAccepted({
    required String super.bestId,
    required super.normalisedTitle,
    required super.bestScore,
    required super.runnerUpId,
    required super.runnerUpScore,
    required super.margin,
    required super.confirmedBy,
    required super.mode,
    required super.revision,
  });
}

/// A title that was not accepted, with the [reason].
final class TitleRejected extends TitleMatch {
  /// Creates a rejection for [reason].
  const TitleRejected({
    required this.reason,
    required super.normalisedTitle,
    super.bestId,
    super.bestScore = 0,
    super.runnerUpId,
    super.runnerUpScore = 0,
    super.margin = 0,
    super.confirmedBy,
    required super.mode,
    required super.revision,
  });

  /// Why the title was rejected.
  final TitleRejectReason reason;
}

final _f32 = Float32List(1);

double _single(double x) {
  _f32[0] = x;
  return _f32[0];
}

final _keptCharacter = RegExp(r'[\p{L}\p{Nd}\p{Nl}]', unicode: true);

/// Normalises [text] for comparison: NFKC, lower case, then every run of
/// characters other than letters and digits becomes one space, with leading
/// and trailing separators dropped.
String normaliseTitle(String text) {
  final folded = unorm.nfkc(text).toLowerCase();
  final out = StringBuffer();
  var pendingSpace = false;
  for (final rune in folded.runes) {
    final ch = String.fromCharCode(rune);
    if (_keptCharacter.hasMatch(ch)) {
      if (pendingSpace && out.isNotEmpty) out.write(' ');
      pendingSpace = false;
      out.write(ch);
    } else {
      pendingSpace = true;
    }
  }
  return out.toString();
}

/// Cyrillic capitals that read as Latin capitals in the game font.
///
/// The design lists `АВЕЅZІКМНОРСТХ`; Cyrillic has no Z look-alike, so `Z` is
/// taken as Latin and needs no mapping.
const _cyrillicToLatin = <int, String>{
  0x0410: 'A',
  0x0412: 'B',
  0x0415: 'E',
  0x0405: 'S',
  0x0406: 'I',
  0x041A: 'K',
  0x041C: 'M',
  0x041D: 'H',
  0x041E: 'O',
  0x0420: 'P',
  0x0421: 'C',
  0x0422: 'T',
  0x0425: 'X',
};

String _mapCyrillic(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    out.write(_cyrillicToLatin[rune] ?? String.fromCharCode(rune));
  }
  return out.toString();
}

const _chromeLabels = [
  'subject search',
  'поиск предмета',
  'rechercher un objet',
  'buscar objeto',
  'procurar item',
  'cerca oggetto',
  'szukaj przedmiotu',
  '搜索物品',
  '아이템 검색',
  'アイテム検索',
];

final _normalisedChrome = HashSet<String>.of(_chromeLabels.map(normaliseTitle));
final _chromeRunes = [
  for (final label in _chromeLabels) Int32List.fromList(label.runes.toList()),
];

/// The last number in [text] as the matcher reads it, or null without digits.
///
/// Digits stop being appended once the value passes
/// [RecognitionGates.quantityCap].
int? _lastNumber(String text, {bool ocrConfusions = false}) {
  final runes = text.runes.toList();
  bool isDigit(int r) => r >= 0x30 && r <= 0x39;
  bool alnum(int r) =>
      isDigit(r) ||
      (r >= 0x61 && r <= 0x7a) ||
      (r >= 0x41 && r <= 0x5a) ||
      (r > 0x7f && _keptCharacter.hasMatch(String.fromCharCode(r)));
  int? last;
  int? current;
  for (var i = 0; i < runes.length; i++) {
    var r = runes[i];
    if (ocrConfusions) {
      if (r == 0x40) {
        r = 0x30;
      } else if (r == 0x69 || r == 0x6c) {
        final startsToken = i == 0 || !alnum(runes[i - 1]);
        final next = i + 1 < runes.length ? runes[i + 1] : -1;
        if (startsToken && (isDigit(next) || next == 0x40)) r = 0x31;
      }
    }
    if (isDigit(r)) {
      final v = current ?? 0;
      current = v <= recognitionGates.quantityCap ? v * 10 + (r - 0x30) : v;
      last = current;
    } else {
      current = null;
    }
  }
  return last;
}

/// Reads the quantity a title states, or null when it has no digits.
///
/// The title's last run of digits is the quantity. OCR confusions are read
/// first: `@` is 0, and an `i` or `l` at the start or after a
/// non-alphanumeric character, followed by a digit or `@`, is 1. So
/// `5.56x45 (i2@ pcs)` has quantity 120.
int? parseTitleQuantity(String text) =>
    _lastNumber(text.toLowerCase(), ocrConfusions: true);

double _ratio(int distance, int longer) =>
    longer == 0 ? 1.0 : 1 - distance / longer;

/// Plain dynamic-programming Levenshtein distance, the fallback when the
/// pattern exceeds one machine word.
int _distanceDp(Int32List a, Int32List b) {
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = Int32List(b.length + 1);
  var cur = Int32List(b.length + 1);
  for (var j = 0; j <= b.length; j++) {
    prev[j] = j;
  }
  for (var i = 1; i <= a.length; i++) {
    cur[0] = i;
    final ai = a[i - 1];
    for (var j = 1; j <= b.length; j++) {
      var v = prev[j - 1] + (ai == b[j - 1] ? 0 : 1);
      final del = prev[j] + 1;
      if (del < v) v = del;
      final ins = cur[j - 1] + 1;
      if (ins < v) v = ins;
      cur[j] = v;
    }
    final t = prev;
    prev = cur;
    cur = t;
  }
  return prev[b.length];
}

/// Levenshtein distance from one fixed pattern to many texts.
///
/// Patterns of up to 64 runes use the bit-parallel algorithm (Myers, in
/// Hyyrö's form), which costs one step per text rune; longer patterns fall
/// back to [_distanceDp].
final class _Distance {
  _Distance(this.pattern) {
    final m = pattern.length;
    if (m == 0 || m > 64) return;
    _masks = Int64List(128);
    for (var i = 0; i < m; i++) {
      final r = pattern[i];
      if (r < 128) {
        _masks[r] |= 1 << i;
      } else {
        _wide[r] = (_wide[r] ?? 0) | (1 << i);
      }
    }
  }

  final Int32List pattern;
  Int64List _masks = Int64List(0);
  final _wide = <int, int>{};

  int to(Int32List text) {
    final m = pattern.length;
    if (m == 0) return text.length;
    if (m > 64) return _distanceDp(pattern, text);
    var pv = -1;
    var mv = 0;
    var score = m;
    final high = 1 << (m - 1);
    for (var j = 0; j < text.length; j++) {
      final c = text[j];
      final eq = c < 128 ? _masks[c] : (_wide[c] ?? 0);
      final xv = eq | mv;
      final xh = (((eq & pv) + pv) ^ pv) | eq;
      var ph = mv | ~(xh | pv);
      var mh = pv & xh;
      if (ph & high != 0) {
        score++;
      } else if (mh & high != 0) {
        score--;
      }
      ph = (ph << 1) | 1;
      mh = mh << 1;
      pv = mh | ~(xv | ph);
      mv = ph & xv;
    }
    return score;
  }
}

Int32List _runes(String s) => Int32List.fromList(s.runes.toList());

Int32List _withoutSpaces(Int32List s) => Int32List.fromList([
  for (final r in s)
    if (r != 0x20) r,
]);

/// Scores many candidates against one title.
final class _Scorer {
  _Scorer(String title)
    : _title = _runes(title),
      _titleCompact = _withoutSpaces(_runes(title)) {
    _plain = _Distance(_title);
    _compact = _titleCompact.length == _title.length
        ? _plain
        : _Distance(_titleCompact);
  }

  final Int32List _title, _titleCompact;
  late final _Distance _plain, _compact;

  /// Plain similarity only (the confirming matcher's measure).
  double plain(Int32List text) {
    final longer = _title.length > text.length ? _title.length : text.length;
    return _single(_ratio(_plain.to(text), longer));
  }

  /// The better of plain and compact similarity.
  double better(Int32List text, Int32List textCompact) {
    final longer = _title.length > text.length ? _title.length : text.length;
    var best = _ratio(_plain.to(text), longer);
    if (textCompact.length != text.length ||
        _titleCompact.length != _title.length) {
      final compactLonger = _titleCompact.length > textCompact.length
          ? _titleCompact.length
          : textCompact.length;
      final compact = _ratio(_compact.to(textCompact), compactLonger);
      if (compact > best) best = compact;
    }
    return _single(best);
  }
}

/// Similarity of two normalised strings: the better of 1 − Levenshtein ÷
/// longer length and the same measure with spaces removed from both. Two
/// empty strings score 1. The result is rounded to single precision.
double titleSimilarity(String a, String b) {
  final text = _runes(b);
  return _Scorer(a).better(text, _withoutSpaces(text));
}

/// The single-precision difference between [bestScore] and [runnerUpScore],
/// each rounded to single precision first.
double singleMargin(double bestScore, double runnerUpScore) =>
    _single(_single(bestScore) - _single(runnerUpScore));

/// Applies the acceptance gates; returns null when the best candidate is
/// accepted, otherwise the reason it is not.
///
/// [confirmationConfidence] is the confirming matcher's confidence when it
/// picked the same item as the best candidate, and null when it picked
/// another item or none. [quantityAgrees] says the title quantity is at
/// least [RecognitionGates.minQuantity] and equals the last number in the
/// best candidate's raw name.
TitleRejectReason? gateRejection({
  required double bestScore,
  required double margin,
  required double? confirmationConfidence,
  required bool quantityAgrees,
}) {
  const gates = recognitionGates;
  if (_single(bestScore) < gates.similarity) {
    return TitleRejectReason.belowSimilarity;
  }
  final m = _single(margin);
  if (m >= gates.margin) return null;
  final confidence = confirmationConfidence == null
      ? null
      : _single(confirmationConfidence);
  if (confidence == null || confidence < gates.similarity) {
    return TitleRejectReason.ambiguous;
  }
  if (m < gates.closeMargin && !quantityAgrees) {
    return TitleRejectReason.ambiguous;
  }
  return null;
}

/// An immutable, sendable match index built from one catalog snapshot.
///
/// It holds plain data only, so it can be copied into `Isolate.run`.
final class TitleMatchIndex {
  TitleMatchIndex._(
    this.mode,
    this.revision,
    this._ids,
    this._names,
    this._nameRunes,
    this._nameCompact,
    this._rawRunes,
    this._lastNumbers,
  );

  /// Builds the index for [snapshot], items in ID order.
  ///
  /// A candidate name is the normalised `normalizedName` (kebab-case becomes
  /// spaces), or the normalised name when that is blank.
  factory TitleMatchIndex.build(CatalogSnapshot snapshot) {
    final items = snapshot.items.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final ids = <String>[];
    final names = <String>[];
    final nameRunes = <Int32List>[];
    final nameCompact = <Int32List>[];
    final rawRunes = <Int32List>[];
    final lastNumbers = Int32List(items.length);
    for (final item in items) {
      var candidate = normaliseTitle(item.normalizedName);
      if (candidate.isEmpty) candidate = normaliseTitle(item.name);
      final runes = _runes(candidate);
      ids.add(item.id);
      names.add(candidate);
      nameRunes.add(runes);
      nameCompact.add(_withoutSpaces(runes));
      rawRunes.add(_runes(_mapCyrillic(item.name).toLowerCase()));
      lastNumbers[ids.length - 1] = _lastNumber(item.name) ?? -1;
    }
    return TitleMatchIndex._(
      snapshot.mode,
      snapshot.revision,
      ids,
      names,
      nameRunes,
      nameCompact,
      rawRunes,
      lastNumbers,
    );
  }

  /// Game mode of the source snapshot.
  final GameMode mode;

  /// Revision of the source snapshot.
  final String revision;

  final List<String> _ids;
  final List<String> _names;
  final List<Int32List> _nameRunes;
  final List<Int32List> _nameCompact;
  final List<Int32List> _rawRunes;
  final Int32List _lastNumbers;

  /// Number of indexed items.
  int get length => _ids.length;

  /// Whether the index holds no items.
  bool get isEmpty => _ids.isEmpty;
}

/// The confirming matcher: compares the trimmed, lower-cased [ocrText] with
/// each item's lower-cased raw name by normalised Levenshtein, the first item
/// in ID order winning ties.
///
/// Returns null when the best confidence is under the similarity gate, and
/// when the title is within the chrome similarity of a UI-chrome label.
/// Confusable Cyrillic capitals are read as Latin first.
TitleConfirmation? confirmTitle(TitleMatchIndex index, String ocrText) {
  final title = _runes(_mapCyrillic(ocrText.trim()).toLowerCase());
  final scorer = _Scorer(String.fromCharCodes(title));
  for (final chrome in _chromeRunes) {
    if (scorer.plain(chrome) >= recognitionGates.chromeSimilarity) return null;
  }
  var bestIndex = -1;
  var best = -1.0;
  for (var i = 0; i < index._rawRunes.length; i++) {
    final s = scorer.plain(index._rawRunes[i]);
    if (s > best) {
      best = s;
      bestIndex = i;
    }
  }
  if (bestIndex < 0 || best < recognitionGates.similarity) return null;
  return TitleConfirmation(index._ids[bestIndex], best);
}

/// Matches [ocrText] against [index] for a caller in [mode].
///
/// Checks run in this order: mode mismatch, empty catalog, title too short,
/// UI chrome, then scoring. Every result carries the normalised title, the
/// best and runner-up IDs and scores, the margin, the confirming matcher's
/// pick, and the index's mode and revision.
TitleMatch matchTitle(TitleMatchIndex index, String ocrText, GameMode mode) {
  final title = normaliseTitle(ocrText);
  TitleRejected reject(
    TitleRejectReason reason, {
    String? bestId,
    double bestScore = 0,
    String? runnerUpId,
    double runnerUpScore = 0,
    double margin = 0,
    TitleConfirmation? confirmedBy,
  }) => TitleRejected(
    reason: reason,
    normalisedTitle: title,
    bestId: bestId,
    bestScore: bestScore,
    runnerUpId: runnerUpId,
    runnerUpScore: runnerUpScore,
    margin: margin,
    confirmedBy: confirmedBy,
    mode: index.mode,
    revision: index.revision,
  );

  if (mode != index.mode) return reject(TitleRejectReason.catalogModeMismatch);
  if (index.isEmpty) return reject(TitleRejectReason.emptyCatalog);
  if (title.runes.length < recognitionGates.minTitleLength) {
    return reject(TitleRejectReason.titleTooShort);
  }
  if (_normalisedChrome.contains(title)) {
    return reject(TitleRejectReason.uiChrome);
  }

  final scorer = _Scorer(title);
  final count = index.length;
  final scores = Float64List(count);
  for (var i = 0; i < count; i++) {
    scores[i] = scorer.better(index._nameRunes[i], index._nameCompact[i]);
  }

  final quantity = parseTitleQuantity(ocrText);
  final wantsQuantity =
      quantity != null && quantity >= recognitionGates.minQuantity;
  var restrict = false;
  if (wantsQuantity) {
    for (var i = 0; i < count; i++) {
      if (index._lastNumbers[i] == quantity &&
          scores[i] >= recognitionGates.similarity) {
        restrict = true;
        break;
      }
    }
  }

  var best = -1;
  var runner = -1;
  for (var i = 0; i < count; i++) {
    if (restrict && index._lastNumbers[i] != quantity) continue;
    if (best < 0) {
      best = i;
    } else if (index._names[i] == index._names[best]) {
      continue;
    } else if (scores[i] > scores[best]) {
      runner = best;
      best = i;
    } else if (runner < 0 || scores[i] > scores[runner]) {
      runner = i;
    }
  }

  final bestScore = scores[best];
  final runnerScore = runner < 0 ? 0.0 : scores[runner];
  final margin = singleMargin(bestScore, runnerScore);
  final confirmation = confirmTitle(index, ocrText);
  final confirmsBest =
      confirmation != null && confirmation.id == index._ids[best];
  final reason = gateRejection(
    bestScore: bestScore,
    margin: margin,
    confirmationConfidence: confirmsBest ? confirmation.confidence : null,
    quantityAgrees: wantsQuantity && index._lastNumbers[best] == quantity,
  );
  final runnerId = runner < 0 ? null : index._ids[runner];
  if (reason != null) {
    return reject(
      reason,
      bestId: index._ids[best],
      bestScore: bestScore,
      runnerUpId: runnerId,
      runnerUpScore: runnerScore,
      margin: margin,
      confirmedBy: confirmation,
    );
  }
  return TitleAccepted(
    bestId: index._ids[best],
    normalisedTitle: title,
    bestScore: bestScore,
    runnerUpId: runnerId,
    runnerUpScore: runnerScore,
    margin: margin,
    confirmedBy: confirmation,
    mode: index.mode,
    revision: index.revision,
  );
}

/// One recognised title candidate offered to [rankOutcome], carrying the
/// caller's own [evidence] payload.
final class RankableEvidence<E> {
  /// Creates a candidate.
  const RankableEvidence({
    required this.evidence,
    required this.markerScore,
    required this.text,
    required this.emptyTitleRegion,
    required this.peakOrder,
  });

  /// The caller's payload, returned untouched in the outcome.
  final E evidence;

  /// Marker correlation of the inspection this title belongs to.
  final double markerScore;

  /// Recognised title text.
  final String text;

  /// Whether the title region was empty; such a candidate is matched as an
  /// empty title regardless of [text].
  final bool emptyTitleRegion;

  /// Index of the candidate in its result's evidence list.
  final int peakOrder;
}

/// The candidates of one recognition result.
final class RecognitionResultInput<E> {
  /// Creates a result input.
  const RecognitionResultInput({
    required this.entries,
    required this.bestMarkerScore,
  });

  /// Candidates in peak order; empty when no marker was found.
  final List<RankableEvidence<E>> entries;

  /// Best marker score the result saw, or null when it reported none.
  final double? bestMarkerScore;
}

/// Why a recognition outcome is a rejection: one of the title matcher's
/// reasons, or a pipeline-level one.
enum OutcomeRejectReason {
  /// No marker evidence in either result.
  noMarker,

  /// The matcher itself failed; set by the async adapter, never by
  /// [rankOutcome].
  matcherFailed,

  /// See [TitleRejectReason.emptyCatalog].
  emptyCatalog,

  /// See [TitleRejectReason.titleTooShort].
  titleTooShort,

  /// See [TitleRejectReason.uiChrome].
  uiChrome,

  /// See [TitleRejectReason.belowSimilarity].
  belowSimilarity,

  /// See [TitleRejectReason.ambiguous].
  ambiguous,

  /// See [TitleRejectReason.catalogModeMismatch].
  catalogModeMismatch;

  /// The outcome reason that mirrors [reason].
  static OutcomeRejectReason fromTitle(TitleRejectReason reason) =>
      switch (reason) {
        TitleRejectReason.emptyCatalog => emptyCatalog,
        TitleRejectReason.titleTooShort => titleTooShort,
        TitleRejectReason.uiChrome => uiChrome,
        TitleRejectReason.belowSimilarity => belowSimilarity,
        TitleRejectReason.ambiguous => ambiguous,
        TitleRejectReason.catalogModeMismatch => catalogModeMismatch,
      };
}

/// The single result of ranking targeted and fallback evidence; either
/// [OutcomeAccepted] or [OutcomeRejected].
sealed class RecognitionOutcome<E> {
  const RecognitionOutcome();
}

/// An accepted item identity and the evidence it came from.
final class OutcomeAccepted<E> extends RecognitionOutcome<E> {
  /// Creates an acceptance.
  const OutcomeAccepted(this.match, this.evidence);

  /// The accepted match; its `bestId` is the item.
  final TitleAccepted match;

  /// The payload of the winning candidate.
  final E evidence;
}

/// A rejection. It never exposes an accepted item ID: [match], when present,
/// is a [TitleRejected].
final class OutcomeRejected<E> extends RecognitionOutcome<E> {
  /// Creates a rejection for [reason].
  const OutcomeRejected(
    this.reason, {
    this.evidence,
    this.match,
    this.targetedBestMarkerScore,
    this.fallbackBestMarkerScore,
  });

  /// Why nothing was accepted.
  final OutcomeRejectReason reason;

  /// Payload of the highest-ranked candidate, if there was one.
  final E? evidence;

  /// That candidate's match result, if there was one.
  final TitleMatch? match;

  /// Best marker score of the targeted result.
  final double? targetedBestMarkerScore;

  /// Best marker score of the fallback result.
  final double? fallbackBestMarkerScore;
}

/// Ranks targeted and fallback evidence into one outcome for a caller in
/// [mode].
///
/// An [index] built for another mode rejects `catalogModeMismatch`. An
/// accepted targeted candidate wins and the fallback is not matched.
/// Otherwise every candidate is matched and the first by acceptance, then
/// best similarity, then marker score (all descending), then peak order
/// (ascending) is the outcome; on a full tie the targeted candidate precedes
/// fallback ones, then input order decides. No candidates at all rejects
/// `noMarker`. Every rejection carries both results' best marker scores.
RecognitionOutcome<E> rankOutcome<E>(
  TitleMatchIndex index, {
  required RecognitionResultInput<E> targeted,
  RecognitionResultInput<E>? fallback,
  required GameMode mode,
}) {
  OutcomeRejected<E> reject(
    OutcomeRejectReason reason, {
    E? evidence,
    TitleMatch? match,
  }) => OutcomeRejected<E>(
    reason,
    evidence: evidence,
    match: match,
    targetedBestMarkerScore: targeted.bestMarkerScore,
    fallbackBestMarkerScore: fallback?.bestMarkerScore,
  );

  if (index.mode != mode) {
    return reject(OutcomeRejectReason.catalogModeMismatch);
  }

  TitleMatch matchEntry(RankableEvidence<E> e) =>
      matchTitle(index, e.emptyTitleRegion ? '' : e.text, mode);

  final ranked = <({RankableEvidence<E> entry, TitleMatch match})>[];
  for (final e in targeted.entries) {
    final m = matchEntry(e);
    if (m is TitleAccepted) return OutcomeAccepted<E>(m, e.evidence);
    ranked.add((entry: e, match: m));
  }
  for (final e in fallback?.entries ?? const []) {
    ranked.add((entry: e, match: matchEntry(e)));
  }
  if (ranked.isEmpty) return reject(OutcomeRejectReason.noMarker);

  var top = ranked.first;
  for (final candidate in ranked.skip(1)) {
    if (_outranks(candidate, top)) top = candidate;
  }
  return switch (top.match) {
    TitleAccepted() => OutcomeAccepted<E>(
      top.match as TitleAccepted,
      top.entry.evidence,
    ),
    TitleRejected(:final reason) => reject(
      OutcomeRejectReason.fromTitle(reason),
      evidence: top.entry.evidence,
      match: top.match,
    ),
  };
}

/// Whether [a] ranks strictly before [b]; ties keep the earlier candidate.
bool _outranks<E>(
  ({RankableEvidence<E> entry, TitleMatch match}) a,
  ({RankableEvidence<E> entry, TitleMatch match}) b,
) {
  final aAccepted = a.match is TitleAccepted;
  if (aAccepted != (b.match is TitleAccepted)) return aAccepted;
  if (a.match.bestScore != b.match.bestScore) {
    return a.match.bestScore > b.match.bestScore;
  }
  if (a.entry.markerScore != b.entry.markerScore) {
    return a.entry.markerScore > b.entry.markerScore;
  }
  return a.entry.peakOrder < b.entry.peakOrder;
}

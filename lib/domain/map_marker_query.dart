import 'dart:typed_data';

/// Accounts for derived metadata and search workspace for one live-map
/// generation.
class MapMarkerMetadataOwner {
  /// Creates an owner backed by materialized-byte admission callbacks.
  ///
  /// [foldScalar] optionally supplies the whole-string lowercase operation.
  MapMarkerMetadataOwner({
    required this._reserveMaterialized,
    required this._releaseMaterialized,
    String Function(String)? foldScalar,
  }) : _foldScalar = foldScalar ?? _lowercase {
    _reserve(128);
  }

  final void Function(int) _reserveMaterialized;
  final void Function(int) _releaseMaterialized;
  final String Function(String) _foldScalar;
  Map<String, _FoldedScalar>? _foldedScalars;
  int _retainedMaterializedBytes = 0;
  int _searchScratchCapacity = 0;
  _SearchPlan? _currentPlan;
  Map<Object, _ScratchMeasurement>? _searchScratchMeasurements;
  int _scratchMeasurementTransaction = 0;
  int _searchPlanSerial = 0;

  int _measureContainer(
    Object value,
    int transaction,
    int Function(Object?) measure,
  ) {
    var measurements = _searchScratchMeasurements;
    if (measurements == null) {
      _reserve(128);
      try {
        measurements = Map<Object, _ScratchMeasurement>.identity();
        _searchScratchMeasurements = measurements;
      } catch (_) {
        _release(128);
        rethrow;
      }
    }
    final cached = measurements[value];
    if (cached != null) return cached.bytes;

    bool hasTokens(Object? child) {
      if (child is String || child is num || child is bool) return true;
      if (child is Map || child is List) {
        return measurements![child]!.hasToken;
      }
      return false;
    }

    var cost = 160;
    _reserve(cost);
    try {
      var maximum = 0;
      var count = 0;
      var allTokens = true;
      final isMap = value is Map;
      List<Object?>? indexed;

      void include(Object? child) {
        final childBytes = measure(child);
        if (childBytes > maximum) maximum = childBytes;
        if (hasTokens(child)) {
          count++;
          if (isMap) {
            if (indexed == null) {
              _reserve(64);
              cost += 64;
              indexed = <Object?>[];
            }
            _reserve(16);
            cost += 16;
            indexed!.add(child);
          }
        } else {
          allTokens = false;
        }
      }

      if (value is Map) {
        for (final entry in value.entries) {
          if (!const {'position', 'outline', 'size'}.contains(entry.key)) {
            include(entry.value);
          }
        }
      } else {
        for (final child in value as List) {
          include(child);
        }
      }

      List<Object?> children;
      if (isMap) {
        children = indexed ?? const [];
      } else if (count == 0) {
        children = const [];
      } else if (allTokens) {
        children = value as List<Object?>;
      } else {
        final indexCost = 64 + count * 16;
        _reserve(indexCost);
        cost += indexCost;
        children = <Object?>[];
        for (final child in value as List) {
          if (hasTokens(child)) children.add(child);
        }
      }
      measurements[value] = _ScratchMeasurement(
        maximum,
        transaction,
        cost,
        children,
      );
      return maximum;
    } catch (_) {
      _release(cost);
      rethrow;
    }
  }

  void _rollbackScratchMeasurements(int transaction) {
    final measurements = _searchScratchMeasurements;
    if (measurements == null) return;
    var removedBytes = 0;
    measurements.removeWhere((_, measurement) {
      if (measurement.transaction != transaction) return false;
      removedBytes += measurement.cost;
      return true;
    });
    _release(removedBytes);
    if (measurements.isEmpty) {
      _searchScratchMeasurements = null;
      _release(128);
    }
  }

  static String _lowercase(String scalar) => scalar.toLowerCase();

  String _fold(String scalar) =>
      _foldedScalars?[scalar]?.folded ?? _foldScalar(scalar);

  _FoldedScalar _scalarRecord(String scalar, int transaction) {
    var records = _foldedScalars;
    if (records == null) {
      _reserve(128);
      try {
        records = Map<String, _FoldedScalar>.identity();
        _foldedScalars = records;
      } catch (_) {
        _release(128);
        rethrow;
      }
    }
    final existing = records[scalar];
    if (existing != null) return existing;
    _reserve(128);
    try {
      final record = _FoldedScalar(transaction);
      records[scalar] = record;
      return record;
    } catch (_) {
      _release(128);
      rethrow;
    }
  }

  void _admitScalar(String scalar, int transaction, {bool shared = false}) {
    if (scalar.length < 128) return;
    final record = _scalarRecord(scalar, transaction);
    if (!record.seen) {
      record.seen = true;
      record.seenTransaction = transaction;
      if (!shared) return;
    } else if (record.folded != null) {
      return;
    }
    // The full-fold workspace was admitted before this traversal. Retained
    // text is charged independently while that workspace is still reserved.
    final folded = _foldScalar(scalar);
    final cost = identical(folded, scalar) ? 0 : 64 + folded.length * 2;
    _reserve(cost);
    record.folded = folded;
    record.foldedCost = cost;
    record.foldedTransaction = transaction;
  }

  String? _admitSourceName(Object? value, int transaction) {
    if (value is! String) return null;
    String trimmed;
    if (value.length < 128) {
      trimmed = value.trim();
    } else {
      final record = _scalarRecord(value, transaction);
      if (record.trimmed == null) {
        final result = value.trim();
        final cost = identical(result, value) ? 0 : 64 + result.length * 2;
        _reserve(cost);
        record.trimmed = result;
        record.trimmedCost = cost;
        record.trimmedTransaction = transaction;
      }
      trimmed = record.trimmed!;
    }
    if (trimmed.isEmpty) return null;
    _admitScalar(trimmed, transaction);
    return trimmed;
  }

  void _admitSearchValue(
    Object? value,
    int transaction, {
    bool shared = false,
  }) {
    if (value is String) {
      _admitScalar(value, transaction, shared: shared);
      return;
    }
    if (value is! Map && value is! List) return;
    final measurement = _searchScratchMeasurements![value]!;
    if (!measurement.scalarVisited) {
      measurement.scalarVisited = true;
      measurement.visitedTransaction = transaction;
    } else {
      shared = true;
    }
    if (shared) {
      if (measurement.scalarShared) return;
      measurement.scalarShared = true;
      measurement.sharedTransaction = transaction;
    }
    for (final child in measurement.children) {
      _admitSearchValue(child, transaction, shared: shared);
    }
  }

  void _rollbackScalars(int transaction) {
    for (final measurement
        in _searchScratchMeasurements?.values ??
            const <_ScratchMeasurement>[]) {
      if (measurement.visitedTransaction == transaction) {
        measurement.scalarVisited = false;
        measurement.visitedTransaction = 0;
      }
      if (measurement.sharedTransaction == transaction) {
        measurement.scalarShared = false;
        measurement.sharedTransaction = 0;
      }
    }
    final records = _foldedScalars;
    if (records == null) return;
    var released = 0;
    records.removeWhere((_, record) {
      if (record.foldedTransaction == transaction) {
        released += record.foldedCost;
        record.folded = null;
        record.foldedCost = 0;
        record.foldedTransaction = 0;
      }
      if (record.trimmedTransaction == transaction) {
        released += record.trimmedCost;
        record.trimmed = null;
        record.trimmedCost = 0;
        record.trimmedTransaction = 0;
      }
      if (record.seenTransaction == transaction) {
        record.seen = false;
        record.seenTransaction = 0;
      }
      if (record.transaction != transaction) return false;
      released += 128;
      return true;
    });
    if (records.isEmpty) {
      _foldedScalars = null;
      released += 128;
    }
    _release(released);
  }

  int _admitSearchScratch(int bytes) {
    if (bytes <= _searchScratchCapacity) return 0;
    final additionalBytes = bytes - _searchScratchCapacity;
    _reserve(additionalBytes);
    _searchScratchCapacity = bytes;
    return additionalBytes;
  }

  void _releaseSearchScratch(int bytes) {
    if (bytes <= 0) return;
    _release(bytes);
    _searchScratchCapacity -= bytes;
  }

  /// The derived metadata and search workspace bytes accounted to this owner.
  int get retainedMaterializedBytes => _retainedMaterializedBytes;

  void _reserve(int bytes) {
    if (bytes <= 0) return;
    _reserveMaterialized(bytes);
    _retainedMaterializedBytes += bytes;
  }

  void _release(int bytes) {
    if (bytes <= 0) return;
    _releaseMaterialized(bytes);
    _retainedMaterializedBytes -= bytes;
  }

  _SearchPlan _planFor(Iterable<String> terms) {
    final current = _currentPlan;
    if (current != null && current.matchesTerms(terms)) return current;

    var count = 0;
    var totalLength = 0;
    var hasEmpty = false;
    for (final term in terms) {
      count++;
      totalLength += term.length;
      if (term.isEmpty) hasEmpty = true;
    }
    final cost = hasEmpty || count == 0
        ? 128
        : 128 + count * 96 + totalLength * 12;
    _reserve(cost);
    try {
      final needles = <_SearchNeedle>[];
      if (!hasEmpty) {
        for (final term in terms) {
          final needle = term.toLowerCase();
          needles.add(_SearchNeedle(term, needle, _prefixTable(needle)));
        }
      }
      if (_searchPlanSerial == 0x7fffffffffffffff) {
        for (final measurement
            in _searchScratchMeasurements?.values ??
                const <_ScratchMeasurement>[]) {
          measurement.stamp = 0;
        }
        _searchPlanSerial = 0;
      }
      final plan = _SearchPlan(needles, cost, ++_searchPlanSerial);
      _currentPlan = plan;
      if (current != null) {
        _release(current.retainedBytes);
      }
      return plan;
    } catch (_) {
      _release(cost);
      rethrow;
    }
  }
}

/// Metadata consumed by Map search, quest eligibility and marker details.
///
/// It retains source identities rather than inferring relationships from names
/// or proximity. Geometry is deliberately not a searchable metadata field.
class MapMarkerMetadata {
  MapMarkerMetadata({
    required this.name,
    required this.type,
    required this.category,
    required Map<String, dynamic> details,
    required Map<String, dynamic> source,
    MapMarkerMetadataOwner? owner,
  }) : _owner =
           owner ??
           MapMarkerMetadataOwner(
             reserveMaterialized: (_) {},
             releaseMaterialized: (_) {},
           ) {
    const excluded = {'position', 'outline', 'size', 'bottom', 'top'};
    final retainedCost = _metadataCost(details, source, excluded);
    final constructionScratch = 192 + category.length * 4;
    final transaction = ++_owner._scratchMeasurementTransaction;
    var scratchAdmission = 0;
    var metadataReserved = false;
    try {
      scratchAdmission = _owner._admitSearchScratch(
        _searchScratchBytes(
          name,
          type,
          category,
          details,
          source,
          _owner,
          transaction,
        ),
      );
      _owner._reserve(retainedCost + constructionScratch);
      metadataReserved = true;
      _owner._admitSearchValue(name, transaction);
      _owner._admitSearchValue(type, transaction);
      _owner._admitSearchValue(category, transaction);
      for (final entry in details.entries) {
        if (!excluded.contains(entry.key)) {
          _owner._admitSearchValue(entry.value, transaction);
        }
      }
      _sourceName = _owner._admitSourceName(source['name'], transaction);
      fields = Map.unmodifiable({
        for (final entry in details.entries)
          if (!excluded.contains(entry.key)) entry.key: entry.value,
      });
      sourceId = _text(details['id']);
      final quests = <Map<String, dynamic>>[];
      for (final key in ['quest', 'task', 'quests', 'tasks']) {
        final value = details[key];
        if (value is Map<String, dynamic>) quests.add(value);
        if (value is List) {
          quests.addAll(value.whereType<Map<String, dynamic>>());
        }
      }
      questNames = List.unmodifiable([
        for (final quest in quests)
          if (_text(quest['name']) case final String name) name,
        if (_text(details['questName']) case final String name) name,
        if (_text(details['taskName']) case final String name) name,
      ]);
      traders = List.unmodifiable([
        for (final quest in quests) ..._names(quest['trader']),
        ..._names(details['trader']),
      ]);
      questLinks = List.unmodifiable([
        for (final quest in quests)
          if (_text(quest['wikiLink'] ?? quest['link']) case final String link)
            link,
        if (_text(details['wikiLink']) case final String link) link,
      ]);
      linkedSwitchIds = Set.unmodifiable(_ids(details['switches']));
      activatedIds = Set.unmodifiable(_ids(details['activates']));
      isQuest =
          type == 'QuestItems' ||
          type == 'QuestObjectives' ||
          category.toLowerCase().contains('quest');
    } catch (_) {
      if (metadataReserved) _owner._release(retainedCost + constructionScratch);
      _owner._releaseSearchScratch(scratchAdmission);
      _owner._rollbackScalars(transaction);
      _owner._rollbackScratchMeasurements(transaction);
      rethrow;
    }
    _owner._release(constructionScratch);
  }

  final MapMarkerMetadataOwner _owner;
  final String name;
  final String type;
  final String category;
  late final Map<String, dynamic> fields;
  late final String? sourceId;
  late final List<String> questNames;
  late final List<String> traders;
  late final List<String> questLinks;
  late final Set<String> linkedSwitchIds;
  late final Set<String> activatedIds;
  late final bool isQuest;

  /// Tests comma-separated search terms against shared source facts.
  bool matchesSearch(Iterable<String> terms) =>
      _owner._planFor(terms).matches(this, _owner);

  // Capture trimmed provenance once so shared identities remain stable.
  late final String? _sourceName;

  /// Whether this marker matches the selected quest and trader.
  bool matchesQuest({required String name, required String trader}) {
    if (!isQuest) return true;
    final query = name.trim().toLowerCase();
    final traderQuery = trader.trim().toLowerCase();
    return (query.isEmpty ||
            questNames.any((name) => name.toLowerCase().contains(query))) &&
        (traderQuery.isEmpty ||
            traderQuery == 'all' ||
            traders.any((name) => name.toLowerCase() == traderQuery));
  }
}

class _SearchNeedle {
  const _SearchNeedle(this.original, this.text, this.prefix);

  final String original;
  final String text;
  final List<int> prefix;
}

class _SearchPlan {
  _SearchPlan(this.needles, this.retainedBytes, this.stamp)
    : _limit = needles.fold<int>(
        0,
        (longest, needle) =>
            needle.text.length > longest ? needle.text.length : longest,
      ),
      _positions = List<int>.filled(needles.length, 0),
      _window = Uint16List(
        needles.fold<int>(
          0,
          (longest, needle) =>
              needle.text.length > longest ? needle.text.length : longest,
        ),
      );

  final List<_SearchNeedle> needles;
  final int retainedBytes;
  final int stamp;
  final int _limit;
  final List<int> _positions;
  final Uint16List _window;

  bool matchesTerms(Iterable<String> terms) {
    var index = 0;
    for (final term in terms) {
      if (index >= needles.length ||
          (needles[index].original != term && needles[index].text != term)) {
        return false;
      }
      index++;
    }
    return index == needles.length;
  }

  void _reset() {
    for (var i = 0; i < _positions.length; i++) {
      _positions[i] = 0;
    }
  }

  bool _accept(int code) {
    var found = false;
    for (var i = 0; i < needles.length; i++) {
      final needle = needles[i];
      var position = _positions[i];
      while (position > 0 && needle.text.codeUnitAt(position) != code) {
        position = needle.prefix[position - 1];
      }
      if (needle.text.codeUnitAt(position) == code) position++;
      if (position == needle.text.length) {
        found = true;
        position = needle.prefix[position - 1];
      }
      _positions[i] = position;
    }
    return found;
  }

  bool matches(MapMarkerMetadata metadata, MapMarkerMetadataOwner owner) {
    if (needles.isEmpty) return true;
    // Finish memoizing before using the plan's single reusable KMP workspace.
    for (final value in metadata.fields.values) {
      _prepare(value, owner);
    }
    _reset();
    var hasToken = false;
    bool append(Object? value) {
      if (!_hasToken(value, owner)) return false;
      if (hasToken && _accept(32)) return true;
      hasToken = true;
      return _apply(value, owner);
    }

    if (append(metadata.name) ||
        append(metadata.type) ||
        append(metadata.category)) {
      return true;
    }
    for (final value in metadata.fields.values) {
      if (append(value)) return true;
    }
    if (metadata._sourceName case final String provenance) {
      if (append(provenance)) return true;
    }
    return false;
  }

  bool _hasToken(Object? value, MapMarkerMetadataOwner owner) {
    if (value is String || value is num || value is bool) return true;
    if (value is Map || value is List) {
      return owner._searchScratchMeasurements![value]!.hasToken;
    }
    return false;
  }

  int _length(Object? value, MapMarkerMetadataOwner owner) {
    if (value is String || value is num || value is bool) {
      final text = owner._fold(value is String ? value : value.toString());
      return text.length < _limit ? text.length : _limit;
    }
    if (value is Map || value is List) {
      return owner._searchScratchMeasurements![value]!.length;
    }
    return 0;
  }

  void _prepare(Object? value, MapMarkerMetadataOwner owner) {
    if (value is! Map && value is! List) return;
    final measurement = owner._searchScratchMeasurements![value]!;
    final summary = measurement;
    if (summary.stamp == stamp) return;
    final children = measurement.children;
    for (final child in children) {
      _prepare(child, owner);
    }

    var length = 0;
    var first = true;
    for (final child in children) {
      if (!first && length < _limit) length++;
      length += _length(child, owner);
      if (length > _limit) length = _limit;
      first = false;
    }
    summary.length = length;
    summary.found = false;
    summary.stamp = stamp;

    _reset();
    first = true;
    for (final child in children) {
      if ((!first && _accept(32)) || _apply(child, owner)) {
        summary.found = true;
        break;
      }
      first = false;
    }
  }

  bool _apply(Object? value, MapMarkerMetadataOwner owner) {
    if (value is String || value is num || value is bool) {
      final text = owner._fold(value is String ? value : value.toString());
      for (var i = 0; i < text.length; i++) {
        if (_accept(text.codeUnitAt(i))) return true;
      }
      return false;
    }
    if (value is! Map && value is! List) return false;
    final summary = owner._searchScratchMeasurements![value]!;
    if (summary.found) return true;
    final count = summary.length < _limit ? summary.length : _limit;
    var found = false;
    _emit(value, owner, count, false, (code) {
      if (_accept(code)) found = true;
    });
    if (found) return true;
    if (summary.length == _limit) {
      _reset();
      var used = 0;
      _emit(value, owner, _limit - 1, true, (code) {
        _window[used++] = code;
      });
      while (used > 0) {
        if (_accept(_window[--used])) return true;
      }
    }
    return false;
  }

  int _emit(
    Object? value,
    MapMarkerMetadataOwner owner,
    int remaining,
    bool reverse,
    void Function(int) accept,
  ) {
    if (remaining == 0) return 0;
    if (value is String || value is num || value is bool) {
      final text = owner._fold(value is String ? value : value.toString());
      final count = text.length < remaining ? text.length : remaining;
      for (var i = 0; i < count; i++) {
        accept(text.codeUnitAt(reverse ? text.length - 1 - i : i));
      }
      return count;
    }
    if (value is! Map && value is! List) return 0;
    final measurement = owner._searchScratchMeasurements![value]!;
    final children = measurement.children;
    var index = reverse ? children.length - 1 : 0;
    var emitted = 0;
    var first = true;
    while (index >= 0 && index < children.length && emitted < remaining) {
      if (!first) {
        accept(32);
        emitted++;
        if (emitted == remaining) break;
      }
      emitted += _emit(
        children[index],
        owner,
        remaining - emitted,
        reverse,
        accept,
      );
      first = false;
      index += reverse ? -1 : 1;
    }
    return emitted;
  }
}

abstract class _SharedSearchSummary {
  int stamp = 0;
  int length = 0;
  bool get hasToken;
  bool found = false;
}

List<int> _prefixTable(String value) {
  final result = List<int>.filled(value.length, 0);
  for (var i = 1, length = 0; i < value.length; i++) {
    while (length > 0 && value.codeUnitAt(i) != value.codeUnitAt(length)) {
      length = result[length - 1];
    }
    if (value.codeUnitAt(i) == value.codeUnitAt(length)) length++;
    result[i] = length;
  }
  return result;
}

/// Commas are OR separators; empty terms do not accidentally match everything.
List<String> mapSearchTerms(String value) => List.unmodifiable(
  value
      .split(',')
      .map((term) => term.trim().toLowerCase())
      .where((term) => term.isNotEmpty),
);

int _metadataCost(
  Map<String, dynamic> details,
  Map<String, dynamic> source,
  Set<String> excluded,
) {
  var entries = 0;
  for (final key in details.keys) {
    if (!excluded.contains(key)) entries++;
  }
  // Facts stay shared. Admit the variable derived collections and any trimmed
  // strings before building them; list copies include construction overlap.
  var bytes = 512 + entries * 64 + source.length * 16;

  int textBytes(Object? value) => value is String ? 64 + value.length * 4 : 0;
  int namesBytes(Object? value) {
    if (value is String) return 64 + value.length * 4;
    if (value is Map) return textBytes(value['name']);
    if (value is List) {
      var total = 64 + value.length * 32;
      for (final item in value) {
        total += namesBytes(item);
      }
      return total;
    }
    return 0;
  }

  int idsBytes(Object? value) {
    if (value is String) return 96 + value.length * 4;
    if (value is Map) return textBytes(value['id']) + 64;
    if (value is List) {
      var total = 64 + value.length * 48;
      for (final item in value) {
        total += idsBytes(item);
      }
      return total;
    }
    return 0;
  }

  void countQuest(Map<String, dynamic> quest) {
    bytes +=
        128 +
        textBytes(quest['name']) +
        textBytes(quest['wikiLink'] ?? quest['link']) +
        namesBytes(quest['trader']);
  }

  for (final key in const ['quest', 'task', 'quests', 'tasks']) {
    final value = details[key];
    if (value is Map<String, dynamic>) countQuest(value);
    if (value is List) {
      bytes += 64 + value.length * 32;
      for (final item in value) {
        if (item is Map<String, dynamic>) countQuest(item);
      }
    }
  }
  return bytes +
      textBytes(details['id']) +
      textBytes(details['questName']) +
      textBytes(details['taskName']) +
      textBytes(details['wikiLink']) +
      textBytes(source['name']) +
      namesBytes(details['trader']) +
      idsBytes(details['switches']) +
      idsBytes(details['activates']);
}

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

Iterable<String> _names(Object? value) sync* {
  if (_text(value) case final String name) yield name;
  if (value is Map) {
    if (_text(value['name']) case final String name) yield name;
  }
  if (value is List) {
    for (final item in value) {
      yield* _names(item);
    }
  }
}

Iterable<String> _ids(Object? value) sync* {
  if (_text(value) case final String id) yield id;
  if (value is Map) {
    if (_text(value['id']) case final String id) yield id;
  }
  if (value is List) {
    for (final item in value) {
      yield* _ids(item);
    }
  }
}

class _FoldedScalar {
  _FoldedScalar(this.transaction);

  final int transaction;
  bool seen = false;
  int seenTransaction = 0;
  String? folded;
  int foldedCost = 0;
  int foldedTransaction = 0;
  String? trimmed;
  int trimmedCost = 0;
  int trimmedTransaction = 0;
}

class _ScratchMeasurement extends _SharedSearchSummary {
  _ScratchMeasurement(this.bytes, this.transaction, this.cost, this.children);

  final int bytes;
  final int transaction;
  final int cost;
  final List<Object?> children;
  bool scalarVisited = false;
  bool scalarShared = false;
  int visitedTransaction = 0;
  int sharedTransaction = 0;

  @override
  bool get hasToken => children.isNotEmpty;
}

// Reserve one conservative lowercase workspace, not a copy per inventory fact.
const _searchScratchBaseBytes = 128;
const _searchScratchBytesPerCodeUnit = 12;
// Numeric and boolean stringification plus lowercasing fit within this bound.
const _numericSearchScratchBytes = 1024;

int _searchScratchBytes(
  String name,
  String type,
  String category,
  Map<String, dynamic> details,
  Map<String, dynamic> source,
  MapMarkerMetadataOwner owner,
  int transaction,
) {
  int measure(Object? value) {
    if (value is String) {
      return _searchScratchBaseBytes +
          value.length * _searchScratchBytesPerCodeUnit;
    }
    if (value is num || value is bool) return _numericSearchScratchBytes;
    if (value == null || (value is! Map && value is! List)) return 0;

    return owner._measureContainer(value, transaction, measure);
  }

  var maximum = measure(name);
  void include(Object? value) {
    final bytes = measure(value);
    if (bytes > maximum) maximum = bytes;
  }

  include(type);
  include(category);
  final sourceName = source['name'];
  if (sourceName is String) include(sourceName);
  // The details root is transient; only cache searchable nested containers.
  for (final entry in details.entries) {
    if (!const {
      'position',
      'outline',
      'size',
      'bottom',
      'top',
    }.contains(entry.key)) {
      include(entry.value);
    }
  }
  return maximum;
}

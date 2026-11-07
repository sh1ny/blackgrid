/// Accounts for derived metadata and search workspace for one live-map
/// generation.
class MapMarkerMetadataOwner {
  /// Creates an owner backed by materialized-byte admission callbacks.
  MapMarkerMetadataOwner({
    required this._reserveMaterialized,
    required this._releaseMaterialized,
  }) {
    _reserve(128);
  }

  final void Function(int) _reserveMaterialized;
  final void Function(int) _releaseMaterialized;
  int _retainedMaterializedBytes = 0;
  int _searchScratchCapacity = 0;
  _SearchPlan? _currentPlan;
  Map<Object, _ScratchMeasurement>? _searchScratchMeasurements;
  int _scratchMeasurementTransaction = 0;

  void _rememberScratchMeasurement(Object value, int bytes, int transaction) {
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
    _reserve(128);
    try {
      measurements[value] = _ScratchMeasurement(bytes, transaction);
    } catch (_) {
      _release(128);
      rethrow;
    }
  }

  void _rollbackScratchMeasurements(int transaction) {
    final measurements = _searchScratchMeasurements;
    if (measurements == null) return;
    var removed = 0;
    measurements.removeWhere((_, measurement) {
      if (measurement.transaction != transaction) return false;
      removed++;
      return true;
    });
    _release(removed * 128);
    if (measurements.isEmpty) {
      _searchScratchMeasurements = null;
      _release(128);
    }
  }

  // Fold one scalar at a time instead of retaining copies of the inventory.
  String _fold(String scalar) => scalar.toLowerCase();

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

  T _withScratch<T>(int bytes, T Function() action) {
    _reserve(bytes);
    try {
      return action();
    } finally {
      _release(bytes);
    }
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
      final plan = _SearchPlan(needles, cost);
      _currentPlan = plan;
      if (current != null) _release(current.retainedBytes);
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
           ),
       _source = source {
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

  // Search only needs source.name; retain its reference, not another map copy.
  Object? get _sourceName => _source['name'];

  final Map<String, dynamic> _source;

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
  const _SearchPlan(this.needles, this.retainedBytes);

  final List<_SearchNeedle> needles;
  final int retainedBytes;

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

  bool matches(MapMarkerMetadata metadata, MapMarkerMetadataOwner owner) {
    if (needles.isEmpty) return true;
    return owner._withScratch(needles.length * 8 + 32, () {
      final positions = List<int>.filled(needles.length, 0);
      var found = 0;
      var hasToken = false;

      bool accept(Object value) {
        if (found > 0) return true;
        final scalar = value is String ? value : value.toString();
        if (hasToken) {
          for (var index = 0; index < needles.length; index++) {
            final needle = needles[index].text;
            positions[index] = _advance(
              needle,
              needles[index].prefix,
              positions[index],
              32,
            );
            if (positions[index] == needle.length) {
              found++;
              positions[index] = needles[index].prefix[needle.length - 1];
            }
          }
        }
        if (found > 0) return true;
        hasToken = true;
        {
          final folded = owner._fold(scalar);
          for (var unit = 0; unit < folded.length && found == 0; unit++) {
            final code = folded.codeUnitAt(unit);
            for (var index = 0; index < needles.length; index++) {
              final needle = needles[index].text;
              positions[index] = _advance(
                needle,
                needles[index].prefix,
                positions[index],
                code,
              );
              if (positions[index] == needle.length) {
                found++;
                positions[index] = needles[index].prefix[needle.length - 1];
              }
            }
          }
        }
        return found > 0;
      }

      if (accept(metadata.name) ||
          accept(metadata.type) ||
          accept(metadata.category) ||
          _visitSearchValues(metadata.fields, accept)) {
        return true;
      }
      if (_text(metadata._sourceName) case final String provenance) {
        return accept(provenance);
      }
      return false;
    });
  }
}

/// Commas are OR separators; empty terms do not accidentally match everything.
List<String> mapSearchTerms(String value) => List.unmodifiable(
  value
      .split(',')
      .map((term) => term.trim().toLowerCase())
      .where((term) => term.isNotEmpty),
);

int _advance(String needle, List<int> prefix, int position, int code) {
  while (position > 0 && needle.codeUnitAt(position) != code) {
    position = prefix[position - 1];
  }
  if (needle.codeUnitAt(position) == code) position++;
  return position;
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

class _ScratchMeasurement {
  const _ScratchMeasurement(this.bytes, this.transaction);

  final int bytes;
  final int transaction;
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

    final cached = owner._searchScratchMeasurements?[value];
    if (cached != null) return cached.bytes;

    var maximum = 0;
    void include(Object? child) {
      final bytes = measure(child);
      if (bytes > maximum) maximum = bytes;
    }

    if (value is Map) {
      for (final entry in value.entries) {
        if (!const {'position', 'outline', 'size'}.contains(entry.key)) {
          include(entry.value);
        }
      }
    } else if (value is List) {
      for (final item in value) {
        include(item);
      }
    }
    owner._rememberScratchMeasurement(value, maximum, transaction);
    return maximum;
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

bool _visitSearchValues(Object? value, bool Function(Object) accept) {
  if (value is String || value is num || value is bool) {
    return accept(value!);
  } else if (value is Map) {
    for (final entry in value.entries) {
      if (!const {'position', 'outline', 'size'}.contains(entry.key) &&
          _visitSearchValues(entry.value, accept)) {
        return true;
      }
    }
  } else if (value is List) {
    for (final item in value) {
      if (_visitSearchValues(item, accept)) return true;
    }
  }
  return false;
}

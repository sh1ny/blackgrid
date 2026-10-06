import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/catalog.dart';
import 'wire_json.dart';

const catalogDatasets = [
  'items',
  'traders',
  'tasks',
  'hideout',
  'crafts',
  'barters',
];
const catalogTranslations = ['items', 'traders', 'tasks', 'hideout'];

class CatalogWireCandidate {
  CatalogWireCandidate({
    required this.mode,
    required this.observedAt,
    required Map<String, String> datasets,
    Map<String, String> localization = const {},
    Iterable<String> localizationErrors = const [],
  }) : datasets = Map.unmodifiable(datasets),
       localization = Map.unmodifiable(localization),
       localizationErrors = List.unmodifiable(localizationErrors);
  final GameMode mode;
  final DateTime observedAt;
  final Map<String, String> datasets, localization;
  final List<String> localizationErrors;
}

CatalogSnapshot normalizeCatalog(CatalogWireCandidate wire) {
  if (wire.mode == GameMode.unknown) {
    throw const FormatException('Catalog mode unavailable');
  }
  final roots = <String, Map<String, dynamic>>{};
  for (final key in catalogDatasets) {
    final bytes = wire.datasets[key];
    if (bytes == null) throw const FormatException('Incomplete catalog');
    roots[key] = decodeWireObject(bytes);
    if (!roots[key]!.containsKey('data')) {
      throw const FormatException('Missing collection');
    }
  }
  final localizationErrors = wire.localizationErrors.toList();
  final dictionaries = <String, Map<String, dynamic>>{};
  for (final key in catalogTranslations) {
    try {
      final text = wire.localization[key];
      if (text == null) throw const FormatException('Missing translation');
      final dictionary = _map(decodeWireObject(text)['data']);
      if (dictionary.values.any((v) => v is! String)) {
        throw const FormatException('Invalid dictionary');
      }
      dictionaries[key] = dictionary;
    } on Object {
      if (!localizationErrors.contains(key)) localizationErrors.add(key);
    }
  }
  String? label(String key, Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    final translated = dictionaries[key]?[value];
    // Raw strings at these endpoints are localization references, not names.
    return translated is String && translated.trim().isNotEmpty
        ? translated
        : null;
  }

  final rawItems = _keyed(
    _map(roots['items']!['data'])['items'],
    nonempty: true,
  );
  final rawTraders = _keyed(roots['traders']!['data'], nonempty: true);
  final rawTasks = _keyed(_map(roots['tasks']!['data'])['tasks']);
  final rawStations = _keyed(roots['hideout']!['data']);
  final rawCrafts = _arrayEntities(roots['crafts']!['data']);
  final rawBarters = _arrayEntities(roots['barters']!['data']);
  void ref(Object? id, Map<String, dynamic> collection) {
    if (id is! String || !collection.containsKey(id)) {
      throw const FormatException('Unresolved required reference');
    }
  }

  final traders = rawTraders.map(
    (k, v) => MapEntry(
      k,
      CatalogTrader(id: k, name: label('traders', _map(v)['name'])),
    ),
  );
  final items = <String, CatalogItem>{};
  for (final entry in rawItems.entries) {
    final j = _map(entry.value);
    final types = j['types'] == null ? null : _strings(j['types']);
    final offers = <CashOffer>[];
    if (j['sellToTrader'] != null) {
      for (final raw in _list(j['sellToTrader'])) {
        final o = _map(raw);
        ref(o['trader'], rawTraders);
        offers.add(
          CashOffer(
            traderId: o['trader'] as String,
            currency: _string(o['currency']),
            price: _number(o['price']),
            barter: o['barter'] == true,
          ),
        );
      }
    }
    final normalized = j['normalizedName'] == null
        ? ''
        : _string(j['normalizedName']);
    items[entry.key] = CatalogItem(
      id: entry.key,
      name:
          label('items', j['name']) ??
          (normalized.isNotEmpty ? normalized : entry.key),
      shortName: label('items', j['shortName']),
      normalizedName: normalized,
      width: _number(j['width']),
      height: _number(j['height']),
      noFlea: types?.contains('noFlea'),
      minLevelForFlea: _integer(j['minLevelForFlea']),
      fleaPrice: _number(j['avg24hPrice']),
      quoteAt: _time(j['lastScanISO'] ?? j['lastScan']),
      updatedAt: _time(j['updated']),
      sellOffers: offers,
    );
  }
  final requirements = <ItemRequirement>[];
  final progressIds = <String>{};
  void unique(String id) {
    if (!progressIds.add(id)) {
      throw const FormatException('Duplicate requirement identity');
    }
  }

  // Objective identity is unique within a task, not across task variants.
  // Preserve raw IDs for Tracker, and retain ambiguity instead of inventing
  // owner-scoped progress IDs that its flat objective response does not supply.
  final objectiveOwners = <String, String>{};
  final ambiguousObjectives = <String>{};
  for (final entry in rawTasks.entries) {
    final localIds = <String>{};
    for (final raw in _list(_map(entry.value)['objectives'])) {
      final id = _string(_map(raw)['id']);
      if (!localIds.add(id)) {
        throw const FormatException('Duplicate requirement identity');
      }
      final owner = objectiveOwners[id];
      if (owner != null && owner != entry.key) {
        ambiguousObjectives.add(id);
      } else {
        objectiveOwners[id] = entry.key;
      }
      progressIds.add(id);
    }
  }

  RequirementGate gate(Map<String, dynamic> j, {bool task = false}) {
    final taskStatuses = <String, List<String>>{};
    final stations = <String, int>{};
    for (final raw in _list(j['taskRequirements'] ?? [])) {
      final r = _map(raw);
      ref(r['task'], rawTasks);
      final id = r['task'] as String;
      if (taskStatuses.containsKey(id)) {
        throw const FormatException('Duplicate prerequisite');
      }
      taskStatuses[id] = _strings(r['status']);
    }
    for (final raw in _list(j['stationLevelRequirements'] ?? [])) {
      final r = _map(raw);
      ref(r['station'], rawStations);
      final level = _integer(r['level']);
      if (level == null || level < 0) {
        throw const FormatException('Invalid station gate');
      }
      stations[r['station'] as String] = level;
    }
    final traderGates = _list(j['traderRequirements'] ?? []);
    for (final raw in traderGates) {
      ref(_map(raw)['trader'], rawTraders);
    }
    final editions = <int>[];
    final editionIds = <String>[];
    for (final v in _list(j['gameEditions'] ?? [])) {
      if (v is String) {
        editionIds.add(_string(v));
      } else {
        final n = _integer(v);
        if (n == null || n < 1) throw const FormatException('Invalid edition');
        editions.add(n);
      }
    }
    return RequirementGate(
      minPlayerLevel: _integer(j['minPlayerLevel']),
      faction: j['factionName'] as String?,
      editions: j.containsKey('gameEditions') ? editions : null,
      editionIds: j.containsKey('gameEditions') ? editionIds : null,
      taskStatuses: taskStatuses,
      stations: stations,
      unknownTraderOrSkill:
          traderGates.isNotEmpty ||
          _list(j['skillRequirements'] ?? []).isNotEmpty,
      incomplete:
          task &&
          (!j.containsKey('minPlayerLevel') ||
              !j.containsKey('factionName') ||
              !j.containsKey('taskRequirements') ||
              !j.containsKey('traderRequirements')),
    );
  }

  for (final entry in rawTasks.entries) {
    final j = _map(entry.value);
    ref(j['trader'], rawTraders);
    final g = gate(j, task: true);
    final objectives = _list(j['objectives']);
    final pending = <ItemRequirement>[];
    for (final raw in objectives) {
      final o = _map(raw);
      final id = _string(o['id']);
      final type = _string(o['type']);
      if (![
        'findItem',
        'giveItem',
        'plantItem',
        'buildWeapon',
      ].contains(type)) {
        continue;
      }
      final ids = type == 'buildWeapon'
          ? [_string(o['item'])]
          : _strings(o['items']);
      if (ids.isEmpty) throw const FormatException('Missing requirement items');
      for (final i in ids) {
        ref(i, rawItems);
      }
      final count = _quantity(o['count']);
      final fir = _boolean(o['foundInRaid']);
      final optional = _boolean(o['optional']);
      final candidate = ItemRequirement(
        kind: RequirementKind.task,
        sourceId: entry.key,
        sourceName:
            label('tasks', j['name']) ??
            (j['normalizedName'] as String? ?? entry.key),
        id: id,
        itemIds: ids..sort(),
        progressIds: [id],
        ambiguousProgressIdentity: ambiguousObjectives.contains(id),
        count: count,
        foundInRaid: fir,
        gate: g,
        optional: optional == true,
      );
      // Pair only equal acquisition quantities and alternative sets; never sum find/give.
      final pair = pending.indexWhere(
        (r) =>
            r.count == count &&
            r.foundInRaid == fir &&
            r.optional == candidate.optional &&
            r.itemIds.join('|') == candidate.itemIds.join('|') &&
            r.id != id &&
            ((type == 'giveItem' &&
                    _map(
                          objectives.firstWhere((v) => _map(v)['id'] == r.id),
                        )['type'] ==
                        'findItem') ||
                (type == 'findItem' &&
                    _map(
                          objectives.firstWhere((v) => _map(v)['id'] == r.id),
                        )['type'] ==
                        'giveItem')) &&
            r.progressIds.length == 1,
      );
      if (pair < 0) {
        pending.add(candidate);
      } else {
        final r = pending[pair];
        final paired = [...r.progressIds, id]..sort();
        pending[pair] = ItemRequirement(
          kind: r.kind,
          sourceId: r.sourceId,
          sourceName: r.sourceName,
          id: paired.first,
          itemIds: r.itemIds,
          progressIds: paired,
          completionId: type == 'giveItem' ? id : r.id,
          ambiguousProgressIdentity:
              r.ambiguousProgressIdentity ||
              candidate.ambiguousProgressIdentity,
          count: r.count,
          foundInRaid: r.foundInRaid,
          gate: r.gate,
          optional: r.optional,
        );
      }
    }
    requirements.addAll(pending);
  }
  for (final entry in rawStations.entries) {
    final j = _map(entry.value);
    for (final raw in _list(j['levels'])) {
      final level = _map(raw);
      final moduleId = _string(level['id']);
      unique(moduleId);
      final levelNumber = _integer(level['level']);
      if (levelNumber == null || levelNumber < 1) {
        throw const FormatException('Invalid module level');
      }
      final g = gate(level);
      for (final part in _list(level['itemRequirements'])) {
        final p = _map(part);
        final id = _string(p['id']);
        unique(id);
        ref(p['item'], rawItems);
        requirements.add(
          ItemRequirement(
            kind: RequirementKind.hideout,
            sourceId: moduleId,
            sourceName:
                label('hideout', j['name']) ??
                (j['normalizedName'] as String? ?? entry.key),
            id: id,
            itemIds: [p['item'] as String],
            progressIds: [id],
            count: _quantity(p['count']),
            foundInRaid: _boolean(_map(p['attributes'] ?? {})['foundInRaid']),
            gate: g,
            stationId: entry.key,
            stationLevel: levelNumber,
          ),
        );
      }
    }
  }
  for (final kind in [RequirementKind.craft, RequirementKind.barter]) {
    final collection = kind == RequirementKind.craft ? rawCrafts : rawBarters;
    for (final entry in collection.entries) {
      final j = _map(entry.value);
      final product = _map(
        j[kind == RequirementKind.craft ? 'productItem' : 'offeredItem'],
      );
      ref(product['item'], rawItems);
      _quantity(product['count']);
      if (kind == RequirementKind.craft) {
        ref(j['station'], rawStations);
      } else {
        ref(j['trader'], rawTraders);
        if (j['taskUnlock'] != null) ref(j['taskUnlock'], rawTasks);
      }
      var n = 0;
      for (final raw in _list(j['requiredItems'])) {
        final p = _map(raw);
        ref(p['item'], rawItems);
        requirements.add(
          ItemRequirement(
            kind: kind,
            sourceId: entry.key,
            sourceName: '${kind.name} ${entry.key}',
            id: '${entry.key}:${n++}',
            itemIds: [p['item'] as String],
            progressIds: const [],
            count: _quantity(p['count']),
            foundInRaid: _boolean(_map(p['attributes'] ?? {})['foundInRaid']),
            gate: gate(j),
            optional: true,
          ),
        );
      }
    }
  }
  final times = <String, DateTime?>{};
  for (final key in catalogDatasets) {
    times[key] = _time(roots[key]!['updated']);
  }
  final revisionBytes = utf8.encode(
    jsonEncode([
      wire.mode.name,
      for (final key in catalogDatasets) wire.datasets[key],
      for (final key in catalogTranslations) wire.localization[key],
    ]),
  );
  return CatalogSnapshot(
    mode: wire.mode,
    revision: sha256.convert(revisionBytes).toString(),
    observedAt: wire.observedAt.toUtc(),
    items: items,
    traders: traders,
    requirements: requirements,
    sourceTimestamps: times,
    localizationErrors: localizationErrors..sort(),
    datasetCounts: {
      'items': rawItems.length,
      'traders': rawTraders.length,
      'tasks': rawTasks.length,
      'hideout': rawStations.length,
      'crafts': rawCrafts.length,
      'barters': rawBarters.length,
    },
  );
}

Map<String, dynamic> _map(Object? v) {
  if (v is! Map) throw const FormatException('Invalid object');
  return Map<String, dynamic>.from(v);
}

List<dynamic> _list(Object? v) {
  if (v is! List) throw const FormatException('Invalid array');
  return v;
}

String _string(Object? v) {
  if (v is! String || v.trim().isEmpty) {
    throw const FormatException('Invalid identity');
  }
  return v;
}

List<String> _strings(Object? v) {
  final result = _list(v).map(_string).toList();
  if (result.toSet().length != result.length) {
    throw const FormatException('Duplicate reference');
  }
  return result;
}

num? _number(Object? v) {
  if (v == null) return null;
  if (v is! num || !v.isFinite) throw const FormatException('Invalid number');
  return v;
}

num? _quantity(Object? v) {
  final n = _number(v);
  if (n != null && n < 0) throw const FormatException('Invalid quantity');
  return n;
}

int? _integer(Object? v) {
  final n = _number(v);
  if (n == null) return null;
  if (n != n.roundToDouble()) throw const FormatException('Invalid integer');
  return n.toInt();
}

bool? _boolean(Object? v) {
  if (v == null) return null;
  if (v is! bool) throw const FormatException('Invalid boolean');
  return v;
}

DateTime? _time(Object? v) {
  if (v == null) return null;
  if (v is! String) throw const FormatException('Invalid timestamp');
  final time = DateTime.tryParse(v);
  if (time == null) throw const FormatException('Invalid timestamp');
  return time.toUtc();
}

Map<String, dynamic> _keyed(Object? v, {bool nonempty = false}) {
  final map = _map(v);
  if (nonempty && map.isEmpty) {
    throw const FormatException('Empty required collection');
  }
  for (final e in map.entries) {
    if (_string(_map(e.value)['id']) != e.key) {
      throw const FormatException('Mismatched identity');
    }
  }
  return map;
}

Map<String, dynamic> _arrayEntities(Object? v) {
  final result = <String, dynamic>{};
  for (final raw in _list(v)) {
    final j = _map(raw);
    final id = _string(j['id']);
    if (result.containsKey(id)) {
      throw const FormatException('Duplicate identity');
    }
    result[id] = j;
  }
  return result;
}

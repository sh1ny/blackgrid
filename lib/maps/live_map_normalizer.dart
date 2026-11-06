import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Semantic format version of the normalized live marker inventory.
///
/// Changes to normalization semantics invalidate compatible live-data caches.
const int liveMapNormalizerVersion = 1;

/// The six decoded source bodies used to normalize one coherent map snapshot.
///
/// Each body is the JSON object returned by its endpoint; source roots are
/// validated by [normalizeLiveMapData].
class LiveMapSourceBodies {
  /// Creates a bundle of decoded endpoint bodies without copying them.
  const LiveMapSourceBodies({
    required this.maps,
    required this.mapTranslations,
    required this.tasks,
    required this.taskTranslations,
    required this.traders,
    required this.traderTranslations,
  });

  /// The maps endpoint body.
  final Map<String, dynamic> maps;

  /// The English maps endpoint body.
  final Map<String, dynamic> mapTranslations;

  /// The tasks endpoint body, including quest items.
  final Map<String, dynamic> tasks;

  /// The English tasks endpoint body, including quest-item labels.
  final Map<String, dynamic> taskTranslations;

  /// The traders endpoint body.
  final Map<String, dynamic> traders;

  /// The English traders endpoint body.
  final Map<String, dynamic> traderTranslations;
}

/// Binds an upstream source identity to one prepared map and calibration.
class LiveMapBinding {
  /// Creates a prepared-map binding.
  const LiveMapBinding({
    required this.sourceKey,
    required this.mapId,
    required this.calibration,
  });

  /// The upstream normalized map identity.
  final String sourceKey;

  /// The prepared map identity used by quest locations.
  final String mapId;

  /// Prepared calibration, including conditional historical floor assignments.
  final Map<String, Object?> calibration;
}

/// Reserves recursively materialized marker data before it is emitted.
///
/// The callback can reject a candidate before marker details are copied.
/// [bytes] is a conservative accounting estimate, not serialized JSON size.
typedef LiveMapMaterializationReservation = void Function(int bytes);

const _mapCategories = [
  'extracts',
  'transits',
  'spawns',
  'locks',
  'hazards',
  'lootContainers',
  'lootLoose',
  'switches',
  'stationaryWeapons',
  'btrStops',
];

/// Normalizes a complete six-source snapshot for the prepared bindings.
///
/// Required dictionaries and consumed records fail with source-specific
/// [FormatException]s. Missing upstream maps yield empty inventories, while
/// unsupported maps are ignored. Optional quest, trader, item, and translation
/// references do not make otherwise valid source content inadmissible.
///
/// [mode] is the endpoint route: `regular`, `pve`, or `pvp-season`. The same
/// route is retained in map and quest provenance.
///
/// [reserveMaterialization] is called before each emitted marker is built and
/// can enforce a caller-owned expansion budget.
Map<String, List<Map<String, Object?>>> normalizeLiveMapData({
  required LiveMapSourceBodies sources,
  required Iterable<LiveMapBinding> bindings,
  required String mode,
  LiveMapMaterializationReservation? reserveMaterialization,
}) {
  final route = _modeRoute(mode);
  final mapsUrl = 'https://json.tarkov.dev/$route/maps';
  final mapsData = _requiredData(sources.maps, 'markers/maps.json');
  final maps = _requiredDictionary(mapsData, 'maps', 'markers/maps.json');
  final mapTranslations = _requiredData(
    sources.mapTranslations,
    'markers/maps_en.json',
  );
  final tasksData = _requiredData(sources.tasks, 'quests/tasks.json');
  final tasks = _requiredDictionary(tasksData, 'tasks', 'quests/tasks.json');
  final questItems = _requiredDictionary(
    tasksData,
    'questItems',
    'quests/tasks.json',
  );
  final taskTranslations = _requiredData(
    sources.taskTranslations,
    'quests/tasks_en.json',
  );
  final traders = _requiredData(sources.traders, 'quests/traders.json');
  final traderTranslations = _requiredData(
    sources.traderTranslations,
    'quests/traders_en.json',
  );

  final bySource = <String, LiveMapBinding>{};
  final mapIds = <String>{};
  for (final binding in bindings) {
    if (bySource.containsKey(binding.sourceKey)) {
      throw FormatException(
        'Duplicate prepared source identity: ${binding.sourceKey}',
      );
    }
    if (!mapIds.add(binding.mapId)) {
      throw FormatException(
        'Duplicate prepared map identity: ${binding.mapId}',
      );
    }
    bySource[binding.sourceKey] = binding;
  }
  final output = <String, List<Map<String, Object?>>>{};
  for (final binding in bySource.values) {
    final calibration = <String, Object?>{
      ...binding.calibration,
      'sourceKey': binding.sourceKey,
    };
    final mapMarkers = _prepareMapMarkers(
      sourceData: mapsData,
      sourceMaps: maps,
      translations: mapTranslations,
      calibration: calibration,
      reserveMaterialization: reserveMaterialization,
      sourceUrl: mapsUrl,
    );
    final hasSourceMap = maps.values.any(
      (raw) => raw is Map && raw['normalizedName'] == binding.sourceKey,
    );
    if (!hasSourceMap) {
      output[binding.mapId] = List.unmodifiable(mapMarkers);
      continue;
    }
    String questMapId = binding.mapId;
    for (final raw in maps.values) {
      if (raw is Map && raw['normalizedName'] == binding.sourceKey) {
        final sourceId = raw['id'];
        if (sourceId is String && sourceId.isNotEmpty) questMapId = sourceId;
        break;
      }
    }
    final questMarkers = prepareQuestMarkers(
      mapId: questMapId,
      tasks: tasks,
      translations: taskTranslations,
      traders: traders,
      traderTranslations: traderTranslations,
      questItems: questItems,
      questItemTranslations: taskTranslations,
      mode: mode,
      reserveMaterialization: reserveMaterialization,
    );
    output[binding.mapId] = List.unmodifiable([...mapMarkers, ...questMarkers]);
  }
  return Map.unmodifiable(output);
}

/// Projects regular-map marker facts from one maps source body.
///
/// This lower-level entry point is shared by pack construction and focused
/// source-fidelity tests. [mode] selects the source route retained in marker
/// provenance. A missing supported source map produces no map markers; a
/// duplicate identity or malformed present consumed record fails.
List<Map<String, Object?>> prepareMarkers(
  Map<String, dynamic> snapshot,
  Map<String, dynamic> translations,
  Map<String, Object?> calibration, {
  String mode = 'regular',
  LiveMapMaterializationReservation? reserveMaterialization,
}) {
  final mapsUrl = 'https://json.tarkov.dev/${_modeRoute(mode)}/maps';
  final sourceKey = calibration['sourceKey'];
  if (sourceKey is! String || sourceKey.isEmpty) {
    throw const FormatException('Prepared calibration lacks sourceKey');
  }
  final data = _requiredData(snapshot, 'markers/maps.json');
  final maps = _requiredDictionary(data, 'maps', 'markers/maps.json');
  return _prepareMapMarkers(
    sourceData: data,
    sourceMaps: maps,
    translations: translations,
    calibration: calibration,
    reserveMaterialization: reserveMaterialization,
    sourceUrl: mapsUrl,
  );
}

List<Map<String, Object?>> _prepareMapMarkers({
  required Map<String, dynamic> sourceData,
  required Map<String, dynamic> sourceMaps,
  required Map<String, dynamic> translations,
  required Map<String, Object?> calibration,
  required LiveMapMaterializationReservation? reserveMaterialization,
  required String sourceUrl,
}) {
  final sourceKey = calibration['sourceKey'] as String;
  FormatException sourceError(String path, String fact, String reason) =>
      FormatException('markers/maps.json: $sourceKey/$path: $fact $reason');
  Map<String, dynamic>? source;
  var matches = 0;
  for (final record in sourceMaps.values) {
    if (record is Map && record['normalizedName'] == sourceKey) {
      if (record is! Map<String, dynamic>) {
        throw sourceError('maps', 'normalizedName', 'map record is malformed');
      }
      source = record;
      matches++;
    }
  }
  if (matches > 1) {
    throw sourceError(
      'maps',
      'normalizedName',
      'duplicate supported map identity $sourceKey',
    );
  }
  if (matches == 0) return const [];
  final selectedSource = source!;
  if (selectedSource['id'] is! String ||
      (selectedSource['id'] as String).isEmpty) {
    throw sourceError('id', 'id', 'must be a nonempty source identity');
  }

  final floorAssignments = switch (calibration['markerFloorAssignments']) {
    Map<String, Object?> value => value,
    null => const <String, Object?>{},
    _ => throw sourceError(
      'markerFloorAssignments',
      'markerFloorAssignments',
      'must be a dictionary',
    ),
  };
  final result = <Map<String, Object?>>[];
  final identityCounts = <String, int>{};
  void add(
    String category,
    Map<String, dynamic> entry,
    String sourcePath, {
    String? label,
  }) {
    final position = entry['position'];
    if (position is! Map ||
        position['x'] is! num ||
        !(position['x'] as num).isFinite ||
        position['z'] is! num ||
        !(position['z'] as num).isFinite ||
        (position['y'] != null &&
            (position['y'] is! num || !(position['y'] as num).isFinite))) {
      throw sourceError(
        sourcePath,
        'position',
        'must contain finite x, z and optional y',
      );
    }
    final name =
        label ??
        entry['name'] ??
        entry['zoneName'] ??
        entry['hazardType'] ??
        entry['description'] ??
        category;
    if (name is! String || name.isEmpty) {
      throw sourceError(sourcePath, 'name', 'must be a string');
    }
    final identity =
        '$category:${entry['id'] ?? _fallbackIdentity(sourceKey, entry)}';
    final occurrence = identityCounts.update(
      identity,
      (count) => count + 1,
      ifAbsent: () => 0,
    );
    final markerId = '$identity:$occurrence';
    final translatedName = _translatedMapName(name, translations, sourcePath);
    final candidateAssignment = floorAssignments[markerId];
    final floorAssignment =
        candidateAssignment is Map<String, Object?> &&
            _overrideMatches(sourceKey, entry, candidateAssignment)
        ? candidateAssignment
        : null;
    final rawOutline = entry['outline'];
    final outline = rawOutline == null
        ? null
        : _sourceList(
            rawOutline,
            sourceError(sourcePath, 'outline', 'must be an array'),
          );

    reserveMaterialization?.call(
      _materializedSize({
        'id': markerId,
        'category': category,
        'name': translatedName,
        'position': {
          'x': position['x'],
          'z': position['z'],
          'height': position['y'],
        },
        'source': {
          'url': sourceUrl,
          'mapId': selectedSource['id'],
          'path': sourcePath,
          'floorAssignment': floorAssignment,
        },
        'details': entry,
        'outline': outline,
        'heightBand': [entry['bottom'], entry['top']],
      }),
    );
    result.add({
      'id': markerId,
      'category': category,
      'name': translatedName,
      'position': {
        'x': position['x'],
        'z': position['z'],
        'height': position['y'],
      },
      if (floorAssignment != null) 'floorId': floorAssignment['floorId'],
      'source': {
        'url': sourceUrl,
        'mapId': selectedSource['id'],
        'path': sourcePath,
        'floorAssignment': ?floorAssignment,
      },
      'details': entry,
      if (outline != null)
        'outline': [
          for (var i = 0; i < outline.length; i++)
            _outlinePoint(outline[i], '$sourcePath/outline/$i', sourceError),
        ],
      if (entry['bottom'] is num && entry['top'] is num)
        'heightBand': [entry['bottom'], entry['top']],
    });
  }

  for (final category in _mapCategories) {
    final rawEntries = selectedSource[category];
    if (rawEntries == null) continue;
    if (rawEntries is! List) {
      throw sourceError(category, category, 'must be an array');
    }
    for (var i = 0; i < rawEntries.length; i++) {
      final raw = rawEntries[i];
      if (raw is! Map<String, dynamic>) {
        throw sourceError(
          '$category/$i',
          category,
          'entry must be a dictionary',
        );
      }
      String? label;
      if (category == 'lootContainers') {
        label = _optionalLabel(
          sourceData,
          'lootContainers',
          raw['lootContainer'],
          '$category/$i',
          sourceError,
        );
      } else if (category == 'stationaryWeapons') {
        label = _optionalLabel(
          sourceData,
          'stationaryWeapons',
          raw['stationaryWeapon'],
          '$category/$i',
          sourceError,
        );
      }
      final entry = category == 'btrStops'
          ? {
              ...raw,
              'position': {'x': raw['x'], 'y': raw['y'], 'z': raw['z']},
            }
          : raw;
      add(category, entry, '$category/$i', label: label);
    }
  }

  final rawBosses = selectedSource['bosses'];
  if (rawBosses == null) {
    throw sourceError('bosses', 'bosses', 'must be an array');
  }
  if (rawBosses is! List) {
    throw sourceError('bosses', 'bosses', 'must be an array');
  }
  final rawMobs = sourceData['mobs'];
  for (var b = 0; b < rawBosses.length; b++) {
    final bossPath = 'bosses/$b';
    final rawBoss = rawBosses[b];
    if (rawBoss is! Map) {
      throw sourceError(bossPath, 'boss', 'must be a dictionary');
    }
    final mobId = rawBoss['mob'];
    if (mobId is! String || mobId.trim().isEmpty) {
      throw sourceError(
        '$bossPath/mob',
        'mob',
        'must be a nonempty identifier',
      );
    }
    if (rawMobs is! Map) {
      throw sourceError('$bossPath/mob', 'mobs', 'must be a dictionary');
    }
    final mob = rawMobs[mobId];
    if (mob is! Map ||
        mob['name'] is! String ||
        (mob['name'] as String).trim().isEmpty) {
      throw sourceError(
        '$bossPath/mob',
        'name',
        'resolved mob record $mobId is missing or malformed',
      );
    }
    final chance = rawBoss['spawnChance'];
    if (chance is! num || !chance.isFinite || chance < 0 || chance > 1) {
      throw sourceError(
        '$bossPath/spawnChance',
        'spawnChance',
        'must be a finite probability in [0, 1]',
      );
    }
    final locations = rawBoss['spawnLocations'];
    if (locations is! List) {
      throw sourceError(
        '$bossPath/spawnLocations',
        'spawnLocations',
        'must be an array',
      );
    }
    for (var l = 0; l < locations.length; l++) {
      final path = '$bossPath/spawnLocations/$l';
      final location = locations[l];
      if (location is! Map ||
          location['name'] is! String ||
          (location['name'] as String).trim().isEmpty ||
          location['positions'] is! List) {
        throw sourceError(
          path,
          'spawnLocations',
          'entry must have a name and positions array',
        );
      }
      final positions = location['positions'] as List;
      for (var p = 0; p < positions.length; p++) {
        final point = positions[p];
        if (point is! Map)
          throw sourceError(
            '$path/positions/$p',
            'position',
            'must be a dictionary',
          );
        for (final axis in ['x', 'z']) {
          if (point[axis] is! num || !(point[axis] as num).isFinite) {
            throw sourceError(
              '$path/positions/$p/$axis',
              axis,
              'must be a finite number',
            );
          }
        }
        final height = point['y'];
        if (height != null && (height is! num || !height.isFinite)) {
          throw sourceError(
            '$path/positions/$p/y',
            'y',
            'must be null or a finite number',
          );
        }
        add(
          'bosses',
          {
            'position': point,
            'mob': mobId,
            'spawnChance': chance,
            'location': location['name'],
          },
          '$path/positions/$p',
          label: mob['name'] as String,
        );
      }
    }
  }
  return result;
}

/// Projects quest and quest-item positions from the frozen task dictionaries.
///
/// Missing optional referenced records and translations are omitted rather
/// than rejecting otherwise valid task content. [mode] selects the source
/// route retained in marker provenance.
List<Map<String, Object?>> prepareQuestMarkers({
  required String mapId,
  required Map<String, dynamic> tasks,
  required Map<String, dynamic> translations,
  required Map<String, dynamic> traders,
  required Map<String, dynamic> traderTranslations,
  required Map<String, dynamic> questItems,
  required Map<String, dynamic> questItemTranslations,
  String mode = 'regular',
  LiveMapMaterializationReservation? reserveMaterialization,
}) {
  _requiredString(mapId, 'mapId');
  final sourceUrl = 'https://json.tarkov.dev/${_modeRoute(mode)}/tasks';
  final markers = <Map<String, Object?>>[];
  for (final taskEntry in tasks.entries) {
    final task = _requiredObject(
      taskEntry.value,
      'quests/tasks.json: tasks/${taskEntry.key}',
    );
    final taskId = _requiredString(task['id'], 'tasks/${taskEntry.key}/id');
    if (taskId != taskEntry.key) {
      throw FormatException(
        'quests/tasks.json: task identity mismatch ${taskEntry.key}/$taskId',
      );
    }
    final objectives = _requiredList(
      task['objectives'],
      'tasks/$taskId/objectives',
    );
    for (var o = 0; o < objectives.length; o++) {
      final path = 'tasks/$taskId/objectives/$o';
      final objective = _requiredObject(objectives[o], path);
      final zones = objective['zones'];
      if (zones != null) {
        final entries = _requiredList(zones, '$path/zones');
        for (var z = 0; z < entries.length; z++) {
          final zonePath = '$path/zones/$z';
          final zone = _requiredObject(entries[z], zonePath);
          if (_requiredString(zone['map'], '$zonePath/map') != mapId) continue;
          final taskNameKey = _requiredString(
            task['name'],
            'tasks/$taskId/name',
          );
          final description = _translatedOptional(
            objective['description'],
            translations,
            'quests/tasks_en.json',
            '$path/description',
          );
          final traderId = task['trader'];
          final trader = _optionalReferencedObject(
            traders,
            traderId,
            'trader',
            'tasks/$taskId/trader',
          );
          final traderFact = trader == null
              ? null
              : {
                  'id': traderId,
                  if (_translatedOptional(
                        trader['name'],
                        traderTranslations,
                        'quests/traders_en.json',
                        'traders/${trader['id']}/name',
                      )
                      case final String name)
                    'name': name,
                };
          final questName = _translatedOptional(
            taskNameKey,
            translations,
            'quests/tasks_en.json',
            'tasks/$taskId/name',
          );
          final wikiLink = _requiredString(
            task['wikiLink'],
            'tasks/$taskId/wikiLink',
          );
          final objectiveId = _requiredString(objective['id'], '$path/id');
          final zoneId = _requiredString(zone['id'], '$zonePath/id');
          final position = _questPosition(
            zone['position'],
            '$zonePath/position',
          );
          final itemId = _optionalIdentity(
            objective['questItem'],
            '$path/questItem',
          );
          final item = _optionalReferencedObject(
            questItems,
            itemId,
            'quest item',
            '$path/questItem',
          );
          final itemName = _translatedOptional(
            item?['name'],
            questItemTranslations,
            'quests/tasks_en.json',
            '$path/questItem/name',
          );
          final identity = {
            'taskId': taskId,
            'objectiveId': objectiveId,
            'objectiveIndex': o,
            if (itemId != null) 'questItemId': itemId,
            'zoneId': zoneId,
            'zoneIndex': z,
          };
          final id =
              'questObjectives:${[mapId, taskId, objectiveId, '$o', zoneId, '$z'].map(Uri.encodeComponent).join(':')}';
          reserveMaterialization?.call(
            _materializedSize({
              'task': task,
              'objective': objective,
              'zone': zone,
              'trader': trader,
              'item': item,
              'questItemName': itemName,
              'quest': {
                'id': taskId,
                'name': questName,
                'trader': traderFact,
                'wikiLink': wikiLink,
              },
              'position': position,
              'outline': zone['outline'],
              'heightBand': zone['bottom'] == null && zone['top'] == null
                  ? null
                  : [zone['bottom'], zone['top']],
            }),
          );
          markers.add({
            'id': id,
            'category': 'questObjectives',
            'filterKey': 'QuestObjectives',
            'name': description ?? 'questObjectives',
            'position': position,
            'source': {
              'url': sourceUrl,
              'mapId': mapId,
              'path': zonePath,
              'originalIdentity': identity,
            },
            'details': {
              'id': objectiveId,
              'quest': {
                'id': taskId,
                if (questName != null) 'name': questName,
                if (traderFact != null) 'trader': traderFact,
                'wikiLink': wikiLink,
              },
              'objective': objective,
              if (description != null) 'description': description,
              'sourceTask': task,
              'sourceTrader': trader,
              'location': zone,
              if (item != null) 'item': item,
              if (item != null && itemName != null)
                'questItem': {...item, 'name': itemName},
            },
            if (zone['outline'] != null)
              'outline': _questOutline(zone['outline'], '$zonePath/outline'),
            if (_heightBand(zone, zonePath) case final List<double> band)
              'heightBand': band,
          });
        }
      }
      final locations = objective['possibleLocations'];
      if (locations != null) {
        final entries = _requiredList(locations, '$path/possibleLocations');
        for (var l = 0; l < entries.length; l++) {
          final locationPath = '$path/possibleLocations/$l';
          final location = _requiredObject(entries[l], locationPath);
          if (_requiredString(location['map'], '$locationPath/map') != mapId)
            continue;
          final taskNameKey = _requiredString(
            task['name'],
            'tasks/$taskId/name',
          );
          final positions = _requiredList(
            location['positions'],
            '$locationPath/positions',
          );
          final itemId = _optionalIdentity(
            objective['questItem'],
            '$path/questItem',
          );
          final item = positions.isEmpty
              ? null
              : _optionalReferencedObject(
                  questItems,
                  itemId,
                  'quest item',
                  '$path/questItem',
                );
          for (var p = 0; p < positions.length; p++) {
            final sourcePath = '$locationPath/positions/$p';
            final position = _questPosition(positions[p], sourcePath);
            final itemName = _translatedOptional(
              item?['name'],
              questItemTranslations,
              'quests/tasks_en.json',
              '$path/questItem/name',
            );
            final description = _translatedOptional(
              objective['description'],
              translations,
              'quests/tasks_en.json',
              '$path/description',
            );
            final traderId = task['trader'];
            final trader = _optionalReferencedObject(
              traders,
              traderId,
              'trader',
              'tasks/$taskId/trader',
            );
            final traderName = _translatedOptional(
              trader?['name'],
              traderTranslations,
              'quests/traders_en.json',
              'traders/${trader?['id']}/name',
            );
            final questName = _translatedOptional(
              taskNameKey,
              translations,
              'quests/tasks_en.json',
              'tasks/$taskId/name',
            );
            final wikiLink = _requiredString(
              task['wikiLink'],
              'tasks/$taskId/wikiLink',
            );
            final objectiveId = _requiredString(objective['id'], '$path/id');
            final identity = {
              'taskId': taskId,
              'objectiveId': objective['id'],
              'objectiveIndex': o,
              'questItemId': itemId,
              'locationIndex': l,
              'positionIndex': p,
            };
            final idParts = [
              mapId,
              taskId,
              objectiveId,
              '$o',
              itemId ?? '',
              '$l',
              '$p',
            ];
            reserveMaterialization?.call(
              _materializedSize({
                'task': task,
                'objective': objective,
                'location': location,
                'trader': trader,
                'item': item,
                'questItem': item,
                'questItemName': itemName,
                'quest': {
                  'id': taskId,
                  'name': questName,
                  'trader': trader,
                  'wikiLink': wikiLink,
                },
                'position': position,
                'outline': location['outline'],
                'heightBand':
                    location['bottom'] == null && location['top'] == null
                    ? null
                    : [location['bottom'], location['top']],
              }),
            );
            markers.add({
              'id': 'questItems:${idParts.map(Uri.encodeComponent).join(':')}',
              'category': 'questItems',
              'filterKey': 'QuestItems',
              'name': itemName ?? 'questItems',
              'position': position,
              'source': {
                'url': sourceUrl,
                'mapId': mapId,
                'path': sourcePath,
                'originalIdentity': identity,
              },
              'details': {
                'id': objectiveId,
                'quest': {
                  'id': taskId,
                  if (questName != null) 'name': questName,
                  if (trader != null)
                    'trader': {
                      'id': traderId,
                      if (traderName != null) 'name': traderName,
                    },
                  'wikiLink': wikiLink,
                },
                'objective': objective,
                if (description != null) 'description': description,
                'sourceTask': task,
                'sourceTrader': trader,
                'location': location,
                if (item != null) 'item': item,
                if (item != null && itemName != null)
                  'questItem': {...item, 'name': itemName},
              },
              if (location['outline'] != null)
                'outline': _questOutline(
                  location['outline'],
                  '$locationPath/outline',
                ),
              if (_heightBand(location, locationPath)
                  case final List<double> band)
                'heightBand': band,
            });
          }
        }
      }
    }
  }
  return markers;
}

Map<String, dynamic> _requiredData(Map<String, dynamic> body, String source) {
  final value = body['data'];
  if (value is! Map<String, dynamic>) {
    throw FormatException('$source: data must be a dictionary');
  }
  return value;
}

Map<String, dynamic> _requiredDictionary(
  Map<String, dynamic> body,
  String key,
  String source,
) {
  final value = body[key];
  if (value is! Map<String, dynamic>) {
    throw FormatException('$source: data.$key must be a dictionary');
  }
  return value;
}

String _fallbackIdentity(String sourceKey, Map<String, dynamic> entry) {
  final canonical = _canonicalJson(entry);
  return sha256
      .convert(utf8.encode('$sourceKey/$canonical'))
      .toString()
      .substring(0, 20);
}

String _canonicalJson(Object? value) => canonicalJson(value);

/// Serializes values with recursively sorted map keys and preserved list order.
///
/// The indented representation is shared with frozen map-pack generation so
/// fallback marker identities remain stable across the parser cutover.
String canonicalJson(Object? value) {
  Object? ordered(Object? input) {
    if (input is Map) {
      final keys = input.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: ordered(input[key])};
    }
    if (input is List) return input.map(ordered).toList();
    return input;
  }

  return '${const JsonEncoder.withIndent('  ').convert(ordered(value))}\n';
}

bool _overrideMatches(
  String sourceKey,
  Map<String, dynamic> entry,
  Map<String, Object?> assignment,
) {
  final position = entry['position'];
  if (position is! Map) return false;
  if (sourceKey == 'interchange') {
    final volume = assignment['sourceVolume'];
    return volume is Map &&
        _canonicalJson(volume) ==
            _canonicalJson({
              'position': position,
              'heightBand': [entry['bottom'], entry['top']],
              'outline': entry['outline'],
            });
  }
  if (sourceKey == 'icebreaker') {
    final markerId = entry['id'];
    if (markerId == '9bf65c4c24d0153f1542a90ddabadb37198ab9ff') {
      return assignment['floorId'] == 'Helipad' &&
          position['x'] == .28 &&
          position['y'] == 22.56 &&
          position['z'] == -66.03;
    }
    if (markerId == 'f680d37a9e9c4f7b4673a2cd1bedd4a8ed73e104') {
      return assignment['floorId'] == 'Officers_Deck' &&
          entry['key'] == assignment['keyId'] &&
          assignment['keyId'] == '69bb3f278af9f360ee010a7a' &&
          position['x'] == -5.25 &&
          position['y'] == 35.64 &&
          position['z'] == 28.39;
    }
  }
  return false;
}

String? _optionalLabel(
  Map<String, dynamic> data,
  String dictionary,
  Object? id,
  String path,
  FormatException Function(String, String, String) sourceError,
) {
  final source = data[dictionary];
  if (source == null) return null;
  if (source is! Map) {
    throw sourceError(dictionary, dictionary, 'must be a dictionary');
  }
  if (id == null) return null;
  final value = source[id];
  if (value == null) return null;
  if (value is! Map || value['name'] is! String) {
    throw sourceError(path, dictionary, 'referenced record is malformed');
  }
  return value['name'] as String;
}

List _sourceList(Object? value, FormatException error) {
  if (value is! List) throw error;
  return value;
}

Map<String, Object?> _outlinePoint(
  Object? value,
  String path,
  FormatException Function(String, String, String) sourceError,
) {
  if (value is! Map ||
      value['x'] is! num ||
      value['y'] is! num ||
      value['z'] is! num ||
      !(value['x'] as num).isFinite ||
      !(value['y'] as num).isFinite ||
      !(value['z'] as num).isFinite) {
    throw sourceError(path, 'outline point', 'must have finite x, y and z');
  }
  return {'x': value['x'], 'z': value['z'], 'height': value['y']};
}

Map<String, dynamic> _requiredObject(Object? value, String path) {
  if (value is! Map<String, dynamic>) {
    throw FormatException(
      'quests/tasks.json: $path: expected a source dictionary',
    );
  }
  return value;
}

Map<String, dynamic>? _optionalReferencedObject(
  Map<String, dynamic> records,
  Object? id,
  String kind,
  String path,
) {
  if (id == null) return null;
  if (id is! String || id.trim().isEmpty) {
    throw FormatException(
      'quests/tasks.json: $path: $kind identity must be a nonempty string',
    );
  }
  final value = records[id];
  if (value == null) return null;
  if (value is! Map<String, dynamic> || value['id'] != id) {
    throw FormatException(
      'quests/tasks.json: $path: referenced $kind record $id is malformed',
    );
  }
  return value;
}

List<dynamic> _requiredList(Object? value, String path) {
  if (value is! List) {
    throw FormatException('quests/tasks.json: $path: expected a source array');
  }
  return value;
}

String? _optionalIdentity(Object? value, String path) {
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw FormatException(
      'quests/tasks.json: $path: reference identity must be a nonempty string',
    );
  }
  return value;
}

String _requiredString(Object? value, String path) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException(
      'quests/tasks.json: $path: expected a nonempty string',
    );
  }
  return value;
}

String _modeRoute(String mode) => switch (mode) {
  'regular' || 'pve' || 'pvp-season' => mode,
  _ => throw FormatException('Unsupported map-data mode route: $mode'),
};

String _translatedMapName(
  String name,
  Map<String, dynamic> translations,
  String path,
) {
  final translated = translations[name];
  if (translated == null) return name;
  if (translated is! String || translated.isEmpty) {
    throw FormatException(
      'markers/maps_en.json: $path: translation must be a nonempty string',
    );
  }
  return translated;
}

String? _translatedOptional(
  Object? key,
  Map<String, dynamic> translations,
  String source,
  String path,
) {
  if (key == null) return null;
  if (key is! String || key.trim().isEmpty) {
    throw FormatException(
      '$source: $path: translation identity must be a nonempty string',
    );
  }
  final value = translations[key];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw FormatException(
      '$source: $path: translation must be a nonempty string',
    );
  }
  return value;
}

Map<String, Object?> _questPosition(Object? value, String path) {
  final point = _requiredObject(value, path);
  final x = _finiteNumber(point['x'], '$path/x');
  final z = _finiteNumber(point['z'], '$path/z');
  final y = point['y'] == null ? null : _finiteNumber(point['y'], '$path/y');
  return {'x': x, 'z': z, 'height': y};
}

double _finiteNumber(Object? value, String path) {
  if (value is! num || !value.isFinite) {
    throw FormatException('quests/tasks.json: $path: expected a finite number');
  }
  final number = value.toDouble();
  if (!number.isFinite) {
    throw FormatException('quests/tasks.json: $path: expected a finite number');
  }
  return number;
}

List<Map<String, Object?>> _questOutline(Object? value, String path) {
  final points = _requiredList(value, path);
  return [
    for (var i = 0; i < points.length; i++)
      _questPosition(points[i], '$path/$i'),
  ];
}

List<double>? _heightBand(Map<String, dynamic> location, String path) {
  final bottom = location['bottom'];
  final top = location['top'];
  if (bottom == null && top == null) return null;
  final lower = _finiteNumber(bottom, '$path/bottom');
  final upper = _finiteNumber(top, '$path/top');
  if (lower > upper) {
    throw FormatException('quests/tasks.json: $path: reversed height band');
  }
  return [lower, upper];
}

int _materializedSize(Object? value) {
  var total = 0;
  void charge(Object? current) {
    if (current == null || current is bool || current is num) {
      total += 16;
    } else if (current is String) {
      total += 24 + current.length * 2;
    } else if (current is List) {
      total += 24 + current.length * 16;
      for (final entry in current) charge(entry);
    } else if (current is Map) {
      total += 48 + current.length * 32;
      for (final entry in current.entries) {
        charge(entry.key);
        charge(entry.value);
      }
    } else {
      total += 32;
    }
  }

  charge(value);
  return total;
}

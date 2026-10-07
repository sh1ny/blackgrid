const _tasksUrl = 'https://json.tarkov.dev/regular/tasks';

// Inputs are frozen endpoint dictionaries: tasks.data.tasks, tasks_en.data,
// traders.data, traders_en.data, tasks.data.questItems and tasks_en.data.
List<Map<String, Object?>> prepareQuestMarkers({
  required String mapId,
  required Map<String, dynamic> tasks,
  required Map<String, dynamic> translations,
  required Map<String, dynamic> traders,
  required Map<String, dynamic> traderTranslations,
  required Map<String, dynamic> questItems,
  required Map<String, dynamic> questItemTranslations,
}) {
  _string(mapId, 'mapId');
  final markers = <Map<String, Object?>>[];
  for (final taskEntry in tasks.entries) {
    final task = _object(taskEntry.value, 'tasks/${taskEntry.key}');
    final taskId = _string(task['id'], 'task id');
    if (taskId != taskEntry.key) {
      throw FormatException('Task identity mismatch: ${taskEntry.key}/$taskId');
    }
    final objectives = _list(task['objectives'], 'tasks/$taskId/objectives');
    Map<String, Object?>? quest;
    Map<String, dynamic>? trader;
    for (var o = 0; o < objectives.length; o++) {
      final path = 'tasks/$taskId/objectives/$o';
      final objective = _object(objectives[o], path);
      String? objectiveId;
      String? description;
      Map<String, dynamic>? item;
      String? itemName;

      void add({
        required String category,
        required Map<String, dynamic> location,
        required Object? position,
        required String sourcePath,
        required Map<String, Object?> originalIdentity,
      }) {
        objectiveId ??= _string(objective['id'], '$path/id');
        description ??= _translated(
          objective['description'],
          translations,
          '$path/description',
        );
        if (quest == null) {
          final traderId = _string(task['trader'], 'tasks/$taskId/trader');
          trader = _dependency(traders, traderId, 'trader');
          quest = {
            'id': taskId,
            'name': _translated(
              task['name'],
              translations,
              'tasks/$taskId/name',
            ),
            'trader': {
              'id': traderId,
              'name': _translated(
                trader!['name'],
                traderTranslations,
                'trader/$traderId/name',
              ),
            },
            'wikiLink': _string(task['wikiLink'], 'tasks/$taskId/wikiLink'),
          };
        }
        final isItem = category == 'questItems';
        if ((isItem || objective['questItem'] != null) && item == null) {
          final itemId = _string(objective['questItem'], '$path/questItem');
          item = _dependency(questItems, itemId, 'quest item');
          itemName = _translated(
            item!['name'],
            questItemTranslations,
            'questItems/$itemId/name',
          );
        }
        final identity = {
          'taskId': taskId,
          'objectiveId': objectiveId,
          'objectiveIndex': o,
          if (item != null) 'questItemId': item!['id'],
          ...originalIdentity,
        };
        // Explicit source indices disambiguate repeated zones, objectives and
        // identical item positions without depending on translated labels.
        final idParts = [
          mapId,
          taskId,
          objectiveId!,
          '$o',
          if (isItem) ...[
            _string(objective['questItem'], '$path/questItem'),
            '${originalIdentity['locationIndex']}',
            '${originalIdentity['positionIndex']}',
          ] else ...[
            _string(location['id'], '$sourcePath/id'),
            '${originalIdentity['zoneIndex']}',
          ],
        ];
        final outline = location['outline'];
        final bottom = location['bottom'];
        final top = location['top'];
        List<double>? band;
        if (bottom != null || top != null) {
          final lower = _number(bottom, '$sourcePath/bottom');
          final upper = _number(top, '$sourcePath/top');
          if (lower > upper) {
            throw FormatException('Reversed quest height band: $sourcePath');
          }
          band = [lower, upper];
        }
        markers.add({
          'id': '$category:${idParts.map(Uri.encodeComponent).join(':')}',
          'category': category,
          'filterKey': isItem ? 'QuestItems' : 'QuestObjectives',
          'name': isItem ? itemName : description,
          'position': _position(position, sourcePath),
          'source': {
            'url': _tasksUrl,
            'mapId': mapId,
            'path': sourcePath,
            'originalIdentity': identity,
          },
          'details': {
            'id': objectiveId,
            'quest': quest,
            'objective': objective,
            'description': description,
            // Keep original localization keys and all source conditions, but
            // do not expose raw keys as a second display quest/trader.
            'sourceTask': task,
            'sourceTrader': trader,
            'location': location,
            'item': ?item,
            if (item != null) 'questItem': {...item!, 'name': itemName},
          },
          if (outline != null)
            'outline': [
              for (final point in _list(outline, '$sourcePath/outline'))
                _position(point, '$sourcePath/outline'),
            ],
          'heightBand': ?band,
        });
      }

      final zones = objective['zones'];
      if (zones != null) {
        final entries = _list(zones, '$path/zones');
        for (var z = 0; z < entries.length; z++) {
          final sourcePath = '$path/zones/$z';
          final zone = _object(entries[z], sourcePath);
          if (_string(zone['map'], '$sourcePath/map') != mapId) continue;
          final zoneId = _string(zone['id'], '$sourcePath/id');
          add(
            category: 'questObjectives',
            location: zone,
            position: zone['position'],
            sourcePath: sourcePath,
            originalIdentity: {'zoneId': zoneId, 'zoneIndex': z},
          );
        }
      }
      final locations = objective['possibleLocations'];
      if (locations != null) {
        final entries = _list(locations, '$path/possibleLocations');
        for (var l = 0; l < entries.length; l++) {
          final locationPath = '$path/possibleLocations/$l';
          final location = _object(entries[l], locationPath);
          if (_string(location['map'], '$locationPath/map') != mapId) continue;
          final positions = _list(
            location['positions'],
            '$locationPath/positions',
          );
          for (var p = 0; p < positions.length; p++) {
            add(
              category: 'questItems',
              location: location,
              position: positions[p],
              sourcePath: '$locationPath/positions/$p',
              originalIdentity: {
                'questItemId': _string(
                  objective['questItem'],
                  '$path/questItem',
                ),
                'locationIndex': l,
                'positionIndex': p,
              },
            );
          }
        }
      }
    }
  }
  return markers;
}

Map<String, dynamic> _dependency(
  Map<String, dynamic> values,
  String id,
  String kind,
) {
  final value = _object(values[id], 'Missing $kind dependency: $id');
  if (value['id'] != id) {
    throw FormatException('$kind identity mismatch: $id/${value['id']}');
  }
  return value;
}

String _translated(
  Object? key,
  Map<String, dynamic> translations,
  String path,
) {
  final identity = _string(key, '$path localization key');
  return _string(
    translations[identity],
    'Missing translation: $path ($identity)',
  );
}

Map<String, Object?> _position(Object? value, String path) {
  final point = _object(value, 'Missing real quest coordinates: $path');
  return {
    'x': _number(point['x'], '$path/x'),
    'z': _number(point['z'], '$path/z'),
    'height': point['y'] == null ? null : _number(point['y'], '$path/y'),
  };
}

double _number(Object? value, String path) {
  if (value is! num || !value.isFinite) {
    throw FormatException('Missing finite quest coordinate: $path');
  }
  final result = value.toDouble();
  if (!result.isFinite) {
    throw FormatException('Nonfinite quest coordinate: $path');
  }
  return result;
}

String _string(Object? value, String path) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Expected nonempty string: $path');
  }
  return value;
}

Map<String, dynamic> _object(Object? value, String path) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('Expected quest source object: $path');
  }
  return value;
}

List<dynamic> _list(Object? value, String path) {
  if (value is! List) {
    throw FormatException('Expected quest source list: $path');
  }
  return value;
}

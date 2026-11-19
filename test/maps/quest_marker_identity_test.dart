import 'package:blackgrid/domain/map_marker_query.dart';
import 'package:blackgrid/maps/live_map_normalizer.dart'
    show prepareQuestMarkers;
import 'package:blackgrid_progress/blackgrid_progress.dart';
import 'package:test/test.dart';

/// One task with a zone objective and a quest-item objective on `source-customs`.
Map<String, dynamic> _tasksBody() => {
  'tasks': <String, dynamic>{
    'task-1': <String, dynamic>{
      'id': 'task-1',
      'name': 'task-1 name',
      'trader': 'trader-1',
      'wikiLink': 'https://example.invalid/task-1',
      'objectives': <Object?>[
        {
          'id': 'obj-zone',
          'type': 'visit',
          'zones': [
            {
              'id': 'zone-1',
              'map': 'source-customs',
              'position': {'x': 4, 'y': 5, 'z': 6},
            },
          ],
        },
        {
          'id': 'obj-item',
          'type': 'findQuestItem',
          'questItem': 'item-1',
          'possibleLocations': [
            {
              'map': 'source-customs',
              'positions': [
                {'x': 7, 'y': 8, 'z': 9},
              ],
            },
          ],
        },
      ],
    },
  },
};

void main() {
  test(
    'quest markers carry the task and objective IDs of the progress catalog',
    () {
      final body = _tasksBody();
      final catalog = parseProgressCatalog(
        body,
        <String, dynamic>{},
        {'trader-1'},
        null,
        null,
      );
      final markers = prepareQuestMarkers(
        mapId: 'source-customs',
        tasks: body['tasks'] as Map<String, dynamic>,
        questItems: {
          'item-1': {'id': 'item-1', 'name': 'item-1 name'},
        },
        translations: const {},
        questItemTranslations: const {},
        traders: {
          'trader-1': {'id': 'trader-1', 'name': 'trader-1 name'},
        },
        traderTranslations: const {},
      );

      expect(markers.map((marker) => marker['filterKey']), [
        'QuestObjectives',
        'QuestItems',
      ]);
      final task = catalog.tasks.single;
      final objectiveIds = task.objectives.map((o) => o.id).toList();
      for (final (index, marker) in markers.indexed) {
        final metadata = MapMarkerMetadata(
          name: marker['name']! as String,
          type: marker['filterKey']! as String,
          category: marker['category']! as String,
          details: marker['details']! as Map<String, dynamic>,
          source: marker['source']! as Map<String, dynamic>,
        );
        expect(metadata.isQuest, isTrue);
        expect(metadata.questTaskId, task.id);
        expect(metadata.sourceId, objectiveIds[index]);
      }
    },
  );
}

import 'package:blackgrid/domain/map_coordinates.dart';
import 'package:blackgrid/maps/prepared_map.dart';
import 'package:blackgrid/maps/quest_objective_refs.dart';
import 'package:flutter_test/flutter_test.dart';

PreparedMarker _marker(String category, Map<String, dynamic> details) =>
    PreparedMarker(
      id: 'm-${details.hashCode}',
      category: category,
      filterKey: 'QuestObjectives',
      name: 'marker',
      position: GamePoint(0, 0),
      details: details,
      source: const {},
      outline: const [],
    );

void main() {
  test('quest objective markers give their task and objective ids', () {
    final refs = questObjectiveRefs([
      _marker('questObjectives', {
        'id': 'obj-1',
        'quest': {'id': 'task-1'},
      }),
    ]);
    expect(refs.single.taskId, 'task-1');
    expect(refs.single.objectiveId, 'obj-1');
  });

  test('other categories and markers without ids are skipped', () {
    final refs = questObjectiveRefs([
      _marker('extracts', {
        'id': 'obj-1',
        'quest': {'id': 'task-1'},
      }),
      _marker('questObjectives', {'id': 'obj-2'}),
      _marker('questObjectives', {
        'quest': {'id': 'task-3'},
      }),
    ]);
    expect(refs, isEmpty);
  });
}

import 'package:blackgrid_progress/blackgrid_progress.dart';
import 'package:blackgrid/domain/alert_rules.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/local_progress.dart';
import 'package:blackgrid/domain/progress_facts.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 11, 21, 12);

QuestObjectiveRef _marker(String taskId, String objectiveId) =>
    QuestObjectiveRef(taskId, objectiveId);

ProgressCatalog _catalog({
  ObjectiveType type = ObjectiveType.plantItem,
  bool? restartable,
  bool withStation = true,
}) => ProgressCatalog(
  tasks: [
    CatalogTask(
      id: 'task-1',
      name: 'Task',
      restartable: restartable,
      objectives: [TaskObjective(id: 'obj-1', type: type)],
    ),
  ],
  stations: [
    if (withStation)
      HideoutStation(
        id: 'station-air',
        name: 'Air Filtering Unit',
        normalizedName: 'air-filtering-unit',
      ),
    HideoutStation(
      id: 'station-gen',
      name: 'Generator',
      normalizedName: 'generator',
    ),
  ],
);

ProgressFacts _facts({
  ProgressTaskStatus? state = ProgressTaskStatus.started,
  bool done = false,
  int airLevel = 0,
}) => ProgressFacts(
  mode: GameMode.pvp,
  taskStates: {'task-1': ?state},
  objectivesComplete: {if (done) 'obj-1'},
  stationLevels: {'station-air': airLevel},
);

QuestItemsCheck _check({
  String? mapId = 'customs',
  List<QuestObjectiveRef>? markers,
  ProgressCatalog? catalog,
  ProgressFacts? facts,
}) => questItemsCheck(
  mapId: mapId,
  objectives: markers,
  catalog: catalog,
  facts: facts,
);

QuestItemsCheck _checkWithData({
  String? mapId = 'customs',
  List<QuestObjectiveRef>? markers,
  ProgressCatalog? catalog,
  ProgressFacts? facts,
}) => _check(
  mapId: mapId,
  markers: markers ?? [_marker('task-1', 'obj-1')],
  catalog: catalog ?? _catalog(),
  facts: facts ?? _facts(),
);

void main() {
  group('freshness', () {
    test('30 s before the clock is fresh, 31 s is stale', () {
      expect(
        isFreshLogTime(_now.subtract(const Duration(seconds: 30)), _now),
        isTrue,
      );
      expect(
        isFreshLogTime(_now.subtract(const Duration(seconds: 31)), _now),
        isFalse,
      );
    });

    test('a log time in the future counts as fresh', () {
      expect(isFreshLogTime(_now.add(const Duration(hours: 2)), _now), isTrue);
    });
  });

  group('quest items', () {
    test('quest items fires for an unfinished plant objective on the map', () {
      expect(_checkWithData(), isA<QuestItemsFire>());
    });

    test('fires for each of the four item objective types', () {
      for (final type in [
        ObjectiveType.plantItem,
        ObjectiveType.plantQuestItem,
        ObjectiveType.mark,
        ObjectiveType.giveQuestItem,
      ]) {
        expect(
          _checkWithData(catalog: _catalog(type: type)),
          isA<QuestItemsFire>(),
          reason: type.name,
        );
      }
    });

    test('other objective types do not count', () {
      for (final type in [
        ObjectiveType.findItem,
        ObjectiveType.visit,
        ObjectiveType.giveItem,
        ObjectiveType.unknown,
      ]) {
        expect(
          _checkWithData(catalog: _catalog(type: type)),
          isA<QuestItemsQuiet>(),
          reason: type.name,
        );
      }
    });

    test('quest items silent when the objective is done', () {
      expect(_checkWithData(facts: _facts(done: true)), isA<QuestItemsQuiet>());
    });

    test('silent when the task is not started', () {
      expect(
        _checkWithData(facts: _facts(state: null)),
        isA<QuestItemsQuiet>(),
      );
      expect(
        _checkWithData(facts: _facts(state: ProgressTaskStatus.finished)),
        isA<QuestItemsQuiet>(),
      );
    });

    test('silent for an unknown objective', () {
      expect(
        _checkWithData(markers: [_marker('task-1', 'other')]),
        isA<QuestItemsQuiet>(),
      );
    });

    test('quest items silent for an unknown map', () {
      expect(_checkWithData(mapId: null), isA<QuestItemsQuiet>());
      expect(_checkWithData(mapId: 'narnia'), isA<QuestItemsQuiet>());
    });

    test('unavailable when markers, catalog or facts are missing', () {
      expect(
        _check(catalog: _catalog(), facts: _facts()),
        isA<QuestItemsUnavailable>().having(
          (u) => u.reason,
          'reason',
          AlertDataGap.markers,
        ),
      );
      expect(
        _check(markers: [_marker('task-1', 'obj-1')], facts: _facts()),
        isA<QuestItemsUnavailable>().having(
          (u) => u.reason,
          'reason',
          AlertDataGap.questData,
        ),
      );
      expect(
        _check(markers: [_marker('task-1', 'obj-1')], catalog: _catalog()),
        isA<QuestItemsUnavailable>().having(
          (u) => u.reason,
          'reason',
          AlertDataGap.progress,
        ),
      );
    });
  });

  group('air filter', () {
    test('built when the station level is 1 or higher', () {
      expect(
        airFilterStatus(catalog: _catalog(), facts: _facts(airLevel: 1)),
        AirFilterStatus.built,
      );
    });

    test('not built at level 0', () {
      expect(
        airFilterStatus(catalog: _catalog(), facts: _facts()),
        AirFilterStatus.notBuilt,
      );
    });

    test('unavailable without catalog, facts or the station', () {
      expect(
        airFilterStatus(catalog: null, facts: _facts(airLevel: 1)),
        AirFilterStatus.unavailable,
      );
      expect(
        airFilterStatus(catalog: _catalog(), facts: null),
        AirFilterStatus.unavailable,
      );
      expect(
        airFilterStatus(
          catalog: _catalog(withStation: false),
          facts: _facts(airLevel: 1),
        ),
        AirFilterStatus.unavailable,
      );
    });
  });

  group('failed tasks', () {
    test('failed tasks ignores tasks not marked restartable', () {
      expect(isRestartable(_catalog(restartable: false), 'task-1'), isFalse);
      expect(isRestartable(_catalog(), 'task-1'), isFalse);
      expect(isRestartable(_catalog(restartable: true), 'missing'), isFalse);
      expect(isRestartable(null, 'task-1'), isFalse);
    });

    test('a restartable task counts', () {
      expect(isRestartable(_catalog(restartable: true), 'task-1'), isTrue);
    });
  });
}

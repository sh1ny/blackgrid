import 'package:blackgrid/application/quest_checklist.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/local_progress.dart';
import 'package:blackgrid_progress/blackgrid_progress.dart';
import 'package:flutter_test/flutter_test.dart';

const _scope = ProgressScope(mode: GameMode.pve, cycleId: 'cycle');
const _started = ProgressTaskState(ProgressTaskStatus.started);

ProgressTarget _taskState(String id) => ProgressTarget(
  kind: ProgressEntityKind.task,
  id: id,
  field: ProgressField.state,
);
ProgressTarget _count(String id) => ProgressTarget(
  kind: ProgressEntityKind.objective,
  id: id,
  field: ProgressField.count,
);
ProgressTarget _complete(String id) => ProgressTarget(
  kind: ProgressEntityKind.objective,
  id: id,
  field: ProgressField.complete,
);

/// Winners keyed by register, as the controller projects them.
Map<ProgressTarget, ProgressEvent> _winners(
  Map<ProgressTarget, ProgressValue> values,
) {
  var n = 0;
  return {
    for (final entry in values.entries)
      entry.key: ProgressEvent(
        eventId: 'event-${++n}',
        deviceId: 'device',
        occurredAtMs: n,
        scope: _scope,
        source: ProgressSource.manual,
        target: entry.key,
        value: entry.value,
      ),
  };
}

CatalogTask _quest(
  String id,
  String name,
  String trader, [
  List<TaskObjective> objectives = const [],
]) => CatalogTask(id: id, name: name, traderId: trader, objectives: objectives);

ProgressCatalog _catalog(List<CatalogTask> tasks) => ProgressCatalog(
  tasks: tasks,
  stations: const [],
  traders: [
    CatalogTraderLevels(id: 'prapor', name: 'Prapor'),
    CatalogTraderLevels(id: 'mechanic', name: 'Mechanic'),
    CatalogTraderLevels(id: 'skier', name: 'Skier'),
  ],
);

List<String> _ids(QuestChecklist checklist) => [
  for (final task in checklist.tasks) task.id,
];

void main() {
  group('QuestChecklist ordering', () {
    final catalog = _catalog([
      _quest('gunsmith', 'Gunsmith', 'prapor'),
      _quest('debut', 'Debut', 'prapor'),
      _quest('farming', 'Farming', 'mechanic'),
      _quest('burning', 'Burning', 'skier'),
    ]);
    final started = {
      for (final id in ['gunsmith', 'debut', 'farming', 'burning'])
        _taskState(id): _started,
    };

    test('started tasks with a quest marker on the map come first, then by trader and name', () {
      final checklist = buildQuestChecklist(
        catalog: catalog,
        winners: _winners(started),
        markerTaskIds: {'burning', 'gunsmith'},
      );
      expect(_ids(checklist), ['gunsmith', 'burning', 'farming', 'debut']);
      expect(
        [for (final t in checklist.tasks) t.onThisMap],
        [true, true, false, false],
      );
      expect(checklist.tasks.first.traderName, 'Prapor');
    });

    test('without quest markers every started task is one group and nothing is on this map', () {
      final checklist = buildQuestChecklist(
        catalog: catalog,
        winners: _winners(started),
      );
      expect(_ids(checklist), ['farming', 'debut', 'gunsmith', 'burning']);
      expect(checklist.tasks.any((t) => t.onThisMap), isFalse);
    });

    test('a task without a known trader sorts by name after named traders', () {
      final checklist = buildQuestChecklist(
        catalog: _catalog([
          CatalogTask(id: 'z', name: 'Zed'),
          _quest('a', 'Alpha', 'skier'),
        ]),
        winners: _winners({
          _taskState('z'): _started,
          _taskState('a'): _started,
        }),
      );
      expect(_ids(checklist), ['a', 'z']);
      expect(checklist.tasks.last.traderName, isNull);
    });

    test('finished and failed tasks leave the list on the next read', () {
      final checklist = buildQuestChecklist(
        catalog: catalog,
        winners: _winners({
          ...started,
          _taskState('debut'): const ProgressTaskState(
            ProgressTaskStatus.finished,
          ),
          _taskState('farming'): const ProgressTaskState(
            ProgressTaskStatus.failed,
          ),
          _taskState('burning'): const ProgressUnset(),
        }),
      );
      expect(_ids(checklist), ['gunsmith']);
    });

    test('a started ID missing from the catalog is not listed', () {
      final checklist = buildQuestChecklist(
        catalog: catalog,
        winners: _winners({
          _taskState('gunsmith'): _started,
          _taskState('ghost'): _started,
        }),
      );
      expect(_ids(checklist), ['gunsmith']);
    });

    test('without a catalog the list is empty', () {
      final checklist = buildQuestChecklist(
        catalog: null,
        winners: _winners(started),
      );
      expect(checklist.tasks, isEmpty);
    });
  });

  group('QuestChecklist objectives', () {
    ProgressCatalog counterCatalog() => _catalog([
      _quest('hunt', 'Hunt', 'prapor', [
        TaskObjective(
          id: 'scavs',
          description: 'Eliminate Scavs on Customs',
          count: 5,
        ),
        TaskObjective(id: 'find', rawType: 'findItem', optional: true),
        TaskObjective(id: 'visit', description: 'Visit the dorms'),
      ]),
    ]);

    test(
      'a counter objective shows its count and target and is not done below it',
      () {
        final task = buildQuestChecklist(
          catalog: counterCatalog(),
          winners: _winners({
            _taskState('hunt'): _started,
            _count('scavs'): const ProgressInteger(3),
          }),
          markerTaskIds: {'hunt'},
          markerObjectiveIds: {'scavs'},
        ).tasks.single;
        final scavs = task.objectives.first;
        expect(scavs.description, 'Eliminate Scavs on Customs');
        expect(scavs.target, 5);
        expect(scavs.count, 3);
        expect(scavs.done, isFalse);
        expect(scavs.onThisMap, isTrue);
        final find = task.objectives[1];
        expect(find.description, 'findItem');
        expect(find.optional, isTrue);
        expect(find.target, isNull);
        expect(find.count, 0);
        expect(find.done, isFalse);
        expect(find.onThisMap, isFalse);
        expect(task.objectives.map((o) => o.id), ['scavs', 'find', 'visit']);
      },
    );

    test('a counter objective at its target reads done', () {
      final objective = buildQuestChecklist(
        catalog: counterCatalog(),
        winners: _winners({
          _taskState('hunt'): _started,
          _count('scavs'): const ProgressInteger(5),
          _complete('visit'): const ProgressBoolean(true),
          _complete('find'): const ProgressBoolean(false),
        }),
      ).tasks.single.objectives;
      expect(objective.map((o) => o.done), [true, false, true]);
    });

    test('a recorded completion reads a counter done below its target', () {
      final scavs = buildQuestChecklist(
        catalog: counterCatalog(),
        winners: _winners({
          _taskState('hunt'): _started,
          _count('scavs'): const ProgressInteger(1),
          _complete('scavs'): const ProgressBoolean(true),
        }),
      ).tasks.single.objectives.first;
      expect(scavs.done, isTrue);
      expect(scavs.count, 1);
    });

    test('a task finished from the logs leaves the list and keeps its objective values', () {
      final catalog = _catalog([
        _quest('first', 'First', 'prapor', [TaskObjective(id: 'shared')]),
        _quest('second', 'Second', 'prapor', [TaskObjective(id: 'shared')]),
      ]);
      final values = {
        _taskState('first'): const ProgressTaskState(
          ProgressTaskStatus.finished,
        ),
        _taskState('second'): _started,
        _complete('shared'): const ProgressBoolean(true),
      };
      final checklist = buildQuestChecklist(
        catalog: catalog,
        winners: _winners(values),
      );
      expect(_ids(checklist), ['second']);
      expect(checklist.tasks.single.objectives.single.done, isTrue);
    });

    test('a shared objective reads the same value under each task and names the others', () {
      final catalog = _catalog([
        _quest('a', 'Alpha', 'prapor', [TaskObjective(id: 'o', count: 3)]),
        _quest('b', 'Beta', 'prapor', [TaskObjective(id: 'o', count: 3)]),
      ]);
      final checklist = buildQuestChecklist(
        catalog: catalog,
        winners: _winners({
          _taskState('a'): _started,
          _taskState('b'): _started,
          _count('o'): const ProgressInteger(3),
        }),
      );
      final a = checklist.tasks[0].objectives.single;
      final b = checklist.tasks[1].objectives.single;
      expect([a.done, b.done], [true, true]);
      expect([a.count, b.count], [3, 3]);
      expect(a.sharedWith.map((t) => t.name), ['Beta']);
      expect(b.sharedWith.map((t) => t.name), ['Alpha']);
    });

    test('a shared objective names a task that is not started', () {
      final catalog = _catalog([
        _quest('a', 'Alpha', 'prapor', [TaskObjective(id: 'o')]),
        _quest('b', 'Beta', 'prapor', [TaskObjective(id: 'o')]),
        _quest('c', 'Gamma', 'prapor', [TaskObjective(id: 'own')]),
      ]);
      final checklist = buildQuestChecklist(
        catalog: catalog,
        winners: _winners({
          _taskState('a'): _started,
          _taskState('c'): _started,
        }),
      );
      expect(checklist.tasks.first.objectives.single.sharedWith.single.id, 'b');
      expect(checklist.tasks.last.objectives.single.sharedWith, isEmpty);
    });
  });

  group('QuestMarkerFilter', () {
    final catalog = _catalog([
      _quest('a', 'Alpha', 'prapor', [
        TaskObjective(id: 'single'),
        TaskObjective(id: 'counter', count: 4),
        TaskObjective(id: 'open'),
      ]),
    ]);

    test('is null when no task is started or progress is missing', () {
      expect(buildQuestMarkerFilter(catalog: catalog, winners: {}), isNull);
      expect(
        buildQuestMarkerFilter(
          catalog: catalog,
          winners: _winners({
            _taskState('a'): const ProgressTaskState(
              ProgressTaskStatus.finished,
            ),
          }),
        ),
        isNull,
      );
    });

    test('holds started IDs, including ones the catalog does not list', () {
      final filter = buildQuestMarkerFilter(
        catalog: catalog,
        winners: _winners({
          _taskState('a'): _started,
          _taskState('ghost'): _started,
          _taskState('done'): const ProgressTaskState(
            ProgressTaskStatus.finished,
          ),
        }),
      )!;
      expect(filter.startedTaskIds, {'a', 'ghost'});
      expect(filter.doneObjectiveIds, isEmpty);
    });

    test('done objectives come from completion and reached counts', () {
      final filter = buildQuestMarkerFilter(
        catalog: catalog,
        winners: _winners({
          _taskState('a'): _started,
          _complete('single'): const ProgressBoolean(true),
          _count('counter'): const ProgressInteger(4),
          _complete('open'): const ProgressBoolean(false),
        }),
      )!;
      expect(filter.doneObjectiveIds, {'single', 'counter'});
    });

    test('a count below the target is not done', () {
      final filter = buildQuestMarkerFilter(
        catalog: catalog,
        winners: _winners({
          _taskState('a'): _started,
          _count('counter'): const ProgressInteger(3),
        }),
      )!;
      expect(filter.doneObjectiveIds, isEmpty);
    });

    test('without the mode catalog an objective is done only by recorded completion', () {
      final filter = buildQuestMarkerFilter(
        catalog: null,
        winners: _winners({
          _taskState('a'): _started,
          _complete('single'): const ProgressBoolean(true),
          _count('counter'): const ProgressInteger(4),
        }),
      )!;
      expect(filter.startedTaskIds, {'a'});
      expect(filter.doneObjectiveIds, {'single'});
    });
  });
}

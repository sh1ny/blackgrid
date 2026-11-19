import 'package:blackgrid/application/local_progress_access.dart';
import 'package:blackgrid/application/manual_progress_controller.dart';
import 'package:blackgrid/application/raid_timers_controller.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/local_progress.dart';
import 'package:blackgrid/domain/local_progress_store.dart';
import 'package:blackgrid/domain/progress_wipe_store.dart';
import 'package:blackgrid/ui/ember/ember_theme.dart';
import 'package:blackgrid/ui/map_quests_section.dart';
import 'package:blackgrid_progress/blackgrid_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _mode = GameMode.pvp;

ProgressTarget _taskState(String id) => ProgressTarget(
  kind: ProgressEntityKind.task,
  id: id,
  field: ProgressField.state,
);

class _Mode extends ChangeNotifier {
  GameMode value = _mode;
}

class _Catalog extends ChangeNotifier implements RaidTimerCatalogSource {
  _Catalog(List<CatalogTask> tasks, {required bool available}) {
    if (available) {
      snapshot = CatalogSnapshot(
        mode: _mode,
        revision: 'fixture',
        observedAt: DateTime(2026, 11, 1),
        items: const {},
        traders: const {},
        requirements: const [],
        progressCatalog: ProgressCatalog(
          tasks: tasks,
          stations: const [],
          traders: [
            CatalogTraderLevels(id: 'prapor', name: 'Prapor'),
            CatalogTraderLevels(id: 'mechanic', name: 'Mechanic'),
          ],
        ),
      );
    }
  }

  @override
  GameMode mode = _mode;
  @override
  CatalogSnapshot? snapshot;
}

/// A hand-written progress store that records what the controller asks of it.
class _Access extends ChangeNotifier implements LocalProgressAccess {
  @override
  bool loaded = true;
  @override
  String? loadError;
  @override
  int progressRevision = 0;
  @override
  final Map<GameMode, ProgressWipe> wipes = {};
  @override
  final Set<GameMode> unavailableModes = {};

  final Map<ProgressTarget, ProgressEvent> heads = {};
  final Map<String, ProgressEvent> events = {};
  final Map<String, ProgressValue> previous = {};
  final writes = <(ProgressTarget, ProgressValue)>[];
  final undone = <String>[];
  ProgressTarget? failTarget;
  int _nextId = 0;

  void addWipe() {
    wipes[_mode] = ProgressWipe(
      mode: _mode,
      cycleId: 'cycle',
      startDate: DateTime(2026, 11, 1),
      lastFolder: null,
      updatedAtMs: 0,
    );
  }

  ProgressEvent seed(
    ProgressTarget target,
    ProgressValue value, {
    ProgressSource source = ProgressSource.manual,
    String? undoOf,
  }) {
    if (wipes.isEmpty) addWipe();
    final event = ProgressEvent(
      eventId: 'event-${_nextId++}',
      deviceId: 'device',
      occurredAtMs: _nextId,
      scope: wipes[_mode]!.scope,
      source: source,
      target: target,
      value: value,
      undoOf: undoOf,
    );
    previous[event.eventId] = heads[target]?.value ?? const ProgressUnset();
    heads[target] = event;
    events[event.eventId] = event;
    return event;
  }

  void _changed() {
    progressRevision++;
    notifyListeners();
  }

  @override
  Future<ProgressResult<LocalProgressSnapshot>> readCurrent(
    GameMode mode,
  ) async => ProgressSuccess(
    LocalProgressSnapshot(scope: wipes[mode]?.scope, winners: Map.of(heads)),
  );

  @override
  Future<ProgressResult<ProgressEvent>> appendManual(
    GameMode mode,
    ProgressTarget target,
    ProgressValue value,
  ) async {
    writes.add((target, value));
    if (target == failTarget) {
      return const ProgressFailure(ProgressStorageFailure('disk full'));
    }
    final event = seed(target, value);
    _changed();
    return ProgressSuccess(event);
  }

  @override
  Future<ProgressResult<ProgressEvent>> undo(
    GameMode mode,
    String cycleId,
    String targetEventId,
  ) async {
    undone.add(targetEventId);
    final target = events[targetEventId]!;
    final event = seed(
      target.target,
      previous[targetEventId]!,
      undoOf: targetEventId,
    );
    _changed();
    return ProgressSuccess(event);
  }

  @override
  Future<ProgressResult<ProgressEvent>> redo(
    GameMode mode,
    String cycleId,
    String undoEventId,
  ) async {
    final original = events[events[undoEventId]!.undoOf]!;
    final event = seed(original.target, original.value);
    _changed();
    return ProgressSuccess(event);
  }
}

class _Rig {
  _Rig({List<CatalogTask>? tasks, bool catalog = true})
    : catalog = _Catalog(tasks ?? _tasks(), available: catalog) {
    controller = ManualProgressController(
      access: access,
      catalog: this.catalog,
      modeChanges: mode,
      effectiveMode: () => mode.value,
    );
  }

  final _Access access = _Access();
  final _Mode mode = _Mode();
  final _Catalog catalog;
  late final ManualProgressController controller;

  void start(String taskId) => access.seed(
    _taskState(taskId),
    const ProgressTaskState(ProgressTaskStatus.started),
  );

  void dispose() {
    controller.dispose();
    access.dispose();
    catalog.dispose();
    mode.dispose();
  }
}

List<CatalogTask> _tasks() => [
  CatalogTask(
    id: 'alpha',
    name: 'Alpha',
    traderId: 'prapor',
    objectives: [
      TaskObjective(id: 'visit', description: 'Visit the dorms'),
      TaskObjective(
        id: 'scavs',
        description: 'Eliminate Scavs on Customs',
        count: 5,
      ),
      TaskObjective(id: 'bonus', description: 'Find the key', optional: true),
      TaskObjective(id: 'both', description: 'Plant the beacon'),
    ],
  ),
  CatalogTask(
    id: 'beta',
    name: 'Beta',
    traderId: 'mechanic',
    objectives: [
      TaskObjective(id: 'both', description: 'Plant the beacon'),
      TaskObjective(id: 'bare', rawType: 'findQuestItem'),
    ],
  ),
  CatalogTask(id: 'gamma', name: 'Gamma', traderId: 'prapor'),
];

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

Finder _objective(String task, String id) =>
    find.byKey(ValueKey('quest-objective-$task-$id'));
Finder _tick(String task, String id) =>
    find.byKey(ValueKey('quest-tick-$task-$id'));
Finder _plus(String task, String id) =>
    find.byKey(ValueKey('quest-plus-$task-$id'));
Finder _minus(String task, String id) =>
    find.byKey(ValueKey('quest-minus-$task-$id'));
Finder _undo(String task, String id) =>
    find.byKey(ValueKey('quest-undo-$task-$id'));
Finder _within(Finder row, String text) =>
    find.descendant(of: row, matching: find.text(text));

Finder get _anyControl => find.byWidgetPredicate(
  (widget) => switch (widget.key) {
    ValueKey<String>(:final value) =>
      value.startsWith('quest-tick-') ||
          value.startsWith('quest-plus-') ||
          value.startsWith('quest-minus-') ||
          value.startsWith('quest-undo-'),
    _ => false,
  },
);

Future<void> _pump(
  WidgetTester tester,
  _Rig rig, {
  Set<String> markerTaskIds = const {},
  Set<String> markerObjectiveIds = const {},
}) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(rig.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: blackgridTheme(Brightness.dark),
      home: Scaffold(
        body: SingleChildScrollView(
          child: QuestsSection(
            controller: rig.controller,
            markerTaskIds: markerTaskIds,
            markerObjectiveIds: markerObjectiveIds,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

bool _done(WidgetTester tester, String task, String id) => find
    .descendant(of: _tick(task, id), matching: find.byIcon(Icons.check_box))
    .evaluate()
    .isNotEmpty;

void main() {
  testWidgets('no started quest shows how to start one', (tester) async {
    final rig = _Rig();
    await _pump(tester, rig);

    expect(find.textContaining('No quest is started'), findsOneWidget);
    expect(find.textContaining('Your progress'), findsOneWidget);
    expect(_anyControl, findsNothing);
  });

  testWidgets(
    'an objective without a description shows its type and keeps its controls',
    (tester) async {
      final rig = _Rig()..start('beta');
      await _pump(tester, rig);

      expect(_within(_objective('beta', 'bare'), 'findQuestItem'), findsOne);
      final tick = tester.widget<IconButton>(_tick('beta', 'bare'));
      expect(tick.onPressed, isNotNull);
    },
  );

  testWidgets(
    'without a task catalog Quests shows the reason and no controls',
    (tester) async {
      final rig = _Rig(catalog: false)..start('alpha');
      await _pump(tester, rig);

      expect(
        find.textContaining('Quest data is not available'),
        findsOneWidget,
      );
      expect(find.text('Alpha'), findsNothing);
      expect(_anyControl, findsNothing);
      expect(rig.access.writes, isEmpty);
    },
  );

  testWidgets('an unavailable wipe shows its reason and no controls', (
    tester,
  ) async {
    final rig = _Rig()..start('alpha');
    rig.access.unavailableModes.add(_mode);
    await _pump(tester, rig);

    expect(find.text(rig.controller.disabledReason!), findsOneWidget);
    expect(_anyControl, findsNothing);
    expect(rig.access.writes, isEmpty);
  });

  testWidgets('started tasks show their objectives, marks and counts', (
    tester,
  ) async {
    final rig = _Rig()
      ..start('alpha')
      ..start('beta');
    rig.access.seed(_count('scavs'), const ProgressInteger(3));
    await _pump(
      tester,
      rig,
      markerTaskIds: {'alpha'},
      markerObjectiveIds: {'scavs'},
    );

    expect(find.text('Gamma'), findsNothing, reason: 'not started');
    expect(
      tester.getTopLeft(find.text('Alpha')).dy,
      lessThan(tester.getTopLeft(find.text('Beta')).dy),
    );
    final scavs = _objective('alpha', 'scavs');
    expect(_within(scavs, 'Eliminate Scavs on Customs'), findsOneWidget);
    expect(_within(scavs, '3/5'), findsOneWidget);
    expect(_within(scavs, 'On this map'), findsOneWidget);
    expect(_done(tester, 'alpha', 'scavs'), isFalse);
    expect(_within(_objective('alpha', 'visit'), 'On this map'), findsNothing);
    expect(_within(_objective('alpha', 'bonus'), 'Optional'), findsOneWidget);
    expect(_within(_objective('alpha', 'visit'), 'Optional'), findsNothing);
    expect(find.textContaining('Beta'), findsWidgets);
    expect(
      find.descendant(
        of: _objective('alpha', 'both'),
        matching: find.textContaining('Beta'),
      ),
      findsOneWidget,
      reason: 'the shared objective names the other task',
    );
  });

  testWidgets('tick, plus, minus and Undo reach the controller', (
    tester,
  ) async {
    final rig = _Rig()..start('alpha');
    rig.access.seed(_count('scavs'), const ProgressInteger(2));
    await _pump(tester, rig);

    await tester.tap(_tick('alpha', 'visit'));
    await tester.pumpAndSettle();
    expect(rig.access.writes.last, (
      _complete('visit'),
      const ProgressBoolean(true),
    ));
    expect(_done(tester, 'alpha', 'visit'), isTrue);

    await tester.tap(_plus('alpha', 'scavs'));
    await tester.pumpAndSettle();
    expect(rig.access.writes.last, (_count('scavs'), const ProgressInteger(3)));
    expect(_within(_objective('alpha', 'scavs'), '3/5'), findsOneWidget);

    await tester.tap(_minus('alpha', 'scavs'));
    await tester.pumpAndSettle();
    expect(rig.access.writes.last, (_count('scavs'), const ProgressInteger(2)));

    await tester.tap(_tick('alpha', 'scavs'));
    await tester.pumpAndSettle();
    expect(rig.access.writes.last, (_count('scavs'), const ProgressInteger(5)));
    expect(_done(tester, 'alpha', 'scavs'), isTrue);
    expect(rig.access.writes, hasLength(4));

    expect(_within(_objective('alpha', 'visit'), 'Undo'), findsOneWidget);
    await tester.tap(_undo('alpha', 'visit'));
    await tester.pumpAndSettle();
    expect(rig.access.undone, hasLength(1));
    expect(_done(tester, 'alpha', 'visit'), isFalse);
    expect(_within(_objective('alpha', 'visit'), 'Redo'), findsOneWidget);
  });

  testWidgets('a failed entry shows its reason on the objective row', (
    tester,
  ) async {
    final rig = _Rig()..start('alpha');
    rig.access.failTarget = _complete('visit');
    await _pump(tester, rig);

    await tester.tap(_tick('alpha', 'visit'));
    await tester.pumpAndSettle();

    expect(_within(_objective('alpha', 'visit'), 'disk full'), findsOneWidget);
    expect(_done(tester, 'alpha', 'visit'), isFalse);
  });
}

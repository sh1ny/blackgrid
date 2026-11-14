import 'package:blackgrid/application/local_progress_access.dart';
import 'package:blackgrid/application/manual_progress_controller.dart';
import 'package:blackgrid/application/raid_timers_controller.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/local_progress.dart';
import 'package:blackgrid/domain/local_progress_store.dart';
import 'package:blackgrid/domain/progress_wipe_store.dart';
import 'package:blackgrid/ui/ember/ember_theme.dart';
import 'package:blackgrid/ui/settings/your_progress_panel.dart';
import 'package:blackgrid_progress/blackgrid_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _level = ProgressTarget(
  kind: ProgressEntityKind.player,
  id: 'self',
  field: ProgressField.level,
);
const _faction = ProgressTarget(
  kind: ProgressEntityKind.player,
  id: 'self',
  field: ProgressField.faction,
);
const _edition = ProgressTarget(
  kind: ProgressEntityKind.player,
  id: 'self',
  field: ProgressField.edition,
);
const _trader = ProgressTarget(
  kind: ProgressEntityKind.trader,
  id: 'prapor',
  field: ProgressField.loyalty,
);
const _station = ProgressTarget(
  kind: ProgressEntityKind.station,
  id: 'workbench',
  field: ProgressField.level,
);
const _task = ProgressTarget(
  kind: ProgressEntityKind.task,
  id: 'debut',
  field: ProgressField.state,
);

class _Mode extends ChangeNotifier {
  _Mode(this.value);
  GameMode value;

  void set(GameMode next) {
    value = next;
    notifyListeners();
  }
}

class _Catalog extends ChangeNotifier implements RaidTimerCatalogSource {
  _Catalog(this.mode) {
    snapshot = CatalogSnapshot(
      mode: mode,
      revision: 'fixture',
      observedAt: DateTime(2026, 11, 1),
      items: const {},
      traders: const {},
      requirements: const [],
      progressCatalog: ProgressCatalog(
        tasks: [CatalogTask(id: 'debut', name: 'Debut')],
        traders: [
          CatalogTraderLevels(id: 'prapor', name: 'Prapor', levels: [1, 2]),
        ],
        stations: [
          HideoutStation(
            id: 'workbench',
            name: 'Workbench',
            levels: [
              StationLevel(id: 'workbench-1', level: 1),
              StationLevel(id: 'workbench-2', level: 2),
            ],
          ),
        ],
      ),
    );
  }

  @override
  GameMode mode;
  @override
  CatalogSnapshot? snapshot;
}

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

  final Map<GameMode, Map<ProgressTarget, ProgressEvent>> heads = {};
  final Map<String, ProgressEvent> events = {};
  final Map<String, ProgressValue> previous = {};
  final writes = <(GameMode, ProgressTarget, ProgressValue)>[];
  ProgressTarget? failTarget;
  int _nextId = 0;

  void addWipe(GameMode mode) {
    wipes[mode] = ProgressWipe(
      mode: mode,
      cycleId: 'cycle-${mode.name}',
      startDate: DateTime(2026, 11, 1),
      lastFolder: null,
      updatedAtMs: 0,
    );
  }

  ProgressEvent seed(
    GameMode mode,
    ProgressTarget target,
    ProgressValue value, {
    ProgressSource source = ProgressSource.manual,
    String? undoOf,
  }) {
    final scope = wipes[mode]!.scope;
    final event = ProgressEvent(
      eventId: 'event-${_nextId++}',
      deviceId: 'device',
      occurredAtMs: _nextId,
      scope: scope,
      source: source,
      target: target,
      value: value,
      undoOf: undoOf,
    );
    final winners = heads.putIfAbsent(mode, () => {});
    previous[event.eventId] = winners[target]?.value ?? const ProgressUnset();
    winners[target] = event;
    events[event.eventId] = event;
    return event;
  }

  @override
  Future<ProgressResult<LocalProgressSnapshot>> readCurrent(
    GameMode mode,
  ) async {
    return ProgressSuccess(
      LocalProgressSnapshot(
        scope: wipes[mode]?.scope,
        winners: Map.of(heads[mode] ?? {}),
      ),
    );
  }

  @override
  Future<ProgressResult<ProgressEvent>> appendManual(
    GameMode mode,
    ProgressTarget target,
    ProgressValue value,
  ) async {
    writes.add((mode, target, value));
    if (target == failTarget) {
      return const ProgressFailure(ProgressStorageFailure('disk full'));
    }
    if (!wipes.containsKey(mode)) addWipe(mode);
    final event = seed(mode, target, value);
    progressRevision++;
    notifyListeners();
    return ProgressSuccess(event);
  }

  @override
  Future<ProgressResult<ProgressEvent>> undo(
    GameMode mode,
    String cycleId,
    String targetEventId,
  ) async {
    final target = events[targetEventId]!;
    final event = seed(
      mode,
      target.target,
      previous[targetEventId]!,
      undoOf: targetEventId,
    );
    progressRevision++;
    notifyListeners();
    return ProgressSuccess(event);
  }

  @override
  Future<ProgressResult<ProgressEvent>> redo(
    GameMode mode,
    String cycleId,
    String undoEventId,
  ) async {
    final undo = events[undoEventId]!;
    final original = events[undo.undoOf]!;
    final event = seed(mode, original.target, original.value);
    progressRevision++;
    notifyListeners();
    return ProgressSuccess(event);
  }
}

class _Rig {
  _Rig(GameMode initialMode)
    : mode = _Mode(initialMode),
      catalog = _Catalog(initialMode) {
    controller = ManualProgressController(
      access: access,
      catalog: catalog,
      modeChanges: mode,
      effectiveMode: () => mode.value,
    );
  }

  final _Access access = _Access();
  final _Mode mode;
  final _Catalog catalog;
  late final ManualProgressController controller;

  void dispose() {
    controller.dispose();
    access.dispose();
    catalog.dispose();
    mode.dispose();
  }
}

Finder _row(String id) => find.byKey(Key('progress-row-$id'));
Finder _control(String id) => find.byKey(Key('progress-control-$id'));
Finder _within(Finder row, String text) =>
    find.descendant(of: row, matching: find.text(text));

String _rowText(WidgetTester tester, Finder row) => tester
    .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
    .map((text) => text.data ?? '')
    .join(' ');

Future<void> _pump(WidgetTester tester, _Rig rig) async {
  tester.view.physicalSize = const Size(1800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(rig.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: blackgridTheme(Brightness.dark),
      home: Scaffold(
        body: SingleChildScrollView(
          child: YourProgressPanel(controller: rig.controller),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String id, String label) async {
  final control = _control(id);
  await tester.ensureVisible(control);
  await tester.tap(control);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _search(WidgetTester tester, String query) async {
  final search = find.byKey(const Key('progress-task-search'));
  await tester.ensureVisible(search);
  await tester.enterText(search, query);
  await tester.pumpAndSettle();
}

void main() {
  test('every edition table ID has a readable display name', () {
    expect(
      progressEditionNames.keys.toSet(),
      containsAll(editionTable.editions),
    );
    for (final id in editionTable.editions) {
      expect(progressEditionNames[id], isNotEmpty, reason: id);
      expect(progressEditionNames[id], isNot(id), reason: id);
    }
  });

  testWidgets('titled for the effective mode', (tester) async {
    final rig = _Rig(GameMode.pve);
    rig.access
      ..addWipe(GameMode.pve)
      ..addWipe(GameMode.pvp)
      ..seed(GameMode.pve, _level, const ProgressInteger(17))
      ..seed(GameMode.pvp, _level, const ProgressInteger(42));
    await _pump(tester, rig);

    expect(find.textContaining('Your progress'), findsOneWidget);
    expect(find.textContaining('PvE'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('progress-level-input')))
          .controller!
          .text,
      '17',
    );

    rig.mode.set(GameMode.pvp);
    await tester.pumpAndSettle();
    expect(find.textContaining('PvP'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('progress-level-input')))
          .controller!
          .text,
      '42',
    );
  });

  testWidgets('unknown mode asks to choose a game mode', (tester) async {
    final rig = _Rig(GameMode.unknown);
    await _pump(tester, rig);

    expect(
      find.textContaining(RegExp('choose.*game mode', caseSensitive: false)),
      findsOneWidget,
    );
    expect(find.byKey(const Key('progress-level-input')), findsNothing);
    expect(_control('faction'), findsNothing);
    expect(_control('edition'), findsNothing);
    expect(find.byKey(const Key('progress-task-search')), findsNothing);
    expect(rig.access.writes, isEmpty);
  });

  testWidgets('mode without a wipe explains the first entry', (tester) async {
    final rig = _Rig(GameMode.pve);
    await _pump(tester, rig);

    final text = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? '')
        .join(' ')
        .toLowerCase();
    expect(text, contains('first'));
    expect(text, contains('wipe'));
    expect(text, contains('today'));
    expect(text, contains('session'));
    for (final row in [
      'level',
      'faction',
      'edition',
      'trader-prapor',
      'station-workbench',
    ]) {
      expect(_rowText(tester, _row(row)).toLowerCase(), contains('unknown'));
    }
    await _search(tester, 'debut');
    expect(
      _rowText(tester, _row('task-debut')).toLowerCase(),
      contains('unknown'),
    );
  });

  testWidgets('values show From game logs or Set by hand', (tester) async {
    final rig = _Rig(GameMode.pve);
    rig.access
      ..addWipe(GameMode.pve)
      ..seed(GameMode.pve, _level, const ProgressInteger(17))
      ..seed(
        GameMode.pve,
        _task,
        const ProgressTaskState(ProgressTaskStatus.finished),
        source: ProgressSource.log,
      );
    await _pump(tester, rig);
    await _search(tester, 'debut');

    expect(_within(_row('level'), 'Set by hand'), findsOneWidget);
    expect(_within(_row('task-debut'), 'From game logs'), findsOneWidget);
    expect(_within(_row('faction'), 'Set by hand'), findsNothing);
    expect(_within(_row('faction'), 'From game logs'), findsNothing);
    expect(_within(_row('task-debut'), 'Undo'), findsNothing);
  });

  testWidgets('a failure shows beside its row with the previous value', (
    tester,
  ) async {
    final rig = _Rig(GameMode.pve);
    rig.access
      ..addWipe(GameMode.pve)
      ..seed(
        GameMode.pve,
        _station,
        const ProgressInteger(1),
        source: ProgressSource.log,
      )
      ..failTarget = _station;
    await _pump(tester, rig);

    await _choose(tester, 'station-workbench', '2');
    expect(rig.access.writes.last, (
      GameMode.pve,
      _station,
      const ProgressInteger(2),
    ));
    expect(rig.controller.failure(_station), isNotNull);
    expect(
      _rowText(tester, _row('station-workbench')),
      contains(rig.controller.failure(_station)!),
    );
    expect(
      tester.widget<DropdownButton<int>>(_control('station-workbench')).value,
      1,
    );
    expect(
      _within(_row('station-workbench'), 'From game logs'),
      findsOneWidget,
    );
    expect(
      rig.access.heads[GameMode.pve]![_station]!.value,
      const ProgressInteger(1),
    );
  });

  testWidgets('controls write player, trader, station and task values', (
    tester,
  ) async {
    final rig = _Rig(GameMode.pve);
    rig.access.addWipe(GameMode.pve);
    await _pump(tester, rig);

    final input = find.byKey(const Key('progress-level-input'));
    await tester.enterText(input, '25');
    await tester.tap(_within(_row('level'), 'Set'));
    await tester.pumpAndSettle();
    await _choose(tester, 'faction', 'BEAR');
    final editionId = editionTable.editions.first;
    await _choose(tester, 'edition', progressEditionNames[editionId]!);
    await _choose(tester, 'trader-prapor', '2');
    await _choose(tester, 'station-workbench', '2');
    await _search(tester, 'debut');
    await _choose(tester, 'task-debut', 'Finished');

    expect(
      rig.access.writes,
      containsAll([
        (GameMode.pve, _level, const ProgressInteger(25)),
        (GameMode.pve, _faction, const ProgressText('bear')),
        (GameMode.pve, _edition, ProgressText(editionId)),
        (GameMode.pve, _trader, const ProgressInteger(2)),
        (GameMode.pve, _station, const ProgressInteger(2)),
        (
          GameMode.pve,
          _task,
          const ProgressTaskState(ProgressTaskStatus.finished),
        ),
      ]),
    );
    await _choose(tester, 'station-workbench', 'Not built');
    expect(rig.access.writes.last, (
      GameMode.pve,
      _station,
      const ProgressInteger(0),
    ));
    await _choose(tester, 'task-debut', 'Not started');
    expect(rig.access.writes.last, (
      GameMode.pve,
      _task,
      const ProgressUnset(),
    ));
  });

  testWidgets('clear, undo and redo act on the selected value', (tester) async {
    final rig = _Rig(GameMode.pve);
    rig.access
      ..addWipe(GameMode.pve)
      ..seed(
        GameMode.pve,
        _level,
        const ProgressInteger(12),
        source: ProgressSource.log,
      );
    await _pump(tester, rig);

    final input = find.byKey(const Key('progress-level-input'));
    await tester.enterText(input, '25');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(_within(_row('level'), 'Undo'));
    await tester.pumpAndSettle();
    expect(rig.controller.value(_level), const ProgressInteger(12));
    await tester.tap(_within(_row('level'), 'Redo'));
    await tester.pumpAndSettle();
    expect(rig.controller.value(_level), const ProgressInteger(25));
    await tester.tap(_within(_row('level'), 'Clear'));
    await tester.pumpAndSettle();
    expect(rig.controller.value(_level), const ProgressUnset());
    expect(_within(_row('level'), 'Set by hand'), findsNothing);
    expect(_within(_row('level'), 'From game logs'), findsNothing);
  });
}

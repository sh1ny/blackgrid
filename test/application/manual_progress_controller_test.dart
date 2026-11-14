import 'dart:async';

import 'package:blackgrid/application/local_progress_access.dart';
import 'package:blackgrid/application/manual_progress_controller.dart';
import 'package:blackgrid/application/raid_timers_controller.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/local_progress.dart';
import 'package:blackgrid/domain/local_progress_store.dart';
import 'package:blackgrid/domain/progress_wipe_store.dart';
import 'package:blackgrid_progress/blackgrid_progress.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const _pve = GameMode.pve;
const _pvp = GameMode.pvp;
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
ProgressTarget _trader(String id) => ProgressTarget(
  kind: ProgressEntityKind.trader,
  id: id,
  field: ProgressField.loyalty,
);
ProgressTarget _station(String id) => ProgressTarget(
  kind: ProgressEntityKind.station,
  id: id,
  field: ProgressField.level,
);
ProgressTarget _task(String id) => ProgressTarget(
  kind: ProgressEntityKind.task,
  id: id,
  field: ProgressField.state,
);

ProgressCatalog _catalog({int extraTasks = 0}) => ProgressCatalog(
  tasks: [
    CatalogTask(id: 'debut', name: 'Debut'),
    for (var i = 0; i < extraTasks; i++)
      CatalogTask(id: 'task-$i', name: 'Shared task $i'),
  ],
  stations: [
    for (final id in ['medstation', 'library', 'booze'])
      HideoutStation(
        id: id,
        name: id,
        levels: [
          for (var level = 1; level <= 3; level++)
            StationLevel(id: '$id-$level', level: level),
        ],
      ),
  ],
  traders: [
    CatalogTraderLevels(
      id: 'fence',
      name: 'Fence',
      normalizedName: 'fence',
      levels: [1, 2, 3],
    ),
    CatalogTraderLevels(
      id: 'lightkeeper',
      name: 'Lightkeeper',
      normalizedName: 'lightkeeper',
      levels: [1],
    ),
    CatalogTraderLevels(
      id: 'unknown',
      name: 'Unknown',
      normalizedName: 'unknown',
      levels: null,
    ),
  ],
);

CatalogSnapshot _snapshot(GameMode mode, ProgressCatalog? catalog) =>
    CatalogSnapshot(
      mode: mode,
      revision: 'fixture',
      observedAt: DateTime.utc(2026, 1, 1),
      items: const {},
      traders: const {},
      requirements: const [],
      progressCatalog: catalog,
    );

class _Catalog extends ChangeNotifier implements RaidTimerCatalogSource {
  @override
  GameMode mode = _pve;
  @override
  CatalogSnapshot? snapshot = _snapshot(_pve, _catalog());

  void changed() => notifyListeners();
}

class _Mode extends ChangeNotifier {
  GameMode value = _pve;
  void change(GameMode mode) {
    value = mode;
    notifyListeners();
  }

  void unchanged() => notifyListeners();
}

class _Access extends ChangeNotifier implements LocalProgressAccess {
  @override
  bool loaded = true;
  @override
  String? loadError;
  @override
  int progressRevision = 0;
  @override
  final Map<GameMode, ProgressWipe> wipes = {
    for (final mode in [_pve, _pvp])
      mode: ProgressWipe(
        mode: mode,
        cycleId: '${mode.name}-cycle',
        startDate: DateTime(2026, 1, 1),
        lastFolder: null,
        updatedAtMs: 0,
      ),
  };
  @override
  final Set<GameMode> unavailableModes = {};

  final Map<GameMode, Map<ProgressTarget, ProgressEvent>> heads = {
    _pve: {},
    _pvp: {},
  };
  final List<(GameMode, ProgressTarget, ProgressValue)> writes = [];
  final List<(String, GameMode, String, String)> controls = [];
  final List<GameMode> reads = [];
  final Map<String, ProgressEvent> events = {};
  final Map<String, ProgressEvent?> predecessors = {};
  Completer<void>? holdWrite;
  Completer<void>? holdRead;
  ProgressStoreFailure? nextWriteFailure;
  ProgressStoreFailure? nextReadFailure;
  int _nextId = 0;

  ProgressEvent seed(
    GameMode mode,
    ProgressTarget target,
    ProgressValue value, {
    ProgressSource source = ProgressSource.manual,
    String? undoOf,
  }) {
    final event = ProgressEvent(
      eventId: 'event-${++_nextId}',
      deviceId: 'device',
      occurredAtMs: _nextId,
      scope: wipes[mode]!.scope,
      source: source,
      target: target,
      value: value,
      undoOf: undoOf,
    );
    predecessors[event.eventId] = heads[mode]![target];
    events[event.eventId] = event;
    heads[mode]![target] = event;
    return event;
  }

  void signal({bool revision = false}) {
    if (revision) progressRevision++;
    notifyListeners();
  }

  @override
  Future<ProgressResult<LocalProgressSnapshot>> readCurrent(
    GameMode mode,
  ) async {
    reads.add(mode);
    final failure = nextReadFailure;
    nextReadFailure = null;
    final wipe = wipes[mode];
    final snapshot = LocalProgressSnapshot(
      scope: wipe?.scope,
      winners: Map.of(heads[mode] ?? {}),
    );
    final gate = holdRead;
    if (gate != null) await gate.future;
    if (failure != null) return ProgressFailure(failure);
    return ProgressSuccess(snapshot);
  }

  @override
  Future<ProgressResult<ProgressEvent>> appendManual(
    GameMode mode,
    ProgressTarget target,
    ProgressValue value,
  ) async {
    writes.add((mode, target, value));
    final gate = holdWrite;
    if (gate != null) await gate.future;
    final failure = nextWriteFailure;
    nextWriteFailure = null;
    if (failure != null) return ProgressFailure(failure);
    wipes.putIfAbsent(
      mode,
      () => ProgressWipe(
        mode: mode,
        cycleId: '${mode.name}-new',
        startDate: DateTime(2026, 1, 1),
        lastFolder: null,
        updatedAtMs: 0,
      ),
    );
    return ProgressSuccess(seed(mode, target, value));
  }

  @override
  Future<ProgressResult<ProgressEvent>> undo(
    GameMode mode,
    String cycleId,
    String targetEventId,
  ) async {
    controls.add(('undo', mode, cycleId, targetEventId));
    final target = events[targetEventId]!;
    final previous = predecessors[targetEventId];
    return ProgressSuccess(
      seed(
        mode,
        target.target,
        previous?.value ?? const ProgressUnset(),
        undoOf: targetEventId,
      ),
    );
  }

  @override
  Future<ProgressResult<ProgressEvent>> redo(
    GameMode mode,
    String cycleId,
    String undoEventId,
  ) async {
    controls.add(('redo', mode, cycleId, undoEventId));
    final compensation = events[undoEventId]!;
    final original = events[compensation.undoOf]!;
    return ProgressSuccess(seed(mode, original.target, original.value));
  }
}

Future<void> _until(Listenable source, bool Function() condition) async {
  if (condition()) return;
  final done = Completer<void>();
  void listener() {
    if (condition() && !done.isCompleted) done.complete();
  }

  source.addListener(listener);
  try {
    if (condition() && !done.isCompleted) done.complete();
    await done.future;
  } finally {
    source.removeListener(listener);
  }
}

class _Harness {
  final access = _Access();
  final catalog = _Catalog();
  final mode = _Mode();
  late final ManualProgressController controller = ManualProgressController(
    access: access,
    catalog: catalog,
    modeChanges: mode,
    effectiveMode: () => mode.value,
  );

  Future<void> attach() async {
    controller.attach();
    await _until(
      controller,
      () => controller.scope == access.wipes[mode.value]?.scope,
    );
  }

  Future<void> shown(ProgressTarget target, ProgressValue value) =>
      _until(controller, () => controller.value(target) == value);

  void dispose() {
    controller.dispose();
    access.dispose();
    catalog.dispose();
    mode.dispose();
  }
}

void main() {
  late _Harness h;
  setUp(() => h = _Harness());
  tearDown(() => h.dispose());

  test('edition choices come from the edition table', () async {
    await h.attach();
    expect(h.controller.editions.toSet(), editionTable.editions);
    for (final edition in editionTable.editions) {
      await h.controller.setEdition(edition);
      expect(h.access.writes.last, (_pve, _edition, ProgressText(edition)));
    }
    final count = h.access.writes.length;
    await h.controller.setEdition('not-an-edition');
    expect(h.access.writes, hasLength(count));
    for (final faction in ['bear', 'usec']) {
      await h.controller.setFaction(faction);
      expect(h.access.writes.last, (_pve, _faction, ProgressText(faction)));
    }
    final afterFactions = h.access.writes.length;
    await h.controller.setFaction('invalid');
    expect(h.access.writes, hasLength(afterFactions));
  });

  test('level outside 1-79 is rejected before the queue', () async {
    await h.attach();
    for (final input in ['0', '80', '-1', 'abc', '1.5', '', '1e1']) {
      await h.controller.setLevel(input);
      expect(h.access.writes, isEmpty, reason: input);
      expect(h.controller.failure(_level), isNotNull, reason: input);
    }
    for (final input in ['1', '79']) {
      await h.controller.setLevel(input);
      expect(h.access.writes.last, (
        _pve,
        _level,
        ProgressInteger(int.parse(input)),
      ));
    }
  });

  test('loyalty choices follow the trader\'s catalog levels', () async {
    await h.attach();
    final fence = h.controller.traders.singleWhere((t) => t.id == 'fence');
    expect(fence.levels, [1, 2, 3]);
    for (final level in [1, 2, 3]) {
      await h.controller.setLoyalty('fence', level);
      expect(h.access.writes.last, (
        _pve,
        _trader('fence'),
        ProgressInteger(level),
      ));
    }
    final count = h.access.writes.length;
    for (final level in [0, 4]) {
      await h.controller.setLoyalty('fence', level);
    }
    await h.controller.setLoyalty('unknown', 1);
    expect(h.access.writes, hasLength(count));
  });

  test('single-level traders are not listed', () async {
    await h.attach();
    expect(h.controller.traders.map((t) => t.id), ['fence']);
    await h.controller.setLoyalty('lightkeeper', 1);
    expect(h.access.writes, isEmpty);
  });

  test('without a task catalog only player values are editable', () async {
    h.catalog.snapshot = _snapshot(_pve, null);
    await h.attach();
    expect(h.controller.progressCatalog, isNull);
    expect(h.controller.traders, isEmpty);
    expect(h.controller.stations, isEmpty);
    expect(h.controller.searchTasks('debut'), isEmpty);
    await h.controller.setLoyalty('fence', 1);
    await h.controller.setStationLevel('medstation', 1);
    await h.controller.setTaskState('debut', ProgressTaskStatus.finished);
    expect(h.access.writes, isEmpty);
    await h.controller.setLevel('34');
    await h.controller.setFaction('usec');
    await h.controller.setEdition('standard');
    expect(h.access.writes.map((w) => w.$2), [_level, _faction, _edition]);
    h.catalog.snapshot = _snapshot(_pvp, _catalog());
    h.catalog.mode = _pvp;
    h.catalog.changed();
    expect(h.controller.progressCatalog, isNull);
    expect(h.controller.traders, isEmpty);
    expect(h.controller.stations, isEmpty);
    expect(h.controller.searchTasks('debut'), isEmpty);
    final count = h.access.writes.length;
    await h.controller.setStationLevel('medstation', 2);
    expect(h.access.writes, hasLength(count));
  });

  test(
    'an older catalog without trader levels retains tasks and stations',
    () async {
      final full = _catalog();
      h.catalog.snapshot = _snapshot(
        _pve,
        ProgressCatalog(tasks: full.tasks, stations: full.stations),
      );
      await h.attach();
      expect(h.controller.traders, isEmpty);
      expect(
        h.controller.stations.map((station) => station.id),
        contains('medstation'),
      );
      expect(h.controller.searchTasks('debut').map((task) => task.id), [
        'debut',
      ]);
      await h.controller.setLoyalty('fence', 1);
      expect(h.access.writes, isEmpty);
      await h.controller.setStationLevel('medstation', 1);
      expect(h.access.writes.single.$2, _station('medstation'));
    },
  );

  test(
    'a catalog snapshot from another mode cannot validate entries',
    () async {
      h.catalog.snapshot = _snapshot(_pvp, _catalog());
      await h.attach();
      expect(h.controller.progressCatalog, isNull);
      expect(h.controller.searchTasks('debut'), isEmpty);
      await h.controller.setLoyalty('fence', 1);
      await h.controller.setStationLevel('medstation', 1);
      await h.controller.setTaskState('debut', ProgressTaskStatus.finished);
      expect(h.access.writes, isEmpty);
    },
  );

  test('station level is bounded by catalog levels', () async {
    await h.attach();
    await h.controller.setStationLevel('medstation', 2);
    expect(h.access.writes.single, (
      _pve,
      _station('medstation'),
      const ProgressInteger(2),
    ));
    for (final level in [-1, 4]) {
      await h.controller.setStationLevel('medstation', level);
    }
    await h.controller.setStationLevel('missing', 0);
    expect(h.access.writes, hasLength(1));
  });

  test('not built records 0, distinct from unknown', () async {
    await h.attach();
    await h.controller.setStationLevel('library', 0);
    await h.shown(_station('library'), const ProgressInteger(0));
    expect(h.access.writes.single.$3, const ProgressInteger(0));
    expect(h.controller.value(_station('booze')), const ProgressUnset());
    expect(h.controller.canClear(_station('library')), isTrue);
    expect(h.controller.canClear(_station('booze')), isFalse);
  });

  test('search finds a task and sets it finished by hand', () async {
    await h.attach();
    expect(h.controller.searchTasks('  DeBuT  ').map((t) => t.id), ['debut']);
    expect(h.controller.searchTasks(' '), isEmpty);
    await h.controller.setTaskState('debut', ProgressTaskStatus.finished);
    await h.shown(
      _task('debut'),
      const ProgressTaskState(ProgressTaskStatus.finished),
    );
    expect(h.controller.sourceLabel(_task('debut')), 'Set by hand');
    await h.controller.setTaskState('debut', null);
    expect(h.access.writes.last.$3, const ProgressUnset());
    await h.shown(_task('debut'), const ProgressUnset());
  });

  test('search with no match lists nothing', () async {
    await h.attach();
    expect(h.controller.searchTasks('no such task'), isEmpty);
    expect(h.controller.searchTruncated('no such task'), isFalse);
    expect(h.access.writes, isEmpty);
  });

  test('task search is case insensitive, ordered and capped at 50', () async {
    h.catalog.snapshot = _snapshot(_pve, _catalog(extraTasks: 52));
    await h.attach();
    final matches = h.controller.searchTasks('  SHARED TASK  ');
    expect(matches.map((t) => t.id), [for (var i = 0; i < 50; i++) 'task-$i']);
    expect(h.controller.searchTruncated('shared task'), isTrue);
    expect(h.controller.searchTruncated('debut'), isFalse);
    expect(h.controller.searchTruncated('  '), isFalse);
  });

  test('clear records unset and reads unknown', () async {
    h.access.seed(_pve, _level, const ProgressInteger(34));
    await h.attach();
    expect(h.controller.canClear(_level), isTrue);
    await h.controller.clear(_level);
    await h.shown(_level, const ProgressUnset());
    expect(h.access.writes.single, (_pve, _level, const ProgressUnset()));
    expect(h.controller.sourceLabel(_level), isNull);
    expect(h.controller.canClear(_level), isFalse);
  });

  test('clear is disabled for an unknown value', () async {
    await h.attach();
    expect(h.controller.canClear(_level), isFalse);
    expect(h.controller.actionLabel(_level), isNull);
    expect(h.controller.sourceLabel(_level), isNull);
    await h.controller.clear(_level);
    expect(h.access.writes, isEmpty);
  });

  test('undo after redo restores the earlier value and offers redo', () async {
    h.access.seed(_pve, _level, const ProgressInteger(30));
    final edit = h.access.seed(_pve, _level, const ProgressInteger(34));
    await h.attach();
    expect(h.controller.actionLabel(_level), 'Undo');
    await h.controller.undoOrRedo(_level);
    await h.shown(_level, const ProgressInteger(30));
    final firstUndo = h.access.heads[_pve]![_level]!;
    expect(h.access.controls.last, (
      'undo',
      _pve,
      edit.scope.cycleId,
      edit.eventId,
    ));
    expect(h.controller.actionLabel(_level), 'Redo');
    await h.controller.undoOrRedo(_level);
    await h.shown(_level, const ProgressInteger(34));
    final redo = h.access.heads[_pve]![_level]!;
    expect(h.access.controls.last, (
      'redo',
      _pve,
      edit.scope.cycleId,
      firstUndo.eventId,
    ));
    expect(redo.undoOf, isNull);
    expect(h.controller.actionLabel(_level), 'Undo');
    await h.controller.undoOrRedo(_level);
    await h.shown(_level, const ProgressInteger(30));
    expect(h.access.controls.last, (
      'undo',
      _pve,
      edit.scope.cycleId,
      redo.eventId,
    ));
    expect(h.controller.actionLabel(_level), 'Redo');
  });

  test('no undo or redo for a log winner', () async {
    h.access.seed(
      _pve,
      _task('debut'),
      const ProgressTaskState(ProgressTaskStatus.finished),
      source: ProgressSource.log,
    );
    await h.attach();
    expect(h.controller.sourceLabel(_task('debut')), 'From game logs');
    expect(h.controller.actionLabel(_task('debut')), isNull);
    await h.controller.undoOrRedo(_task('debut'));
    expect(h.access.controls, isEmpty);
  });

  test(
    'storage failure is shown beside the value and nothing changes',
    () async {
      h.access.seed(_pve, _level, const ProgressInteger(30));
      await h.attach();
      h.access.nextWriteFailure = const ProgressStorageFailure('disk failed');
      await h.controller.setLevel('34');
      expect(h.controller.value(_level), const ProgressInteger(30));
      expect(h.controller.failure(_level), contains('disk failed'));
      expect(h.controller.failure(_faction), isNull);
      expect(h.access.heads[_pve]![_level]!.value, const ProgressInteger(30));
      await h.controller.setLevel('35');
      expect(h.controller.failure(_level), isNull);
      await h.shown(_level, const ProgressInteger(35));
    },
  );

  test('pending state is per value and rejects duplicate actions', () async {
    await h.attach();
    h.access.holdWrite = Completer<void>();
    final first = h.controller.setLevel('34');
    expect(h.controller.pending(_level), isTrue);
    expect(h.controller.pending(_faction), isFalse);
    await h.controller.setLevel('35');
    final faction = h.controller.setFaction('bear');
    expect(h.controller.pending(_faction), isTrue);
    expect(h.access.writes.map((w) => w.$2), [_level, _faction]);
    h.access.holdWrite!.complete();
    await Future.wait([first, faction]);
    expect(h.controller.pending(_level), isFalse);
    expect(h.controller.pending(_faction), isFalse);
  });

  test('a successful refresh clears an existing row failure', () async {
    await h.attach();
    h.access.nextWriteFailure = const ProgressStorageFailure('disk failed');
    await h.controller.setLevel('34');
    expect(h.controller.failure(_level), contains('disk failed'));
    h.access.seed(
      _pve,
      _faction,
      const ProgressText('usec'),
      source: ProgressSource.log,
    );
    h.access.signal(revision: true);
    await h.shown(_faction, const ProgressText('usec'));
    expect(h.controller.failure(_level), isNull);
  });

  test('a read started before a row failure does not erase it', () async {
    await h.attach();
    h.access.seed(
      _pve,
      _faction,
      const ProgressText('usec'),
      source: ProgressSource.log,
    );
    h.access.holdRead = Completer<void>();
    h.access.signal(revision: true);
    h.access.nextWriteFailure = const ProgressStorageFailure('new failure');
    await h.controller.setLevel('34');
    expect(h.controller.failure(_level), contains('new failure'));
    final gate = h.access.holdRead!;
    h.access.holdRead = null;
    gate.complete();
    await h.shown(_faction, const ProgressText('usec'));
    expect(h.controller.failure(_level), contains('new failure'));
  });

  test(
    'a read failure disables entry and a later successful read recovers',
    () async {
      h.access.nextReadFailure = const ProgressStorageFailure('read failed');
      h.controller.attach();
      await _until(h.controller, () => h.controller.disabledReason != null);
      expect(h.controller.disabledReason, contains('read failed'));
      await h.controller.setLevel('34');
      expect(h.access.writes, isEmpty);
      h.access.seed(_pve, _level, const ProgressInteger(30));
      h.access.signal(revision: true);
      await h.shown(_level, const ProgressInteger(30));
      expect(h.controller.disabledReason, isNull);
      await h.controller.setLevel('34');
      expect(h.access.writes.single.$3, const ProgressInteger(34));
    },
  );

  test('no active wipe reads unknown and still allows a first entry', () async {
    h.access.wipes.remove(_pve);
    h.controller.attach();
    await _until(
      h.controller,
      () => h.access.reads.isNotEmpty && !h.controller.loading,
    );
    expect(h.controller.hasWipe, isFalse);
    expect(h.controller.value(_level), const ProgressUnset());
    expect(h.controller.disabledReason, isNull);
    await h.controller.setLevel('34');
    await h.shown(_level, const ProgressInteger(34));
    expect(h.controller.hasWipe, isTrue);
    expect(h.access.writes.single, (_pve, _level, const ProgressInteger(34)));
  });

  test('unavailable wipe disables entry with its reason', () async {
    h.access.unavailableModes.add(_pve);
    h.controller.attach();
    expect(h.controller.disabledReason, isNotNull);
    await h.controller.setLevel('34');
    expect(h.access.writes, isEmpty);
  });

  test('failed initial load disables entry for every mode', () async {
    h.access.loaded = false;
    h.access.loadError = 'cannot load device';
    h.controller.attach();
    expect(h.controller.disabledReason, isNotNull);
    await h.controller.setLevel('34');
    h.mode.change(_pvp);
    expect(h.controller.disabledReason, isNotNull);
    await h.controller.setLevel('35');
    expect(h.access.writes, isEmpty);
  });

  test('a progress revision change re-reads while shown', () async {
    await h.attach();
    final count = h.access.reads.length;
    h.access.signal();
    h.catalog.changed();
    h.mode.unchanged();
    expect(h.access.reads, hasLength(count));
    h.access.seed(
      _pve,
      _task('debut'),
      const ProgressTaskState(ProgressTaskStatus.finished),
      source: ProgressSource.log,
    );
    h.access.signal(revision: true);
    await h.shown(
      _task('debut'),
      const ProgressTaskState(ProgressTaskStatus.finished),
    );
    expect(h.controller.sourceLabel(_task('debut')), 'From game logs');
    expect(h.access.reads, hasLength(count + 1));
    h.controller.detach();
    expect(h.controller.winners, isEmpty);
    expect(h.controller.scope, isNull);
    h.access.signal(revision: true);
    expect(h.access.reads, hasLength(count + 1));
  });

  test(
    'catalog changes trigger reads but ordinary notifications do not',
    () async {
      await h.attach();
      final count = h.access.reads.length;
      h.catalog.changed();
      expect(h.access.reads, hasLength(count));
      h.catalog.snapshot = _snapshot(_pve, _catalog(extraTasks: 1));
      h.catalog.changed();
      await _until(
        h.controller,
        () => h.controller.searchTasks('shared').isNotEmpty,
      );
      expect(h.access.reads, hasLength(count + 1));
    },
  );

  test('one read in flight coalesces changes into one dirty re-read', () async {
    h.access.holdRead = Completer<void>();
    h.controller.attach();
    expect(h.access.reads, [_pve]);
    h.access.seed(_pve, _level, const ProgressInteger(40));
    h.access.signal(revision: true);
    h.access.signal(revision: true);
    h.access.signal(revision: true);
    expect(h.access.reads, [_pve]);
    final gate = h.access.holdRead!;
    h.access.holdRead = null;
    gate.complete();
    await h.shown(_level, const ProgressInteger(40));
    expect(h.access.reads, [_pve, _pve]);
  });

  test(
    'a detached in-flight read cannot publish its stale projection',
    () async {
      h.access.seed(_pve, _level, const ProgressInteger(10));
      h.access.holdRead = Completer<void>();
      final observed = <ProgressValue>[];
      void record() => observed.add(h.controller.value(_level));
      h.controller.addListener(record);
      h.controller.attach();
      expect(h.access.reads, [_pve]);
      h.controller.detach();
      h.access.seed(_pve, _level, const ProgressInteger(20));
      h.controller.attach();
      final gate = h.access.holdRead!;
      h.access.holdRead = null;
      gate.complete();
      await h.shown(_level, const ProgressInteger(20));
      expect(observed, isNot(contains(const ProgressInteger(10))));
      h.controller.removeListener(record);
    },
  );

  test('a read from the previous mode cannot replace the new mode', () async {
    h.access.seed(_pve, _level, const ProgressInteger(10));
    h.access.seed(_pvp, _level, const ProgressInteger(20));
    h.access.holdRead = Completer<void>();
    final observed = <ProgressValue>[];
    void record() {
      if (h.controller.mode == _pvp) observed.add(h.controller.value(_level));
    }

    h.controller.addListener(record);
    h.controller.attach();
    h.mode.change(_pvp);
    final gate = h.access.holdRead!;
    h.access.holdRead = null;
    gate.complete();
    await h.shown(_level, const ProgressInteger(20));
    expect(h.controller.mode, _pvp);
    expect(observed, isNot(contains(const ProgressInteger(10))));
    h.controller.removeListener(record);
  });

  test('a new wipe shows every value unknown', () async {
    h.access.seed(_pve, _level, const ProgressInteger(34));
    h.access.seed(
      _pve,
      _task('debut'),
      const ProgressTaskState(ProgressTaskStatus.finished),
    );
    await h.attach();
    h.access.wipes[_pve] = ProgressWipe(
      mode: _pve,
      cycleId: 'new-cycle',
      startDate: DateTime(2026, 2, 1),
      lastFolder: null,
      updatedAtMs: 1,
    );
    h.access.heads[_pve]!.clear();
    h.access.signal(revision: true);
    await _until(
      h.controller,
      () => h.controller.scope?.cycleId == 'new-cycle',
    );
    expect(h.controller.value(_level), const ProgressUnset());
    expect(h.controller.value(_task('debut')), const ProgressUnset());
    expect(h.controller.winners, isEmpty);
  });

  test('write submitted for PvE lands in PvE after a mode switch', () async {
    h.access.seed(_pvp, _level, const ProgressInteger(20));
    await h.attach();
    h.access.holdWrite = Completer<void>();
    final write = h.controller.setLevel('34');
    expect(h.controller.pending(_level), isTrue);
    h.mode.change(_pvp);
    await h.shown(_level, const ProgressInteger(20));
    expect(h.controller.mode, _pvp);
    expect(h.controller.pending(_level), isFalse);
    h.access.holdWrite!.complete();
    await write;
    expect(h.access.writes.single.$1, _pve);
    expect(h.access.heads[_pve]![_level]!.value, const ProgressInteger(34));
    expect(h.access.heads[_pvp]![_level]!.value, const ProgressInteger(20));
    expect(h.controller.value(_level), const ProgressInteger(20));
    h.mode.change(_pve);
    await h.shown(_level, const ProgressInteger(34));
  });
}

import 'dart:async';

import 'package:blackgrid/application/local_progress_access.dart';
import 'package:blackgrid/application/raid_timers_controller.dart';
import 'package:blackgrid/application/task_log_progress_controller.dart';
import 'package:blackgrid/data/game_log/session_folder_read.dart';
import 'package:blackgrid/data/game_log/session_folders.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/local_progress.dart';
import 'package:blackgrid/domain/local_progress_store.dart';
import 'package:blackgrid/domain/progress_wipe_store.dart';
import 'package:blackgrid/domain/raid_lifecycle.dart';
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
const _taskTarget = ProgressTarget(
  kind: ProgressEntityKind.task,
  id: 'task',
  field: ProgressField.state,
);
const _loyalty = ProgressTarget(
  kind: ProgressEntityKind.trader,
  id: 'fence',
  field: ProgressField.loyalty,
);

SessionFolder _folder(int day, [int hour = 10]) {
  final name =
      'log_2026.11.${day.toString().padLeft(2, '0')}_'
      '${hour.toString().padLeft(2, '0')}-00-00_1.3.0.0.48484';
  return SessionFolder(name, '/logs/$name', DateTime(2026, 11, day, hour));
}

TaskTransition _task(
  SessionFolder folder,
  int offset, {
  String id = 'task',
  ProgressTaskStatus status = ProgressTaskStatus.started,
}) => TaskTransition(
  LogRecordId(folder.name, LogFile.pushNotifications, offset),
  folder.time.add(Duration(seconds: offset)),
  id,
  status,
  _pve,
);

T _success<T>(ProgressResult<T> result) {
  expect(result, isA<ProgressSuccess<T>>());
  return (result as ProgressSuccess<T>).value;
}

void _conflict(ProgressResult<ProgressEvent> result) {
  expect(result, isA<ProgressFailure<ProgressEvent>>());
  expect(
    (result as ProgressFailure<ProgressEvent>).failure,
    isA<ProgressUndoConflict>(),
  );
}

class _Lifecycle extends ChangeNotifier implements RaidTimerLifecycleSource {
  final _events = StreamController<RaidTransition>.broadcast(sync: true);
  @override
  RaidLifecycleState state = RaidLifecycleState.initial;
  @override
  Stream<RaidTransition> get transitions => _events.stream;

  void setState({RaidPhase phase = RaidPhase.inMenus, String? folder}) {
    state = RaidLifecycleState(phase: phase, currentFolder: folder);
    notifyListeners();
  }

  void publish(TaskTransition event) => _events.add(event);

  Future<void> close() async {
    await _events.close();
    dispose();
  }
}

class _Wipes implements ProgressWipeStore {
  final rows = <GameMode, ProgressWipe>{};
  bool failRead = false;

  @override
  Future<List<ProgressWipe>> readProgressWipes() async {
    if (failRead) throw StateError('wipe read failed');
    return rows.values.toList();
  }

  @override
  Future<void> replaceProgressWipe(ProgressWipe wipe) async {
    rows[wipe.mode] = wipe;
  }

  @override
  Future<void> advanceProgressWipeFolder(
    GameMode mode,
    String folder,
    int updatedAtMs,
  ) async {
    final old = rows[mode]!;
    if (old.lastFolder == null ||
        compareSessionFolderNames(old.lastFolder!, folder) < 0) {
      rows[mode] = ProgressWipe(
        mode: mode,
        cycleId: old.cycleId,
        startDate: old.startDate,
        lastFolder: folder,
        updatedAtMs: updatedAtMs,
      );
    }
  }

  @override
  Future<void> moveProgressWipeStartEarlier(
    GameMode mode,
    DateTime startDate,
    int updatedAtMs,
  ) async {
    final old = rows[mode]!;
    if (startDate.isBefore(old.startDate)) {
      rows[mode] = ProgressWipe(
        mode: mode,
        cycleId: old.cycleId,
        startDate: startDate,
        lastFolder: old.lastFolder,
        updatedAtMs: updatedAtMs,
      );
    }
  }
}

class _Ledger implements LocalProgressStore {
  _Ledger(this.now);
  final DateTime Function() now;
  final histories = <ProgressScope, List<ProgressEvent>>{};
  final revisions = <ProgressScope, int>{};
  final unavailable = <ProgressScope>{};
  final batches = <List<ProgressEvent>>[];
  int nextCycle = 0;
  int pageSize = progressPageLimit;
  int staleContinuations = 0;
  int currentReads = 0;
  ProgressStoreFailure? createFailure;
  ProgressStoreFailure? appendFailure;
  Completer<void>? appendEntered;
  Completer<void>? appendRelease;

  ProgressCycle seed(GameMode mode) {
    final scope = ProgressScope(mode: mode, cycleId: 'cycle-${++nextCycle}');
    histories[scope] = [];
    revisions[scope] = 0;
    return cycle(scope);
  }

  ProgressCycle cycle(ProgressScope scope) =>
      ProgressCycle(scope: scope, createdAtMs: 0, revision: revisions[scope]!);

  ProgressEvent? winner(ProgressScope scope, ProgressTarget target) {
    final events = histories[scope]!.where((e) => e.target == target);
    return events.isEmpty
        ? null
        : events.reduce((a, b) => compareProgressEvents(a, b) >= 0 ? a : b);
  }

  @override
  Future<ProgressResult<String>> progressDeviceId() async =>
      const ProgressSuccess('device');

  @override
  Future<ProgressResult<ProgressCycle>> createProgressCycle(
    GameMode mode,
  ) async {
    final failure = createFailure;
    if (failure != null) return ProgressFailure(failure);
    return ProgressSuccess(seed(mode));
  }

  @override
  Future<ProgressResult<ProgressCycle>> openProgressCycle(
    ProgressScope scope,
  ) async {
    if (unavailable.contains(scope)) {
      return ProgressFailure(
        ProgressUnavailable(scope: scope, reason: 'damaged'),
      );
    }
    return ProgressSuccess(cycle(scope));
  }

  @override
  Future<ProgressResult<ProgressAppendResult>> appendProgressEvents(
    ProgressScope scope,
    Iterable<ProgressEvent> events,
  ) async {
    final batch = events.toList();
    batches.add(batch);
    final entered = appendEntered;
    final release = appendRelease;
    if (entered != null && release != null) {
      appendEntered = null;
      appendRelease = null;
      entered.complete();
      await release.future;
    }
    final failure = appendFailure;
    appendFailure = null;
    if (failure != null) return ProgressFailure(failure);
    final history = histories[scope]!;
    for (final event in batch) {
      final matches = histories.values
          .expand((items) => items)
          .where((old) => old.eventId == event.eventId);
      if (matches.isNotEmpty && matches.first != event) {
        return const ProgressFailure(
          ProgressIdentityConflict('different event'),
        );
      }
    }
    var count = 0;
    for (final event in batch) {
      if (!history.any((old) => old.eventId == event.eventId)) {
        history.add(event);
        count++;
      }
    }
    if (count > 0) revisions[scope] = revisions[scope]! + 1;
    return ProgressSuccess(
      ProgressAppendResult(insertedCount: count, revision: revisions[scope]!),
    );
  }

  @override
  Future<ProgressResult<ProgressEvent?>> readProgressEvent(
    ProgressScope scope,
    String eventId,
  ) async {
    final events = histories[scope]!.where((e) => e.eventId == eventId);
    return ProgressSuccess(events.isEmpty ? null : events.single);
  }

  @override
  Future<ProgressResult<ProgressCurrentPage>> readProgressCurrent(
    ProgressScope scope, {
    int limit = progressPageLimit,
    ProgressCurrentCursor? cursor,
  }) async {
    currentReads++;
    if (cursor != null && staleContinuations > 0) {
      staleContinuations--;
      return const ProgressFailure(ProgressStaleCursor());
    }
    if (cursor != null && cursor.revision != revisions[scope]) {
      return const ProgressFailure(ProgressStaleCursor());
    }
    final targets = histories[scope]!.map((e) => e.target).toSet().toList()
      ..sort((a, b) {
        final kind = a.kind.name.compareTo(b.kind.name);
        if (kind != 0) return kind;
        final id = a.id.compareTo(b.id);
        return id != 0 ? id : a.field.name.compareTo(b.field.name);
      });
    final start = cursor == null ? 0 : targets.indexOf(cursor.lastTarget) + 1;
    final count = pageSize < limit ? pageSize : limit;
    final end = start + count < targets.length ? start + count : targets.length;
    final events = targets
        .sublist(start, end)
        .map((t) => winner(scope, t)!)
        .toList();
    final revision = revisions[scope]!;
    return ProgressSuccess(
      ProgressCurrentPage(
        events: events,
        revision: revision,
        nextCursor: end == targets.length
            ? null
            : ProgressCurrentCursor(
                scope: scope,
                revision: revision,
                lastTarget: targets[end - 1],
              ),
      ),
    );
  }

  @override
  Future<ProgressResult<ProgressEvent>> undoProgress(
    ProgressScope scope, {
    required String targetEventId,
    required String requestEventId,
  }) async {
    final history = histories[scope]!;
    final matching = history.where((event) => event.eventId == targetEventId);
    if (matching.isEmpty) {
      return const ProgressFailure(ProgressUndoConflict('missing'));
    }
    final target = matching.single;
    if (winner(scope, target.target)?.eventId != targetEventId) {
      return const ProgressFailure(ProgressUndoConflict('changed'));
    }
    final predecessors = history.where(
      (event) =>
          event.target == target.target &&
          compareProgressEvents(event, target) < 0,
    );
    final previous = predecessors.isEmpty
        ? null
        : predecessors.reduce(
            (a, b) => compareProgressEvents(a, b) >= 0 ? a : b,
          );
    final clockMs = now().millisecondsSinceEpoch;
    final compensation = ProgressEvent(
      eventId: requestEventId,
      deviceId: 'device',
      occurredAtMs: clockMs > target.occurredAtMs
          ? clockMs
          : target.occurredAtMs + 1,
      scope: scope,
      source: ProgressSource.manual,
      target: target.target,
      value: previous?.value ?? const ProgressUnset(),
      undoOf: target.eventId,
    );
    history.add(compensation);
    revisions[scope] = revisions[scope]! + 1;
    return ProgressSuccess(compensation);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Harness {
  DateTime now = DateTime(2026, 11, 13, 0, 30);
  late final store = _Ledger(() => now);
  final wipes = _Wipes();
  final lifecycle = _Lifecycle();
  final folders = <SessionFolder>[];
  final reads = <String, FolderTaskRead>{};
  final readNames = <String>[];
  int nextId = 0;
  late TaskLogProgressController controller;

  ProgressWipe seed(GameMode mode) {
    final cycle = store.seed(mode);
    final wipe = ProgressWipe(
      mode: mode,
      cycleId: cycle.scope.cycleId,
      startDate: DateTime(2026, 11, 1),
      lastFolder: null,
      updatedAtMs: 0,
    );
    wipes.rows[mode] = wipe;
    return wipe;
  }

  void add(SessionFolder folder, List<TaskTransition> tasks) {
    folders.add(folder);
    reads[folder.path] = FolderTaskRead(
      folder: folder.name,
      tasks: tasks,
      skippedNoMode: 0,
      rejected: 0,
      unreadable: false,
    );
  }

  Future<void> start() async {
    controller = TaskLogProgressController(
      store: store,
      wipeStore: wipes,
      lifecycle: lifecycle,
      logRoot: () => '/logs',
      folderLister: (_) async => List.of(folders),
      folderReader: (path) async {
        readNames.add(path);
        return reads[path]!;
      },
      clock: () => now,
      newId: () => 'manual-${++nextId}',
    );
    await controller.ready;
  }

  Future<void> activate(
    SessionFolder folder, {
    RaidPhase phase = RaidPhase.inMenus,
  }) async {
    lifecycle.setState(folder: folder.name, phase: phase);
    await controller.settled;
  }

  Future<void> close() async {
    await controller.close();
    await lifecycle.close();
  }
}

void main() {
  late _Harness h;
  setUp(() => h = _Harness());
  tearDown(() async => h.close());

  test('appendManual records one manual level event', () async {
    final wipe = h.seed(_pve);
    await h.start();
    final event = _success(
      await h.controller.appendManual(_pve, _level, const ProgressInteger(34)),
    );
    expect(
      event,
      ProgressEvent(
        eventId: 'manual-1',
        deviceId: 'device',
        occurredAtMs: h.now.toUtc().millisecondsSinceEpoch,
        scope: wipe.scope,
        source: ProgressSource.manual,
        target: _level,
        value: const ProgressInteger(34),
      ),
    );
    expect(h.store.histories[wipe.scope], [event]);
    final snapshot = _success(await h.controller.readCurrent(_pve));
    expect(snapshot.scope, wipe.scope);
    expect(snapshot.winners[_level], event);
  });

  test('a newer log event beats an older manual edit', () async {
    final wipe = h.seed(_pve);
    final live = _folder(13, 10);
    h.add(live, []);
    await h.start();
    await h.activate(live);
    _success(
      await h.controller.appendManual(
        _pve,
        _taskTarget,
        const ProgressTaskState(ProgressTaskStatus.failed),
      ),
    );
    h.lifecycle.publish(_task(live, 1, status: ProgressTaskStatus.finished));
    await h.controller.settled;
    final winner = _success(await h.controller.readCurrent(_pve))
        .winners[_taskTarget]!;
    expect(winner.source, ProgressSource.log);
    expect(winner.value, const ProgressTaskState(ProgressTaskStatus.finished));
    expect(h.store.histories[wipe.scope], hasLength(2));
  });

  test('a newer manual edit beats older log evidence', () async {
    final live = _folder(12, 23);
    h.seed(_pve);
    h.add(live, []);
    await h.start();
    await h.activate(live);
    h.lifecycle.publish(_task(live, 1));
    await h.controller.settled;
    final edit = _success(
      await h.controller.appendManual(
        _pve,
        _taskTarget,
        const ProgressTaskState(ProgressTaskStatus.finished),
      ),
    );
    expect(
      _success(await h.controller.readCurrent(_pve)).winners[_taskTarget],
      edit,
    );
    expect(edit.source, ProgressSource.manual);
  });

  test('appendManual writes only the submitting mode', () async {
    final pvp = h.seed(_pvp),
        pve = h.seed(_pve),
        seasonal = h.seed(GameMode.seasonal);
    await h.start();
    final event = _success(
      await h.controller.appendManual(_pvp, _level, const ProgressInteger(20)),
    );
    expect(event.scope, pvp.scope);
    expect(h.store.histories[pvp.scope], [event]);
    expect(h.store.histories[pve.scope], isEmpty);
    expect(h.store.histories[seasonal.scope], isEmpty);
  });

  test('first entry creates a wipe starting today without a folder', () async {
    await h.start();
    final empty = _success(await h.controller.readCurrent(GameMode.seasonal));
    expect(empty.scope, isNull);
    expect(empty.winners, isEmpty);
    final event = _success(
      await h.controller.appendManual(
        GameMode.seasonal,
        _faction,
        const ProgressText('USEC'),
      ),
    );
    final wipe = h.wipes.rows[GameMode.seasonal]!;
    expect(wipe.startDate, DateTime(2026, 11, 13));
    expect(wipe.lastFolder, isNull);
    expect(h.readNames, isEmpty);
    expect(h.store.histories[wipe.scope], [event]);
  });

  test(
    'wipe starts on the earlier live folder date and keeps later live events',
    () async {
      final live = _folder(12, 23);
      h.add(live, []);
      await h.start();
      await h.activate(live);
      _success(
        await h.controller.appendManual(
          _pve,
          _level,
          const ProgressInteger(34),
        ),
      );
      final wipe = h.wipes.rows[_pve]!;
      expect(wipe.startDate, DateTime(2026, 11, 12));
      expect(h.readNames, isEmpty);
      h.lifecycle.publish(_task(live, 5401));
      await h.controller.settled;
      expect(h.store.histories[wipe.scope], hasLength(2));
      expect(
        _success(await h.controller.readCurrent(_pve))
            .winners[_taskTarget]!
            .source,
        ProgressSource.log,
      );
    },
  );

  test('failed cycle creation records nothing and reports', () async {
    h.store.createFailure = const ProgressStorageFailure('disk');
    await h.start();
    final before = h.controller.progressRevision;
    final result = await h.controller.appendManual(
      GameMode.seasonal,
      _faction,
      const ProgressText('USEC'),
    );
    expect(result, isA<ProgressFailure<ProgressEvent>>());
    expect(
      (result as ProgressFailure<ProgressEvent>).failure,
      isA<ProgressStorageFailure>(),
    );
    expect(h.wipes.rows, isEmpty);
    expect(h.store.histories, isEmpty);
    expect(h.store.batches, isEmpty);
    expect(h.controller.progressRevision, before);
  });

  test('undo restores the previous value and keeps history', () async {
    final wipe = h.seed(_pve);
    await h.start();
    final first = _success(
      await h.controller.appendManual(_pve, _level, const ProgressInteger(30)),
    );
    h.now = h.now.add(const Duration(seconds: 1));
    final second = _success(
      await h.controller.appendManual(_pve, _level, const ProgressInteger(34)),
    );
    h.now = h.now.add(const Duration(seconds: 1));
    final before = h.controller.progressRevision;
    final undo = _success(
      await h.controller.undo(_pve, wipe.cycleId, second.eventId),
    );
    expect(undo.undoOf, second.eventId);
    expect(undo.source, ProgressSource.manual);
    expect(undo.value, const ProgressInteger(30));
    expect(h.store.histories[wipe.scope], [first, second, undo]);
    expect(
      _success(await h.controller.readCurrent(_pve)).winners[_level],
      undo,
    );
    expect(h.controller.progressRevision, greaterThan(before));
  });

  for (final (name, redoClockChange) in [
    (
      'redo appends a new manual edit with the undone value',
      const Duration(seconds: 1),
    ),
    ('redo restores the value when the clock does not advance', Duration.zero),
    (
      'redo restores the value after the clock moves backward',
      const Duration(minutes: -1),
    ),
  ]) {
    test(name, () async {
      final wipe = h.seed(_pve);
      await h.start();
      final first = _success(
        await h.controller.appendManual(
          _pve,
          _level,
          const ProgressInteger(30),
        ),
      );
      h.now = h.now.add(const Duration(seconds: 1));
      final second = _success(
        await h.controller.appendManual(
          _pve,
          _level,
          const ProgressInteger(34),
        ),
      );
      h.now = h.now.add(const Duration(seconds: 1));
      // Redo's manual-10 sorts before the undo's manual-9.
      h.nextId = 8;
      final undo = _success(
        await h.controller.undo(_pve, wipe.cycleId, second.eventId),
      );
      h.now = h.now.add(redoClockChange);
      final redo = _success(
        await h.controller.redo(_pve, wipe.cycleId, undo.eventId),
      );
      expect(
        redo.eventId,
        isNot(anyOf(first.eventId, second.eventId, undo.eventId)),
      );
      expect(redo.undoOf, isNull);
      expect(redo.source, ProgressSource.manual);
      expect(redo.value, second.value);
      expect(h.store.histories[wipe.scope], [first, second, undo, redo]);
      expect(
        _success(await h.controller.readCurrent(_pve)).winners[_level],
        redo,
      );
      expect(redo.occurredAtMs, greaterThan(undo.occurredAtMs));
      final undoneAgain = _success(
        await h.controller.undo(_pve, wipe.cycleId, redo.eventId),
      );
      expect(undoneAgain.value, first.value);
      expect(
        _success(await h.controller.readCurrent(_pve)).winners[_level],
        undoneAgain,
      );
    });
  }

  test('stale undo or redo reports a conflict and records nothing', () async {
    final wipe = h.seed(_pve);
    final live = _folder(13, 10);
    h.add(live, []);
    await h.start();
    await h.activate(live);
    final edit = _success(
      await h.controller.appendManual(
        _pve,
        _taskTarget,
        const ProgressTaskState(ProgressTaskStatus.failed),
      ),
    );
    h.lifecycle.publish(_task(live, 1, status: ProgressTaskStatus.finished));
    await h.controller.settled;
    var before = List<ProgressEvent>.of(h.store.histories[wipe.scope]!);
    var revision = h.controller.progressRevision;
    _conflict(await h.controller.undo(_pve, wipe.cycleId, edit.eventId));
    expect(h.store.histories[wipe.scope], before);
    expect(h.controller.progressRevision, revision);

    h.now = DateTime(2026, 11, 13, 11);
    final newer = _success(
      await h.controller.appendManual(
        _pve,
        _taskTarget,
        const ProgressTaskState(ProgressTaskStatus.started),
      ),
    );
    h.now = h.now.add(const Duration(seconds: 1));
    final undo = _success(
      await h.controller.undo(_pve, wipe.cycleId, newer.eventId),
    );
    h.now = h.now.add(const Duration(seconds: 1));
    _success(
      await h.controller.appendManual(
        _pve,
        _taskTarget,
        const ProgressTaskState(ProgressTaskStatus.failed),
      ),
    );
    before = List.of(h.store.histories[wipe.scope]!);
    revision = h.controller.progressRevision;
    _conflict(await h.controller.redo(_pve, wipe.cycleId, undo.eventId));
    expect(h.store.histories[wipe.scope], before);
    expect(h.controller.progressRevision, revision);
    _conflict(await h.controller.undo(_pve, 'old-cycle', newer.eventId));
    _conflict(await h.controller.redo(_pve, 'old-cycle', undo.eventId));
    expect(h.store.histories[wipe.scope], before);
  });

  test('an equal-time log event wins over a manual event', () async {
    final live = _folder(13, 10);
    h.seed(_pve);
    h.add(live, []);
    h.now = live.time.add(const Duration(seconds: 1));
    await h.start();
    await h.activate(live);
    _success(
      await h.controller.appendManual(
        _pve,
        _taskTarget,
        const ProgressTaskState(ProgressTaskStatus.failed),
      ),
    );
    h.lifecycle.publish(_task(live, 1, status: ProgressTaskStatus.finished));
    await h.controller.settled;
    final winner = _success(await h.controller.readCurrent(_pve))
        .winners[_taskTarget]!;
    expect(winner.source, ProgressSource.log);
    expect(winner.value, const ProgressTaskState(ProgressTaskStatus.finished));
  });

  test(
    'queued edit resolves the new active cycle and old undo conflicts',
    () async {
      final old = h.seed(_pve);
      final live = _folder(13);
      h.add(live, []);
      await h.start();
      await h.activate(live);
      final previous = _success(
        await h.controller.appendManual(
          _pve,
          _level,
          const ProgressInteger(30),
        ),
      );
      h.now = h.now.add(const Duration(seconds: 1));
      final changed = _success(
        await h.controller.appendManual(
          _pve,
          _level,
          const ProgressInteger(34),
        ),
      );
      h.now = h.now.add(const Duration(seconds: 1));
      final undo = _success(
        await h.controller.undo(_pve, old.cycleId, changed.eventId),
      );
      final oldHistory = List<ProgressEvent>.of(h.store.histories[old.scope]!);
      final entered = Completer<void>(), release = Completer<void>();
      final blocker = h.controller.enqueueProgress(() async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      final replacement = h.controller.startNewWipe(
        _pve,
        DateTime(2026, 11, 13),
      );
      final edit = h.controller.appendManual(
        _pve,
        _level,
        const ProgressInteger(40),
      );
      final staleUndo = h.controller.undo(_pve, old.cycleId, previous.eventId);
      final staleRedo = h.controller.redo(_pve, old.cycleId, undo.eventId);
      release.complete();
      await blocker;
      final event = _success(await edit);
      await replacement;
      _conflict(await staleUndo);
      _conflict(await staleRedo);
      final active = h.controller.wipes[_pve]!;
      expect(active.cycleId, isNot(old.cycleId));
      expect(event.scope, active.scope);
      expect(h.store.histories[old.scope], oldHistory);
      expect(h.store.histories[active.scope], [event]);
    },
  );

  test(
    'failed initial load prevents writes and remains distinct from run errors',
    () async {
      h.wipes.failRead = true;
      await h.start();
      expect(h.controller.loaded, isFalse);
      expect(h.controller.loadError, isNotNull);
      final result = await h.controller.appendManual(
        _pve,
        _level,
        const ProgressInteger(34),
      );
      expect(result, isA<ProgressFailure<ProgressEvent>>());
      expect(h.wipes.rows, isEmpty);
      expect(h.store.histories, isEmpty);
      expect(h.store.batches, isEmpty);
    },
  );

  test(
    'an unavailable wipe rejects a manual entry without creating a replacement',
    () async {
      final wipe = h.seed(_pve);
      h.store.unavailable.add(wipe.scope);
      await h.start();
      expect(h.controller.loaded, isTrue);
      expect(h.controller.loadError, isNull);
      expect(h.controller.unavailableModes, contains(_pve));
      final revision = h.controller.progressRevision;
      final result = await h.controller.appendManual(
        _pve,
        _level,
        const ProgressInteger(34),
      );
      expect(result, isA<ProgressFailure<ProgressEvent>>());
      expect(h.wipes.rows[_pve]!.cycleId, wipe.cycleId);
      expect(h.store.histories[wipe.scope], isEmpty);
      expect(h.store.batches, isEmpty);
      expect(h.controller.progressRevision, revision);
    },
  );

  test('manual entry queued during replay is recorded between chunks', () async {
    final wipe = h.seed(_pve);
    final old = _folder(12), live = _folder(13);
    h.add(old, [
      for (var i = 0; i <= progressPageLimit; i++) _task(old, i, id: 'task-$i'),
    ]);
    h.add(live, []);
    await h.start();
    await h.activate(live);
    // Catch-up already recorded these events; replay still presents two chunks.
    h.store.batches.clear();
    final entered = Completer<void>(), release = Completer<void>();
    h.store.appendEntered = entered;
    h.store.appendRelease = release;
    final replay = h.controller.replay(_pve, DateTime(2026, 11, 1));
    await entered.future;
    final manual = h.controller.appendManual(
      _pve,
      _level,
      const ProgressInteger(40),
    );
    release.complete();
    final event = _success(await manual);
    await replay;
    expect(h.store.batches, hasLength(3));
    expect(h.store.batches.map((b) => b.length), [progressPageLimit, 1, 1]);
    expect(h.store.batches[1], [event]);
    expect(h.store.batches[2].single.source, ProgressSource.log);
    expect(
      _success(await h.controller.readCurrent(_pve)).winners[_level],
      event,
    );
    expect(h.store.histories[wipe.scope], contains(event));
  });

  test('manual entry is recorded during a raid', () async {
    final wipe = h.seed(_pve);
    final live = _folder(13);
    h.add(live, []);
    await h.start();
    await h.activate(live, phase: RaidPhase.inRaid);
    final event = _success(
      await h.controller.appendManual(_pve, _loyalty, const ProgressInteger(2)),
    );
    expect(event.scope, wipe.scope);
    expect(h.store.histories[wipe.scope], [event]);
  });

  test('progressRevision tracks inserted data and wipe replacement, not notifications or duplicates', () async {
    final wipe = h.seed(_pve);
    final live = _folder(13);
    h.add(live, []);
    await h.start();
    await h.activate(live);
    var revision = h.controller.progressRevision;
    h.lifecycle.setState(folder: live.name);
    await h.controller.settled;
    expect(h.controller.progressRevision, revision);
    final task = _task(live, 1);
    h.lifecycle.publish(task);
    await h.controller.settled;
    expect(h.controller.progressRevision, greaterThan(revision));
    revision = h.controller.progressRevision;
    h.lifecycle.publish(task);
    await h.controller.settled;
    expect(h.controller.progressRevision, revision);
    h.store.appendFailure = const ProgressBusy();
    expect(
      await h.controller.appendManual(_pve, _level, const ProgressInteger(1)),
      isA<ProgressFailure<ProgressEvent>>(),
    );
    expect(h.controller.progressRevision, revision);
    _success(
      await h.controller.appendManual(_pve, _level, const ProgressInteger(2)),
    );
    expect(h.controller.progressRevision, greaterThan(revision));
    revision = h.controller.progressRevision;
    await h.controller.startNewWipe(_pve, DateTime(2026, 11, 13));
    expect(h.controller.wipes[_pve]!.cycleId, isNot(wipe.cycleId));
    expect(h.controller.progressRevision, greaterThan(revision));
  });

  test(
    'progressRevision reflects wipe creation and restored availability',
    () async {
      final damaged = h.seed(_pve);
      h.store.unavailable.add(damaged.scope);
      final live = _folder(13);
      h.add(live, []);
      await h.start();
      expect(h.controller.unavailableModes, contains(_pve));
      await h.activate(live);
      var revision = h.controller.progressRevision;
      await h.controller.startNewWipe(_pve, DateTime(2026, 11, 13));
      expect(h.controller.unavailableModes, isNot(contains(_pve)));
      expect(h.controller.progressRevision, greaterThan(revision));
      revision = h.controller.progressRevision;
      _success(
        await h.controller.appendManual(
          _pvp,
          _level,
          const ProgressInteger(10),
        ),
      );
      expect(h.controller.wipes, contains(_pvp));
      expect(h.controller.progressRevision, greaterThan(revision));
    },
  );

  test(
    'readCurrent collects pages and retries one stale traversal from the start',
    () async {
      h.seed(_pve);
      await h.start();
      _success(
        await h.controller.appendManual(
          _pve,
          _level,
          const ProgressInteger(34),
        ),
      );
      _success(
        await h.controller.appendManual(
          _pve,
          _faction,
          const ProgressText('USEC'),
        ),
      );
      _success(
        await h.controller.appendManual(
          _pve,
          _loyalty,
          const ProgressInteger(2),
        ),
      );
      h.store.pageSize = 1;
      h.store.staleContinuations = 1;
      h.store.currentReads = 0;
      final snapshot = _success(await h.controller.readCurrent(_pve));
      expect(snapshot.winners.keys, containsAll([_level, _faction, _loyalty]));
      expect(snapshot.winners, hasLength(3));
      expect(h.store.currentReads, 5);
      expect(() => snapshot.winners.clear(), throwsUnsupportedError);
      h.store.staleContinuations = 2;
      h.store.currentReads = 0;
      final failed = await h.controller.readCurrent(_pve);
      expect(failed, isA<ProgressFailure<LocalProgressSnapshot>>());
      expect(
        (failed as ProgressFailure<LocalProgressSnapshot>).failure,
        isA<ProgressStaleCursor>(),
      );
      expect(h.store.currentReads, 4);
    },
  );
}

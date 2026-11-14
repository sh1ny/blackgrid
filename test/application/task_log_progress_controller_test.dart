import 'dart:async';

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

const _pvp = GameMode.pvp;
const _pve = GameMode.pve;
final _date = DateTime(2026, 11, 1);

SessionFolder _folder(int day, [int hour = 10]) {
  final name =
      'log_2026.11.${day.toString().padLeft(2, '0')}_$hour-00-00_1.3.0.0.48484';
  return SessionFolder(name, '/logs/$name', DateTime(2026, 11, day, hour));
}

TaskTransition _task(
  SessionFolder folder,
  int offset,
  GameMode? mode, {
  String? taskId,
  ProgressTaskStatus status = ProgressTaskStatus.started,
}) => TaskTransition(
  LogRecordId(folder.name, LogFile.pushNotifications, offset),
  folder.time.add(Duration(seconds: offset)),
  taskId ?? 'task-$offset',
  status,
  mode,
);

FolderTaskRead _read(
  SessionFolder folder,
  List<TaskTransition> tasks, {
  int noMode = 0,
  int rejected = 0,
  bool unreadable = false,
}) => FolderTaskRead(
  folder: folder.name,
  tasks: tasks,
  skippedNoMode: noMode,
  rejected: rejected,
  unreadable: unreadable,
);

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
    if (failRead) throw StateError('injected wipe read failure');
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
  int nextCycle = 0;
  final histories = <ProgressScope, List<ProgressEvent>>{};
  final revisions = <ProgressScope, int>{};
  final unavailable = <ProgressScope>{};
  final rejected = <String, ProgressStoreFailure>{};
  ProgressStoreFailure? createFailure;
  ProgressStoreFailure? nextAppendFailure;
  final appendSizes = <int>[];
  final appendEntered = <Completer<void>>[];
  final appendRelease = <Completer<void>>[];
  int active = 0;
  int maximumActive = 0;

  ProgressCycle seed(GameMode mode) {
    final scope = ProgressScope(mode: mode, cycleId: 'cycle-${++nextCycle}');
    histories[scope] = [];
    revisions[scope] = 0;
    return cycle(scope);
  }

  ProgressCycle cycle(ProgressScope scope) =>
      ProgressCycle(scope: scope, createdAtMs: 0, revision: revisions[scope]!);
  List<ProgressEvent> history(ProgressWipe wipe) => histories[wipe.scope]!;
  ProgressEvent winner(ProgressWipe wipe, String id) =>
      history(wipe)
          .where((event) => event.target.id == id)
          .reduce((a, b) => compareProgressEvents(a, b) >= 0 ? a : b);
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
    appendSizes.add(batch.length);
    active++;
    if (active > maximumActive) maximumActive = active;
    try {
      if (appendEntered.isNotEmpty) {
        appendEntered.removeAt(0).complete();
        await appendRelease.removeAt(0).future;
      }
      final transient = nextAppendFailure;
      nextAppendFailure = null;
      if (transient != null) return ProgressFailure(transient);
      if (batch.isEmpty || batch.length > progressPageLimit) {
        return const ProgressFailure(ProgressInvalidInput('batch size'));
      }
      for (final event in batch) {
        final failure = rejected[event.target.id];
        if (failure != null) return ProgressFailure(failure);
        final existing = histories.values
            .expand((items) => items)
            .where((old) => old.eventId == event.eventId);
        if (existing.isNotEmpty && existing.first != event) {
          return const ProgressFailure(
            ProgressIdentityConflict('different event'),
          );
        }
      }
      var count = 0;
      final history = histories[scope]!;
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
    } finally {
      active--;
    }
  }

  @override
  Future<ProgressResult<ProgressEvent?>> readProgressEvent(
    ProgressScope scope,
    String eventId,
  ) async {
    if (unavailable.contains(scope)) {
      return ProgressFailure(
        ProgressUnavailable(scope: scope, reason: 'damaged'),
      );
    }
    final history = histories[scope];
    if (history == null) {
      return const ProgressFailure(
        ProgressInvalidInput('Progress cycle does not exist in this mode'),
      );
    }
    for (final event in history) {
      if (event.eventId == eventId) return ProgressSuccess(event);
    }
    return const ProgressSuccess<ProgressEvent?>(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Harness {
  final store = _Ledger();
  final wipes = _Wipes();
  final lifecycle = _Lifecycle();
  final folders = <SessionFolder>[];
  final reads = <String, FolderTaskRead>{};
  final readNames = <String>[];
  final readEntered = <String, Completer<void>>{};
  final readRelease = <String, Completer<void>>{};
  late TaskLogProgressController controller;

  ProgressWipe seed(GameMode mode, {DateTime? start, SessionFolder? last}) {
    final cycle = store.seed(mode);
    final wipe = ProgressWipe(
      mode: mode,
      cycleId: cycle.scope.cycleId,
      startDate: start ?? _date,
      lastFolder: last?.name,
      updatedAtMs: 0,
    );
    wipes.rows[mode] = wipe;
    return wipe;
  }

  void add(
    SessionFolder folder,
    List<TaskTransition> tasks, {
    int noMode = 0,
    int rejected = 0,
    bool unreadable = false,
  }) {
    folders.add(folder);
    reads[folder.path] = _read(
      folder,
      tasks,
      noMode: noMode,
      rejected: rejected,
      unreadable: unreadable,
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
        final entered = readEntered[path];
        if (entered != null) {
          entered.complete();
          await readRelease[path]!.future;
        }
        return reads[path]!;
      },
      clock: () => DateTime(2026, 12, 1),
    );
    await controller.ready;
  }

  Future<void> activate(
    SessionFolder live, {
    RaidPhase phase = RaidPhase.inMenus,
  }) async {
    lifecycle.setState(phase: phase, folder: live.name);
    await controller.settled;
  }

  Future<void> close() async {
    await controller.close();
    await lifecycle.close();
  }
}

void main() {
  late _Harness h;
  setUp(() {
    h = _Harness();
  });
  tearDown(() async {
    await h.close();
  });

  test('modes record into separate cycles', () async {
    final live = _folder(4);
    h.add(live, []);
    await h.start();
    await h.activate(live);
    h.lifecycle.publish(_task(live, 1, _pvp));
    h.lifecycle.publish(_task(live, 2, _pve));
    await h.controller.settled;
    expect(h.wipes.rows.keys, containsAll([_pvp, _pve]));
    expect(h.store.history(h.wipes.rows[_pvp]!).single.target.id, 'task-1');
    expect(h.store.history(h.wipes.rows[_pve]!).single.target.id, 'task-2');
  });

  test('unavailable cycle marks wipe unavailable and creates none', () async {
    final wipe = h.seed(_pvp);
    h.store.unavailable.add(wipe.scope);
    final live = _folder(4);
    h.add(live, []);
    await h.start();
    await h.activate(live);
    h.lifecycle.publish(_task(live, 1, _pvp));
    await h.controller.settled;
    expect(h.controller.unavailableModes, contains(_pvp));
    expect(h.wipes.rows[_pvp]!.cycleId, wipe.cycleId);
    expect(h.store.nextCycle, 1);
    expect(h.store.history(wipe), isEmpty);
  });

  test('first task event creates wipe at its folder date', () async {
    final live = _folder(12);
    h.add(live, []);
    await h.start();
    await h.activate(live);
    expect(h.readNames, isEmpty);
    h.lifecycle.publish(_task(live, 1, _pvp));
    await h.controller.settled;
    final wipe = h.wipes.rows[_pvp]!;
    expect(wipe.startDate, DateTime(2026, 11, 12));
    expect(h.store.history(wipe).single.target.id, 'task-1');
  });

  test('failed cycle creation records nothing and reports', () async {
    h.store.createFailure = const ProgressStorageFailure('disk');
    final live = _folder(4);
    h.add(live, []);
    await h.start();
    await h.activate(live);
    h.lifecycle.publish(_task(live, 1, _pvp));
    await h.controller.settled;
    expect(h.wipes.rows, isEmpty);
    expect(h.store.histories, isEmpty);
    expect(h.controller.error, isNotNull);
  });

  test('over-budget identity is skipped and the rest recorded', () async {
    h.seed(_pvp);
    final old = _folder(2), live = _folder(4);
    h.add(old, [_task(old, 1, _pvp, taskId: 'x' * 300), _task(old, 2, _pvp)]);
    h.add(live, []);
    await h.start();
    await h.activate(live);
    expect(h.controller.lastResult!.identityOverBudget, 1);
    expect(h.controller.lastResult!.eventsRecorded, 1);
    expect(h.store.history(h.wipes.rows[_pvp]!).single.target.id, 'task-2');
  });

  test('re-published live transitions leave revision unchanged', () async {
    final live = _folder(4);
    h.add(live, []);
    await h.start();
    await h.activate(live);
    final task = _task(live, 1, _pvp);
    h.lifecycle.publish(task);
    await h.controller.settled;
    final wipe = h.wipes.rows[_pvp]!;
    final revision = h.store.revisions[wipe.scope];
    h.lifecycle.publish(task);
    await h.controller.settled;
    expect(h.store.history(wipe), hasLength(1));
    expect(h.store.revisions[wipe.scope], revision);
  });

  test('replay over caught-up folder adds nothing', () async {
    h.seed(_pvp);
    final old = _folder(2), live = _folder(4);
    h.add(old, [_task(old, 1, _pvp)]);
    h.add(live, []);
    await h.start();
    await h.activate(live);
    final wipe = h.wipes.rows[_pvp]!;
    final revision = h.store.revisions[wipe.scope];
    await h.controller.replay(_pvp, _date);
    await h.controller.settled;
    expect(h.store.history(wipe), hasLength(1));
    expect(h.store.revisions[wipe.scope], revision);
    expect(h.controller.lastResult!.eventsRecorded, 0);
  });

  test('message without mode is skipped and counted', () async {
    h.seed(_pvp);
    final old = _folder(2), live = _folder(4);
    h.add(old, [], noMode: 1);
    h.add(live, []);
    await h.start();
    await h.activate(live);
    expect(h.controller.lastResult!.skippedNoMode, 1);
    expect(h.store.history(h.wipes.rows[_pvp]!), isEmpty);
  });

  test('unrecognised mode is skipped, counted and creates no cycle', () async {
    h.seed(_pvp);
    final old = _folder(2), live = _folder(4);
    h.add(old, [], noMode: 1);
    h.add(live, []);
    await h.start();
    await h.activate(live);
    expect(h.controller.lastResult!.skippedNoMode, 1);
    expect(h.store.nextCycle, 1);
    expect(h.store.history(h.wipes.rows[_pvp]!), isEmpty);
  });

  test('mode change within a folder routes messages per mode', () async {
    h.seed(_pvp);
    final old = _folder(2), live = _folder(4);
    h.add(old, [_task(old, 1, _pvp), _task(old, 2, _pve)]);
    h.add(live, []);
    await h.start();
    await h.activate(live);
    expect(h.store.history(h.wipes.rows[_pvp]!).single.target.id, 'task-1');
    expect(h.store.history(h.wipes.rows[_pve]!).single.target.id, 'task-2');
  });

  test('live task start becomes current state', () async {
    final live = _folder(4);
    h.add(live, []);
    await h.start();
    await h.activate(live);
    h.lifecycle.publish(_task(live, 1, _pve));
    await h.controller.settled;
    final event = h.store.winner(h.wipes.rows[_pve]!, 'task-1');
    expect(event.value, const ProgressTaskState(ProgressTaskStatus.started));
    expect(event.source, ProgressSource.log);
    expect(
      event.occurredAtMs,
      live.time.add(const Duration(seconds: 1)).millisecondsSinceEpoch,
    );
  });

  test('live write failure shown until next success', () async {
    h.seed(_pvp);
    final live = _folder(4);
    h.add(live, []);
    await h.start();
    await h.activate(live);
    h.store.nextAppendFailure = const ProgressBusy();
    h.lifecycle.publish(_task(live, 1, _pvp));
    await h.controller.settled;
    expect(h.controller.error, isNotNull);
    expect(h.store.history(h.wipes.rows[_pvp]!), isEmpty);
    h.lifecycle.publish(_task(live, 2, _pvp));
    await h.controller.settled;
    expect(h.controller.error, isNull);
    expect(h.store.history(h.wipes.rows[_pvp]!).single.target.id, 'task-2');
  });

  test('conflicting live record falls back per event', () async {
    h.seed(_pvp);
    final live = _folder(4);
    h.add(live, []);
    await h.start();
    await h.activate(live);
    h.store.rejected['task-2'] = const ProgressIdentityConflict('conflict');
    h.lifecycle.publish(_task(live, 1, _pvp));
    await h.controller.settled;
    h.lifecycle.publish(_task(live, 2, _pvp));
    await h.controller.settled;
    expect(h.controller.error, isNotNull);
    h.lifecycle.publish(_task(live, 3, _pvp));
    await h.controller.settled;
    expect(h.store.history(h.wipes.rows[_pvp]!).map((e) => e.target.id), [
      'task-1',
      'task-3',
    ]);
  });

  test('catch-up reads missed folders and leaves the live folder', () async {
    final previous = _folder(1);
    h.seed(_pve, last: previous);
    for (var day = 2; day <= 29; day++) {
      final f = _folder(day);
      h.add(f, [_task(f, day, _pve)]);
    }
    final live = _folder(30);
    h.add(live, [_task(live, 1, _pve)]);
    await h.start();
    await h.activate(live);
    expect(h.readNames, hasLength(28));
    expect(h.readNames, isNot(contains(live.path)));
    expect(h.wipes.rows[_pve]!.lastFolder, _folder(29).name);
    expect(h.controller.lastResult!.eventsRecorded, 28);
  });

  test('catch-up waits for the raid to end and runs once', () async {
    h.seed(_pvp);
    final old = _folder(2), live = _folder(4);
    h.add(old, [_task(old, 1, _pvp)]);
    h.add(live, []);
    await h.start();
    await h.activate(live, phase: RaidPhase.inRaid);
    expect(h.readNames, isEmpty);
    await h.activate(live, phase: RaidPhase.raidEnded);
    expect(h.readNames, [old.path]);
    await h.activate(live);
    expect(h.readNames, [old.path]);
  });

  test('storage failure keeps last folder and resumes there', () async {
    h.seed(_pvp);
    final a = _folder(2), b = _folder(3), live = _folder(4);
    h.add(a, [_task(a, 1, _pvp)]);
    h.add(b, [_task(b, 2, _pvp)]);
    h.add(live, []);
    h.readEntered[b.path] = Completer();
    h.readRelease[b.path] = Completer();
    await h.start();
    h.lifecycle.setState(folder: live.name);
    await h.readEntered[b.path]!.future;
    h.store.nextAppendFailure = const ProgressStorageFailure('disk');
    h.readRelease[b.path]!.complete();
    await h.controller.settled;
    expect(h.wipes.rows[_pvp]!.lastFolder, a.name);
    expect(h.controller.lastResult!.failure, isNotNull);
    h.readEntered.clear();
    h.readRelease.clear();
    await h.controller.close();
    await h.start();
    await h.controller.settled;
    expect(h.wipes.rows[_pvp]!.lastFolder, b.name);
    expect(h.store.history(h.wipes.rows[_pvp]!), hasLength(2));
  });

  test('conflicting record is skipped and catch-up advances', () async {
    h.seed(_pvp);
    final old = _folder(2), live = _folder(4);
    h.store.rejected['task-2'] = const ProgressIdentityConflict('conflict');
    h.add(old, [_task(old, 1, _pvp), _task(old, 2, _pvp), _task(old, 3, _pvp)]);
    h.add(live, []);
    await h.start();
    await h.activate(live);
    expect(h.controller.lastResult!.conflictingRecords, 1);
    expect(h.controller.lastResult!.eventsRecorded, 2);
    expect(h.wipes.rows[_pvp]!.lastFolder, old.name);
  });

  test(
    "catch-up creates a missing mode's wipe and advances its last folder",
    () async {
      h.seed(_pvp);
      final a = _folder(2), b = _folder(3), live = _folder(4);
      h.add(a, [_task(a, 1, _pve)]);
      h.add(b, [_task(b, 2, _pve)]);
      h.add(live, []);
      await h.start();
      await h.activate(live);
      final wipe = h.wipes.rows[_pve]!;
      expect(wipe.startDate, DateTime(2026, 11, 2));
      expect(wipe.lastFolder, b.name);
      expect(h.store.history(wipe), hasLength(2));
    },
  );

  test('catch-up orders folders by date-time not name', () async {
    final nine = _folder(2, 9), ten = _folder(2, 10), live = _folder(3);
    h.seed(_pvp, last: nine);
    h.add(ten, [_task(ten, 1, _pvp)]);
    h.add(nine, []);
    h.add(live, []);
    await h.start();
    await h.activate(live);
    expect(h.readNames, [ten.path]);
    expect(h.wipes.rows[_pvp]!.lastFolder, ten.name);
  });

  test('earlier replay date fills same cycle and moves start back', () async {
    final wipe = h.seed(_pvp, start: DateTime(2026, 11, 3));
    final old = _folder(2), live = _folder(4);
    h.add(old, [_task(old, 1, _pvp)]);
    h.add(live, []);
    await h.start();
    await h.activate(live);
    await h.controller.replay(_pvp, _date);
    expect(h.wipes.rows[_pvp]!.cycleId, wipe.cycleId);
    expect(h.wipes.rows[_pvp]!.startDate, _date);
    expect(h.store.history(wipe), hasLength(1));
  });

  test('rebound live folder before wipe start stays excluded', () async {
    final oldLive = _folder(10);
    h.add(oldLive, [_task(oldLive, 1, _pvp)]);
    await h.start();
    await h.activate(oldLive);
    final entered = Completer<void>(), release = Completer<void>();
    final blocker = h.controller.enqueueProgress(() async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    final newWipe = h.controller.startNewWipe(_pvp, DateTime(2026, 11, 12));
    h.lifecycle.publish(_task(oldLive, 1, _pvp));
    release.complete();
    await blocker;
    await newWipe;
    await h.controller.settled;
    final wipe = h.wipes.rows[_pvp]!;
    expect(h.store.history(wipe), isEmpty);

    await h.controller.close();
    await h.start();
    await h.controller.settled;
    h.lifecycle.setState(folder: oldLive.name);
    h.lifecycle.publish(_task(oldLive, 1, _pvp));
    await h.controller.settled;
    expect(h.store.history(wipe), isEmpty);
    expect(h.wipes.rows[_pvp]!.startDate, DateTime(2026, 11, 12));

    await h.controller.replay(_pvp, DateTime(2026, 11, 10));
    expect(h.store.history(wipe).single.target.id, 'task-1');
    expect(h.wipes.rows[_pvp]!.startDate, DateTime(2026, 11, 10));
  });

  test('replay never watermarks a newer not-yet-bound folder', () async {
    final wipe = h.seed(_pvp);
    final live = _folder(10), growing = _folder(11), next = _folder(12);
    h.add(live, []);
    h.add(growing, [_task(growing, 1, _pvp)]);
    await h.start();
    await h.activate(live);
    await h.controller.replay(_pvp, _date);
    expect(h.wipes.rows[_pvp]!.lastFolder, isNull);

    h.reads[growing.path] = _read(growing, [
      _task(growing, 1, _pvp),
      _task(growing, 2, _pvp),
    ]);
    h.add(next, []);
    await h.controller.close();
    h.lifecycle.setState(folder: next.name);
    await h.start();
    await h.controller.settled;
    expect(h.readNames.where((path) => path == growing.path), hasLength(2));
    expect(h.store.history(wipe).map((event) => event.target.id), [
      'task-1',
      'task-2',
    ]);
    expect(h.wipes.rows[_pvp]!.lastFolder, growing.name);
  });

  test('failed earlier replay retains watermark and exposes original retry date', () async {
    final marker = _folder(11), live = _folder(12);
    final wipe = h.seed(_pvp, start: DateTime(2026, 11, 1), last: marker);
    SessionFolder october(int day) {
      final name =
          'log_2026.10.${day.toString().padLeft(2, '0')}_10-00-00_1.3.0.0.48484';
      return SessionFolder(name, '/logs/$name', DateTime(2026, 10, day, 10));
    }

    final first = october(20), second = october(21);
    h.add(first, [_task(first, 1, _pvp)]);
    h.add(second, [_task(second, 2, _pvp)]);
    h.add(live, []);
    await h.start();
    await h.activate(live);
    h.readEntered[second.path] = Completer();
    h.readRelease[second.path] = Completer();
    final run = h.controller.replay(_pvp, DateTime(2026, 10, 20));
    await h.readEntered[second.path]!.future;
    h.store.nextAppendFailure = const ProgressStorageFailure('disk');
    h.readRelease[second.path]!.complete();
    await run;
    expect(h.store.history(wipe).single.target.id, 'task-1');
    expect(h.wipes.rows[_pvp]!.lastFolder, marker.name);
    expect(h.controller.lastResult!.lastStoredFolder, first.name);
    expect(h.controller.lastResult!.failure, isNotNull);
    expect(h.controller.lastResult!.retryFrom, DateTime(2026, 10, 20));

    h.readEntered.clear();
    h.readRelease.clear();
    await h.controller.close();
    await h.start();
    await h.controller.settled;
    expect(h.readNames.where((path) => path == second.path), hasLength(1));
    expect(h.store.history(wipe), hasLength(1));
    expect(h.wipes.rows[_pvp]!.lastFolder, marker.name);
  });

  test('replay records only its mode', () async {
    final pvp = h.seed(_pvp), pve = h.seed(_pve);
    final live = _folder(4);
    h.add(live, [_task(live, 1, _pvp), _task(live, 2, _pve)], noMode: 1);
    await h.start();
    await h.activate(live);
    await h.controller.replay(_pvp, _date);
    expect(h.store.history(pvp), hasLength(1));
    expect(h.store.history(pve), isEmpty);
    expect(h.controller.lastResult!.skippedNoMode, 1);
  });

  test('replay with no folders keeps start date', () async {
    final wipe = h.seed(_pve);
    final live = _folder(4);
    h.add(live, []);
    await h.start();
    await h.activate(live);
    await h.controller.replay(_pve, DateTime(2026, 11, 12));
    expect(h.wipes.rows[_pve]!.startDate, wipe.startDate);
    expect(h.controller.lastResult!.foldersRead, 0);
  });

  test('replay reads live folder but never stores it as last folder', () async {
    h.seed(_pve);
    final old = _folder(2), live = _folder(4);
    h.add(old, [_task(old, 1, _pve)]);
    h.add(live, [_task(live, 2, _pve)]);
    await h.start();
    await h.activate(live);
    await h.controller.replay(_pve, _date);
    expect(h.store.history(h.wipes.rows[_pve]!), hasLength(2));
    expect(h.wipes.rows[_pve]!.lastFolder, old.name);
  });

  test('new wipe creates cycle, replays and keeps old cycle', () async {
    final old = h.seed(_pvp);
    final live = _folder(4);
    h.add(live, [_task(live, 1, _pvp)]);
    await h.start();
    await h.activate(live);
    h.lifecycle.publish(_task(live, 2, _pvp));
    await h.controller.settled;
    await h.controller.startNewWipe(_pvp, _date);
    final fresh = h.wipes.rows[_pvp]!;
    expect(fresh.cycleId, isNot(old.cycleId));
    expect(h.store.history(old).single.target.id, 'task-2');
    expect(h.store.history(fresh).single.target.id, 'task-1');
    expect(fresh.lastFolder, isNull);
  });

  test('failed new wipe keeps previous wipe active', () async {
    final old = h.seed(_pvp);
    final live = _folder(4);
    h.add(live, []);
    await h.start();
    await h.activate(live);
    h.store.createFailure = const ProgressStorageFailure('disk');
    await h.controller.startNewWipe(_pvp, _date);
    expect(h.wipes.rows[_pvp]!.cycleId, old.cycleId);
    expect(h.controller.lastResult!.failure, isNotNull);
    expect(h.controller.lastResult!.retryFrom, isNull);
  });

  test('replay in raid is refused with reason', () async {
    h.seed(_pve);
    final live = _folder(4);
    h.add(live, []);
    await h.start();
    await h.activate(live, phase: RaidPhase.inRaid);
    await h.controller.replay(_pve, _date);
    expect(h.readNames, isEmpty);
    expect(h.controller.disabledReason, isNotNull);
  });

  test('second run is refused while one runs', () async {
    h.seed(_pvp);
    final old = _folder(2), live = _folder(4);
    h.add(old, []);
    h.add(live, []);
    h.readEntered[old.path] = Completer();
    h.readRelease[old.path] = Completer();
    await h.start();
    h.lifecycle.setState(folder: live.name);
    await h.readEntered[old.path]!.future;
    expect(h.controller.running, isTrue);
    await h.controller.startNewWipe(_pvp, _date);
    expect(h.store.nextCycle, 1);
    expect(h.controller.disabledReason, isNotNull);
    h.readRelease[old.path]!.complete();
    await h.controller.settled;
  });

  test('raid stops replay after current folder and names it', () async {
    h.seed(_pvp, last: _folder(3));
    final a = _folder(2), b = _folder(3), live = _folder(4);
    h.add(a, [_task(a, 1, _pvp)]);
    h.add(b, [_task(b, 2, _pvp)]);
    h.add(live, []);
    await h.start();
    await h.activate(live);
    h.readEntered[a.path] = Completer();
    h.readRelease[a.path] = Completer();
    final run = h.controller.replay(_pvp, _date);
    await h.readEntered[a.path]!.future;
    h.lifecycle.setState(folder: live.name, phase: RaidPhase.inQueue);
    h.readRelease[a.path]!.complete();
    await run;
    await h.controller.settled;
    expect(h.controller.lastResult!.stoppedByRaid, isTrue);
    expect(h.controller.lastResult!.lastStoredFolder, a.name);
    expect(h.controller.lastResult!.retryFrom, _date);
    expect(h.wipes.rows[_pvp]!.lastFolder, b.name);
    expect(h.store.history(h.wipes.rows[_pvp]!).single.target.id, 'task-1');
  });

  test('replay result counts folders, events and skips', () async {
    h.seed(_pve);
    final old = _folder(2), live = _folder(4);
    h.add(old, [_task(old, 1, _pve)], noMode: 1, rejected: 2);
    h.add(live, [_task(live, 2, _pve)]);
    await h.start();
    await h.activate(live);
    await h.controller.replay(_pve, _date);
    final result = h.controller.lastResult!;
    expect(result.kind, TaskLogRunKind.replay);
    expect(result.modes, {_pve});
    expect(result.foldersRead, 2);
    expect(result.eventsRecorded, 1);
    expect(result.skippedNoMode, 1);
    expect(result.rejectedRecords, 2);
    expect(result.failure, isNull);
  });

  test('unreadable folder is counted and run continues', () async {
    h.seed(_pvp);
    final old = _folder(2), next = _folder(3), live = _folder(4);
    h.add(old, [], unreadable: true);
    h.add(next, [_task(next, 1, _pvp)]);
    h.add(live, []);
    await h.start();
    await h.activate(live);
    await h.controller.replay(_pvp, _date);
    expect(h.controller.lastResult!.unreadableFolders, 1);
    expect(h.store.history(h.wipes.rows[_pvp]!), hasLength(1));
    expect(h.readNames.where((p) => p == old.path), hasLength(2));
  });

  test('invalid record fallback advances and counts rejected record', () async {
    h.seed(_pvp);
    final old = _folder(2), live = _folder(4);
    h.store.rejected['task-2'] = const ProgressInvalidInput('invalid');
    h.add(old, [_task(old, 1, _pvp), _task(old, 2, _pvp), _task(old, 3, _pvp)]);
    h.add(live, []);
    await h.start();
    await h.activate(live);
    expect(h.controller.lastResult!.conflictingRecords, 1);
    expect(h.controller.lastResult!.eventsRecorded, 2);
    expect(h.wipes.rows[_pvp]!.lastFolder, old.name);
  });

  test(
    'large folder chunks share FIFO with live writes without overlap',
    () async {
      h.seed(_pvp);
      final old = _folder(2), live = _folder(4);
      h.add(old, [for (var i = 0; i < 257; i++) _task(old, i, _pvp)]);
      h.add(live, []);
      final entered = Completer<void>(), release = Completer<void>();
      h.store.appendEntered.add(entered);
      h.store.appendRelease.add(release);
      await h.start();
      h.lifecycle.setState(folder: live.name);
      await entered.future;
      h.lifecycle.publish(_task(live, 1000, _pvp));
      release.complete();
      await h.controller.settled;
      expect(h.store.maximumActive, 1);
      expect(h.store.appendSizes, everyElement(lessThanOrEqualTo(256)));
      expect(h.store.history(h.wipes.rows[_pvp]!), hasLength(258));
      expect(
        h.store
            .history(h.wipes.rows[_pvp]!)
            .indexWhere((e) => e.target.id == 'task-1000'),
        256,
      );
    },
  );

  test(
    'catch-up uses the union of wipe ranges but respects each mode range',
    () async {
      final a = _folder(2), b = _folder(3), c = _folder(4), live = _folder(5);
      final pvp = h.seed(_pvp, last: b);
      final pve = h.seed(_pve, start: DateTime(2026, 11, 3), last: a);
      h.add(a, [_task(a, 1, _pvp), _task(a, 2, _pve)]);
      h.add(b, [_task(b, 3, _pvp), _task(b, 4, _pve)]);
      h.add(c, [_task(c, 5, _pvp), _task(c, 6, _pve)]);
      h.add(live, []);
      await h.start();
      await h.activate(live);
      expect(h.readNames, [b.path, c.path]);
      expect(h.store.history(pvp).map((e) => e.target.id), ['task-5']);
      expect(h.store.history(pve).map((e) => e.target.id), [
        'task-4',
        'task-6',
      ]);
      expect(h.wipes.rows[_pvp]!.lastFolder, c.name);
      expect(h.wipes.rows[_pve]!.lastFolder, c.name);
    },
  );

  test('all raid phases refuse replay and new wipe without writes', () async {
    final wipe = h.seed(_pvp);
    final live = _folder(4);
    h.add(live, []);
    await h.start();
    for (final phase in [
      RaidPhase.inQueue,
      RaidPhase.matchFound,
      RaidPhase.raidStarting,
      RaidPhase.inRaid,
    ]) {
      await h.activate(live, phase: phase);
      await h.controller.replay(_pvp, _date);
      await h.controller.startNewWipe(_pvp, _date);
      expect(h.controller.disabledReason, isNotNull);
      expect(h.wipes.rows[_pvp]!.cycleId, wipe.cycleId);
      expect(h.readNames, isEmpty);
      expect(h.store.history(wipe), isEmpty);
    }
  });

  test('enqueueProgress serializes public operations in FIFO order', () async {
    final live = _folder(4);
    h.add(live, []);
    await h.start();
    await h.activate(live);
    final entered = Completer<void>(), release = Completer<void>();
    final order = <String>[];
    final first = h.controller.enqueueProgress(() async {
      order.add('first-start');
      entered.complete();
      await release.future;
      order.add('first-end');
      return 1;
    });
    await entered.future;
    final second = h.controller.enqueueProgress(() async {
      order.add('second');
      return 2;
    });
    expect(order, ['first-start']);
    release.complete();
    expect(await first, 1);
    expect(await second, 2);
    expect(order, ['first-start', 'first-end', 'second']);
  });

  test('later live event remains winner when older catch-up arrives', () async {
    final wipe = h.seed(_pvp);
    final old = _folder(2), live = _folder(4);
    h.add(old, [
      _task(old, 1, _pvp, taskId: 'same', status: ProgressTaskStatus.started),
    ]);
    h.add(live, []);
    h.readEntered[old.path] = Completer();
    h.readRelease[old.path] = Completer();
    await h.start();
    h.lifecycle.setState(folder: live.name);
    await h.readEntered[old.path]!.future;
    h.lifecycle.publish(
      _task(live, 1, _pvp, taskId: 'same', status: ProgressTaskStatus.finished),
    );
    h.readRelease[old.path]!.complete();
    await h.controller.settled;
    expect(h.store.history(wipe), hasLength(2));
    expect(
      h.store.winner(wipe, 'same').value,
      const ProgressTaskState(ProgressTaskStatus.finished),
    );
  });

  for (final kind in ['storage', 'busy', 'unavailable']) {
    test(
      '$kind append failure stops a run before advancing the failed folder',
      () async {
        final wipe = h.seed(_pvp);
        final old = _folder(2), live = _folder(4);
        h.add(old, [_task(old, 1, _pvp)]);
        h.add(live, []);
        h.store.nextAppendFailure = switch (kind) {
          'storage' => const ProgressStorageFailure('disk'),
          'busy' => const ProgressBusy(),
          _ => ProgressUnavailable(scope: wipe.scope, reason: 'damaged'),
        };
        await h.start();
        await h.activate(live);
        expect(h.controller.lastResult!.failure, isNotNull);
        expect(h.wipes.rows[_pvp]!.lastFolder, isNull);
        expect(h.store.history(wipe), isEmpty);
      },
    );
  }

  test('runs are refused until a live folder is known', () async {
    final wipe = h.seed(_pvp);
    await h.start();
    await h.controller.replay(_pvp, _date);
    await h.controller.startNewWipe(_pvp, _date);
    expect(h.controller.disabledReason, isNotNull);
    expect(h.wipes.rows[_pvp]!.cycleId, wipe.cycleId);
    expect(h.readNames, isEmpty);
    expect(h.store.history(wipe), isEmpty);
  });
  test('failed wipe load never replaces a stored active cycle', () async {
    final original = h.seed(_pvp);
    h.wipes.failRead = true;
    final live = _folder(4);
    h.add(live, []);
    await h.start();
    await h.activate(live);
    h.lifecycle.publish(_task(live, 1, _pvp));
    await h.controller.settled;
    expect(h.wipes.rows[_pvp]!.cycleId, original.cycleId);
    expect(h.store.nextCycle, 1);
    expect(h.store.history(original), isEmpty);
    expect(h.controller.error, isNotNull);
  });

  test('live records without a mode are counted and reported', () async {
    final live = _folder(4);
    h.add(live, []);
    await h.start();
    await h.activate(live);
    h.lifecycle.publish(_task(live, 1, null));
    h.lifecycle.publish(_task(live, 2, GameMode.unknown));
    await h.controller.settled;
    expect(h.store.nextCycle, 0);
    expect(h.controller.error, contains('2 no mode'));
  });
}

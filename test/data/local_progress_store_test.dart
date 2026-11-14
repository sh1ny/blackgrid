import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/local_progress.dart';
import 'package:blackgrid/domain/local_progress_store.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/deferred_sqlite.dart';

class _CommitFault extends QueryInterceptor {
  bool failNext = false;

  @override
  Future<void> commitTransaction(TransactionExecutor inner) {
    if (failNext) {
      failNext = false;
      throw StateError('injected commit failure');
    }
    return inner.send();
  }
}

class _SelectBarrier extends QueryInterceptor {
  Completer<void>? entered;
  Completer<void>? release;

  void arm() {
    entered = Completer<void>();
    release = Completer<void>();
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await executor.runSelect(statement, args);
    if (entered != null &&
        statement.toLowerCase().contains('progress_cycles')) {
      final signal = entered!;
      final resume = release!;
      entered = null;
      signal.complete();
      await resume.future;
    }
    return rows;
  }
}

T _success<T>(ProgressResult<T> result) {
  expect(result, isA<ProgressSuccess<T>>());
  return (result as ProgressSuccess<T>).value;
}

void _failure<T, F extends ProgressStoreFailure>(ProgressResult<T> result) {
  expect(result, isA<ProgressFailure<T>>());
  expect((result as ProgressFailure<T>).failure, isA<F>());
}

ProgressEvent _event(
  ProgressScope scope,
  String id, {
  String target = 'objective',
  int time = 1,
  int value = 1,
  String device = 'device',
}) => ProgressEvent(
  eventId: id,
  deviceId: device,
  occurredAtMs: time,
  scope: scope,
  source: ProgressSource.manual,
  target: ProgressTarget(
    kind: ProgressEntityKind.objective,
    id: target,
    field: ProgressField.count,
  ),
  value: ProgressInteger(value),
);

Future<List<Map<String, Object?>>> _rows(
  BlackgridDatabase db,
  String table,
) async => (await db.customSelect('SELECT * FROM $table ORDER BY rowid').get())
    .map((row) => Map<String, Object?>.from(row.data))
    .toList();

Future<List<List<Map<String, Object?>>>> _snapshot(
  BlackgridDatabase db,
) async => [
  await _rows(db, 'progress_cycles'),
  await _rows(db, 'progress_events'),
  await _rows(db, 'progress_heads'),
];

void main() {
  test(
    'cycles and device identity survive reopen without replacing history',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'progress-reopen-',
      );
      final file = File('${directory.path}/progress.sqlite');
      var db = BlackgridDatabase(NativeDatabase(file));
      addTearDown(() async {
        await db.close();
        await directory.delete(recursive: true);
      });
      var store = db as LocalProgressStore;
      final device = _success(await store.progressDeviceId());
      final first = _success(await store.createProgressCycle(GameMode.pvp));
      final event = _event(first.scope, 'persisted');
      _success(await store.appendProgressEvents(first.scope, [event]));
      final before = await _snapshot(db);
      final second = _success(await store.createProgressCycle(GameMode.pvp));
      expect(second.scope, isNot(first.scope));
      await db.close();
      db = BlackgridDatabase(NativeDatabase(file));
      store = db as LocalProgressStore;
      expect(_success(await store.progressDeviceId()), device);
      final cycles = _success(await store.listProgressCycles(GameMode.pvp))
          .cycles;
      expect(
        cycles.map((c) => c.scope),
        containsAll([first.scope, second.scope]),
      );
      expect(await _rows(db, 'progress_events'), before[1]);
    },
  );

  test('missing unknown and mismatched scopes reject atomically', () async {
    final db = BlackgridDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = db as LocalProgressStore;
    final scope = _success(await store.createProgressCycle(GameMode.pvp)).scope;
    final baseline = await _snapshot(db);
    final missing = ProgressScope(mode: GameMode.pvp, cycleId: 'missing');
    final unknown = ProgressScope(
      mode: GameMode.unknown,
      cycleId: scope.cycleId,
    );
    final mismatch = ProgressScope(mode: GameMode.pve, cycleId: scope.cycleId);
    for (final bad in [missing, unknown, mismatch]) {
      _failure<ProgressAppendResult, ProgressInvalidInput>(
        await store.appendProgressEvents(bad, [_event(bad, 'bad')]),
      );
      expect(await _snapshot(db), baseline);
    }
    _failure<ProgressAppendResult, ProgressInvalidInput>(
      await store.appendProgressEvents(scope, [
        _event(scope, 'good'),
        _event(mismatch, 'bad'),
      ]),
    );
    expect(await _snapshot(db), baseline);
    _failure<ProgressCycle, ProgressInvalidInput>(
      await store.createProgressCycle(GameMode.unknown),
    );
    expect(await _snapshot(db), baseline);
  });

  test(
    'identical replay and intra-batch duplicates store each event once',
    () async {
      final db = BlackgridDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = db as LocalProgressStore;
      final scope = _success(await store.createProgressCycle(GameMode.pvp))
          .scope;
      final a = _event(scope, 'a');
      final b = _event(scope, 'b', time: 2, value: 2);
      final first = _success(
        await store.appendProgressEvents(scope, [a, b, a]),
      );
      expect(first.insertedCount, 2);
      final before = await _snapshot(db);
      final replay = _success(
        await store.appendProgressEvents(scope, [a, b, a]),
      );
      expect(replay.insertedCount, 0);
      expect(replay.revision, first.revision);
      expect(await _snapshot(db), before);
      expect(before[1], hasLength(2));
    },
  );

  test(
    'conflicting global identity and failed commit roll back batch and heads',
    () async {
      final fault = _CommitFault();
      final db = BlackgridDatabase(
        NativeDatabase.memory().interceptWith(fault),
      );
      addTearDown(db.close);
      final store = db as LocalProgressStore;
      final scope = _success(await store.createProgressCycle(GameMode.pvp))
          .scope;
      final other = _success(await store.createProgressCycle(GameMode.pve))
          .scope;
      final original = _event(scope, 'original');
      _success(await store.appendProgressEvents(scope, [original]));
      final before = await _snapshot(db);
      _failure<ProgressAppendResult, ProgressIdentityConflict>(
        await store.appendProgressEvents(scope, [
          _event(scope, 'new'),
          _event(scope, 'original', value: 9),
        ]),
      );
      expect(await _snapshot(db), before);
      _failure<ProgressAppendResult, ProgressIdentityConflict>(
        await store.appendProgressEvents(scope, [
          _event(scope, 'duplicate'),
          _event(scope, 'duplicate', value: 7),
        ]),
      );
      expect(await _snapshot(db), before);
      _failure<ProgressAppendResult, ProgressIdentityConflict>(
        await store.appendProgressEvents(other, [
          _event(other, 'other-new'),
          _event(other, 'original'),
        ]),
      );
      expect(await _snapshot(db), before);
      fault.failNext = true;
      _failure<ProgressAppendResult, ProgressStorageFailure>(
        await store.appendProgressEvents(scope, [
          _event(scope, 'commit-new', time: 2, value: 4),
        ]),
      );
      expect(await _snapshot(db), before);
    },
  );

  test(
    'opening valid history returns its actual projection and history',
    () async {
      final db = BlackgridDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = db as LocalProgressStore;
      final scope = _success(await store.createProgressCycle(GameMode.pvp))
          .scope;
      final events = [
        _event(scope, 'a'),
        _event(scope, 'b', time: 2, value: 2),
      ];
      _success(await store.appendProgressEvents(scope, events));
      _success(await store.openProgressCycle(scope));
      expect(_success(await store.readProgressHistory(scope)).events, events);
      expect(_success(await store.readProgressCurrent(scope)).events, [
        events.last,
      ]);
    },
  );

  test(
    'rebuild matches incremental winners across modes and cycles after reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'progress-rebuild-',
      );
      final file = File('${directory.path}/progress.sqlite');
      var db = BlackgridDatabase(NativeDatabase(file));
      addTearDown(() async {
        await db.close();
        await directory.delete(recursive: true);
      });
      var store = db as LocalProgressStore;
      final scopes = [
        _success(await store.createProgressCycle(GameMode.pvp)).scope,
        _success(await store.createProgressCycle(GameMode.pvp)).scope,
        _success(await store.createProgressCycle(GameMode.pve)).scope,
      ];
      for (var i = 0; i < scopes.length; i++) {
        final scope = scopes[i];
        _success(
          await store.appendProgressEvents(scope, [
            _event(scope, 'new-$i', time: 10, value: i + 3),
            _event(scope, 'old-$i', time: 1, value: i),
            _event(scope, 'other-$i', target: 'other', value: 5),
          ]),
        );
      }
      final before = await _snapshot(db);
      final projections = <List<ProgressEvent>>[];
      for (final scope in scopes) {
        projections.add(
          _success(await store.readProgressCurrent(scope)).events,
        );
      }
      await db.close();
      db = BlackgridDatabase(NativeDatabase(file));
      store = db as LocalProgressStore;
      for (var i = 0; i < scopes.length; i++) {
        _success(await store.rebuildProgress(scopes[i]));
        expect(
          _success(await store.readProgressCurrent(scopes[i])).events,
          projections[i],
        );
      }
      expect((await _snapshot(db))[1], before[1]);
    },
  );

  test(
    'failed rebuild rolls back heads and preserves immutable event bytes',
    () async {
      final fault = _CommitFault();
      final db = BlackgridDatabase(
        NativeDatabase.memory().interceptWith(fault),
      );
      addTearDown(db.close);
      final store = db as LocalProgressStore;
      final scope = _success(await store.createProgressCycle(GameMode.pvp))
          .scope;
      _success(
        await store.appendProgressEvents(scope, [
          _event(scope, 'a'),
          _event(scope, 'b', target: 'other'),
        ]),
      );
      final before = await _snapshot(db);
      fault.failNext = true;
      _failure<ProgressCycle, ProgressStorageFailure>(
        await store.rebuildProgress(scope),
      );
      expect(await _snapshot(db), before);
    },
  );

  test(
    'current-value continuation returns each register at one revision',
    () async {
      final db = BlackgridDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = db as LocalProgressStore;
      final scope = _success(await store.createProgressCycle(GameMode.pvp))
          .scope;
      final events = [
        for (var i = 0; i < 3; i++) _event(scope, 'e$i', target: 'target$i'),
      ];
      _success(await store.appendProgressEvents(scope, events));
      final first = _success(await store.readProgressCurrent(scope, limit: 1));
      final second = _success(
        await store.readProgressCurrent(
          scope,
          limit: 1,
          cursor: first.nextCursor,
        ),
      );
      final last = _success(
        await store.readProgressCurrent(
          scope,
          limit: 1,
          cursor: second.nextCursor,
        ),
      );
      expect([
        first.revision,
        second.revision,
        last.revision,
      ], everyElement(first.revision));
      expect([...first.events, ...second.events, ...last.events], events);
      expect(last.nextCursor, isNull);
      _success(
        await store.appendProgressEvents(scope, [
          _event(scope, 'later', target: 'target2', time: 2),
        ]),
      );
      _failure<ProgressCurrentPage, ProgressStaleCursor>(
        await store.readProgressCurrent(
          scope,
          limit: 1,
          cursor: first.nextCursor,
        ),
      );
      final other = _success(await store.createProgressCycle(GameMode.pve))
          .scope;
      _failure<ProgressCurrentPage, ProgressInvalidInput>(
        await store.readProgressCurrent(other, cursor: first.nextCursor),
      );
    },
  );

  test(
    'history high-water cursor excludes concurrent appends without omissions',
    () async {
      final db = BlackgridDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = db as LocalProgressStore;
      final scope = _success(await store.createProgressCycle(GameMode.pvp))
          .scope;
      final events = [
        for (var i = 0; i < 5; i++) _event(scope, 'e$i', time: i),
      ];
      _success(await store.appendProgressEvents(scope, events));
      final first = _success(await store.readProgressHistory(scope, limit: 2));
      _success(
        await store.appendProgressEvents(scope, [
          _event(scope, 'late', time: 0),
        ]),
      );
      final second = _success(
        await store.readProgressHistory(
          scope,
          limit: 2,
          cursor: first.nextCursor,
        ),
      );
      final last = _success(
        await store.readProgressHistory(
          scope,
          limit: 2,
          cursor: second.nextCursor,
        ),
      );
      expect([...first.events, ...second.events, ...last.events], events);
      expect(last.nextCursor, isNull);
      final other = _success(await store.createProgressCycle(GameMode.pve))
          .scope;
      _failure<ProgressHistoryPage, ProgressInvalidInput>(
        await store.readProgressHistory(other, cursor: first.nextCursor),
      );
      _failure<ProgressHistoryPage, ProgressInvalidInput>(
        await store.readProgressHistory(
          scope,
          cursor: ProgressHistoryCursor(
            scope: scope,
            highWaterSequence: 1,
            lastSequence: 2,
          ),
        ),
      );
    },
  );

  test('readProgressEvent returns the event and keeps the revision', () async {
    var nextId = 0;
    final db = BlackgridDatabase(
      NativeDatabase.memory(),
      progressClock: () => DateTime.utc(2026),
      progressIdGenerator: () => 'generated-${nextId++}',
    );
    addTearDown(db.close);
    final store = db as LocalProgressStore;
    final scope = _success(await store.createProgressCycle(GameMode.pve)).scope;
    const target = ProgressTarget(
      kind: ProgressEntityKind.player,
      id: 'self',
      field: ProgressField.level,
    );
    final event = ProgressEvent(
      eventId: 'level-34',
      deviceId: 'device',
      occurredAtMs: 100,
      scope: scope,
      source: ProgressSource.manual,
      target: target,
      value: const ProgressInteger(34),
    );
    final undo = ProgressEvent(
      eventId: 'undo-level-34',
      deviceId: 'device',
      occurredAtMs: 101,
      scope: scope,
      source: ProgressSource.manual,
      target: target,
      value: const ProgressUnset(),
      undoOf: event.eventId,
    );
    final append = _success(
      await store.appendProgressEvents(scope, [event, undo]),
    );
    final before = await _snapshot(db);

    expect(
      _success(await store.readProgressEvent(scope, event.eventId)),
      event,
    );
    expect(_success(await store.readProgressEvent(scope, undo.eventId)), undo);
    expect(
      _success(await store.readProgressCurrent(scope)).revision,
      append.revision,
    );
    expect(await _snapshot(db), before);
  });

  test("readProgressEvent does not find another cycle's event", () async {
    var nextId = 0;
    final db = BlackgridDatabase(
      NativeDatabase.memory(),
      progressClock: () => DateTime.utc(2026),
      progressIdGenerator: () => 'generated-${nextId++}',
    );
    addTearDown(db.close);
    final store = db as LocalProgressStore;
    final scope = _success(await store.createProgressCycle(GameMode.pve)).scope;
    final otherCycle = _success(await store.createProgressCycle(GameMode.pve))
        .scope;
    final otherMode = _success(await store.createProgressCycle(GameMode.pvp))
        .scope;
    for (final (foreignScope, id) in [
      (otherCycle, 'other-cycle'),
      (otherMode, 'other-mode'),
    ]) {
      _success(
        await store.appendProgressEvents(foreignScope, [
          _event(foreignScope, id),
        ]),
      );
    }
    await db.customStatement(
      'UPDATE progress_events SET canonical_payload = ? WHERE event_id IN (?, ?)',
      ['{broken', 'other-cycle', 'other-mode'],
    );
    final before = await _snapshot(db);

    for (final id in ['other-cycle', 'other-mode', 'missing']) {
      expect(_success(await store.readProgressEvent(scope, id)), isNull);
    }
    expect(await _snapshot(db), before);
  });

  test('readProgressEvent reports a damaged event as unavailable', () async {
    for (final corruption in <(String, List<Object?>)>[
      ('UPDATE progress_events SET canonical_payload = ?', ['{broken']),
      ('UPDATE progress_events SET format_version = ?', [2]),
      ('UPDATE progress_events SET device_id = ?', ['wrong-device']),
    ]) {
      var nextId = 0;
      final db = BlackgridDatabase(
        NativeDatabase.memory(),
        progressClock: () => DateTime.utc(2026),
        progressIdGenerator: () => 'generated-${nextId++}',
      );
      try {
        final store = db as LocalProgressStore;
        final scope = _success(await store.createProgressCycle(GameMode.pve))
            .scope;
        final event = _event(scope, 'damaged');
        _success(await store.appendProgressEvents(scope, [event]));
        await db.customStatement(corruption.$1, corruption.$2);
        final before = await _snapshot(db);

        final result = await store.readProgressEvent(scope, event.eventId);
        _failure<ProgressEvent?, ProgressUnavailable>(result);
        expect(
          ((result as ProgressFailure<ProgressEvent?>).failure
                  as ProgressUnavailable)
              .scope,
          scope,
        );
        expect(await _snapshot(db), before);
      } finally {
        await db.close();
      }
    }
  });

  test('malformed future and envelope-mismatched stored events make the cycle unavailable', () async {
    for (final corruption in <(String, List<Object?>)>[
      ('UPDATE progress_events SET canonical_payload = ?', ['{broken']),
      (
        'UPDATE progress_events SET format_version = 2, canonical_payload = replace(canonical_payload, ?, ?)',
        ['"formatVersion":1', '"formatVersion":2'],
      ),
      ('UPDATE progress_events SET format_version = ?', [2]),
      ('UPDATE progress_events SET device_id = ?', ['wrong-device']),
      ('UPDATE progress_events SET occurred_at_ms = ?', [12345]),
      ('UPDATE progress_events SET source_rank = ?', [1]),
      ('UPDATE progress_events SET undo_of = ?', ['wrong-link']),
      ('UPDATE progress_events SET entity_id = ?', ['wrong-target']),
      (
        'UPDATE progress_events SET canonical_payload = ?',
        ['x' * (progressEventByteLimit + 1)],
      ),
    ]) {
      final directory = await Directory.systemTemp.createTemp(
        'progress-corrupt-',
      );
      final file = File('${directory.path}/progress.sqlite');
      var db = BlackgridDatabase(NativeDatabase(file));
      try {
        var store = db as LocalProgressStore;
        final scope = _success(await store.createProgressCycle(GameMode.pvp))
            .scope;
        _success(
          await store.appendProgressEvents(scope, [_event(scope, 'valid')]),
        );
        await db.customStatement(corruption.$1, corruption.$2);
        final damaged = await _rows(db, 'progress_events');
        await db.close();
        db = BlackgridDatabase(NativeDatabase(file));
        store = db as LocalProgressStore;
        _failure<ProgressCycle, ProgressUnavailable>(
          await store.openProgressCycle(scope),
        );
        _failure<ProgressHistoryPage, ProgressUnavailable>(
          await store.readProgressHistory(scope),
        );
        _failure<ProgressCurrentPage, ProgressUnavailable>(
          await store.readProgressCurrent(scope),
        );
        expect(await _rows(db, 'progress_events'), damaged);
      } finally {
        await db.close();
        await directory.delete(recursive: true);
      }
    }
  });

  test(
    'busy and record-byte-page limits reject without partial work',
    () async {
      final barrier = _SelectBarrier();
      final db = BlackgridDatabase(
        NativeDatabase.memory().interceptWith(barrier),
      );
      addTearDown(db.close);
      final store = db as LocalProgressStore;
      final scope = _success(await store.createProgressCycle(GameMode.pvp))
          .scope;
      final before = await _snapshot(db);
      var consumed = 0;
      Iterable<ProgressEvent> tooMany() sync* {
        while (true) {
          consumed++;
          yield _event(scope, 'e$consumed');
        }
      }

      _failure<ProgressAppendResult, ProgressInvalidInput>(
        await store.appendProgressEvents(scope, tooMany()),
      );
      expect(consumed, lessThanOrEqualTo(progressPageLimit + 1));
      _failure<ProgressAppendResult, ProgressInvalidInput>(
        await store.appendProgressEvents(scope, []),
      );
      _failure<ProgressAppendResult, ProgressInvalidInput>(
        await store.appendProgressEvents(scope, [
          _event(scope, 'x' * progressEventByteLimit),
        ]),
      );
      for (final limit in [0, progressPageLimit + 1]) {
        _failure<ProgressHistoryPage, ProgressInvalidInput>(
          await store.readProgressHistory(scope, limit: limit),
        );
        _failure<ProgressCurrentPage, ProgressInvalidInput>(
          await store.readProgressCurrent(scope, limit: limit),
        );
        _failure<ProgressCyclePage, ProgressInvalidInput>(
          await store.listProgressCycles(GameMode.pvp, limit: limit),
        );
      }
      expect(await _snapshot(db), before);
      barrier.arm();
      final entered = barrier.entered!;
      final release = barrier.release!;
      final pending = store.openProgressCycle(scope);
      final reached = await Future.any([
        entered.future.then((_) => true),
        pending.then((_) => false),
      ]);
      try {
        expect(reached, isTrue, reason: 'open must reach its real cycle query');
        _failure<String, ProgressBusy>(await store.progressDeviceId());
        _failure<ProgressCycle, ProgressBusy>(
          await store.createProgressCycle(GameMode.pvp),
        );
        _failure<ProgressCyclePage, ProgressBusy>(
          await store.listProgressCycles(GameMode.pvp),
        );
        _failure<ProgressCycle, ProgressBusy>(
          await store.openProgressCycle(scope),
        );
        _failure<ProgressAppendResult, ProgressBusy>(
          await store.appendProgressEvents(scope, [_event(scope, 'busy')]),
        );
        _failure<ProgressHistoryPage, ProgressBusy>(
          await store.readProgressHistory(scope),
        );
        _failure<ProgressCurrentPage, ProgressBusy>(
          await store.readProgressCurrent(scope),
        );
        _failure<ProgressCycle, ProgressBusy>(
          await store.rebuildProgress(scope),
        );
        _failure<ProgressEvent, ProgressBusy>(
          await store.undoProgress(
            scope,
            targetEventId: 'x',
            requestEventId: 'y',
          ),
        );
      } finally {
        release.complete();
        await pending;
      }
    },
  );

  test(
    'second-instance commit cannot mix revisions during the final page',
    () async {
      for (final finalPage in [false, true]) {
        final directory = await Directory.systemTemp.createTemp(
          'progress-race-',
        );
        final file = File('${directory.path}/progress.sqlite');
        final barrier = _SelectBarrier();
        final db = BlackgridDatabase(
          deferredSqlite(file).interceptWith(barrier),
        );
        final otherDb = BlackgridDatabase(NativeDatabase(file));
        try {
          await db.customStatement('PRAGMA journal_mode=WAL');
          await otherDb.customStatement('PRAGMA journal_mode=WAL');
          final store = db as LocalProgressStore;
          final other = otherDb as LocalProgressStore;
          final scope = _success(await store.createProgressCycle(GameMode.pvp))
              .scope;
          final events = [
            for (var i = 0; i < 3; i++)
              _event(scope, 'race$i', target: 'target$i'),
          ];
          _success(await store.appendProgressEvents(scope, events));
          final first = _success(
            await store.readProgressCurrent(scope, limit: 1),
          );
          var cursor = first.nextCursor;
          if (finalPage) {
            cursor = _success(
              await store.readProgressCurrent(scope, limit: 1, cursor: cursor),
            ).nextCursor;
          }
          barrier.arm();
          final entered = barrier.entered!;
          final release = barrier.release!;
          final pending = store.readProgressCurrent(
            scope,
            limit: 1,
            cursor: cursor,
          );
          final reached = await Future.any([
            entered.future.then((_) => true),
            pending.then((_) => false),
          ]);
          try {
            expect(
              reached,
              isTrue,
              reason: 'continuation must check the real cycle row',
            );
            final target = finalPage ? 'target2' : 'target1';
            _success(
              await other.appendProgressEvents(scope, [
                _event(scope, 'racing-write', target: target, time: 3),
              ]),
            );
          } finally {
            release.complete();
          }
          final result = await pending;
          if (result is ProgressSuccess<ProgressCurrentPage>) {
            expect(result.value.revision, first.revision);
            expect(
              result.value.events.single.eventId,
              finalPage ? 'race2' : 'race1',
            );
          } else {
            final failure =
                (result as ProgressFailure<ProgressCurrentPage>).failure;
            expect(
              failure,
              anyOf(isA<ProgressStaleCursor>(), isA<ProgressStorageFailure>()),
            );
          }
        } finally {
          await otherDb.close();
          await db.close();
          await directory.delete(recursive: true);
        }
      }
    },
  );

  test('cycle listing uses bounded mode-scoped keyset continuation', () async {
    final db = BlackgridDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = db as LocalProgressStore;
    final expected = <ProgressScope>[];
    for (var i = 0; i < 4; i++) {
      expected.add(
        _success(await store.createProgressCycle(GameMode.pvp)).scope,
      );
    }
    _success(await store.createProgressCycle(GameMode.pve));
    final found = <ProgressScope>[];
    String? cursor;
    do {
      final page = _success(
        await store.listProgressCycles(
          GameMode.pvp,
          limit: 2,
          afterCycleId: cursor,
        ),
      );
      expect(page.cycles.length, lessThanOrEqualTo(2));
      found.addAll(page.cycles.map((cycle) => cycle.scope));
      cursor = page.nextCursor;
    } while (cursor != null);
    expect(found, hasLength(expected.length));
    expect(found.toSet(), expected.toSet());
    _failure<ProgressCyclePage, ProgressInvalidInput>(
      await store.listProgressCycles(GameMode.unknown),
    );
    for (final invalid in ['', 'x' * progressIdentityTokenLimit]) {
      _failure<ProgressCyclePage, ProgressInvalidInput>(
        await store.listProgressCycles(GameMode.pvp, afterCycleId: invalid),
      );
    }
  });

  test(
    'undo appends the predecessor value and retains original facts',
    () async {
      final db = BlackgridDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = db as LocalProgressStore;
      final scope = _success(await store.createProgressCycle(GameMode.pvp))
          .scope;
      final old = _event(scope, 'old', value: 2);
      final current = _event(scope, 'current', time: 2, value: 5);
      _success(await store.appendProgressEvents(scope, [old, current]));
      final undo = _success(
        await store.undoProgress(
          scope,
          targetEventId: current.eventId,
          requestEventId: 'undo',
        ),
      );
      expect(undo.value, const ProgressInteger(2));
      expect(undo.undoOf, current.eventId);
      expect(undo.source, ProgressSource.manual);
      expect(undo.occurredAtMs, greaterThan(current.occurredAtMs));
      expect(_success(await store.readProgressHistory(scope)).events, [
        old,
        current,
        undo,
      ]);
      expect(_success(await store.readProgressCurrent(scope)).events, [undo]);
      final before = await _snapshot(db);
      _success(await store.appendProgressEvents(scope, [current]));
      expect(await _snapshot(db), before);
    },
  );

  test('undo first value records unset and repeated request returns one compensation', () async {
    final db = BlackgridDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = db as LocalProgressStore;
    final scope = _success(await store.createProgressCycle(GameMode.pvp)).scope;
    final event = _event(scope, 'first');
    _success(await store.appendProgressEvents(scope, [event]));
    final undo = _success(
      await store.undoProgress(
        scope,
        targetEventId: 'first',
        requestEventId: 'request',
      ),
    );
    expect(undo.value, const ProgressUnset());
    expect(undo.undoOf, 'first');
    final before = await _snapshot(db);
    expect(
      _success(
        await store.undoProgress(
          scope,
          targetEventId: 'first',
          requestEventId: 'request',
        ),
      ),
      undo,
    );
    expect(await _snapshot(db), before);
    final later = _event(scope, 'later', time: undo.occurredAtMs + 1, value: 9);
    _success(await store.appendProgressEvents(scope, [later]));
    final afterLater = await _snapshot(db);
    expect(
      _success(
        await store.undoProgress(
          scope,
          targetEventId: 'first',
          requestEventId: 'request',
        ),
      ),
      undo,
    );
    expect(await _snapshot(db), afterLater);
    _failure<ProgressEvent, ProgressIdentityConflict>(
      await store.undoProgress(
        scope,
        targetEventId: 'later',
        requestEventId: 'request',
      ),
    );
    expect(await _snapshot(db), afterLater);
    expect(_success(await store.readProgressHistory(scope)).events, [
      event,
      undo,
      later,
    ]);
  });

  test('stale undo cannot erase a later winning event', () async {
    final db = BlackgridDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = db as LocalProgressStore;
    final scope = _success(await store.createProgressCycle(GameMode.pvp)).scope;
    final first = _event(scope, 'first');
    final second = _event(scope, 'second', time: 2, value: 2);
    _success(await store.appendProgressEvents(scope, [first, second]));
    final before = await _snapshot(db);
    _failure<ProgressEvent, ProgressUndoConflict>(
      await store.undoProgress(
        scope,
        targetEventId: 'first',
        requestEventId: 'stale',
      ),
    );
    expect(await _snapshot(db), before);
    expect(_success(await store.readProgressCurrent(scope)).events, [second]);
  });

  test('undo commit failure leaves history and projection unchanged', () async {
    final fault = _CommitFault();
    final db = BlackgridDatabase(NativeDatabase.memory().interceptWith(fault));
    addTearDown(db.close);
    final store = db as LocalProgressStore;
    final scope = _success(await store.createProgressCycle(GameMode.pvp)).scope;
    _success(
      await store.appendProgressEvents(scope, [_event(scope, 'winner')]),
    );
    final before = await _snapshot(db);
    fault.failNext = true;
    _failure<ProgressEvent, ProgressStorageFailure>(
      await store.undoProgress(
        scope,
        targetEventId: 'winner',
        requestEventId: 'failed-undo',
      ),
    );
    expect(await _snapshot(db), before);
  });

  test(
    'maximum encoded edition survives undo and undo of compensation',
    () async {
      String id(String prefix) => prefix + 'x' * (254 - prefix.length);
      final generated = [id('device'), id('cycle'), id('spare')].iterator;
      final db = BlackgridDatabase(
        NativeDatabase.memory(),
        progressClock: () =>
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        progressIdGenerator: () {
          if (!generated.moveNext()) {
            throw StateError('unexpected ID generation');
          }
          return generated.current;
        },
      );
      addTearDown(db.close);
      final store = db as LocalProgressStore;
      final scope = _success(await store.createProgressCycle(GameMode.pvp))
          .scope;
      final device = _success(await store.progressDeviceId());
      expect(
        utf8.encode(jsonEncode(scope.cycleId)),
        hasLength(progressIdentityTokenLimit),
      );
      expect(
        utf8.encode(jsonEncode(device)),
        hasLength(progressIdentityTokenLimit),
      );
      final edition = '${'\\' * 510}ab';
      expect(
        utf8.encode(jsonEncode(edition)),
        hasLength(progressTextTokenLimit),
      );
      const target = ProgressTarget(
        kind: ProgressEntityKind.player,
        id: 'self',
        field: ProgressField.edition,
      );
      ProgressEvent event(String eventId, int time, String value) =>
          ProgressEvent(
            eventId: eventId,
            deviceId: device,
            occurredAtMs: time,
            scope: scope,
            source: ProgressSource.manual,
            target: target,
            value: ProgressText(value),
          );
      final original = event(
        id('original'),
        progressMaxTimestampMs - 3,
        edition,
      );
      final replacement = event(
        id('replacement'),
        progressMaxTimestampMs - 2,
        'other',
      );
      _success(
        await store.appendProgressEvents(scope, [original, replacement]),
      );
      final first = _success(
        await store.undoProgress(
          scope,
          targetEventId: replacement.eventId,
          requestEventId: id('undo-one'),
        ),
      );
      expect(first.value, ProgressText(edition));
      expect(first.occurredAtMs, progressMaxTimestampMs - 1);
      final second = _success(
        await store.undoProgress(
          scope,
          targetEventId: first.eventId,
          requestEventId: id('undo-two'),
        ),
      );
      expect(second.value, const ProgressText('other'));
      expect(second.occurredAtMs, progressMaxTimestampMs);
      for (final compensation in [first, second]) {
        expect(
          utf8.encode(ProgressEventCodec.encode(compensation)).length,
          lessThanOrEqualTo(progressEventByteLimit),
        );
        expect(
          utf8.encode(jsonEncode(compensation.eventId)),
          hasLength(progressIdentityTokenLimit),
        );
        expect(
          utf8.encode(jsonEncode(compensation.undoOf)),
          hasLength(progressIdentityTokenLimit),
        );
      }
      expect(_success(await store.readProgressHistory(scope)).events, [
        original,
        replacement,
        first,
        second,
      ]);
      final before = await _snapshot(db);
      _failure<ProgressEvent, ProgressInvalidInput>(
        await store.undoProgress(
          scope,
          targetEventId: second.eventId,
          requestEventId: id('overflow'),
        ),
      );
      expect(await _snapshot(db), before);
    },
  );

  test('over-budget escaped tokens reject the entire batch', () async {
    final db = BlackgridDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = db as LocalProgressStore;
    final scope = _success(await store.createProgressCycle(GameMode.pvp)).scope;
    _success(
      await store.appendProgressEvents(scope, [_event(scope, 'original')]),
    );
    final before = await _snapshot(db);
    final invalidId = '${'\\' * 127}x';
    final invalidEdition = '${'\\' * 511}x';
    expect(
      utf8.encode(jsonEncode(invalidId)).length,
      greaterThan(progressIdentityTokenLimit),
    );
    expect(
      utf8.encode(jsonEncode(invalidEdition)).length,
      greaterThan(progressTextTokenLimit),
    );
    final invalid = ProgressEvent(
      eventId: 'invalid-edition',
      deviceId: 'device',
      occurredAtMs: 1,
      scope: scope,
      source: ProgressSource.manual,
      target: const ProgressTarget(
        kind: ProgressEntityKind.player,
        id: 'self',
        field: ProgressField.edition,
      ),
      value: ProgressText(invalidEdition),
    );
    for (final bad in [_event(scope, invalidId), invalid]) {
      _failure<ProgressAppendResult, ProgressInvalidInput>(
        await store.appendProgressEvents(scope, [
          _event(scope, 'valid-new'),
          bad,
        ]),
      );
      expect(await _snapshot(db), before);
    }
  });

  test(
    'unicode ordinal tie winners and undo predecessors use the pure comparator',
    () async {
      final db = BlackgridDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = db as LocalProgressStore;
      final scope = _success(await store.createProgressCycle(GameMode.pvp))
          .scope;
      final astral = _event(scope, 'astral', device: '\u{10000}', value: 1);
      final bmp = _event(scope, 'bmp', device: '\uE000', value: 2);
      expect(compareProgressEvents(bmp, astral), greaterThan(0));
      _success(await store.appendProgressEvents(scope, [bmp, astral]));
      expect(_success(await store.readProgressCurrent(scope)).events, [bmp]);
      _success(await store.rebuildProgress(scope));
      expect(_success(await store.readProgressCurrent(scope)).events, [bmp]);
      final newest = _event(scope, 'newest', time: 2, value: 3);
      _success(await store.appendProgressEvents(scope, [newest]));
      final undo = _success(
        await store.undoProgress(
          scope,
          targetEventId: 'newest',
          requestEventId: 'undo-unicode',
        ),
      );
      expect(undo.value, bmp.value);
    },
  );

  test('malformed Unicode identities reject atomically and valid pairs survive reopen', () async {
    final directory = await Directory.systemTemp.createTemp(
      'progress-unicode-',
    );
    final file = File('${directory.path}/progress.sqlite');
    var identity = 0;
    var db = BlackgridDatabase(
      NativeDatabase(file),
      progressIdGenerator: () => 'local-\u{1F600}-${identity++}',
    );
    addTearDown(() async {
      await db.close();
      await directory.delete(recursive: true);
    });
    LocalProgressStore store = db;
    final device = _success(await store.progressDeviceId());
    final scope = _success(await store.createProgressCycle(GameMode.pvp)).scope;
    final baseline = _event(scope, 'baseline');
    _success(await store.appendProgressEvents(scope, [baseline]));
    final before = await _snapshot(db);
    for (final invalid in [
      String.fromCharCode(0xD800),
      String.fromCharCode(0xDC00),
    ]) {
      _failure<ProgressAppendResult, ProgressInvalidInput>(
        await store.appendProgressEvents(scope, [
          _event(scope, 'valid-new'),
          _event(scope, 'invalid', device: invalid),
        ]),
      );
      expect(await _snapshot(db), before);
    }
    final valid = _event(
      scope,
      'event-\u{1F600}',
      device: 'origin-\u{1F600}',
      target: 'objective-\u{1F600}',
      time: 2,
      value: 9,
    );
    _success(await store.appendProgressEvents(scope, [valid]));
    final undo = _success(
      await store.undoProgress(
        scope,
        targetEventId: valid.eventId,
        requestEventId: 'undo-\u{1F600}',
      ),
    );
    expect(undo.undoOf, valid.eventId);
    expect(undo.value, const ProgressUnset());
    await db.close();
    db = BlackgridDatabase(NativeDatabase(file));
    store = db;
    expect(_success(await store.progressDeviceId()), device);
    _success(await store.openProgressCycle(scope));
    expect(_success(await store.readProgressHistory(scope)).events, [
      baseline,
      valid,
      undo,
    ]);
    expect(_success(await store.readProgressCurrent(scope)).events.toSet(), {
      baseline,
      undo,
    });
  });
}

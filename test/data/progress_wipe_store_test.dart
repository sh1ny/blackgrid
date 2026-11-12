import 'dart:io';

import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/local_progress.dart';
import 'package:blackgrid/domain/local_progress_store.dart';
import 'package:blackgrid/domain/progress_wipe_store.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

T _success<T>(ProgressResult<T> result) {
  expect(result, isA<ProgressSuccess<T>>());
  return (result as ProgressSuccess<T>).value;
}

Future<ProgressCycle> _cycle(BlackgridDatabase db, GameMode mode) async =>
    _success(await db.createProgressCycle(mode));

ProgressWipe _wipe(
  ProgressCycle cycle, {
  DateTime? startDate,
  String? lastFolder,
  int updatedAtMs = 1,
}) => ProgressWipe(
  mode: cycle.scope.mode,
  cycleId: cycle.scope.cycleId,
  startDate: startDate ?? DateTime(2026, 11, 2),
  lastFolder: lastFolder,
  updatedAtMs: updatedAtMs,
);

void _expectWipe(ProgressWipe actual, ProgressWipe expected) {
  expect(actual.mode, expected.mode);
  expect(actual.cycleId, expected.cycleId);
  expect(actual.startDate, expected.startDate);
  expect(actual.lastFolder, expected.lastFolder);
  expect(actual.updatedAtMs, expected.updatedAtMs);
}

void main() {
  test('wipe row survives reopening the database', () async {
    final directory = await Directory.systemTemp.createTemp('wipe-reopen-');
    final file = File('${directory.path}/progress.sqlite');
    var db = BlackgridDatabase(NativeDatabase(file));
    addTearDown(() async {
      await db.close();
      await directory.delete(recursive: true);
    });
    final cycle = await _cycle(db, GameMode.pve);
    final wipe = _wipe(
      cycle,
      lastFolder: 'log_2026.11.02_9-00-00_1.3.0.0.48484',
      updatedAtMs: 1234,
    );
    await db.replaceProgressWipe(wipe);
    await db.close();
    db = BlackgridDatabase(NativeDatabase(file));
    final rows = await db.readProgressWipes();
    expect(rows, hasLength(1));
    _expectWipe(rows.single, wipe);
  });

  test(
    'replacing one mode leaves other wipes and old cycle history intact',
    () async {
      final db = BlackgridDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final oldCycle = await _cycle(db, GameMode.pvp);
      final newCycle = await _cycle(db, GameMode.pvp);
      final pveCycle = await _cycle(db, GameMode.pve);
      final event = ProgressEvent(
        eventId: 'old-event',
        deviceId: 'device',
        occurredAtMs: 123,
        scope: oldCycle.scope,
        source: ProgressSource.log,
        target: const ProgressTarget(
          kind: ProgressEntityKind.task,
          id: 'task',
          field: ProgressField.state,
        ),
        value: const ProgressTaskState(ProgressTaskStatus.finished),
      );
      _success(await db.appendProgressEvents(oldCycle.scope, [event]));
      final pve = _wipe(pveCycle, updatedAtMs: 2);
      await db.replaceProgressWipe(_wipe(oldCycle));
      await db.replaceProgressWipe(pve);
      final replacement = _wipe(
        newCycle,
        startDate: DateTime(2026, 11, 12),
        updatedAtMs: 3,
      );
      await db.replaceProgressWipe(replacement);
      final rows = await db.readProgressWipes();
      expect(rows, hasLength(2));
      _expectWipe(
        rows.singleWhere((row) => row.mode == GameMode.pvp),
        replacement,
      );
      _expectWipe(rows.singleWhere((row) => row.mode == GameMode.pve), pve);
      final history = _success(await db.readProgressHistory(oldCycle.scope));
      expect(history.events, [event]);
    },
  );

  test(
    'last folder advances by date-time then name and never goes backward',
    () async {
      final db = BlackgridDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final pvp = await _cycle(db, GameMode.pvp);
      final pve = await _cycle(db, GameMode.pve);
      const nine = 'log_2026.11.02_9-00-00_1.3.0.0.48484';
      const tenA = 'log_2026.11.02_10-00-00_1.3.0.0.48484';
      const tenB = 'log_2026.11.02_10-00-00_1.3.0.0.48485';
      await db.replaceProgressWipe(_wipe(pvp));
      await db.replaceProgressWipe(_wipe(pve, lastFolder: nine));
      await db.advanceProgressWipeFolder(GameMode.pvp, nine, 2);
      expect(
        (await db.readProgressWipes())
            .singleWhere((w) => w.mode == GameMode.pvp)
            .lastFolder,
        nine,
      );
      expect(
        (await db.readProgressWipes())
            .singleWhere((w) => w.mode == GameMode.pvp)
            .updatedAtMs,
        2,
      );
      await db.advanceProgressWipeFolder(GameMode.pvp, tenA, 3);
      await db.advanceProgressWipeFolder(GameMode.pvp, tenB, 4);
      expect(
        (await db.readProgressWipes())
            .singleWhere((w) => w.mode == GameMode.pvp)
            .updatedAtMs,
        4,
      );
      await db.advanceProgressWipeFolder(GameMode.pvp, nine, 5);
      await db.advanceProgressWipeFolder(GameMode.pvp, tenA, 6);
      final rows = await db.readProgressWipes();
      expect(rows.singleWhere((w) => w.mode == GameMode.pvp).lastFolder, tenB);
      expect(rows.singleWhere((w) => w.mode == GameMode.pve).lastFolder, nine);
    },
  );

  test('start date moves only earlier and leaves other modes alone', () async {
    final db = BlackgridDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final pvp = await _cycle(db, GameMode.pvp);
    final pve = await _cycle(db, GameMode.pve);
    await db.replaceProgressWipe(_wipe(pvp));
    await db.replaceProgressWipe(_wipe(pve));
    await db.moveProgressWipeStartEarlier(
      GameMode.pvp,
      DateTime(2026, 10, 20),
      2,
    );
    expect(
      (await db.readProgressWipes())
          .singleWhere((w) => w.mode == GameMode.pvp)
          .updatedAtMs,
      2,
    );
    await db.moveProgressWipeStartEarlier(
      GameMode.pvp,
      DateTime(2026, 11, 12),
      3,
    );
    final rows = await db.readProgressWipes();
    expect(
      rows.singleWhere((w) => w.mode == GameMode.pvp).startDate,
      DateTime(2026, 10, 20),
    );
    expect(
      rows.singleWhere((w) => w.mode == GameMode.pve).startDate,
      DateTime(2026, 11, 2),
    );
  });

  test('wipe requires an existing cycle with the same mode', () async {
    final db = BlackgridDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final pvp = await _cycle(db, GameMode.pvp);
    final valid = _wipe(pvp);
    await db.replaceProgressWipe(valid);
    for (final bad in [
      ProgressWipe(
        mode: GameMode.pvp,
        cycleId: 'missing',
        startDate: DateTime(2026, 11, 2),
        lastFolder: null,
        updatedAtMs: 2,
      ),
      ProgressWipe(
        mode: GameMode.pve,
        cycleId: pvp.scope.cycleId,
        startDate: DateTime(2026, 11, 2),
        lastFolder: null,
        updatedAtMs: 3,
      ),
    ]) {
      await expectLater(db.replaceProgressWipe(bad), throwsA(anything));
      final rows = await db.readProgressWipes();
      expect(rows, hasLength(1));
      _expectWipe(rows.single, valid);
    }
    await expectLater(
      db.customStatement(
        'INSERT INTO progress_wipes '
        '(mode, cycle_id, start_date, last_folder, updated_at_ms) '
        'VALUES (?, ?, ?, ?, ?)',
        ['pve', pvp.scope.cycleId, '2026-11-02', null, 4],
      ),
      throwsA(anything),
    );
    final rows = await db.readProgressWipes();
    expect(rows, hasLength(1));
    _expectWipe(rows.single, valid);
  });
}

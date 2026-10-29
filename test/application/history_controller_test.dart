import 'dart:async';

import 'package:blackgrid/application/history_controller.dart';
import 'package:blackgrid/application/settings_controller.dart';
import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/m1/catalog/fixture.dart';

/// A database whose activity read and write complete only when released.
class _GatedDatabase extends BlackgridDatabase {
  _GatedDatabase() : super(NativeDatabase.memory());
  final readGate = Completer<void>();
  final writeGate = Completer<void>();
  bool failWrite = false;

  @override
  Future<List<ItemActivity>> readActivity() async {
    await readGate.future;
    return super.readActivity();
  }

  @override
  Future<ItemActivity> recordActivity(
    String itemId,
    GameMode mode,
    DateTime time, {
    ActivitySource source = ActivitySource.manual,
  }) async {
    await writeGate.future;
    if (failWrite) throw StateError('synthetic write failure');
    return super.recordActivity(itemId, mode, time, source: source);
  }
}

void main() {
  test('load finishing after dispose does not notify listeners', () async {
    final db = _GatedDatabase();
    final history = HistoryController(db);
    var notified = 0;
    history.addListener(() => notified++);
    final pending = history.load();
    history.dispose();
    db.readGate.complete();
    await pending;
    expect(notified, 0);
    await db.close();
  });
  test('record finishing after dispose does not notify listeners', () async {
    final db = _GatedDatabase()..failWrite = true;
    final history = HistoryController(db);
    var notified = 0;
    history.addListener(() => notified++);
    final pending = history.record(
      'synthetic-unknown-item',
      GameMode.pve,
      fixtureNow,
      source: ActivitySource.scan,
    );
    history.dispose();
    db.writeGate.complete();
    expect(await pending, isFalse);
    expect(notified, 0);
    await db.close();
  });
  test('record failure message follows the source', () async {
    final db = _GatedDatabase()..failWrite = true;
    db.writeGate.complete();
    final history = HistoryController(db);
    await history.record('synthetic-unknown-item', GameMode.pve, fixtureNow);
    expect(history.error, contains('The item you looked up was not recorded'));
    await history.record(
      'synthetic-unknown-item',
      GameMode.pve,
      fixtureNow,
      source: ActivitySource.scan,
    );
    expect(history.error, 'The accepted scan was not recorded in history.');
    history.dispose();
    await db.close();
  });
  test(
    'durable identity activity is unique by mode and no transient fields exist',
    () async {
      final db = BlackgridDatabase(NativeDatabase.memory());
      final history = HistoryController(db);
      await history.load();
      await history.record('synthetic-unknown-item', GameMode.pve, fixtureNow);
      await history.record(
        'synthetic-unknown-item',
        GameMode.pve,
        fixtureNow.add(const Duration(seconds: 2)),
      );
      await history.record('synthetic-unknown-item', GameMode.pvp, fixtureNow);
      expect(history.rows.length, 2);
      expect(history.rows.first.revision, 2);
      expect(
        history.rows.first.toJson().keys,
        unorderedEquals(['itemId', 'mode', 'source', 'observedAt', 'revision']),
      );
      history.dispose();
      await db.close();
    },
  );
  test(
    'failed settings persistence leaves controller and database old preference',
    () async {
      final db = BlackgridDatabase(NativeDatabase.memory());
      final settings = SettingsController(db);
      await settings.load();
      await db.customStatement(
        "CREATE TRIGGER preference_failure BEFORE INSERT ON preferences BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
      );
      expect(await settings.setMode(GameMode.pve), isFalse);
      expect(settings.settings.mode, GameMode.unknown);
      expect((await db.readSettings()).mode, GameMode.unknown);
      expect(settings.error, isNotNull);
      settings.dispose();
      await db.close();
    },
  );
  test('finite off-map pins survive and unsupported frames fail without changing saved pins', () async {
    final db = BlackgridDatabase(NativeDatabase.memory());
    final settings = SettingsController(db);
    await settings.load();
    final valid = CustomPin(
      id: 'synthetic-pin',
      mapId: 'woods',
      x: -2,
      y: 3,
      frame: 'legacy-normalized',
      frameRevision: 0,
      label: 'Synthetic',
      updatedAt: fixtureNow,
    );
    expect(await settings.savePin(valid), isTrue);
    expect(settings.pins.single.x, -2);
    final invalid = CustomPin(
      id: 'bad',
      mapId: 'woods',
      x: 0,
      y: 0,
      frame: 'unqualified',
      frameRevision: 9,
      label: 'Invalid',
      updatedAt: fixtureNow,
    );
    expect(await settings.savePin(invalid), isFalse);
    expect(settings.pins.length, 1);
    settings.dispose();
    await db.close();
  });
}

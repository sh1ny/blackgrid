import 'dart:async';

import 'package:blackgrid/application/settings_controller.dart';
import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// An in-memory database whose settings saves can fail or block on demand.
class _ControlledDatabase extends BlackgridDatabase {
  _ControlledDatabase() : super(NativeDatabase.memory());

  /// How many saves were attempted, including failed ones.
  int attempts = 0;

  /// Makes every save throw while set.
  bool failSaves = false;

  /// Holds the next save until completed, then clears itself.
  Completer<void>? gate;

  @override
  Future<void> saveSettings(AppSettings settings) async {
    attempts++;
    final held = gate;
    gate = null;
    if (held != null) await held.future;
    if (failSaves) throw StateError('synthetic save failure');
    await super.saveSettings(settings);
  }
}

const _unreadableNotice =
    'Your saved settings could not be read. '
    'Default settings are in use until you change one.';

AppSettings _withStart(GameMode mode, DateTime start) => AppSettings(
  raidTimers: RaidTimerSettings(scavCooldownStarts: {mode: start}),
);

void main() {
  late _ControlledDatabase db;
  late SettingsController controller;
  setUp(() {
    db = _ControlledDatabase();
    controller = SettingsController(db);
  });
  tearDown(() async {
    controller.dispose();
    await db.close();
  });

  Future<Map<GameMode, DateTime>> storedStarts() async =>
      (await db.readSettings()).settings.raidTimers.scavCooldownStarts;

  final seasonal2005 = DateTime.utc(2026, 11, 1, 20, 5);

  test('recording the stored start again saves nothing', () async {
    await db.saveSettings(_withStart(GameMode.seasonal, seasonal2005));
    db.attempts = 0;
    await controller.load();
    await controller.recordScavCooldownStart(GameMode.seasonal, seasonal2005);
    expect(db.attempts, 0);
    expect(controller.effectiveScavCooldownStarts, {
      GameMode.seasonal: seasonal2005,
    });
    expect(controller.error, isNull);
  });

  test('older start never replaces a later one', () async {
    final later = DateTime.utc(2026, 11, 1, 22);
    await db.saveSettings(_withStart(GameMode.pvp, later));
    db.attempts = 0;
    await controller.load();
    await controller.recordScavCooldownStart(
      GameMode.pvp,
      DateTime.utc(2026, 11, 1, 19),
    );
    expect(db.attempts, 0);
    expect(controller.effectiveScavCooldownStarts[GameMode.pvp], later);
    expect((await storedStarts())[GameMode.pvp], later);
  });

  test('save built from older settings keeps the newer start', () async {
    await controller.load();
    final older = controller.settings;
    await controller.recordScavCooldownStart(GameMode.seasonal, seasonal2005);
    expect((await storedStarts())[GameMode.seasonal], seasonal2005);
    expect(await controller.save(older.copyWith(mode: GameMode.pvp)), isTrue);
    expect((await storedStarts())[GameMode.seasonal], seasonal2005);
    expect(
      controller.settings.raidTimers.scavCooldownStarts[GameMode.seasonal],
      seasonal2005,
    );
    expect((await db.readSettings()).settings.mode, GameMode.pvp);
  });

  test('later start replaces the stored one', () async {
    await db.saveSettings(
      _withStart(GameMode.pvp, DateTime.utc(2026, 11, 1, 19)),
    );
    await controller.load();
    final later = DateTime.utc(2026, 11, 1, 21, 30);
    await controller.recordScavCooldownStart(GameMode.pvp, later);
    expect((await storedStarts())[GameMode.pvp], later);
    expect(controller.effectiveScavCooldownStarts[GameMode.pvp], later);
    expect(
      controller.settings.raidTimers.scavCooldownStarts[GameMode.pvp],
      later,
    );
  });

  test('failed save keeps the start pending and effective', () async {
    await controller.load();
    db.failSaves = true;
    await controller.recordScavCooldownStart(GameMode.seasonal, seasonal2005);
    expect(db.attempts, 1);
    expect(controller.error, isNotNull);
    expect(controller.busy, isFalse);
    expect(controller.effectiveScavCooldownStarts, {
      GameMode.seasonal: seasonal2005,
    });
    expect(controller.settings.raidTimers.scavCooldownStarts, isEmpty);
    expect(await storedStarts(), isEmpty);

    // The next save retries the pending start and then drops it.
    db.failSaves = false;
    expect(await controller.setMode(GameMode.pve), isTrue);
    expect((await storedStarts())[GameMode.seasonal], seasonal2005);
    expect(controller.error, isNull);
    final attempts = db.attempts;
    expect(await controller.setMode(GameMode.pvp), isTrue);
    expect(db.attempts, attempts + 1);
  });

  test('unreadable record is never saved by a recorded start', () async {
    await db.customStatement(
      'INSERT INTO preferences (id, payload) VALUES (1, ?)',
      ['{not json'],
    );
    await controller.load();
    expect(controller.loadNotice, _unreadableNotice);
    await controller.recordScavCooldownStart(GameMode.seasonal, seasonal2005);
    expect(db.attempts, 0);
    expect(controller.effectiveScavCooldownStarts, {
      GameMode.seasonal: seasonal2005,
    });
    expect(controller.loadNotice, _unreadableNotice);
    expect((await db.readSettings()).unreadable, isTrue);

    expect(await controller.setMode(GameMode.pvp), isTrue);
    expect(controller.loadNotice, isNull);
    expect((await storedStarts())[GameMode.seasonal], seasonal2005);
  });

  test('recordScavCooldownStart during an in-flight user save is written right after that save ends', () async {
    await controller.load();
    final gate = db.gate = Completer<void>();
    final saving = controller.setMode(GameMode.pve);
    expect(controller.busy, isTrue);
    await controller.recordScavCooldownStart(GameMode.seasonal, seasonal2005);
    expect(db.attempts, 1);
    expect(controller.effectiveScavCooldownStarts, {
      GameMode.seasonal: seasonal2005,
    });
    gate.complete();
    expect(await saving, isTrue);
    expect(db.attempts, 2);
    expect(controller.busy, isFalse);
    final stored = (await db.readSettings()).settings;
    expect(stored.mode, GameMode.pve);
    expect(
      stored.raidTimers.scavCooldownStarts[GameMode.seasonal],
      seasonal2005,
    );
  });

  test('a start recorded during an in-flight cooldown save is written right after it', () async {
    await controller.load();
    final later = DateTime.utc(2026, 11, 1, 21, 30);
    final gate = db.gate = Completer<void>();
    final first = controller.recordScavCooldownStart(
      GameMode.seasonal,
      seasonal2005,
    );
    expect(controller.busy, isTrue);
    await controller.recordScavCooldownStart(GameMode.seasonal, later);
    expect(db.attempts, 1);
    gate.complete();
    await first;
    expect(db.attempts, 2);
    expect(controller.busy, isFalse);
    expect((await storedStarts())[GameMode.seasonal], later);
  });

  test('a start recorded during the flush write is written after it', () async {
    await controller.load();
    final second = DateTime.utc(2026, 11, 1, 21, 30);
    final third = DateTime.utc(2026, 11, 1, 22, 45);
    final firstGate = db.gate = Completer<void>();
    final first = controller.recordScavCooldownStart(
      GameMode.seasonal,
      seasonal2005,
    );
    await controller.recordScavCooldownStart(GameMode.seasonal, second);
    // Hold the flush write that saves the second start.
    final flushGate = db.gate = Completer<void>();
    firstGate.complete();
    await pumpEventQueue();
    expect(db.attempts, 2);
    expect(controller.busy, isTrue);
    await controller.recordScavCooldownStart(GameMode.seasonal, third);
    flushGate.complete();
    await first;
    expect(db.attempts, 3);
    expect(controller.busy, isFalse);
    expect((await storedStarts())[GameMode.seasonal], third);
  });

  test('a start recorded before load only waits in the pending map', () async {
    await controller.recordScavCooldownStart(GameMode.pve, seasonal2005);
    expect(db.attempts, 0);
    expect(controller.effectiveScavCooldownStarts, {
      GameMode.pve: seasonal2005,
    });
    await controller.load();
    expect(await controller.setMode(GameMode.pve), isTrue);
    expect((await storedStarts())[GameMode.pve], seasonal2005);
  });

  test(
    'timer setters save through the guarded save and keep recorded starts',
    () async {
      await controller.load();
      await controller.recordScavCooldownStart(GameMode.seasonal, seasonal2005);
      final timers = controller.settings.raidTimers.copyWith(
        runThroughSeconds: 480,
        enabled: false,
      );
      expect(await controller.setRaidTimers(timers), isTrue);
      expect(
        await controller.setFenceReputation(GameMode.seasonal, 3.2),
        isTrue,
      );
      final stored = (await db.readSettings()).settings.raidTimers;
      expect(stored.enabled, isFalse);
      expect(stored.runThroughSeconds, 480);
      expect(stored.fenceReputationFor(GameMode.seasonal), 3.2);
      expect(stored.scavCooldownStarts[GameMode.seasonal], seasonal2005);

      final gate = db.gate = Completer<void>();
      final saving = controller.setFenceReputation(GameMode.pve, 1);
      expect(await controller.setRaidTimers(timers), isFalse);
      gate.complete();
      expect(await saving, isTrue);
    },
  );
}

import 'dart:async';

import 'package:blackgrid/application/local_stats_controller.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/local_stats.dart';
import 'package:blackgrid/domain/raid_lifecycle.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const _folder = 'log_a';

LogRecordId _id(int offset) =>
    LogRecordId(_folder, LogFile.application, offset);

LocalStatsTotals _totals(int raids) => LocalStatsTotals(
  raidsByMap: {'bigmap': raids},
  raidTotal: raids,
  sales: 0,
  items: 0,
  roubles: 0,
  salesNotInRoubles: 0,
);

RaidStartedTransition _raidStart(int offset) => RaidStartedTransition(
  _id(offset),
  DateTime(2026, 11, 1, 12),
  Raid(
    mapId: 'bigmap',
    mode: GameMode.pvp,
    queueTime: null,
    startTime: DateTime(2026, 11, 1, 12),
    startId: _id(offset),
    entry: RaidEntry.noQueue,
  ),
);

FleaSoldTransition _sale(int offset) => FleaSoldTransition(
  _id(offset),
  DateTime(2026, 11, 1, 13),
  'item',
  2,
  1000,
  GameMode.pvp,
);

/// A store whose calls are recorded and can be held or made to fail.
final class _FakeStore implements LocalStatsStore {
  final calls = <String>[];
  final totalsByMode = <GameMode, LocalStatsTotals>{};
  DateTime? sinceValue;
  bool failRecord = false;
  bool failRead = false;
  bool failClear = false;
  Completer<void>? holdRecord;
  Completer<void>? holdRead;

  @override
  Future<void> recordRaid(RaidStatRow row) async {
    calls.add('raid:${row.id.offset}');
    await holdRecord?.future;
    if (failRecord) throw StateError('record');
  }

  @override
  Future<void> recordSale(FleaSaleRow row) async {
    calls.add('sale:${row.id.offset}');
    await holdRecord?.future;
    if (failRecord) throw StateError('record');
  }

  @override
  Future<LocalStatsTotals> readTotals(GameMode mode) async {
    calls.add('read:${mode.name}');
    await holdRead?.future;
    if (failRead) throw StateError('read');
    return totalsByMode[mode] ?? LocalStatsTotals.empty;
  }

  @override
  Future<DateTime?> readSince() async => sinceValue;

  @override
  Future<void> clear(DateTime now) async {
    calls.add('clear:${now.toIso8601String()}');
    if (failClear) throw StateError('clear');
    sinceValue = now;
    totalsByMode.clear();
  }

  int get reads => calls.where((c) => c.startsWith('read:')).length;
}

void main() {
  late StreamController<RaidTransition> lifecycle;
  late ValueNotifier<GameMode> mode;
  late _FakeStore store;
  late LocalStatsController controller;
  late int notifications;
  final now = DateTime(2026, 11, 2, 9);

  LocalStatsController build() {
    final built = LocalStatsController(
      transitions: lifecycle.stream,
      modeChanges: mode,
      mode: () => mode.value,
      store: store,
      clock: () => now,
    );
    notifications = 0;
    built.addListener(() => notifications++);
    return built;
  }

  setUp(() {
    lifecycle = StreamController<RaidTransition>.broadcast(sync: true);
    mode = ValueNotifier(GameMode.pvp);
    store = _FakeStore()..totalsByMode[GameMode.pvp] = _totals(3);
  });

  tearDown(() async {
    controller.dispose();
    mode.dispose();
    await lifecycle.close();
  });

  group('LocalStatsController', () {
    test('initial load reads the known mode and the clear time', () async {
      store.sinceValue = DateTime(2026, 10, 1);
      controller = build();
      await pumpEventQueue();

      expect(controller.modeKnown, isTrue);
      expect(controller.totals.raidTotal, 3);
      expect(controller.since, DateTime(2026, 10, 1));
    });

    test('unknown app mode loads no totals', () async {
      mode.value = GameMode.unknown;
      controller = build();
      lifecycle.add(_sale(1));
      await pumpEventQueue();

      expect(controller.modeKnown, isFalse);
      expect(controller.totals.isEmpty, isTrue);
      expect(store.calls, ['sale:1']);
    });

    test('unknown app mode still loads the clear time', () async {
      store.sinceValue = DateTime(2026, 10, 1);
      mode.value = GameMode.unknown;
      controller = build();
      await pumpEventQueue();

      expect(controller.modeKnown, isFalse);
      expect(controller.totals.isEmpty, isTrue);
      expect(controller.since, DateTime(2026, 10, 1));
      expect(store.reads, 0);
    });

    test('mode change reloads the new mode\'s totals', () async {
      store.totalsByMode[GameMode.pve] = _totals(7);
      controller = build();
      await pumpEventQueue();
      expect(controller.totals.raidTotal, 3);

      mode.value = GameMode.pve;
      await pumpEventQueue();

      expect(store.calls.last, 'read:pve');
      expect(controller.totals.raidTotal, 7);
    });

    test('mode change to unknown clears the shown totals', () async {
      controller = build();
      await pumpEventQueue();
      mode.value = GameMode.unknown;
      await pumpEventQueue();

      expect(controller.modeKnown, isFalse);
      expect(controller.totals.isEmpty, isTrue);
      expect(store.reads, 1);
    });

    test('stored sale reloads totals and notifies', () async {
      controller = build();
      await pumpEventQueue();
      final before = notifications;
      store.totalsByMode[GameMode.pvp] = _totals(4);

      lifecycle.add(_sale(2));
      await pumpEventQueue();

      expect(store.calls, containsAllInOrder(['sale:2', 'read:pvp']));
      expect(controller.totals.raidTotal, 4);
      expect(notifications, greaterThan(before));
    });

    test('raid end and aborted matching store nothing', () async {
      controller = build();
      await pumpEventQueue();
      final raid = _raidStart(1).raid.ended(now, RaidEndCause.menus);
      lifecycle
        ..add(RaidEndedTransition(_id(2), now, raid))
        ..add(MatchingAbortedTransition(_id(3), now));
      await pumpEventQueue();

      expect(store.calls, ['read:pvp']);
    });

    test('failed read sets the read message', () async {
      store.failRead = true;
      controller = build();
      await pumpEventQueue();

      expect(controller.readError, 'Stats could not be read.');
      expect(controller.totals.isEmpty, isTrue);
    });

    test('a successful read removes the read message', () async {
      store.failRead = true;
      controller = build();
      await pumpEventQueue();

      store.failRead = false;
      mode.value = GameMode.pve;
      await pumpEventQueue();

      expect(controller.readError, isNull);
    });

    test('a read failure message stays after a successful write', () async {
      store.failRead = true;
      controller = build();
      await pumpEventQueue();

      lifecycle.add(_raidStart(1));
      await pumpEventQueue();

      expect(controller.writeError, isNull);
      expect(controller.readError, 'Stats could not be read.');
    });

    test(
      'failed insert sets the write message and the next insert still runs',
      () async {
        store.failRecord = true;
        controller = build();
        await pumpEventQueue();

        lifecycle.add(_raidStart(1));
        await pumpEventQueue();
        expect(
          controller.writeError,
          'Some raids or sales could not be saved.',
        );

        store.failRecord = false;
        lifecycle.add(_raidStart(2));
        await pumpEventQueue();

        expect(store.calls, containsAllInOrder(['raid:1', 'raid:2']));
        expect(controller.writeError, isNull);
      },
    );

    test('successful reload keeps the write message', () async {
      store.failRecord = true;
      controller = build();
      await pumpEventQueue();
      lifecycle.add(_sale(1));
      await pumpEventQueue();
      final reads = store.reads;

      mode.value = GameMode.pve;
      await pumpEventQueue();

      expect(store.reads, greaterThan(reads));
      expect(controller.readError, isNull);
      expect(controller.writeError, 'Some raids or sales could not be saved.');
    });

    test('next successful insert clears the write message', () async {
      store.failRecord = true;
      controller = build();
      await pumpEventQueue();
      lifecycle.add(_raidStart(1));
      await pumpEventQueue();
      expect(controller.writeError, isNotNull);

      store.failRecord = false;
      lifecycle.add(_sale(2));
      await pumpEventQueue();

      expect(controller.writeError, isNull);
    });

    test('failed clear keeps totals and shows the clear message', () async {
      store.sinceValue = DateTime(2026, 10, 1);
      controller = build();
      await pumpEventQueue();
      store.failClear = true;

      await controller.clear();
      await pumpEventQueue();

      expect(controller.clearError, 'Stats could not be cleared.');
      expect(controller.totals.raidTotal, 3);
      expect(controller.since, DateTime(2026, 10, 1));
    });

    test('successful clear reloads empty totals and the clear time', () async {
      controller = build();
      await pumpEventQueue();

      await controller.clear();
      await pumpEventQueue();

      expect(store.calls, contains('clear:${now.toIso8601String()}'));
      expect(controller.clearError, isNull);
      expect(controller.totals.isEmpty, isTrue);
      expect(controller.since, now);
    });

    test('successful reload keeps the clear message', () async {
      store.failClear = true;
      controller = build();
      await pumpEventQueue();
      await controller.clear();
      await pumpEventQueue();

      mode.value = GameMode.pve;
      await pumpEventQueue();

      expect(controller.readError, isNull);
      expect(controller.clearError, 'Stats could not be cleared.');
    });

    test('dismissClearError removes only the clear message', () async {
      store.failClear = true;
      store.failRecord = true;
      controller = build();
      await pumpEventQueue();
      lifecycle.add(_sale(1));
      await controller.clear();
      await pumpEventQueue();
      final before = notifications;

      controller.dismissClearError();

      expect(controller.clearError, isNull);
      expect(controller.writeError, isNotNull);
      expect(notifications, before + 1);
    });

    test('a successful clear removes the clear message', () async {
      store.failClear = true;
      controller = build();
      await pumpEventQueue();
      await controller.clear();
      expect(controller.clearError, isNotNull);

      store.failClear = false;
      await controller.clear();

      expect(controller.clearError, isNull);
    });

    test(
      'writes run in publication order and a clear waits for them',
      () async {
        store.holdRecord = Completer<void>();
        controller = build();
        await pumpEventQueue();
        store.calls.clear();

        lifecycle
          ..add(_raidStart(1))
          ..add(_sale(2));
        final cleared = controller.clear();
        await pumpEventQueue();
        expect(store.calls, ['raid:1']);

        store.holdRecord!.complete();
        await cleared;
        await pumpEventQueue();

        final order = store.calls.where((c) => !c.startsWith('read:')).toList();
        expect(order, ['raid:1', 'sale:2', 'clear:${now.toIso8601String()}']);
      },
    );

    test('reload requests coalesce into one more read', () async {
      controller = build();
      await pumpEventQueue();
      store.holdRead = Completer<void>();
      final reads = store.reads;

      mode.value = GameMode.pve;
      await pumpEventQueue();
      mode.value = GameMode.seasonal;
      mode.value = GameMode.pvp;
      mode.value = GameMode.pve;
      await pumpEventQueue();
      expect(store.reads, reads + 1);

      store.holdRead!.complete();
      await pumpEventQueue();

      expect(store.reads, reads + 2);
      expect(store.calls.last, 'read:pve');
    });

    test('disposal stops notifications and drops queued work', () async {
      controller = build();
      await pumpEventQueue();
      store.holdRecord = Completer<void>();
      store.calls.clear();

      lifecycle
        ..add(_raidStart(1))
        ..add(_sale(2));
      final cleared = controller.clear();
      await pumpEventQueue();
      controller.dispose();
      final after = notifications;

      store.holdRecord!.complete();
      await cleared;
      await pumpEventQueue();
      mode.value = GameMode.pve;
      lifecycle.add(_sale(3));
      await controller.clear();
      await pumpEventQueue();

      expect(store.calls, ['raid:1']);
      expect(notifications, after);
    });
  });
}

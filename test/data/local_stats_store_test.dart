import 'dart:io';

import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/local_stats.dart';
import 'package:blackgrid/domain/raid_lifecycle.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

DateTime at(int hour, [int minute = 0]) =>
    DateTime.utc(2026, 10, 28, hour, minute);

RaidStatRow raid(
  int offset,
  DateTime start, {
  String? mapId = 'customs',
  GameMode? mode = GameMode.pvp,
  RaidEntry entry = RaidEntry.queue,
  String folder = 'f1',
}) => RaidStatRow(
  id: LogRecordId(folder, LogFile.application, offset),
  mode: mode,
  mapId: mapId,
  start: start,
  entry: entry,
);

FleaSaleRow sale(
  int offset,
  DateTime time, {
  GameMode? mode = GameMode.pvp,
  String itemId = 'item-a',
  int count = 1,
  int? roubles = 1000,
}) => FleaSaleRow(
  id: LogRecordId('f1', LogFile.pushNotifications, offset),
  mode: mode,
  time: time,
  itemId: itemId,
  count: count,
  roubles: roubles,
);

void main() {
  late BlackgridDatabase db;
  setUp(() => db = BlackgridDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('raids', () {
    test('two raid starts on one map count 2', () async {
      await db.recordRaid(raid(1, at(20)));
      await db.recordRaid(raid(2, at(21)));
      final totals = await db.readTotals(GameMode.pvp);
      expect(totals.raidsByMap, {'customs': 2});
      expect(totals.raidTotal, 2);
    });

    test('transit raid counts on its own map', () async {
      await db.recordRaid(raid(1, at(20)));
      await db.recordRaid(
        raid(2, at(21), mapId: 'woods', entry: RaidEntry.transit),
      );
      final totals = await db.readTotals(GameMode.pvp);
      expect(totals.raidsByMap, {'customs': 1, 'woods': 1});
    });

    test('same raid identity stored twice counts once', () async {
      await db.recordRaid(raid(1, at(20)));
      await db.recordRaid(raid(1, at(20)));
      expect((await db.readTotals(GameMode.pvp)).raidTotal, 1);
    });

    test(
      'unknown-mode reconnect after a no-mode raid is not counted',
      () async {
        await db.recordRaid(raid(1, at(20), mode: null));
        await db.recordRaid(
          raid(
            2,
            at(20, 25),
            mode: GameMode.unknown,
            entry: RaidEntry.reconnect,
          ),
        );
        expect((await db.readTotals(GameMode.unknown)).raidTotal, 1);
      },
    );

    test('raid with no map counts under unknown map', () async {
      await db.recordRaid(raid(1, at(20), mapId: null));
      final totals = await db.readTotals(GameMode.pvp);
      expect(totals.raidsByMap, {null: 1});
      expect(totals.raidTotal, 1);
    });

    test(
      'replayed skipped reconnect stays skipped after a later raid',
      () async {
        final first = raid(1, at(20));
        final reconnect = raid(2, at(20, 25), entry: RaidEntry.reconnect);
        final later = raid(3, at(21), mapId: 'woods');
        for (final row in [first, reconnect, later]) {
          await db.recordRaid(row);
        }
        for (final row in [first, reconnect, later]) {
          await db.recordRaid(row);
        }
        final totals = await db.readTotals(GameMode.pvp);
        expect(totals.raidsByMap, {'customs': 1, 'woods': 1});
      },
    );
  });

  group('sales', () {
    test('two sales total sales items and roubles', () async {
      await db.recordSale(sale(1, at(20), count: 1, roubles: 30000));
      await db.recordSale(sale(2, at(20, 5), count: 3, roubles: 12000));
      final totals = await db.readTotals(GameMode.pvp);
      expect(totals.sales, 2);
      expect(totals.items, 4);
      expect(totals.roubles, 42000);
      expect(totals.salesNotInRoubles, 0);
    });

    test('same sale identity stored twice counts once', () async {
      await db.recordSale(sale(1, at(20)));
      await db.recordSale(sale(1, at(20)));
      expect((await db.readTotals(GameMode.pvp)).sales, 1);
    });

    test('sale without roubles counts items but no roubles', () async {
      await db.recordSale(sale(1, at(20), count: 2, roubles: null));
      final totals = await db.readTotals(GameMode.pvp);
      expect(totals.sales, 1);
      expect(totals.items, 2);
      expect(totals.roubles, 0);
      expect(totals.salesNotInRoubles, 1);
    });

    test('sale with no mode is in no known mode\'s totals', () async {
      await db.recordSale(sale(1, at(20), mode: null));
      await db.recordRaid(raid(2, at(20), mode: null));
      for (final mode in [GameMode.pvp, GameMode.pve]) {
        expect((await db.readTotals(mode)).isEmpty, isTrue);
      }
      expect((await db.readTotals(GameMode.unknown)).sales, 1);
    });

    test('PvE sale changes only PvE totals', () async {
      await db.recordSale(sale(1, at(20), mode: GameMode.pve));
      expect((await db.readTotals(GameMode.pve)).sales, 1);
      expect((await db.readTotals(GameMode.pvp)).isEmpty, isTrue);
    });
  });

  group('durability and clear', () {
    test('stats read back after close and reopen', () async {
      final dir = await Directory.systemTemp.createTemp('blackgrid-stats-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/stats.sqlite');
      final first = BlackgridDatabase(NativeDatabase(file));
      await first.recordRaid(raid(1, at(20)));
      await first.recordRaid(raid(2, at(21), mapId: 'woods'));
      await first.recordRaid(raid(3, at(22), mapId: null));
      await first.recordSale(sale(4, at(20)));
      await first.recordSale(sale(5, at(21)));
      await first.close();
      final second = BlackgridDatabase(NativeDatabase(file));
      addTearDown(second.close);
      final totals = await second.readTotals(GameMode.pvp);
      expect(totals.raidTotal, 3);
      expect(totals.sales, 2);
    });

    test('clear empties every mode', () async {
      await db.recordRaid(raid(1, at(20)));
      await db.recordRaid(raid(2, at(20), mode: GameMode.pve));
      await db.recordSale(sale(3, at(20)));
      await db.recordSale(sale(4, at(20), mode: GameMode.pve));
      expect(await db.readSince(), isNull);
      await db.clear(at(21));
      for (final mode in [GameMode.pvp, GameMode.pve, GameMode.unknown]) {
        expect((await db.readTotals(mode)).isEmpty, isTrue);
      }
      expect(await db.readSince(), at(21));
    });

    test(
      'records at or before the clear time are not stored after reopen',
      () async {
        final dir = await Directory.systemTemp.createTemp('blackgrid-stats-');
        addTearDown(() => dir.delete(recursive: true));
        final file = File('${dir.path}/stats.sqlite');
        final first = BlackgridDatabase(NativeDatabase(file));
        await first.recordRaid(raid(1, at(20)));
        await first.clear(at(21));
        await first.close();
        final second = BlackgridDatabase(NativeDatabase(file));
        addTearDown(second.close);
        expect((await second.readSince())?.toUtc(), at(21));
        await second.recordRaid(raid(1, at(20)));
        await second.recordRaid(raid(5, at(21)));
        await second.recordSale(sale(6, at(20, 59)));
        await second.recordSale(sale(7, at(21)));
        expect((await second.readTotals(GameMode.pvp)).isEmpty, isTrue);
      },
    );

    test('raid after the clear time is stored', () async {
      await db.clear(at(21));
      await db.recordRaid(raid(1, at(21, 10)));
      expect((await db.readTotals(GameMode.pvp)).raidsByMap, {'customs': 1});
    });
  });
}

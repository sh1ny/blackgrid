import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/local_stats.dart';
import 'package:blackgrid/domain/raid_lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';

RaidStatRow _raid(
  DateTime start, {
  String? mapId = 'customs',
  GameMode? mode = GameMode.pvp,
  RaidEntry entry = RaidEntry.queue,
  int offset = 0,
}) => RaidStatRow(
  id: LogRecordId('log_a', LogFile.application, offset),
  mode: mode,
  mapId: mapId,
  start: start,
  entry: entry,
);

void main() {
  final previousStart = DateTime(2026, 11, 1, 20, 0);

  group('countsReconnect', () {
    test('reconnect on same map within 2 h is not counted', () {
      final previous = _raid(previousStart);
      final candidate = _raid(
        previousStart.add(const Duration(minutes: 25)),
        entry: RaidEntry.reconnect,
        offset: 1,
      );
      expect(countsReconnect(previous, candidate), isFalse);
    });

    test('reconnect on another map counts', () {
      final previous = _raid(previousStart, mapId: 'woods');
      final candidate = _raid(
        previousStart.add(const Duration(minutes: 25)),
        entry: RaidEntry.reconnect,
        offset: 1,
      );
      expect(countsReconnect(previous, candidate), isTrue);
    });

    test('reconnect 2 h 1 min after counts', () {
      final previous = _raid(previousStart);
      final candidate = _raid(
        previousStart.add(const Duration(hours: 2, minutes: 1)),
        entry: RaidEntry.reconnect,
        offset: 1,
      );
      expect(countsReconnect(previous, candidate), isTrue);
    });

    test('reconnect with no earlier raid counts', () {
      final candidate = _raid(previousStart, entry: RaidEntry.reconnect);
      expect(countsReconnect(null, candidate), isTrue);
    });

    test('exactly 2 h is the same raid', () {
      final previous = _raid(previousStart);
      final candidate = _raid(
        previousStart.add(reconnectSameRaidWindow),
        entry: RaidEntry.reconnect,
        offset: 1,
      );
      expect(reconnectSameRaidWindow, const Duration(hours: 2));
      expect(countsReconnect(previous, candidate), isFalse);
    });

    test('a non-reconnect entry always counts', () {
      final previous = _raid(previousStart);
      for (final entry in RaidEntry.values.where(
        (e) => e != RaidEntry.reconnect,
      )) {
        final candidate = _raid(
          previousStart.add(const Duration(minutes: 5)),
          entry: entry,
          offset: 1,
        );
        expect(countsReconnect(previous, candidate), isTrue, reason: '$entry');
      }
    });

    test('a previous raid of another mode never suppresses a count', () {
      final previous = _raid(previousStart, mode: GameMode.pve);
      final candidate = _raid(
        previousStart.add(const Duration(minutes: 25)),
        entry: RaidEntry.reconnect,
        offset: 1,
      );
      expect(countsReconnect(previous, candidate), isTrue);
    });

    test('unknown map on both sides is the same map', () {
      final previous = _raid(previousStart, mapId: null);
      final candidate = _raid(
        previousStart.add(const Duration(minutes: 25)),
        mapId: null,
        entry: RaidEntry.reconnect,
        offset: 1,
      );
      expect(countsReconnect(previous, candidate), isFalse);
    });

    test('a previous raid starting after the candidate is ignored', () {
      final previous = _raid(previousStart.add(const Duration(minutes: 5)));
      final candidate = _raid(
        previousStart,
        entry: RaidEntry.reconnect,
        offset: 1,
      );
      expect(countsReconnect(previous, candidate), isTrue);
    });
  });

  group('LocalStatsTotals', () {
    test('empty has no raids, sales or roubles', () {
      expect(LocalStatsTotals.empty.isEmpty, isTrue);
      expect(LocalStatsTotals.empty.raidsByMap, isEmpty);
    });

    test('orders maps by count descending, then by key', () {
      final totals = LocalStatsTotals(
        raidsByMap: {'woods': 2, 'customs': 2, 'shoreline': 5},
        raidTotal: 9,
        sales: 0,
        items: 0,
        roubles: 0,
        salesNotInRoubles: 0,
      );
      expect(totals.raidsByMap.keys, ['shoreline', 'customs', 'woods']);
    });

    test('puts the unknown map by its label key among equal counts', () {
      final totals = LocalStatsTotals(
        raidsByMap: {'woods': 1, null: 1, 'customs': 1},
        raidTotal: 3,
        sales: 1,
        items: 2,
        roubles: 10,
        salesNotInRoubles: 0,
      );
      expect(totals.raidsByMap.keys, [null, 'customs', 'woods']);
      expect(totals.isEmpty, isFalse);
    });
  });
}

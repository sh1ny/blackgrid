import 'package:flutter_test/flutter_test.dart';
import 'package:blackgrid/domain/raid_lifecycle.dart';

/// Builds events with increasing record offsets in one session folder.
final class _Log {
  _Log();

  final folder = 'f1';
  int _offset = 0;

  LogRecordId _id() => LogRecordId(folder, LogFile.application, _offset += 10);

  DateTime t(String hms, [int millisecond = 0]) {
    final [h, m, s] = hms.split(':').map(int.parse).toList();
    return DateTime(2026, 10, 28, h, m, s, millisecond);
  }

  GameLogEvent profile(String at) => ProfileSelected(_id(), t(at));
  GameLogEvent queue(String at) => QueueEntered(_id(), t(at));
  GameLogEvent found(String at) => MatchFound(_id(), t(at));
  GameLogEvent starting(String at) => RaidStarting(_id(), t(at));
  GameLogEvent started(String at) => RaidStarted(_id(), t(at));
  GameLogEvent aborted(String at) => MatchingAborted(_id(), t(at));
  GameLogEvent exit(String at) => RaidExit(_id(), t(at));
  GameLogEvent rejoin(String at, String location, String? mapId) =>
      RaidRejoined(_id(), t(at), 'MatchWait', location, mapId);
}

RaidLifecycleState _fold(List<GameLogEvent> events) {
  var state = RaidLifecycleState.initial;
  for (final event in events) {
    state = reduce(state, event).$1;
  }
  return state;
}

void main() {
  test('countdown over 3 s records raid starting and side PMC', () {
    final log = _Log();
    final raid = _fold([
      log.queue('19:38:10'),
      log.found('19:40:00'),
      log.starting('19:40:51'),
      log.started('19:41:06'),
    ]).raid!;
    expect(raid.raidStartingTime, log.t('19:40:51'));
    expect(raid.side, RaidSide.pmc);
  });

  test('no raid starting gives side scav', () {
    final log = _Log();
    final raid = _fold([
      log.queue('19:38:10'),
      log.found('19:40:00'),
      log.started('19:41:06'),
    ]).raid!;
    expect(raid.raidStartingTime, isNull);
    expect(raid.side, RaidSide.scav);
  });

  test('2 s countdown gives side scav', () {
    final log = _Log();
    final raid = _fold([
      log.queue('19:38:10'),
      log.starting('19:41:04'),
      log.started('19:41:06'),
    ]).raid!;
    expect(raid.side, RaidSide.scav);
  });

  test('exactly 3 s countdown gives side scav', () {
    final log = _Log();
    final raid = _fold([
      log.queue('19:38:10'),
      RaidStarting(
        LogRecordId('f1', LogFile.application, 500),
        log.t('19:41:03', 0),
      ),
      RaidStarted(
        LogRecordId('f1', LogFile.application, 510),
        log.t('19:41:06', 0),
      ),
    ]).raid!;
    expect(raid.side, RaidSide.scav);
  });

  test('raid starting of an aborted queue is forgotten', () {
    final log = _Log();
    final raid = _fold([
      log.queue('19:29:00'),
      log.starting('19:30:00'),
      log.aborted('19:30:10'),
      log.queue('19:38:10'),
      log.found('19:40:00'),
      log.started('19:41:06'),
    ]).raid!;
    expect(raid.raidStartingTime, isNull);
    expect(raid.side, RaidSide.scav);
  });

  test('transit raid takes the previous raid\'s side', () {
    final log = _Log();
    final state = _fold([
      log.queue('19:38:10'),
      log.starting('19:40:51'),
      log.started('19:41:06'),
      log.exit('19:54:20'),
      log.rejoin('19:54:30', 'factory4_day', 'factory'),
      log.started('19:54:40'),
    ]);
    expect(state.raid!.entry, RaidEntry.transit);
    expect(state.raid!.side, RaidSide.pmc);

    final scavLog = _Log();
    final scav = _fold([
      scavLog.queue('19:38:10'),
      scavLog.started('19:41:06'),
      scavLog.exit('19:54:20'),
      scavLog.rejoin('19:54:30', 'factory4_day', 'factory'),
      scavLog.started('19:54:40'),
    ]).raid!;
    expect(scav.entry, RaidEntry.transit);
    expect(scav.side, RaidSide.scav);
  });

  test('continued reconnect keeps side PMC', () {
    final log = _Log();
    final before = _fold([
      log.queue('19:38:10'),
      log.starting('19:40:51'),
      log.started('19:41:06'),
    ]);
    expect(before.raid!.side, RaidSide.pmc);
    var state = reduce(before, const SessionFolderChanged('f2')).$1;
    for (final event in [
      log.profile('19:50:00'),
      log.rejoin('19:50:10', 'bigmap', 'customs'),
      log.started('19:50:20'),
    ]) {
      state = reduce(state, event).$1;
    }
    expect(state.raid!.interrupted, isFalse);
    expect(state.raid!.side, RaidSide.pmc);
  });

  test('raid without a queue has side unknown', () {
    final log = _Log();
    final raid = _fold([log.profile('19:30:00'), log.started('19:41:06')])
        .raid!;
    expect(raid.entry, RaidEntry.noQueue);
    expect(raid.side, RaidSide.unknown);
  });

  test('new reconnect raid has side unknown', () {
    final log = _Log();
    final raid = _fold([
      const SessionFolderChanged('f2'),
      log.profile('19:50:00'),
      log.rejoin('19:50:10', 'bigmap', 'customs'),
      log.started('19:50:20'),
    ]).raid!;
    expect(raid.entry, RaidEntry.reconnect);
    expect(raid.side, RaidSide.unknown);
  });
}

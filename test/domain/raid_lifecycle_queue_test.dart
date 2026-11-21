import 'package:flutter_test/flutter_test.dart';
import 'package:blackgrid/domain/raid_lifecycle.dart';

/// Builds events with increasing record offsets in one session folder.
final class _Log {
  int _offset = 0;

  LogRecordId _id() => LogRecordId('f1', LogFile.application, _offset += 10);

  DateTime t(String hms) {
    final [h, m, s] = hms.split(':').map(int.parse).toList();
    return DateTime(2026, 10, 28, h, m, s);
  }

  GameLogEvent profile(String at) => ProfileSelected(_id(), t(at));
  GameLogEvent queue(String at) => QueueEntered(_id(), t(at));
  GameLogEvent scene(String at, String? mapId) =>
      SceneLoaded(_id(), t(at), mapId);
  GameLogEvent found(String at) => MatchFound(_id(), t(at));
  GameLogEvent starting(String at) => RaidStarting(_id(), t(at));
  GameLogEvent started(String at) => RaidStarted(_id(), t(at));
  GameLogEvent exit(String at) => RaidExit(_id(), t(at));
  GameLogEvent rejoin(String at, String location, String? mapId) =>
      RaidRejoined(_id(), t(at), 'MatchWait', location, mapId);
}

/// Reduces [events] and returns every published transition, in order.
List<RaidTransition> _publish(List<GameLogEvent> events) {
  var state = RaidLifecycleState.initial;
  final published = <RaidTransition>[];
  for (final event in events) {
    final (next, transitions) = reduce(state, event);
    state = next;
    published.addAll(transitions);
  }
  return published;
}

LogRecordId _idOf(GameLogEvent event) => (event as RecordedGameLogEvent).id;

DateTime _timeOf(GameLogEvent event) => (event as RecordedGameLogEvent).time;

void main() {
  test('queue to raid publishes queue progress in order', () {
    final log = _Log();
    final events = [
      log.profile('19:30:00'),
      log.queue('19:38:10'),
      log.scene('19:38:20', 'customs'),
      log.found('19:40:00'),
      log.starting('19:40:30'),
      log.started('19:41:06'),
    ];
    final published = _publish(events);

    expect(published.map((t) => t.runtimeType).toList(), [
      QueueEnteredTransition,
      MapKnownTransition,
      MatchFoundTransition,
      RaidStartingTransition,
      RaidStartedTransition,
    ]);
    for (final (transition, event) in [
      (published[0], events[1]),
      (published[1], events[2]),
      (published[2], events[3]),
      (published[3], events[4]),
      (published[4], events[5]),
    ]) {
      expect(transition.id, _idOf(event));
      expect(transition.time, _timeOf(event));
    }
    expect((published[1] as MapKnownTransition).mapId, 'customs');
  });

  test('scene in menus publishes no map-known', () {
    final log = _Log();
    final published = _publish([
      log.profile('19:30:00'),
      log.scene('19:31:00', 'customs'),
    ]);
    expect(published.whereType<MapKnownTransition>(), isEmpty);
  });

  test('rejoin publishes no map-known', () {
    final log = _Log();
    final published = _publish([
      log.profile('19:30:00'),
      log.rejoin('19:31:00', 'bigmap', 'customs'),
    ]);
    expect(published, isEmpty);
  });

  test('scene after a transit rejoin publishes no map-known', () {
    final log = _Log();
    final published = _publish([
      log.profile('19:30:00'),
      log.queue('19:38:10'),
      log.found('19:40:00'),
      log.started('19:41:06'),
      log.exit('19:54:20'),
      log.rejoin('19:54:30', 'bigmap', 'customs'),
      log.scene('19:54:40', 'customs'),
    ]);
    expect(published.whereType<MapKnownTransition>(), isEmpty);
    expect(published.whereType<RaidStartingTransition>(), isEmpty);
  });

  test('unsupported scene in queue publishes map-known with no map', () {
    final log = _Log();
    final scene = log.scene('19:38:20', null);
    final published = _publish([
      log.profile('19:30:00'),
      log.queue('19:38:10'),
      scene,
    ]);
    final known = published.whereType<MapKnownTransition>().single;
    expect(known.mapId, isNull);
    expect(known.id, _idOf(scene));
    expect(known.time, _timeOf(scene));
  });

  test('queue progress leaves raid start and end identities unchanged', () {
    final log = _Log();
    final queued = [
      log.profile('19:30:00'),
      log.queue('19:38:10'),
      log.scene('19:38:20', 'customs'),
      log.found('19:40:00'),
      log.starting('19:40:30'),
      log.started('19:41:06'),
      log.exit('19:54:20'),
      log.profile('19:54:35'),
    ];
    final published = _publish(queued);
    final started = published.whereType<RaidStartedTransition>().single;
    final ended = published.whereType<RaidEndedTransition>().single;
    expect(started.id, _idOf(queued[5]));
    expect(started.time, _timeOf(queued[5]));
    expect(ended.id, _idOf(queued[6]));
    expect(ended.time, _timeOf(queued[6]));
    expect(ended.cause, RaidEndCause.raidExit);

    // The same events without the queue progress events publish the same two.
    final bare = _publish([queued[0], queued[5], queued[6], queued[7]]);
    expect(bare.whereType<RaidStartedTransition>().single.id, started.id);
    expect(bare.whereType<RaidEndedTransition>().single.id, ended.id);
  });
}

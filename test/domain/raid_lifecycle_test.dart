import 'package:flutter_test/flutter_test.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/raid_lifecycle.dart';

/// Builds events with increasing record offsets in one session folder.
final class _Log {
  _Log([this.folder = 'f1']);

  String folder;
  int _offset = 0;

  LogRecordId _id() => LogRecordId(folder, LogFile.application, _offset += 10);

  DateTime t(String hms) {
    final [h, m, s] = hms.split(':').map(int.parse).toList();
    return DateTime(2026, 10, 28, h, m, s);
  }

  GameLogEvent mode(String at, GameMode mode) =>
      SessionModeChanged(_id(), t(at), mode);
  GameLogEvent profile(String at) => ProfileSelected(_id(), t(at));
  GameLogEvent queue(String at) => QueueEntered(_id(), t(at));
  GameLogEvent scene(String at, String? mapId) =>
      SceneLoaded(_id(), t(at), mapId);
  GameLogEvent found(String at) => MatchFound(_id(), t(at));
  GameLogEvent starting(String at) => RaidStarting(_id(), t(at));
  GameLogEvent started(String at) => RaidStarted(_id(), t(at));
  GameLogEvent aborted(String at) => MatchingAborted(_id(), t(at));
  GameLogEvent exit(String at) => RaidExit(_id(), t(at));
  GameLogEvent rejoin(
    String at,
    String location,
    String? mapId, [
    String status = 'MatchWait',
  ]) => RaidRejoined(_id(), t(at), status, location, mapId);
}

/// The states and transitions produced by reducing a list of events.
final class _Trace {
  _Trace(List<GameLogEvent> events) {
    var state = RaidLifecycleState.initial;
    for (final event in events) {
      final (next, published) = reduce(state, event);
      state = next;
      states.add(state);
      steps.add(published);
      transitions.addAll(published);
    }
  }

  final states = <RaidLifecycleState>[];
  final steps = <List<RaidTransition>>[];
  final transitions = <RaidTransition>[];

  RaidLifecycleState get last => states.last;
  List<RaidPhase> get phases => [for (final s in states) s.phase];
  Iterable<T> all<T extends RaidTransition>() => transitions.whereType<T>();
}

/// A queued raid on Customs up to and including raid started at 19:41:06.
List<GameLogEvent> _raidInProgress(_Log log) => [
  log.profile('19:30:00'),
  log.queue('19:38:10'),
  log.scene('19:38:20', 'customs'),
  log.found('19:40:00'),
  log.starting('19:40:30'),
  log.started('19:41:06'),
];

void main() {
  group('phases', () {
    test('there are exactly seven phases; interrupted is not one', () {
      expect(RaidPhase.values.map((p) => p.name).toSet(), {
        'unknown',
        'inMenus',
        'inQueue',
        'matchFound',
        'raidStarting',
        'inRaid',
        'raidEnded',
      });
    });

    test('initial state is unknown', () {
      expect(RaidLifecycleState.initial.phase, RaidPhase.unknown);
      expect(RaidLifecycleState.initial.raid, isNull);
      expect(RaidLifecycleState.initial.lastQueueAborted, isFalse);
    });

    test('a whole raid walks every phase', () {
      final log = _Log();
      final trace = _Trace([
        log.profile('19:30:00'),
        log.queue('19:38:10'),
        log.scene('19:38:20', 'customs'),
        log.found('19:40:00'),
        log.starting('19:40:30'),
        log.started('19:41:06'),
        log.exit('19:54:20'),
        log.profile('19:54:35'),
      ]);
      expect(trace.phases, [
        RaidPhase.inMenus,
        RaidPhase.inQueue,
        RaidPhase.inQueue,
        RaidPhase.matchFound,
        RaidPhase.raidStarting,
        RaidPhase.inRaid,
        RaidPhase.raidEnded,
        RaidPhase.inMenus,
      ]);
      expect(trace.last.raid?.mapId, 'customs');
    });

    test('a whole raid publishes one start and one end', () {
      final log = _Log();
      final events = [
        ..._raidInProgress(log),
        log.exit('19:54:20'),
        log.profile('19:54:35'),
      ];
      final trace = _Trace(events);
      final started = trace.all<RaidStartedTransition>().single;
      final ended = trace.all<RaidEndedTransition>().single;
      expect(trace.transitions, hasLength(2));
      expect(started.id, (events[5] as RecordedGameLogEvent).id);
      expect(started.time, log.t('19:41:06'));
      expect(ended.id, (events[6] as RecordedGameLogEvent).id);
      expect(ended.time, log.t('19:54:20'));
      expect(ended.cause, RaidEndCause.raidExit);
    });

    test('match found goes straight to in raid', () {
      final log = _Log();
      final trace = _Trace([
        log.profile('19:30:00'),
        log.queue('19:38:10'),
        log.found('19:40:00'),
        log.started('19:41:06'),
      ]);
      expect(trace.phases.sublist(2), [RaidPhase.matchFound, RaidPhase.inRaid]);
    });

    test('raid started without a queue enters in raid with no map', () {
      final log = _Log();
      final trace = _Trace([log.profile('19:30:00'), log.started('19:41:06')]);
      expect(trace.last.phase, RaidPhase.inRaid);
      expect(trace.last.raid?.mapId, isNull);
      expect(trace.last.raid?.entry, RaidEntry.noQueue);
      expect(trace.all<RaidStartedTransition>(), hasLength(1));
    });

    test('push events and session mode do not change the phase', () {
      final log = _Log();
      final id = LogRecordId('f1', LogFile.pushNotifications, 1);
      final before = _Trace([log.profile('19:30:00')]).last;
      for (final event in <GameLogEvent>[
        FleaSale(id, log.t('19:31:00'), 'item', 1, 100),
        TaskStarted(id, log.t('19:31:00'), 'task'),
        TaskFailed(id, log.t('19:31:00'), 'task'),
        TaskFinished(id, log.t('19:31:00'), 'task'),
      ]) {
        final (state, published) = reduce(before, event);
        expect(state.phase, RaidPhase.inMenus);
        expect(published, isEmpty);
      }
      final (moded, published) = reduce(
        before,
        log.mode('19:31:00', GameMode.pve) as SessionModeChanged,
      );
      expect(moded.phase, RaidPhase.inMenus);
      expect(moded.sessionMode, GameMode.pve);
      expect(published, isEmpty);
    });

    test('log input reset returns to the initial state', () {
      final log = _Log();
      final state = _Trace(_raidInProgress(log)).last;
      final (reset, published) = reduce(state, const LogInputReset());
      expect(reset.phase, RaidPhase.unknown);
      expect(reset.raid, isNull);
      expect(published, isEmpty);
    });
  });

  group('raid record', () {
    test('records map, mode, times, entry and cause', () {
      final log = _Log();
      final trace = _Trace([
        log.mode('19:30:00', GameMode.seasonal),
        log.profile('19:30:05'),
        log.queue('19:38:10'),
        log.scene('19:38:20', 'lighthouse'),
        log.started('19:41:06'),
        log.exit('19:54:20'),
      ]);
      final raid = trace.last.raid!;
      expect(raid.mapId, 'lighthouse');
      expect(raid.mode, GameMode.seasonal);
      expect(raid.queueTime, log.t('19:38:10'));
      expect(raid.startTime, log.t('19:41:06'));
      expect(raid.endTime, log.t('19:54:20'));
      expect(raid.entry, RaidEntry.queue);
      expect(raid.endCause, RaidEndCause.raidExit);
      expect(raid.interrupted, isFalse);
    });

    test('unsupported scene leaves the map unknown', () {
      final log = _Log();
      final trace = _Trace([
        log.profile('19:30:00'),
        log.queue('19:38:10'),
        log.scene('19:38:20', null),
        log.started('19:41:06'),
      ]);
      expect(trace.last.raid?.mapId, isNull);
      expect(trace.last.phase, RaidPhase.inRaid);
    });
  });

  group('first ending wins', () {
    test('raid exit first ends the raid once', () {
      final log = _Log();
      final trace = _Trace([
        ..._raidInProgress(log),
        log.exit('19:54:20'),
        log.profile('19:54:35'),
      ]);
      expect(trace.phases.sublist(5), [
        RaidPhase.inRaid,
        RaidPhase.raidEnded,
        RaidPhase.inMenus,
      ]);
      final ended = trace.all<RaidEndedTransition>().single;
      expect(ended.time, log.t('19:54:20'));
      expect(ended.cause, RaidEndCause.raidExit);
      expect(trace.last.raid?.endTime, log.t('19:54:20'));
    });

    test('profile select first ends the raid once, from the menus', () {
      final log = _Log();
      final trace = _Trace([
        ..._raidInProgress(log),
        log.profile('19:54:35'),
        log.exit('19:54:36'),
      ]);
      final ended = trace.all<RaidEndedTransition>().single;
      expect(ended.time, log.t('19:54:35'));
      expect(ended.cause, RaidEndCause.menus);
      expect(trace.phases.sublist(6), [RaidPhase.inMenus, RaidPhase.inMenus]);
      expect(trace.steps.last, isEmpty);
      expect(trace.last.raid?.endTime, log.t('19:54:35'));
    });

    test('late raid exit after a menu ending changes nothing', () {
      final log = _Log();
      final trace = _Trace([
        ..._raidInProgress(log),
        log.profile('19:54:35'),
        log.exit('19:54:20'),
      ]);
      expect(trace.all<RaidEndedTransition>(), hasLength(1));
      expect(trace.steps.last, isEmpty);
      expect(trace.last.phase, RaidPhase.inMenus);
      expect(trace.last.raid?.endTime, log.t('19:54:35'));
      expect(trace.last.raid?.endCause, RaidEndCause.menus);
    });

    test('stale exit after a new queue is ignored', () {
      final log = _Log();
      final trace = _Trace([
        ..._raidInProgress(log),
        log.profile('19:54:35'),
        log.queue('19:56:45'),
        log.exit('19:54:20'),
      ]);
      expect(trace.last.phase, RaidPhase.inQueue);
      expect(trace.steps.last, isEmpty);
      expect(trace.all<RaidEndedTransition>(), hasLength(1));
    });

    test('stale profile select before the queue time ends nothing', () {
      final log = _Log();
      final trace = _Trace([
        log.profile('19:30:00'),
        log.queue('19:38:10'),
        log.profile('19:38:00'),
      ]);
      expect(trace.last.phase, RaidPhase.inQueue);
      expect(trace.all<MatchingAbortedTransition>(), isEmpty);
    });

    test('raid exit in menus is ignored', () {
      final log = _Log();
      final trace = _Trace([log.profile('19:30:00'), log.exit('19:31:00')]);
      expect(trace.last.phase, RaidPhase.inMenus);
      expect(trace.last.raid, isNull);
      expect(trace.transitions, isEmpty);
    });
  });

  group('aborted queue', () {
    test('matching cancelled aborts the queue', () {
      final log = _Log();
      final events = [
        log.profile('19:30:00'),
        log.queue('19:38:10'),
        log.scene('19:38:20', 'shoreline'),
        log.found('19:40:00'),
        log.aborted('19:40:20'),
      ];
      final trace = _Trace(events);
      expect(trace.last.phase, RaidPhase.inMenus);
      expect(trace.last.lastQueueAborted, isTrue);
      expect(trace.all<RaidStartedTransition>(), isEmpty);
      final abort = trace.all<MatchingAbortedTransition>().single;
      expect(abort.id, (events[4] as RecordedGameLogEvent).id);
      expect(abort.time, log.t('19:40:20'));
      expect(trace.transitions, hasLength(1));
    });

    test('profile select while loading aborts the queue', () {
      final log = _Log();
      final trace = _Trace([
        log.profile('19:30:00'),
        log.queue('19:38:10'),
        log.found('19:40:00'),
        log.starting('19:40:30'),
        log.profile('19:40:50'),
      ]);
      expect(trace.last.phase, RaidPhase.inMenus);
      expect(trace.last.lastQueueAborted, isTrue);
      expect(trace.all<MatchingAbortedTransition>(), hasLength(1));
      expect(trace.transitions, hasLength(1));
    });

    test('raid exit while in the queue aborts it', () {
      final log = _Log();
      final trace = _Trace([
        log.profile('19:30:00'),
        log.queue('19:38:10'),
        log.exit('19:39:00'),
      ]);
      expect(trace.last.phase, RaidPhase.inMenus);
      expect(trace.last.lastQueueAborted, isTrue);
      expect(trace.all<MatchingAbortedTransition>(), hasLength(1));
    });

    test('abort in menus is ignored', () {
      final log = _Log();
      final trace = _Trace([log.profile('19:30:00'), log.aborted('19:31:00')]);
      expect(trace.last.phase, RaidPhase.inMenus);
      expect(trace.last.lastQueueAborted, isFalse);
      expect(trace.transitions, isEmpty);
    });

    test('a new queue clears the aborted outcome', () {
      final log = _Log();
      final trace = _Trace([
        log.profile('19:30:00'),
        log.queue('19:38:10'),
        log.aborted('19:40:20'),
        log.queue('19:41:00'),
      ]);
      expect(trace.last.phase, RaidPhase.inQueue);
      expect(trace.last.lastQueueAborted, isFalse);
    });
  });

  group('rejoin', () {
    List<GameLogEvent> endedShoreline(_Log log) => [
      log.profile('19:30:00'),
      log.queue('19:38:10'),
      log.scene('19:38:20', 'shoreline'),
      log.started('19:41:06'),
      log.exit('19:54:20'),
    ];

    test('rejoin after an ended raid is a transit', () {
      final log = _Log();
      final trace = _Trace([
        ...endedShoreline(log),
        log.profile('19:54:35'),
        log.rejoin('19:55:00', 'Icebreaker', 'icebreaker'),
        log.started('19:55:30'),
      ]);
      expect(
        trace.states[trace.states.length - 2].phase,
        RaidPhase.raidStarting,
      );
      expect(trace.last.phase, RaidPhase.inRaid);
      final raid = trace.last.raid!;
      expect(raid.mapId, 'icebreaker');
      expect(raid.entry, RaidEntry.transit);
      expect(trace.all<RaidStartedTransition>(), hasLength(2));
    });

    test('rejoin after a queue is a reconnect', () {
      final log = _Log();
      final trace = _Trace([
        ...endedShoreline(log),
        log.queue('19:56:00'),
        log.aborted('19:56:30'),
        log.rejoin('19:57:00', 'Woods', 'woods'),
        log.started('19:57:30'),
      ]);
      expect(trace.last.raid?.entry, RaidEntry.reconnect);
      expect(trace.last.raid?.mapId, 'woods');
    });

    test('rejoin in a new folder after an ended raid is a reconnect', () {
      final log = _Log();
      final trace = _Trace([
        ...endedShoreline(log),
        SessionFolderChanged('f2', log.t('20:00:00')),
        log.profile('20:00:10'),
        log.rejoin('20:00:20', 'Woods', 'woods'),
        log.started('20:00:50'),
      ]);
      expect(trace.last.raid?.entry, RaidEntry.reconnect);
    });

    test('unknown rejoin location has no map', () {
      final log = _Log();
      final trace = _Trace([
        log.profile('19:30:00'),
        log.rejoin('19:31:00', 'mystery', null),
      ]);
      expect(trace.last.phase, RaidPhase.raidStarting);
      final (state, _) = reduce(trace.last, log.started('19:31:30'));
      expect(state.raid?.mapId, isNull);
    });

    test('rejoin status text does not decide transit or reconnect', () {
      final log = _Log();
      final trace = _Trace([
        ...endedShoreline(log),
        log.rejoin('19:55:00', 'Icebreaker', 'icebreaker', 'Busy'),
        log.started('19:55:30'),
      ]);
      expect(trace.last.raid?.entry, RaidEntry.transit);
    });

    test('a rejoin started raid carries the rejoin record identity', () {
      final log = _Log();
      final rejoin = log.rejoin('19:55:00', 'Icebreaker', 'icebreaker');
      final trace = _Trace([
        ...endedShoreline(log),
        rejoin,
        log.started('19:55:30'),
      ]);
      final started = trace.all<RaidStartedTransition>().last;
      expect(started.id, (rejoin as RecordedGameLogEvent).id);
      expect(started.time, log.t('19:55:00'));
      expect(trace.last.raid?.startId, started.id);
    });

    test('rejoin then profile select aborts without a raid', () {
      final log = _Log();
      final trace = _Trace([
        log.profile('19:30:00'),
        log.rejoin('19:31:00', 'Woods', 'woods'),
        log.profile('19:31:30'),
      ]);
      expect(trace.last.phase, RaidPhase.inMenus);
      expect(trace.all<MatchingAbortedTransition>(), hasLength(1));
    });
  });

  group('client restart', () {
    test('restart and reconnect continue one raid', () {
      final log = _Log();
      final trace = _Trace([
        log.profile('22:00:00'),
        log.queue('22:05:00'),
        log.scene('22:05:10', 'laboratory'),
        log.started('22:10:00'),
      ]);
      var state = trace.last;
      log.folder = 'f2';
      final published = <RaidTransition>[];
      final phases = <RaidPhase>[];
      final events = [
        SessionFolderChanged('f2', log.t('23:14:00')),
        log.mode('23:15:00', GameMode.pvp),
        log.profile('23:15:20'),
        log.rejoin('23:16:00', 'laboratory', 'laboratory'),
        log.started('23:16:30'),
      ];
      for (final event in events) {
        final (next, step) = reduce(state, event);
        state = next;
        published.addAll(step);
        phases.add(state.phase);
      }
      expect(phases, [
        RaidPhase.inRaid,
        RaidPhase.inRaid,
        RaidPhase.inMenus,
        RaidPhase.raidStarting,
        RaidPhase.inRaid,
      ]);
      expect(published, isEmpty);
      expect(state.raid?.mapId, 'laboratory');
      expect(state.raid?.endTime, isNull);
      expect(state.raid?.interrupted, isFalse);
      expect(state.raid?.startTime, log.t('22:10:00'));
    });

    test('a new folder during a raid flags it interrupted, not a phase', () {
      final log = _Log();
      final state = _Trace(_raidInProgress(log)).last;
      final (next, published) = reduce(
        state,
        SessionFolderChanged('f2', log.t('23:14:00')),
      );
      expect(next.phase, RaidPhase.inRaid);
      expect(next.raid?.interrupted, isTrue);
      expect(next.currentFolder, 'f2');
      expect(published, isEmpty);
    });

    test('restart then queue ends the raid by client restart', () {
      final log = _Log();
      var state = _Trace(_raidInProgress(log)).last;
      log.folder = 'f2';
      final profile = log.profile('23:15:20') as ProfileSelected;
      final steps = <(RaidLifecycleState, List<RaidTransition>)>[];
      for (final event in [
        SessionFolderChanged('f2', log.t('23:14:00')),
        profile,
        log.queue('23:20:00'),
      ]) {
        final result = reduce(state, event);
        state = result.$1;
        steps.add(result);
      }
      expect(steps[1].$1.phase, RaidPhase.inMenus);
      expect(steps[1].$2, isEmpty);
      expect(steps[1].$1.raid?.endTime, isNull);
      expect(steps[2].$1.phase, RaidPhase.inQueue);
      final ended = steps[2].$2.single as RaidEndedTransition;
      expect(ended.cause, RaidEndCause.clientRestart);
      expect(ended.time, log.t('23:15:20'));
      expect(ended.id, profile.id);
      expect(state.raid?.endTime, log.t('23:15:20'));
      expect(state.raid?.endCause, RaidEndCause.clientRestart);
    });

    test('profile select in the same folder still ends a raid in progress', () {
      final log = _Log();
      final trace = _Trace([..._raidInProgress(log), log.profile('19:54:35')]);
      expect(trace.last.phase, RaidPhase.inMenus);
      final ended = trace.all<RaidEndedTransition>().single;
      expect(ended.cause, RaidEndCause.menus);
    });

    test('only the first profile select after the new folder is deferred', () {
      final log = _Log();
      var state = _Trace(_raidInProgress(log)).last;
      final published = <RaidTransition>[];
      for (final event in [
        SessionFolderChanged('f2', log.t('23:14:00')),
        log.profile('23:15:20'),
      ]) {
        final (next, step) = reduce(state, event);
        state = next;
        published.addAll(step);
      }
      expect(published, isEmpty);
      expect(state.raid?.endTime, isNull);
    });

    test('new folder alone starts a reconnect raid', () {
      final log = _Log('f2');
      final rejoin = log.rejoin(
        '23:16:00',
        'laboratory',
        'laboratory',
        'MatchWait',
      );
      final trace = _Trace([
        SessionFolderChanged('f2', log.t('23:14:00')),
        log.profile('23:15:20'),
        rejoin,
        log.started('23:16:30'),
      ]);
      final started = trace.all<RaidStartedTransition>().single;
      expect(started.id, (rejoin as RecordedGameLogEvent).id);
      expect(trace.last.phase, RaidPhase.inRaid);
      expect(trace.last.raid?.mapId, 'laboratory');
      expect(trace.last.raid?.entry, RaidEntry.reconnect);
      expect(trace.transitions, hasLength(1));
    });
  });
}

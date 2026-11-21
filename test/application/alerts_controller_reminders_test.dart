import 'package:blackgrid/application/audio_port.dart';
import 'package:blackgrid/domain/alert_rules.dart';
import 'package:blackgrid/domain/alerts.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/local_progress.dart';
import 'package:blackgrid/domain/progress_facts.dart';
import 'package:blackgrid/domain/raid_lifecycle.dart';
import 'package:blackgrid_progress/blackgrid_progress.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/alerts_support.dart';

const _questRefs = [QuestObjectiveRef('task-1', 'obj-1')];

/// Task 1 is restartable and has a plant objective; task 2 is not
/// restartable; the Air Filtering Unit is station-air.
ProgressCatalog _catalog() => ProgressCatalog(
  tasks: [
    CatalogTask(
      id: 'task-1',
      name: 'Task one',
      restartable: true,
      objectives: [TaskObjective(id: 'obj-1', type: ObjectiveType.plantItem)],
    ),
    CatalogTask(id: 'task-2', name: 'Task two', restartable: false),
  ],
  stations: [
    HideoutStation(
      id: 'station-air',
      name: 'Air Filtering Unit',
      normalizedName: 'air-filtering-unit',
    ),
  ],
);

ProgressFacts _facts({int air = 1, bool started = true, bool done = false}) =>
    ProgressFacts(
      mode: GameMode.pvp,
      taskStates: {if (started) 'task-1': ProgressTaskStatus.started},
      objectivesComplete: {if (done) 'obj-1'},
      stationLevels: {'station-air': air},
    );

/// Opens the rig on PvP with the catalog, [facts] and every alert on, each
/// playback completing at once.
void _openWithData(AlertsRig rig, {ProgressFacts? facts, bool data = true}) {
  rig.audio.autoComplete = const AudioOk();
  for (final kind in AlertKind.values) {
    rig.settings.setOn(kind, on: true);
  }
  rig.catalog.set(
    GameMode.pvp,
    alertsSnapshot(GameMode.pvp, progressCatalog: data ? _catalog() : null),
  );
  rig.progress.set(GameMode.pvp, data ? (facts ?? _facts()) : null);
  rig.objectives = (mapId) => mapId == 'customs' ? _questRefs : const [];
  rig.open();
}

int _n = 0;

/// Each lifecycle event is logged a second after the one before, because the
/// reducer ignores an exit or profile not after its guard time.
DateTime _t() => alertsAt(12).add(Duration(seconds: ++_n));

void main() {
  final now = alertsAt(12);
  setUp(() => _n = 0);

  group('air filter', () {
    test('air filter on at queue and off at raid end when built', () {
      runAlerts(now, (rig) {
        _openWithData(rig);
        rig.lifecycle
          ..profile(_t())
          ..queue(_t());
        expect(rig.played, ['Air filter on']);

        rig.lifecycle
          ..raidStarted(_t())
          ..raidExit(_t());

        expect(rig.played, ['Air filter on', 'Air filter off']);
      });
    });

    test('client-restart ending skips air filter off', () {
      runAlerts(now, (rig) {
        _openWithData(rig);
        rig.lifecycle.startRaid(_t(), mode: GameMode.pvp);
        expect(rig.played, ['Air filter on']);

        rig.lifecycle.restartClient(_t(), _t());

        expect(rig.played, ['Air filter on', 'Air filter on']);
      });
    });

    test('air filter reminders silent when the unit is not built', () {
      runAlerts(now, (rig) {
        _openWithData(rig, facts: _facts(air: 0));
        rig.lifecycle
          ..profile(_t())
          ..queue(_t())
          ..raidStarted(_t())
          ..raidExit(_t());

        expect(rig.audio.calls, isEmpty);
        expect(rig.controller.airFilterNote, isNull);
      });
    });

    test('air filter reminders wait for local progress', () {
      runAlerts(now, (rig) {
        _openWithData(rig, data: false);
        rig.lifecycle
          ..profile(_t())
          ..queue(_t())
          ..raidStarted(_t())
          ..raidExit(_t());

        expect(rig.audio.calls, isEmpty);
        expect(rig.controller.airFilterNote, contains('local progress'));

        rig.catalog.set(
          GameMode.pvp,
          alertsSnapshot(GameMode.pvp, progressCatalog: _catalog()),
        );
        rig.progress.set(GameMode.pvp, _facts());

        expect(rig.controller.airFilterNote, isNull);
      });
    });

    test('no note shows while both air filter alerts are off', () {
      runAlerts(now, (rig) {
        _openWithData(rig, data: false);
        rig.settings
          ..setOn(AlertKind.airFilterOn, on: false)
          ..setOn(AlertKind.airFilterOff, on: false);

        expect(rig.controller.airFilterNote, isNull);
      });
    });

    test('a replayed queue 20 minutes ago plays nothing', () {
      runAlerts(now, (rig) {
        _openWithData(rig);
        final old = now.subtract(const Duration(minutes: 20));
        rig.lifecycle.startRaid(old, mode: GameMode.pvp);
        rig.lifecycle.raidExit(old.add(const Duration(minutes: 10)));

        expect(rig.audio.calls, isEmpty);
      });
    });

    test('a switched-off air filter alert stays silent', () {
      runAlerts(now, (rig) {
        _openWithData(rig);
        rig.settings.setOn(AlertKind.airFilterOn, on: false);
        rig.lifecycle
          ..profile(_t())
          ..queue(_t());

        expect(rig.audio.calls, isEmpty);
      });
    });
  });

  group('quest items', () {
    test('quest items plays at most once per queue', () {
      runAlerts(now, (rig) {
        _openWithData(rig);
        rig.settings.setOn(AlertKind.airFilterOn, on: false);
        rig.lifecycle
          ..profile(_t())
          ..queue(_t())
          ..scene(_t(), 'customs');
        expect(rig.played, ['Check your quest items']);

        // The map changes in the same queue.
        rig.lifecycle.scene(_t(), 'customs');
        expect(rig.played, ['Check your quest items']);

        // A new queue asks again.
        rig.lifecycle
          ..queue(_t())
          ..scene(_t(), 'customs');
        expect(rig.played, [
          'Check your quest items',
          'Check your quest items',
        ]);
      });
    });

    test('a map with no matching objective stays quiet', () {
      runAlerts(now, (rig) {
        _openWithData(rig);
        rig.settings.setOn(AlertKind.airFilterOn, on: false);
        rig.lifecycle
          ..profile(_t())
          ..queue(_t())
          ..scene(_t(), 'woods');

        expect(rig.audio.calls, isEmpty);
        expect(rig.controller.questItemsNote, isNull);
      });
    });

    test('an unknown map stays quiet', () {
      runAlerts(now, (rig) {
        _openWithData(rig);
        rig.settings.setOn(AlertKind.airFilterOn, on: false);
        rig.lifecycle
          ..profile(_t())
          ..queue(_t())
          ..scene(_t(), null);

        expect(rig.audio.calls, isEmpty);
        expect(rig.controller.questItemsNote, isNull);
      });
    });

    test('a finished objective stays quiet', () {
      runAlerts(now, (rig) {
        _openWithData(rig, facts: _facts(done: true));
        rig.settings.setOn(AlertKind.airFilterOn, on: false);
        rig.lifecycle
          ..profile(_t())
          ..queue(_t())
          ..scene(_t(), 'customs');

        expect(rig.audio.calls, isEmpty);
      });
    });

    test('a stale map-known plays nothing', () {
      runAlerts(now, (rig) {
        _openWithData(rig);
        rig.settings.setOn(AlertKind.airFilterOn, on: false);
        final old = now.subtract(const Duration(minutes: 20));
        rig.lifecycle
          ..profile(old)
          ..queue(old)
          ..scene(old, 'customs');

        expect(rig.audio.calls, isEmpty);
      });
    });

    test('quest items waits for map, quest or progress data', () {
      runAlerts(now, (rig) {
        _openWithData(rig);
        rig.settings.setOn(AlertKind.airFilterOn, on: false);

        // No map pack: the lookup answers null.
        rig.objectives = (_) => null;
        rig.lifecycle
          ..profile(_t())
          ..queue(_t())
          ..scene(_t(), 'customs');
        expect(rig.audio.calls, isEmpty);
        expect(
          rig.controller.questItemsNote,
          contains('map, quest or progress'),
        );

        // The pack arrives: the note clears, and the next queue plays.
        rig.objectives = (_) => _questRefs;
        rig.catalog.set(
          GameMode.pvp,
          alertsSnapshot(GameMode.pvp, progressCatalog: _catalog()),
        );
        expect(rig.controller.questItemsNote, isNull);
        rig.lifecycle
          ..queue(_t())
          ..scene(_t(), 'customs');
        expect(rig.played, ['Check your quest items']);

        // No quest data.
        rig.catalog.set(GameMode.pvp, alertsSnapshot(GameMode.pvp));
        rig.lifecycle
          ..queue(_t())
          ..scene(_t(), 'customs');
        expect(rig.controller.questItemsNote, isNotNull);

        // No progress.
        rig.catalog.set(
          GameMode.pvp,
          alertsSnapshot(GameMode.pvp, progressCatalog: _catalog()),
        );
        rig.progress.set(GameMode.pvp, null);
        rig.lifecycle
          ..queue(_t())
          ..scene(_t(), 'customs');
        expect(rig.controller.questItemsNote, isNotNull);
        expect(rig.played, ['Check your quest items']);
      });
    });

    test('the note is hidden while the alert is off', () {
      runAlerts(now, (rig) {
        _openWithData(rig);
        rig.objectives = (_) => null;
        rig.lifecycle
          ..profile(_t())
          ..queue(_t())
          ..scene(_t(), 'customs');
        expect(rig.controller.questItemsNote, isNotNull);

        rig.settings.setOn(AlertKind.questItems, on: false);

        expect(rig.controller.questItemsNote, isNull);
      });
    });
  });

  group('failed tasks', () {
    test('failed tasks plays on return to menus, not mid-raid', () {
      runAlerts(now, (rig) {
        _openWithData(rig);
        rig.settings.setOn(AlertKind.airFilterOn, on: false);
        rig.settings.setOn(AlertKind.airFilterOff, on: false);
        rig.lifecycle.startRaid(_t());
        rig.lifecycle.taskFailed(_t(), 'task-1');
        expect(rig.played, isNot(contains('Restart failed tasks')));

        rig.lifecycle.raidExit(_t());
        expect(rig.played, isNot(contains('Restart failed tasks')));

        rig.lifecycle.profile(_t());
        expect(
          rig.played.where((l) => l == 'Restart failed tasks'),
          hasLength(1),
        );
      });
    });

    test('two failures play one reminder', () {
      runAlerts(now, (rig) {
        _openWithData(rig);
        rig.lifecycle.startRaid(_t());
        rig.lifecycle
          ..taskFailed(_t(), 'task-1')
          ..taskFailed(_t(), 'task-1');
        rig.lifecycle
          ..raidExit(_t())
          ..profile(_t());
        rig.lifecycle.profile(_t());

        expect(
          rig.played.where((l) => l == 'Restart failed tasks'),
          hasLength(1),
        );
      });
    });

    test('failure read in menus plays at once', () {
      runAlerts(now, (rig) {
        _openWithData(rig);
        rig.lifecycle.profile(_t());
        expect(rig.played, isEmpty);

        rig.lifecycle.taskFailed(_t(), 'task-1');

        expect(rig.played, ['Restart failed tasks']);
      });
    });

    test('a failure and the return to menus in one batch plays once', () {
      runAlerts(now, (rig) {
        _openWithData(rig);
        rig.settings.setOn(AlertKind.airFilterOff, on: false);
        rig.lifecycle.startRaid(_t());
        final id = rig.lifecycle.nextId;
        rig.lifecycle.feedBatch([
          TaskFailed(id(), _t(), 'task-1'),
          RaidExit(id(), _t()),
          ProfileSelected(id(), _t()),
        ]);

        expect(
          rig.played.where((l) => l == 'Restart failed tasks'),
          hasLength(1),
        );
      });
    });

    test('two failures and the return to menus in one batch play once', () {
      runAlerts(now, (rig) {
        _openWithData(rig);
        rig.settings.setOn(AlertKind.airFilterOff, on: false);
        rig.lifecycle.startRaid(_t());
        final id = rig.lifecycle.nextId;
        rig.lifecycle.feedBatch([
          TaskFailed(id(), _t(), 'task-1'),
          TaskFailed(id(), _t(), 'task-1'),
          RaidExit(id(), _t()),
          ProfileSelected(id(), _t()),
        ]);
        rig.settle();

        expect(
          rig.played.where((l) => l == 'Restart failed tasks'),
          hasLength(1),
        );
      });
    });

    test('a later failure read in menus plays again', () {
      runAlerts(now, (rig) {
        _openWithData(rig);
        rig.lifecycle.profile(_t());
        rig.lifecycle.taskFailed(_t(), 'task-1');
        rig.settle();
        rig.lifecycle.taskFailed(_t(), 'task-1');
        rig.settle();

        expect(
          rig.played.where((l) => l == 'Restart failed tasks'),
          hasLength(2),
        );
      });
    });

    test('failed tasks waits through a client restart until the raid ends', () {
      runAlerts(now, (rig) {
        _openWithData(rig);
        rig.lifecycle.startRaid(_t(), mode: GameMode.pvp);
        rig.lifecycle.taskFailed(_t(), 'task-1');

        // The client restarts: in menus, but the raid can still be rejoined.
        rig.lifecycle.feed(const SessionFolderChanged('next'));
        rig.lifecycle.profile(_t());
        expect(rig.lifecycle.state.phase, RaidPhase.inMenus);
        expect(rig.lifecycle.state.currentRaid, isNotNull);
        expect(rig.played, isNot(contains('Restart failed tasks')));

        // The next queue ends the interrupted raid; the player is not in the
        // menus yet.
        rig.lifecycle.queue(_t());
        expect(rig.played, isNot(contains('Restart failed tasks')));

        // The queue is abandoned: in menus with no raid.
        rig.lifecycle.feed(MatchingAborted(rig.lifecycle.nextId(), _t()));
        expect(rig.lifecycle.state.phase, RaidPhase.inMenus);
        expect(
          rig.played.where((l) => l == 'Restart failed tasks'),
          hasLength(1),
        );
      });
    });

    test('a failure that cannot be restarted plays nothing', () {
      runAlerts(now, (rig) {
        _openWithData(rig);
        rig.lifecycle.profile(_t());
        rig.lifecycle
          ..taskFailed(_t(), 'task-2')
          ..taskFailed(_t(), 'unknown-task');

        expect(rig.audio.calls, isEmpty);
      });
    });

    test('a replayed failure plays nothing', () {
      runAlerts(now, (rig) {
        _openWithData(rig);
        final old = now.subtract(const Duration(minutes: 20));
        rig.lifecycle.profile(old);
        rig.lifecycle.taskFailed(old, 'task-1');
        rig.lifecycle.profile(_t());

        expect(rig.audio.calls, isEmpty);
      });
    });

    test('a switched-off failed tasks alert stays silent', () {
      runAlerts(now, (rig) {
        _openWithData(rig);
        rig.settings.setOn(AlertKind.failedTasks, on: false);
        rig.lifecycle.profile(_t());
        rig.lifecycle.taskFailed(_t(), 'task-1');

        expect(rig.audio.calls, isEmpty);
      });
    });
  });
}

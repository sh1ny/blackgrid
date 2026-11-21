import 'package:blackgrid/application/audio_port.dart';
import 'package:blackgrid/domain/alerts.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/progress_facts.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/alerts_support.dart';

const _second = Duration(seconds: 1);

/// Opens the rig on [mode] with its scav cooldown data, completing every
/// playback at once.
void _openOn(AlertsRig rig, GameMode mode) {
  rig.audio.autoComplete = const AudioOk();
  rig.catalog.set(mode, alertsSnapshot(mode));
  rig.progress.set(mode, null);
  rig.open();
}

void main() {
  final now = alertsAt(12);

  group('run-through over', () {
    test('run-through over plays once when the countdown reaches zero', () {
      runAlerts(now, (rig) {
        rig.audio.autoComplete = const AudioOk();
        rig.settings.setTimers(RaidTimerSettings(runThroughSeconds: 430));
        rig.lifecycle.startRaid(now, mode: GameMode.pvp);
        rig.open();

        rig.async.elapse(const Duration(seconds: 429));
        expect(rig.played, isEmpty);
        rig.async.elapse(_second);
        expect(rig.played, ['Run-through over']);

        rig.async.elapse(const Duration(minutes: 30));
        expect(rig.played, ['Run-through over']);
      });
    });

    test('it fires with the timer strip switched off', () {
      runAlerts(now, (rig) {
        rig.audio.autoComplete = const AudioOk();
        rig.settings.setTimers(
          RaidTimerSettings(enabled: false, runThroughSeconds: 430),
        );
        rig.lifecycle.startRaid(now);
        rig.open();

        rig.async.elapse(const Duration(seconds: 430));

        expect(rig.played, ['Run-through over']);
      });
    });

    test('raid ending before the run-through plays nothing', () {
      runAlerts(now, (rig) {
        rig.audio.autoComplete = const AudioOk();
        rig.lifecycle.startRaid(now);
        rig.open();

        rig.async.elapse(const Duration(minutes: 5));
        rig.lifecycle.raidExit(alertsAt(12, 5));
        rig.async.elapse(const Duration(minutes: 30));

        expect(rig.audio.calls, isEmpty);
      });
    });

    test('run-through already over at startup plays nothing', () {
      runAlerts(now, (rig) {
        rig.audio.autoComplete = const AudioOk();
        rig.lifecycle.startRaid(alertsAt(11, 50));
        rig.open();

        rig.async.elapse(const Duration(minutes: 30));

        expect(rig.audio.calls, isEmpty);
      });
    });

    test('a shorter length that is already over plays nothing', () {
      runAlerts(now, (rig) {
        rig.audio.autoComplete = const AudioOk();
        rig.lifecycle.startRaid(now);
        rig.open();
        rig.async.elapse(const Duration(minutes: 2));

        rig.settings.setTimers(RaidTimerSettings(runThroughSeconds: 60));
        rig.async.elapse(const Duration(minutes: 30));

        expect(rig.audio.calls, isEmpty);
      });
    });

    test('a longer length moves the alert later', () {
      runAlerts(now, (rig) {
        rig.audio.autoComplete = const AudioOk();
        rig.lifecycle.startRaid(now);
        rig.open();
        rig.async.elapse(const Duration(minutes: 2));

        rig.settings.setTimers(RaidTimerSettings(runThroughSeconds: 600));
        rig.async.elapse(const Duration(minutes: 7, seconds: 59));
        expect(rig.played, isEmpty);
        rig.async.elapse(_second);

        expect(rig.played, ['Run-through over']);
      });
    });

    test('a new raid counts its own run-through', () {
      runAlerts(now, (rig) {
        rig.audio.autoComplete = const AudioOk();
        rig.lifecycle.startRaid(now);
        rig.open();
        rig.async.elapse(const Duration(minutes: 8));
        rig.lifecycle.raidExit(alertsAt(12, 8));
        rig.lifecycle.startRaid(alertsAt(12, 8));
        rig.async.elapse(const Duration(minutes: 9));

        expect(rig.played, ['Run-through over', 'Run-through over']);
      });
    });

    test('it stays silent when the alert is off', () {
      runAlerts(now, (rig) {
        rig.audio.autoComplete = const AudioOk();
        rig.settings.setOn(AlertKind.runThroughOver, on: false);
        rig.lifecycle.startRaid(now);
        rig.open();

        rig.async.elapse(const Duration(minutes: 30));

        expect(rig.audio.calls, isEmpty);
      });
    });

    test('a scav raid has no run-through alert', () {
      runAlerts(now, (rig) {
        rig.audio.autoComplete = const AudioOk();
        rig.lifecycle.startRaid(now, scav: true);
        rig.open();

        rig.async.elapse(const Duration(minutes: 30));

        expect(rig.audio.calls, isEmpty);
      });
    });

    test('a reconnected raid has no run-through alert', () {
      runAlerts(now, (rig) {
        rig.audio.autoComplete = const AudioOk();
        rig.lifecycle
          ..profile(now)
          ..rejoin(now)
          ..raidStarted(now);
        rig.open();

        rig.async.elapse(const Duration(minutes: 30));

        expect(rig.audio.calls, isEmpty);
      });
    });

    test('one timer is armed for the earliest deadline', () {
      runAlerts(now, (rig) {
        rig.lifecycle.startRaid(now);
        rig.settings.setStart(
          GameMode.pvp,
          now.subtract(const Duration(minutes: 20)),
        );
        _openOn(rig, GameMode.pvp);

        // The scav deadline is 5 minutes ahead, the run-through 7:10. The scav
        // deadline passes mid-raid, so only the run-through speaks.
        expect(rig.async.nonPeriodicTimerCount, 1);
        rig.async.elapse(const Duration(minutes: 5));
        expect(rig.played, isEmpty);
        expect(rig.async.nonPeriodicTimerCount, 1);
        rig.async.elapse(const Duration(minutes: 2, seconds: 10));
        expect(rig.played, ['Run-through over']);
      });
    });
  });

  group('scav ready', () {
    test('scav ready plays once when the cooldown runs out', () {
      runAlerts(now, (rig) {
        rig.settings.setStart(
          GameMode.pvp,
          now.subtract(const Duration(seconds: 1499)),
        );
        _openOn(rig, GameMode.pvp);

        expect(rig.played, isEmpty);
        rig.async.elapse(_second);
        expect(rig.played, ['Scav ready']);

        rig.async.elapse(const Duration(hours: 1));
        expect(rig.played, ['Scav ready']);
      });
    });

    test('scav already ready at startup plays nothing', () {
      runAlerts(now, (rig) {
        rig.settings.setStart(
          GameMode.pvp,
          now.subtract(const Duration(seconds: 2000)),
        );
        _openOn(rig, GameMode.pvp);

        rig.async.elapse(const Duration(hours: 1));

        expect(rig.audio.calls, isEmpty);
      });
    });

    test('switching to a ready mode plays nothing', () {
      runAlerts(now, (rig) {
        rig.settings.setStart(
          GameMode.pvp,
          now.subtract(const Duration(minutes: 20)),
        );
        _openOn(rig, GameMode.pvp);

        rig.catalog.set(GameMode.pve, alertsSnapshot(GameMode.pve));
        rig.progress.set(GameMode.pve, null);
        rig.async.elapse(const Duration(hours: 1));

        expect(rig.audio.calls, isEmpty);
      });
    });

    test('progress loading that makes the cooldown ready plays nothing', () {
      runAlerts(now, (rig) {
        rig.settings.setStart(
          GameMode.pvp,
          now.subtract(const Duration(minutes: 20)),
        );
        rig.audio.autoComplete = const AudioOk();
        rig.catalog.set(
          GameMode.pvp,
          alertsSnapshot(GameMode.pvp, bonuses: {'scav-1': -0.5}),
        );
        rig.progress.set(GameMode.pvp, null);
        rig.open();
        // Without hideout bonuses 5:00 are left.

        rig.progress.set(
          GameMode.pvp,
          ProgressFacts(mode: GameMode.pvp, stationLevels: {'scav': 1}),
        );
        rig.async.elapse(const Duration(hours: 1));

        expect(rig.audio.calls, isEmpty);
      });
    });

    test('a raid ending starts a cooldown that fires when it runs out', () {
      runAlerts(now, (rig) {
        _openOn(rig, GameMode.pvp);

        rig.settings.setStart(GameMode.pvp, now);
        rig.async.elapse(const Duration(seconds: 1499));
        expect(rig.played, isEmpty);
        rig.async.elapse(_second);

        expect(rig.played, ['Scav ready']);
      });
    });

    test('it stays silent when the alert is off', () {
      runAlerts(now, (rig) {
        rig.settings.setOn(AlertKind.scavReady, on: false);
        rig.settings.setStart(
          GameMode.pvp,
          now.subtract(const Duration(minutes: 20)),
        );
        _openOn(rig, GameMode.pvp);

        rig.async.elapse(const Duration(hours: 1));

        expect(rig.audio.calls, isEmpty);
      });
    });

    test('a cooldown that ends mid-raid plays nothing', () {
      runAlerts(now, (rig) {
        rig.settings.setStart(
          GameMode.pvp,
          now.subtract(const Duration(minutes: 20)),
        );
        rig.lifecycle.startRaid(now, mode: GameMode.pvp, scav: true);
        _openOn(rig, GameMode.pvp);

        rig.async.elapse(const Duration(minutes: 10));
        rig.lifecycle.raidExit(alertsAt(12, 10));
        rig.async.elapse(const Duration(hours: 1));

        expect(rig.audio.calls, isEmpty);
      });
    });

    test('an unknown mode has no deadline', () {
      runAlerts(now, (rig) {
        rig.settings.setStart(GameMode.pvp, now);
        _openOn(rig, GameMode.unknown);

        rig.async.elapse(const Duration(hours: 1));

        expect(rig.audio.calls, isEmpty);
        expect(rig.async.nonPeriodicTimerCount, 0);
      });
    });
  });

  test('dispose cancels the deadline timer', () {
    runAlerts(now, (rig) {
      rig.lifecycle.startRaid(now);
      rig.open();
      expect(rig.async.nonPeriodicTimerCount, 1);

      rig.controller.dispose();

      expect(rig.async.nonPeriodicTimerCount, 0);
    });
  });
}

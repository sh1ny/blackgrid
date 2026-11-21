import 'package:blackgrid/application/audio_port.dart';
import 'package:blackgrid/domain/alerts.dart';
import 'package:blackgrid/domain/raid_lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/alerts_support.dart';

void main() {
  final now = alertsAt(12);

  group('lifecycle alerts', () {
    test('match found then raid starting each play once', () {
      runAlerts(now, (rig) {
        rig.open();
        rig.lifecycle
          ..profile(now)
          ..queue(now)
          ..matchFound(now)
          ..raidStarting(now)
          ..raidStarted(now);
        rig.settle();

        expect(rig.played, ['Match found']);
        rig.finish();
        expect(rig.played, ['Match found', 'Raid starting']);
        rig.finish();
        expect(rig.played, ['Match found', 'Raid starting']);
        expect(rig.audio.pendingCount, 0);
      });
    });

    test('match found and raid starting in one batch both play in order', () {
      runAlerts(now, (rig) {
        rig.open();
        rig.lifecycle
          ..profile(now)
          ..queue(now);
        final id = rig.lifecycle.nextId;
        rig.lifecycle.feedBatch([
          MatchFound(id(), now),
          ServerJoined(id(), now),
          RaidStarting(id(), now),
        ]);
        rig.settle();
        rig.finish();

        expect(rig.played, ['Match found', 'Raid starting']);
      });
    });

    test('raid starting plays at raid start when no countdown was logged', () {
      runAlerts(now, (rig) {
        rig.audio.autoComplete = const AudioOk();
        rig.open();
        rig.lifecycle
          ..profile(now)
          ..queue(now)
          ..matchFound(now)
          ..raidStarted(now);
        rig.settle();

        expect(rig.played, ['Match found', 'Raid starting']);
      });
    });

    test('a rejoined raid plays no raid starting', () {
      runAlerts(now, (rig) {
        rig.audio.autoComplete = const AudioOk();
        rig.open();
        rig.lifecycle
          ..profile(now)
          ..rejoin(now)
          ..raidStarted(now);
        rig.settle();

        expect(rig.played, isEmpty);
      });
    });

    test('matching completed without joining a server plays nothing', () {
      runAlerts(now, (rig) {
        rig.audio.autoComplete = const AudioOk();
        rig.open();
        rig.lifecycle
          ..profile(now)
          ..queue(now)
          ..matchingCompleted(now)
          ..matchingCancelled(now);
        rig.settle();

        expect(rig.played, isEmpty);
      });
    });

    test('a transition identity fires at most once', () {
      runAlerts(now, (rig) {
        rig.audio.autoComplete = const AudioOk();
        rig.open();
        final id = rig.lifecycle.nextId();
        rig.lifecycle
          ..emit(MatchFoundTransition(id, now))
          ..emit(MatchFoundTransition(id, now));
        rig.settle();

        expect(rig.played, ['Match found']);
      });
    });

    test('only the last 256 identities are remembered', () {
      runAlerts(now, (rig) {
        rig.audio.autoComplete = const AudioOk();
        rig.open();
        final first = rig.lifecycle.nextId();
        rig.lifecycle.emit(MatchFoundTransition(first, now));
        for (var i = 0; i < 256; i++) {
          rig.lifecycle.emit(MatchFoundTransition(rig.lifecycle.nextId(), now));
          rig.settle();
        }
        expect(rig.played, hasLength(257));

        rig.lifecycle.emit(MatchFoundTransition(first, now));
        rig.settle();

        expect(rig.played, hasLength(258));
      });
    });

    test('the same record can fire different alerts', () {
      runAlerts(now, (rig) {
        rig.audio.autoComplete = const AudioOk();
        rig.open();
        final id = rig.lifecycle.nextId();
        rig.lifecycle
          ..emit(MatchFoundTransition(id, now))
          ..emit(RaidStartingTransition(id, now));
        rig.settle();

        expect(rig.played, ['Match found', 'Raid starting']);
      });
    });
  });

  group('freshness', () {
    test('a transition logged 2 s ago plays', () {
      runAlerts(now, (rig) {
        rig.open();
        rig.lifecycle.emit(
          MatchFoundTransition(
            rig.lifecycle.nextId(),
            now.subtract(const Duration(seconds: 2)),
          ),
        );
        rig.settle();

        expect(rig.played, ['Match found']);
      });
    });

    test('a transition read while its alert is off never plays later', () {
      runAlerts(now, (rig) {
        rig.settings.setOn(AlertKind.matchFound, on: false);
        rig.open();
        final transition = MatchFoundTransition(rig.lifecycle.nextId(), now);
        rig.lifecycle.emit(transition);
        rig.settle();

        // The switch goes on and a rescan delivers the same transition again.
        rig.settings.setOn(AlertKind.matchFound, on: true);
        rig.lifecycle.emit(transition);
        rig.settle();

        expect(rig.audio.calls, isEmpty);
      });
    });

    test('a replayed transition logged 20 minutes ago plays nothing', () {
      runAlerts(now, (rig) {
        rig.open();
        final old = now.subtract(const Duration(minutes: 20));
        rig.lifecycle
          ..profile(old)
          ..queue(old)
          ..matchFound(old)
          ..raidStarting(old)
          ..raidStarted(old);
        rig.settle();

        expect(rig.audio.calls, isEmpty);
      });
    });

    test('a transition with a future log time counts as fresh', () {
      runAlerts(now, (rig) {
        rig.open();
        rig.lifecycle.emit(
          MatchFoundTransition(
            rig.lifecycle.nextId(),
            now.add(const Duration(hours: 2)),
          ),
        );
        rig.settle();

        expect(rig.played, ['Match found']);
      });
    });

    test('30 s old is fresh and 31 s old is not', () {
      runAlerts(now, (rig) {
        rig.audio.autoComplete = const AudioOk();
        rig.open();
        rig.lifecycle
          ..emit(
            MatchFoundTransition(
              rig.lifecycle.nextId(),
              now.subtract(const Duration(seconds: 31)),
            ),
          )
          ..emit(
            RaidStartingTransition(
              rig.lifecycle.nextId(),
              now.subtract(const Duration(seconds: 30)),
            ),
          );
        rig.settle();

        expect(rig.played, ['Raid starting']);
      });
    });
  });

  group('switches', () {
    test('an alert switched off does not play', () {
      runAlerts(now, (rig) {
        rig.settings.setOn(AlertKind.matchFound, on: false);
        rig.open();
        rig.lifecycle.emit(MatchFoundTransition(rig.lifecycle.nextId(), now));
        rig.settle();

        expect(rig.audio.calls, isEmpty);
      });
    });

    test('an alert switched off while it waits is dropped', () {
      runAlerts(now, (rig) {
        final c = rig.open().controller;
        c.test(AlertKind.scavReady);
        rig.settle();
        rig.lifecycle.emit(MatchFoundTransition(rig.lifecycle.nextId(), now));
        rig.settings.setOn(AlertKind.matchFound, on: false);
        rig.finish();

        expect(rig.played, ['Scav ready']);
        expect(rig.audio.pendingCount, 0);
      });
    });

    test('a test still plays after a stale-gated alert is refused', () {
      runAlerts(now, (rig) {
        final c = rig.open().controller;
        rig.lifecycle.emit(
          MatchFoundTransition(
            rig.lifecycle.nextId(),
            now.subtract(const Duration(minutes: 5)),
          ),
        );
        c.test(AlertKind.matchFound);
        rig.settle();

        expect(rig.played, ['Match found']);
      });
    });
  });
}

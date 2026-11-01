import 'dart:async';

import 'package:blackgrid/application/raid_timers_controller.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/progress.dart';
import 'package:blackgrid/domain/raid_lifecycle.dart';
import 'package:blackgrid/domain/raid_timers.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const _folder = 'log_2026.10.31_19-00-00_1.3.0.0.48484';

DateTime _at(int h, [int m = 0, int s = 0]) => DateTime(2026, 10, 31, h, m, s);

/// A lifecycle source folding events with the real reducer, publishing like
/// [RaidLifecycleController]: state first, then each transition, synchronously.
class _FakeLifecycle extends ChangeNotifier
    implements RaidTimerLifecycleSource {
  RaidLifecycleState _state = RaidLifecycleState.initial;
  final _out = StreamController<RaidTransition>.broadcast(sync: true);
  int _offset = 0;

  @override
  RaidLifecycleState get state => _state;

  @override
  Stream<RaidTransition> get transitions => _out.stream;

  bool get hasTransitionListener => _out.hasListener;

  LogRecordId get _id => LogRecordId(_folder, LogFile.application, _offset++);

  void feed(GameLogEvent event) {
    final (next, published) = reduce(_state, event);
    _state = next;
    notifyListeners();
    published.forEach(_out.add);
  }

  /// A raid entered from the queue at [start]; a raid-starting countdown more
  /// than three seconds before [start] makes the side PMC, none makes it scav.
  void startRaid(DateTime start, {GameMode? mode, bool pmc = false}) {
    if (mode != null) feed(SessionModeChanged(_id, start, mode));
    feed(ProfileSelected(_id, start));
    feed(QueueEntered(_id, start));
    if (pmc) feed(RaidStarting(_id, start));
    feed(
      RaidStarted(_id, pmc ? start.add(const Duration(seconds: 10)) : start),
    );
  }

  void exitRaid(DateTime time) => feed(RaidExit(_id, time));

  void restartClient(DateTime profileTime, DateTime queueTime) {
    feed(const SessionFolderChanged('next'));
    feed(ProfileSelected(_id, profileTime));
    feed(QueueEntered(_id, queueTime));
  }

  @override
  void dispose() {
    unawaited(_out.close());
    super.dispose();
  }
}

class _FakeSettings extends ChangeNotifier implements RaidTimerSettingsSource {
  _FakeSettings([RaidTimerSettings? timers])
    : _timers = timers ?? RaidTimerSettings();

  /// The saved app mode. The controller never reads it: the surface has no
  /// such member, and the active mode comes from the catalog.
  final GameMode mode = GameMode.unknown;

  RaidTimerSettings _timers;
  final Map<GameMode, DateTime> starts = {};
  final recorded = <(GameMode, DateTime)>[];

  @override
  RaidTimerSettings get raidTimers => _timers;

  @override
  Map<GameMode, DateTime> get effectiveScavCooldownStarts =>
      Map.unmodifiable(starts);

  void setTimers(RaidTimerSettings timers) {
    _timers = timers;
    notifyListeners();
  }

  @override
  Future<void> recordScavCooldownStart(GameMode mode, DateTime start) async {
    recorded.add((mode, start));
    starts[mode] = start;
    notifyListeners();
  }
}

class _FakeCatalog extends ChangeNotifier implements RaidTimerCatalogSource {
  @override
  GameMode mode = GameMode.unknown;
  @override
  CatalogSnapshot? snapshot;

  void set(GameMode newMode, CatalogSnapshot? newSnapshot) {
    mode = newMode;
    snapshot = newSnapshot;
    notifyListeners();
  }
}

class _FakeProgress extends ChangeNotifier implements RaidTimerProgressSource {
  @override
  GameMode mode = GameMode.unknown;
  @override
  ProgressSnapshot? snapshot;

  void changed() => notifyListeners();
}

/// Base 25:00; Fence modifier 1.0 below reputation 3 and 0.8 from it.
ScavCooldownInputs _inputs() => ScavCooldownInputs(
  baseSeconds: 1500,
  fenceLevels: const [
    FenceCooldownLevel(minimumReputation: -7, modifier: 1),
    FenceCooldownLevel(minimumReputation: 3, modifier: 0.8),
  ],
  bonuses: const {},
);

CatalogSnapshot _snapshot(GameMode mode) => CatalogSnapshot(
  mode: mode,
  revision: 'r',
  observedAt: _at(0, 0),
  items: const {},
  traders: const {},
  requirements: const [],
  scavCooldown: _inputs(),
);

/// Everything one test needs, built inside [fakeAsync].
class _Rig {
  _Rig(this.async, {required this._origin, RaidTimerSettings? timers})
    : settings = _FakeSettings(timers);

  final FakeAsync async;
  final DateTime _origin;
  Duration jump = Duration.zero;
  final lifecycle = _FakeLifecycle();
  final _FakeSettings settings;
  final catalog = _FakeCatalog();
  final progress = _FakeProgress();
  late final RaidTimersController controller;

  /// The clock: the origin, fake elapsed time and any [jump] with no ticks.
  DateTime now() => _origin.add(async.elapsed + jump);

  void open() {
    controller = RaidTimersController(
      lifecycle: lifecycle,
      settings: settings,
      catalog: catalog,
      progress: progress,
      clock: now,
    );
  }

  /// Opens the controller on [mode] with its item data.
  void openOn(GameMode mode) {
    catalog.set(mode, _snapshot(mode));
    open();
  }

  String text(RaidTimerKind kind) =>
      controller.view.entries.singleWhere((e) => e.kind == kind).text;
}

void _run(
  DateTime origin,
  void Function(_Rig rig) body, {
  RaidTimerSettings? timers,
}) {
  fakeAsync((async) {
    final rig = _Rig(async, origin: origin, timers: timers);
    body(rig);
    rig.controller.dispose();
    rig.lifecycle.dispose();
    async.flushTimers();
  });
}

void main() {
  test('replayed current raid shows elapsed time before any tick', () {
    _run(_at(20, 10), (rig) {
      // Replay finished before the controller exists: only state, no events.
      rig.lifecycle.startRaid(_at(19, 41, 6), mode: GameMode.pvp);
      rig.openOn(GameMode.pvp);

      expect(rig.text(RaidTimerKind.inRaid), 'In raid 28:54');
    });
  });

  test('run-through length change applies at once', () {
    _run(_at(19, 45), (rig) {
      rig.lifecycle.startRaid(_at(19, 42), mode: GameMode.pvp);
      rig.openOn(GameMode.pvp);
      expect(rig.text(RaidTimerKind.inRaid), 'In raid 3:00');
      expect(rig.text(RaidTimerKind.runThrough), 'Run-through 4:10');

      rig.settings.setTimers(RaidTimerSettings(runThroughSeconds: 600));

      expect(rig.text(RaidTimerKind.runThrough), 'Run-through 7:00');
    });
  });

  test('scav raid ending records its mode\'s start', () {
    _run(_at(20, 6), (rig) {
      rig.openOn(GameMode.seasonal);
      rig.lifecycle.startRaid(_at(19, 41), mode: GameMode.seasonal);
      rig.lifecycle.exitRaid(_at(20, 5));

      expect(rig.settings.recorded, [(GameMode.seasonal, _at(20, 5))]);
    });
  });

  test('PMC raid ending records nothing', () {
    _run(_at(20, 6), (rig) {
      final running = _at(19, 50);
      rig.settings.starts[GameMode.pvp] = running;
      rig.openOn(GameMode.pvp);
      rig.lifecycle.startRaid(_at(19, 41), mode: GameMode.pvp, pmc: true);
      rig.lifecycle.exitRaid(_at(20, 5));

      expect(rig.settings.recorded, isEmpty);
      expect(rig.settings.effectiveScavCooldownStarts[GameMode.pvp], running);
    });
  });

  test('any PvE raid ending records a PvE start', () {
    _run(_at(18, 1), (rig) {
      rig.openOn(GameMode.pve);
      rig.lifecycle.startRaid(_at(17, 30), mode: GameMode.pve, pmc: true);
      rig.lifecycle.exitRaid(_at(18));

      expect(rig.settings.recorded, [(GameMode.pve, _at(18))]);
    });
  });

  test('raid with unknown mode records nothing', () {
    _run(_at(20, 30), (rig) {
      rig.openOn(GameMode.pvp);
      // No session mode was logged: the raid's mode is null.
      rig.lifecycle.startRaid(_at(19, 41));
      rig.lifecycle.exitRaid(_at(20, 5));
      // A logged but unrecognised mode is unknown, not a mode.
      rig.lifecycle.startRaid(_at(20, 10), mode: GameMode.unknown);
      rig.lifecycle.exitRaid(_at(20, 20));

      expect(rig.settings.recorded, isEmpty);
    });
  });

  test('client-restart ending records its end time', () {
    _run(_at(23, 20), (rig) {
      rig.openOn(GameMode.seasonal);
      rig.lifecycle.startRaid(_at(22, 50), mode: GameMode.seasonal);
      rig.lifecycle.restartClient(_at(23, 15, 20), _at(23, 16));

      expect(rig.settings.recorded, [(GameMode.seasonal, _at(23, 15, 20))]);
    });
  });

  test('reputation change recomputes the remaining time', () {
    // Started 15:30 ago: 25:00 x 1.0 leaves 9:30, 25:00 x 0.8 leaves 4:30.
    _run(_at(20, 0), (rig) {
      rig.settings.starts[GameMode.pvp] = _at(19, 44, 30);
      rig.openOn(GameMode.pvp);
      expect(rig.text(RaidTimerKind.scav), 'Scav 9:30');

      rig.settings.setTimers(
        RaidTimerSettings(fenceReputation: {GameMode.pvp: 3}),
      );

      expect(rig.text(RaidTimerKind.scav), 'Scav 4:30');
    });
  });

  test('switching mode shows that mode\'s cooldown and keeps the other', () {
    _run(_at(20, 0), (rig) {
      final seasonalStart = _at(19, 50);
      rig.settings.starts[GameMode.seasonal] = seasonalStart;
      rig.openOn(GameMode.seasonal);
      expect(rig.text(RaidTimerKind.scav), 'Scav 15:00');

      // The mode changed but its item data has not arrived yet.
      rig.catalog.set(GameMode.pve, _snapshot(GameMode.seasonal));
      expect(rig.text(RaidTimerKind.scav), 'Scav unknown');

      rig.catalog.set(GameMode.pve, _snapshot(GameMode.pve));
      expect(rig.text(RaidTimerKind.scav), 'Scav ready');
      expect(
        rig.settings.effectiveScavCooldownStarts[GameMode.seasonal],
        seasonalStart,
      );
    });
  });

  test('log-detected mode drives the scav entry', () {
    _run(_at(20, 0), (rig) {
      rig.settings.starts[GameMode.pvp] = _at(19, 50);
      rig.openOn(GameMode.pvp);

      expect(rig.settings.mode, GameMode.unknown);
      expect(rig.text(RaidTimerKind.scav), 'Scav 15:00');
    });
  });

  test('missed ticks do not drift', () {
    _run(_at(19, 41, 6), (rig) {
      rig.lifecycle.startRaid(_at(19, 41, 6), mode: GameMode.pvp);
      rig.openOn(GameMode.pvp);

      rig.async.elapse(const Duration(seconds: 54));
      expect(rig.text(RaidTimerKind.inRaid), 'In raid 0:54');

      // The clock moves on with no tick delivered, then one tick arrives.
      rig.jump = const Duration(minutes: 2, seconds: 59);
      rig.async.elapse(const Duration(seconds: 1));

      expect(rig.now(), _at(19, 45));
      expect(rig.text(RaidTimerKind.inRaid), 'In raid 3:54');
    });
  });

  test('no periodic timer while nothing moves', () {
    _run(_at(20, 0), (rig) {
      rig.openOn(GameMode.pvp);

      expect(rig.controller.view.moving, isFalse);
      expect(rig.async.periodicTimerCount, 0);
    });
  });

  test('a moving view arms one timer and a still view cancels it', () {
    _run(_at(19, 45), (rig) {
      rig.openOn(GameMode.pvp);
      rig.lifecycle.startRaid(_at(19, 41), mode: GameMode.pvp, pmc: true);
      expect(rig.async.periodicTimerCount, 1);

      rig.lifecycle.exitRaid(_at(19, 44));

      expect(rig.async.periodicTimerCount, 0);
    });
  });

  test('ticks notify and dispose cancels timer, stream and listeners', () {
    _run(_at(19, 45), (rig) {
      rig.lifecycle.startRaid(_at(19, 41), mode: GameMode.pvp);
      rig.openOn(GameMode.pvp);
      var notified = 0;
      rig.controller.addListener(() => notified++);

      rig.async.elapse(const Duration(seconds: 3));
      expect(notified, 3);
      expect(rig.text(RaidTimerKind.inRaid), 'In raid 4:03');

      rig.controller.dispose();

      expect(rig.async.periodicTimerCount, 0);
      expect(rig.lifecycle.hasTransitionListener, isFalse);
      rig.settings.setTimers(RaidTimerSettings(runThroughSeconds: 90));
      rig.catalog.set(GameMode.pve, null);
      rig.progress.changed();
      expect(notified, 3);
    });
  });
}

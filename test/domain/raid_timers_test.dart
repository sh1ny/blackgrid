import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/progress_facts.dart';
import 'package:blackgrid/domain/raid_lifecycle.dart';
import 'package:blackgrid/domain/raid_timers.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:flutter_test/flutter_test.dart';

const _id = LogRecordId('folder', LogFile.backend, 0);

Raid _raid(
  DateTime start, {
  DateTime? end,
  bool interrupted = false,
  GameMode? mode = GameMode.seasonal,
  RaidSide side = RaidSide.pmc,
}) => Raid(
  mapId: 'map',
  mode: mode,
  queueTime: null,
  startTime: start,
  startId: _id,
  entry: RaidEntry.queue,
  endTime: end,
  endCause: end == null ? null : RaidEndCause.raidExit,
  interrupted: interrupted,
  side: side,
);

RaidLifecycleState _state(Raid? raid) => RaidLifecycleState(
  phase: switch (raid) {
    null => RaidPhase.inMenus,
    Raid(isCurrent: true) => RaidPhase.inRaid,
    _ => RaidPhase.raidEnded,
  },
  raid: raid,
);

ScavCooldownInputs _inputs({
  double base = 1500,
  List<FenceCooldownLevel>? levels,
  Map<String, double>? bonuses,
}) => ScavCooldownInputs(
  baseSeconds: base,
  fenceLevels:
      levels ??
      const [
        FenceCooldownLevel(minimumReputation: 0, modifier: 1),
        FenceCooldownLevel(minimumReputation: 2, modifier: 0.8),
        FenceCooldownLevel(minimumReputation: 3, modifier: 0.7),
      ],
  bonuses: bonuses ?? const {'ic-1': -0.15, 'ic-3': -0.2},
);

ProgressFacts _progress(GameMode mode, Map<String, int> stations) =>
    ProgressFacts(mode: mode, stationLevels: stations);

RaidTimersView _view({
  required DateTime now,
  Raid? raid,
  RaidTimerSettings? settings,
  GameMode activeMode = GameMode.seasonal,
  Map<GameMode, DateTime> starts = const {},
  ScavCooldownInputs? inputs,
  ProgressFacts? progress,
}) => raidTimersView(
  now: now,
  lifecycle: _state(raid),
  settings: settings ?? RaidTimerSettings(),
  activeMode: activeMode,
  cooldownStarts: starts,
  inputs: inputs,
  progress: progress,
);

String _text(RaidTimersView v, RaidTimerKind kind) =>
    v.entries.singleWhere((e) => e.kind == kind).text;

RaidTimerEntry _entry(RaidTimersView v, RaidTimerKind kind) =>
    v.entries.singleWhere((e) => e.kind == kind);

void main() {
  final start = DateTime(2026, 11, 1, 19, 41, 6);

  group('time in raid', () {
    test('time in raid is now minus the log start', () {
      final v = _view(
        now: DateTime(2026, 11, 1, 19, 53, 40),
        raid: _raid(start),
      );
      expect(_text(v, RaidTimerKind.inRaid), 'In raid 12:34');
      expect(v.moving, isTrue);
    });

    test('ended raid freezes as last raid', () {
      final raid = _raid(start, end: DateTime(2026, 11, 1, 20, 5));
      final a = _view(now: DateTime(2026, 11, 1, 20, 30), raid: raid);
      final b = _view(now: DateTime(2026, 11, 1, 22), raid: raid);
      expect(_text(a, RaidTimerKind.inRaid), 'Last raid 23:54');
      expect(_text(b, RaidTimerKind.inRaid), 'Last raid 23:54');
      expect(a.moving, isFalse);
    });

    test('continued reconnect keeps the original start', () {
      final raid = _raid(DateTime(2026, 11, 1, 21), interrupted: true);
      final v = _view(now: DateTime(2026, 11, 1, 21, 20), raid: raid);
      expect(_text(v, RaidTimerKind.inRaid), 'In raid 20:00');
    });

    test('start after now clamps to zero', () {
      final now = DateTime(2026, 11, 1, 19, 53, 40);
      final v = _view(
        now: now,
        raid: _raid(now.add(const Duration(seconds: 10))),
      );
      expect(_text(v, RaidTimerKind.inRaid), 'In raid 0:00');
    });

    test('no raid gives a dash', () {
      final v = _view(now: start);
      expect(_text(v, RaidTimerKind.inRaid), 'In raid —');
      expect(_text(v, RaidTimerKind.runThrough), 'Run-through —');
    });

    test('durations from an hour use h:mm:ss', () {
      final v = _view(
        now: start.add(const Duration(hours: 1, minutes: 2, seconds: 5)),
        raid: _raid(start),
      );
      expect(_text(v, RaidTimerKind.inRaid), 'In raid 1:02:05');
    });
  });

  group('run-through', () {
    final settings = RaidTimerSettings(runThroughSeconds: 430);

    test('run-through is length minus time in raid', () {
      final v = _view(
        now: start.add(const Duration(minutes: 2)),
        raid: _raid(start),
        settings: settings,
      );
      expect(_text(v, RaidTimerKind.runThrough), 'Run-through 5:10');
    });

    test('run-through past the length is done', () {
      final v = _view(
        now: start.add(const Duration(minutes: 9)),
        raid: _raid(start),
        settings: settings,
      );
      expect(_text(v, RaidTimerKind.runThrough), 'Run-through done');
    });

    test('a raid that starts after now shows the full run-through', () {
      final v = _view(
        now: start.subtract(const Duration(seconds: 10)),
        raid: _raid(start),
        settings: settings,
      );
      expect(_text(v, RaidTimerKind.runThrough), 'Run-through 7:10');
    });

    test('a fractional elapsed time rounds the run-through up', () {
      final v = _view(
        now: start.add(const Duration(seconds: 120, milliseconds: 500)),
        raid: _raid(start),
        settings: settings,
      );
      expect(_text(v, RaidTimerKind.runThrough), 'Run-through 5:10');
    });

    test('no run-through after the raid ends', () {
      final raid = _raid(start, end: start.add(const Duration(minutes: 4)));
      final v = _view(
        now: start.add(const Duration(minutes: 5)),
        raid: raid,
        settings: settings,
      );
      expect(_text(v, RaidTimerKind.runThrough), 'Run-through —');
    });
  });

  group('scav cooldown length', () {
    test('neutral reputation and no bonus give the base', () {
      final length = scavCooldownLength(_inputs(), 0, null, GameMode.seasonal);
      expect(length?.seconds, 1500);
    });

    test('reputation 2.50 and two bonuses give 780 s', () {
      final length = scavCooldownLength(
        _inputs(),
        2.5,
        _progress(GameMode.seasonal, {'ic': 3}),
        GameMode.seasonal,
      );
      expect(length?.seconds, 780);
    });

    test('reputation below every level uses the lowest', () {
      final length = scavCooldownLength(
        _inputs(
          levels: const [
            FenceCooldownLevel(minimumReputation: -7, modifier: 6),
            FenceCooldownLevel(minimumReputation: 0, modifier: 1),
          ],
        ),
        -7,
        null,
        GameMode.seasonal,
      );
      expect(length?.seconds, 9000);
      final below = scavCooldownLength(
        _inputs(
          levels: const [
            FenceCooldownLevel(minimumReputation: -5, modifier: 6),
            FenceCooldownLevel(minimumReputation: 0, modifier: 1),
          ],
        ),
        -7,
        null,
        GameMode.seasonal,
      );
      expect(below?.fenceModifier, 6);
    });

    test('missing cooldown inputs give unknown with a reason', () {
      final v = _view(now: start);
      expect(_text(v, RaidTimerKind.scav), 'Scav unknown');
      expect(
        _entry(v, RaidTimerKind.scav).tooltip,
        'No item data for this mode',
      );
      final noLevels = _view(
        now: start,
        inputs: _inputs(levels: const []),
      );
      expect(_text(noLevels, RaidTimerKind.scav), 'Scav unknown');
      expect(
        _entry(noLevels, RaidTimerKind.scav).tooltip,
        'No item data for this mode',
      );
    });

    test('a length too long to count gives unknown, never a throw', () {
      final starts = {GameMode.seasonal: start};
      for (final inputs in [
        // Finite inputs whose product overflows to infinity.
        _inputs(
          base: 1e308,
          levels: const [
            FenceCooldownLevel(minimumReputation: 0, modifier: 10),
          ],
        ),
        // Finite, but longer than any cooldown the timer can show.
        _inputs(base: 1e12),
      ]) {
        expect(
          scavCooldownLength(inputs, 0, null, GameMode.seasonal),
          isNull,
          reason: '${inputs.baseSeconds}',
        );
        final v = _view(now: start, starts: starts, inputs: inputs);
        expect(_text(v, RaidTimerKind.scav), 'Scav unknown');
      }
    });
  });

  group('hideout progress', () {
    final now = DateTime(2026, 11, 1, 20);
    const noBonuses = 'Progress unavailable: no hideout bonuses';

    test('raid-timers: Progress for the mode', () {
      final length = scavCooldownLength(
        _inputs(),
        0,
        _progress(GameMode.pvp, {'ic': 1}),
        GameMode.pvp,
      );
      expect(length?.seconds, 1275);
      expect(length?.hideoutFactor, closeTo(0.85, 1e-9));
      expect(length?.hasProgress, isTrue);
    });

    test('raid-timers: Higher level counts lower bonuses', () {
      final length = scavCooldownLength(
        _inputs(),
        0,
        _progress(GameMode.pvp, {'ic': 3}),
        GameMode.pvp,
      );
      expect(length?.hideoutFactor, closeTo(0.65, 1e-9));
      expect(length?.seconds, 975);
      final belowLevel = scavCooldownLength(
        _inputs(),
        0,
        _progress(GameMode.pvp, {'ic': 2}),
        GameMode.pvp,
      );
      expect(belowLevel?.seconds, 1275);
    });

    test('raid-timers: Progress for another mode', () {
      final progress = _progress(GameMode.pve, {'ic': 1});
      final length = scavCooldownLength(_inputs(), 0, progress, GameMode.pvp);
      expect(length?.seconds, 1500);
      final v = _view(
        now: now,
        activeMode: GameMode.pvp,
        inputs: _inputs(),
        progress: progress,
      );
      expect(_entry(v, RaidTimerKind.scav).tooltip, contains(noBonuses));
    });

    test('raid-timers: Progress unavailable', () {
      final length = scavCooldownLength(_inputs(), 0, null, GameMode.pvp);
      expect(length?.seconds, 1500);
      expect(length?.hasProgress, isFalse);
      final v = _view(now: now, activeMode: GameMode.pvp, inputs: _inputs());
      expect(_entry(v, RaidTimerKind.scav).tooltip, contains(noBonuses));
    });

    test('raid-timers: Stale progress', () {
      // Facts carry no age: a level recorded long ago counts like any other.
      final length = scavCooldownLength(
        _inputs(),
        0,
        _progress(GameMode.pvp, {'ic': 3}),
        GameMode.pvp,
      );
      expect(length?.seconds, 975);
      final v = _view(
        now: now,
        activeMode: GameMode.pvp,
        inputs: _inputs(),
        progress: _progress(GameMode.pvp, {'ic': 3}),
      );
      expect(_entry(v, RaidTimerKind.scav).tooltip, isNot(contains(noBonuses)));
    });

    test('a bonus key splits at the last dash and needs a positive level', () {
      final progress = _progress(GameMode.pvp, {'water-collector': 2, 'ic': 9});
      final length = scavCooldownLength(
        _inputs(
          bonuses: const {
            'water-collector-1': -0.1,
            'water-collector-2': -0.05,
            'water-collector-3': -0.5,
            'ic-0': -0.5,
            'ic--1': -0.5,
            'ic-x': -0.5,
            'ic-': -0.5,
            'nodash': -0.5,
          },
        ),
        0,
        progress,
        GameMode.pvp,
      );
      expect(length?.hideoutFactor, closeTo(0.85, 1e-9));
    });
  });

  group('scav countdown', () {
    final cooldownStart = DateTime(2026, 11, 1, 20, 5);
    final starts = {GameMode.seasonal: cooldownStart};

    test('cooldown remaining is start plus length minus now', () {
      final v = _view(
        now: DateTime(2026, 11, 1, 20, 20, 30),
        starts: starts,
        inputs: _inputs(),
        settings: RaidTimerSettings(),
      );
      expect(_text(v, RaidTimerKind.scav), 'Scav 9:30');
      expect(v.moving, isTrue);
      expect(
        _entry(v, RaidTimerKind.scav).tooltip,
        startsWith('Base 25:00 × Fence 1.00 × hideout 1.00'),
      );
    });

    test('cooldown past its end is ready', () {
      final v = _view(
        now: DateTime(2026, 11, 1, 20, 31),
        starts: starts,
        inputs: _inputs(),
      );
      expect(_text(v, RaidTimerKind.scav), 'Scav ready');
      expect(v.moving, isFalse);
    });

    test('unknown active mode gives unknown with a reason', () {
      final v = _view(
        now: cooldownStart,
        activeMode: GameMode.unknown,
        starts: starts,
        inputs: _inputs(),
      );
      expect(_text(v, RaidTimerKind.scav), 'Scav unknown');
      expect(_entry(v, RaidTimerKind.scav).tooltip, 'Choose a mode');
    });
  });

  group('deadlines', () {
    final settings = RaidTimerSettings(runThroughSeconds: 430);
    final cooldownStart = DateTime(2026, 11, 1, 20, 5);
    final starts = {GameMode.seasonal: cooldownStart};

    RaidTimerDeadlines deadlines({
      Raid? raid,
      GameMode activeMode = GameMode.seasonal,
      Map<GameMode, DateTime> starts = const {},
      ScavCooldownInputs? inputs,
    }) => raidTimerDeadlines(
      lifecycle: _state(raid),
      settings: settings,
      activeMode: activeMode,
      cooldownStarts: starts,
      inputs: inputs,
      progress: null,
    );

    test('the run-through ends its length after the raid start', () {
      final d = deadlines(raid: _raid(start));
      expect(d.runThroughEnd, start.add(const Duration(seconds: 430)));
    });

    test('an ended raid or no raid has no run-through end', () {
      final ended = _raid(start, end: start.add(const Duration(minutes: 4)));
      expect(deadlines(raid: ended).runThroughEnd, isNull);
      expect(deadlines().runThroughEnd, isNull);
    });

    test('the scav cooldown is ready its length after the start', () {
      final d = deadlines(starts: starts, inputs: _inputs());
      expect(d.scavLength?.seconds, 1500);
      expect(d.scavReady, cooldownStart.add(const Duration(seconds: 1500)));
    });

    test('a mode without a start has a length but no ready time', () {
      final d = deadlines(
        activeMode: GameMode.pvp,
        starts: starts,
        inputs: _inputs(),
      );
      expect(d.scavLength?.seconds, 1500);
      expect(d.scavReady, isNull);
    });

    test('an unknown mode or missing inputs give no scav deadline', () {
      for (final d in [
        deadlines(
          activeMode: GameMode.unknown,
          starts: {GameMode.unknown: cooldownStart},
          inputs: _inputs(),
        ),
        deadlines(starts: starts),
      ]) {
        expect(d.scavLength, isNull);
        expect(d.scavReady, isNull);
      }
    });

    test('the strip flips exactly at the deadlines', () {
      final d = deadlines(
        raid: _raid(start),
        starts: starts,
        inputs: _inputs(),
      );
      final runThroughEnd = d.runThroughEnd!;
      final scavReady = d.scavReady!;
      RaidTimersView at(DateTime now) => _view(
        now: now,
        raid: _raid(start),
        settings: settings,
        starts: starts,
        inputs: _inputs(),
      );

      final beforeEnd = at(
        runThroughEnd.subtract(const Duration(microseconds: 1)),
      );
      expect(_text(beforeEnd, RaidTimerKind.runThrough), 'Run-through 0:01');
      expect(
        _text(at(runThroughEnd), RaidTimerKind.runThrough),
        'Run-through done',
      );

      final beforeReady = at(
        scavReady.subtract(const Duration(milliseconds: 1)),
      );
      expect(_text(beforeReady, RaidTimerKind.scav), 'Scav 0:01');
      expect(_text(at(scavReady), RaidTimerKind.scav), 'Scav ready');
    });
  });

  group('settings and scav rule', () {
    test('disabled timers show no entries and nothing moves', () {
      final v = _view(
        now: start,
        raid: _raid(start),
        settings: RaidTimerSettings(enabled: false),
      );
      expect(v.entries, isEmpty);
      expect(v.moving, isFalse);
    });

    test('each show flag hides its entry', () {
      final v = _view(
        now: start,
        raid: _raid(start),
        inputs: _inputs(),
        settings: RaidTimerSettings(
          showTimeInRaid: false,
          showRunThrough: false,
        ),
      );
      expect([for (final e in v.entries) e.kind], [RaidTimerKind.scav]);
    });

    test('a raid counts as scav by mode PvE or by side', () {
      final pvePmc = _raid(start, mode: GameMode.pve);
      final pvpScav = _raid(start, mode: GameMode.pvp, side: RaidSide.scav);
      final pvpPmc = _raid(start, mode: GameMode.pvp);
      final unknownSide = _raid(
        start,
        mode: GameMode.pvp,
        side: RaidSide.unknown,
      );
      expect(countsAsScavRaid(pvePmc), isTrue);
      expect(countsAsScavRaid(pvpScav), isTrue);
      expect(countsAsScavRaid(pvpPmc), isFalse);
      expect(countsAsScavRaid(unknownSide), isFalse);
    });
  });
}

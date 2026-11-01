import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/progress.dart';
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

ProgressSnapshot _progress(
  GameMode mode,
  DateTime observedAt,
  Iterable<String> complete,
) => ProgressSnapshot(
  mode: mode,
  credentialSession: 1,
  owner: 'owner',
  observedAt: observedAt,
  tasks: const {},
  objectives: const {},
  modules: {
    for (final id in complete) id: const EntityProgress(complete: true),
  },
  parts: const {},
);

RaidTimersView _view({
  required DateTime now,
  Raid? raid,
  RaidTimerSettings? settings,
  GameMode activeMode = GameMode.seasonal,
  Map<GameMode, DateTime> starts = const {},
  ScavCooldownInputs? inputs,
  ProgressSnapshot? progress,
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
      final now = DateTime(2026, 11, 1, 20);
      final length = scavCooldownLength(
        _inputs(),
        2.5,
        _progress(GameMode.seasonal, now, ['ic-1', 'ic-3']),
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
  });

  group('hideout progress', () {
    final now = DateTime(2026, 11, 1, 20);

    test('complete module of the same mode adds its bonus', () {
      final length = scavCooldownLength(
        _inputs(),
        0,
        _progress(GameMode.pvp, now, ['ic-1']),
        GameMode.pvp,
      );
      expect(length?.seconds, 1275);
      expect(length?.hideoutFactor, closeTo(0.85, 1e-9));
    });

    test('progress of another mode adds no bonus and says so', () {
      final progress = _progress(GameMode.pve, now, ['ic-1']);
      final length = scavCooldownLength(_inputs(), 0, progress, GameMode.pvp);
      expect(length?.seconds, 1500);
      final v = _view(
        now: now,
        activeMode: GameMode.pvp,
        inputs: _inputs(),
        progress: progress,
      );
      expect(
        _entry(v, RaidTimerKind.scav).tooltip,
        contains('No Tracker progress for this mode: no hideout bonuses'),
      );
    });

    test('stale progress still counts', () {
      final stale = _progress(
        GameMode.pvp,
        now.subtract(const Duration(minutes: 20)),
        ['ic-3'],
      );
      expect(stale.authoritativeAt(now), isFalse);
      final length = scavCooldownLength(_inputs(), 0, stale, GameMode.pvp);
      expect(length?.seconds, 1200);
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

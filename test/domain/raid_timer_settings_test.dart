import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _record({Object? raidTimers = _absent}) {
  final json = AppSettings(
    mode: GameMode.pve,
    selectedMap: 'woods',
    trackerEnabled: true,
  ).toJson();
  json.remove('raidTimers');
  if (raidTimers != _absent) json['raidTimers'] = raidTimers;
  return json;
}

const _absent = Object();

Map<String, Object?> _block({Map<String, Object?> overrides = const {}}) => {
  'enabled': true,
  'showTimeInRaid': true,
  'showRunThrough': true,
  'showScavCooldown': true,
  'runThroughSeconds': 430,
  'fenceReputation': {'pvp': 0.0, 'pve': 1.5, 'seasonal': 3.2},
  'scavCooldownStarts': {'seasonal': '2026-11-01T19:05:00.000Z'},
  ...overrides,
};

void main() {
  test('record without raidTimers decodes to defaults', () {
    final settings = AppSettings.fromJson(_record());
    expect(settings.mode, GameMode.pve);
    expect(settings.selectedMap, 'woods');
    final timers = settings.raidTimers;
    expect(timers.enabled, isTrue);
    expect(timers.showTimeInRaid, isTrue);
    expect(timers.showRunThrough, isTrue);
    expect(timers.showScavCooldown, isTrue);
    expect(timers.runThroughSeconds, 430);
    for (final mode in [GameMode.pvp, GameMode.pve, GameMode.seasonal]) {
      expect(timers.fenceReputationFor(mode), 0);
    }
    expect(timers.scavCooldownStarts, isEmpty);
    expect(timers.toJson(), RaidTimerSettings.defaults.toJson());
  });

  test('a malformed raidTimers block gives timer defaults and keeps every other setting', () {
    for (final bad in <Object?>[
      'text',
      42,
      [1, 2],
      _block(overrides: {'enabled': 'yes'}),
      _block(overrides: {'fenceReputation': 'high'}),
      _block(overrides: {'scavCooldownStarts': 7}),
    ]) {
      final settings = AppSettings.fromJson(_record(raidTimers: bad));
      expect(settings.mode, GameMode.pve, reason: '$bad');
      expect(settings.selectedMap, 'woods', reason: '$bad');
      expect(settings.trackerEnabled, isTrue, reason: '$bad');
      expect(
        settings.raidTimers.toJson(),
        RaidTimerSettings.defaults.toJson(),
        reason: '$bad',
      );
    }
  });

  test(
    'an unknown mode key or an out-of-range value drops only that entry',
    () {
      final timers = AppSettings.fromJson(
        _record(
          raidTimers: _block(
            overrides: {
              'fenceReputation': {
                'pvp': -7.5,
                'pve': 1.5,
                'seasonal': 6.01,
                'unknown': 2.0,
                'arena': 1.0,
              },
              'scavCooldownStarts': {
                'pvp': 'not a time',
                'pve': '2026-11-01T19:05:00.000Z',
                'unknown': '2026-11-01T19:05:00.000Z',
                'arena': '2026-11-01T19:05:00.000Z',
              },
            },
          ),
        ),
      ).raidTimers;
      expect(timers.fenceReputationFor(GameMode.pvp), 0);
      expect(timers.fenceReputationFor(GameMode.pve), 1.5);
      expect(timers.fenceReputationFor(GameMode.seasonal), 0);
      expect(timers.scavCooldownStarts, {
        GameMode.pve: DateTime.utc(2026, 11, 1, 19, 5),
      });
    },
  );

  test('a reputation too large to round drops only that entry', () {
    final timers = AppSettings.fromJson(
      _record(
        raidTimers: _block(
          overrides: {
            'fenceReputation': {'pve': 1e308, 'seasonal': 3.2},
          },
        ),
      ),
    ).raidTimers;
    expect(timers.fenceReputationFor(GameMode.pve), 0);
    expect(timers.fenceReputationFor(GameMode.seasonal), 3.2);
    expect(timers.scavCooldownStarts, {
      GameMode.seasonal: DateTime.utc(2026, 11, 1, 19, 5),
    });
  });

  test(
    'an out-of-range run-through length gives the default and keeps the rest',
    () {
      for (final seconds in <Object?>[59, 1801, 'x', 430.5]) {
        final timers = AppSettings.fromJson(
          _record(
            raidTimers: _block(overrides: {'runThroughSeconds': seconds}),
          ),
        ).raidTimers;
        expect(timers.runThroughSeconds, 430, reason: '$seconds');
        expect(
          timers.fenceReputationFor(GameMode.pve),
          1.5,
          reason: '$seconds',
        );
      }
      for (final seconds in [60, 1800]) {
        final timers = AppSettings.fromJson(
          _record(
            raidTimers: _block(overrides: {'runThroughSeconds': seconds}),
          ),
        ).raidTimers;
        expect(timers.runThroughSeconds, seconds);
      }
    },
  );

  test('raid timer settings round-trip through JSON', () {
    final timers = RaidTimerSettings(
      enabled: false,
      showTimeInRaid: false,
      showRunThrough: true,
      showScavCooldown: false,
      runThroughSeconds: 480,
      fenceReputation: {GameMode.pve: 1.5, GameMode.seasonal: -7},
      scavCooldownStarts: {GameMode.seasonal: DateTime.utc(2026, 11, 1, 19, 5)},
    );
    final settings = AppSettings(mode: GameMode.seasonal, raidTimers: timers);
    final restored = AppSettings.fromJson(settings.toJson());
    expect(restored.toJson(), settings.toJson());
    expect(restored.raidTimers.enabled, isFalse);
    expect(restored.raidTimers.runThroughSeconds, 480);
    expect(restored.raidTimers.fenceReputationFor(GameMode.seasonal), -7);
    expect(restored.raidTimers.scavCooldownStarts, {
      GameMode.seasonal: DateTime.utc(2026, 11, 1, 19, 5),
    });
    expect((settings.toJson()['raidTimers']! as Map)['scavCooldownStarts'], {
      'seasonal': '2026-11-01T19:05:00.000Z',
    });
  });

  test('copyWith keeps raidTimers unless replaced', () {
    final timers = RaidTimerSettings(runThroughSeconds: 600);
    final settings = AppSettings(raidTimers: timers);
    expect(settings.copyWith(mode: GameMode.pvp).raidTimers, same(timers));
    expect(
      settings.copyWith(raidTimers: RaidTimerSettings.defaults).raidTimers,
      same(RaidTimerSettings.defaults),
    );
  });
}

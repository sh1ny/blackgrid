import 'package:blackgrid/domain/alerts.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _record({Object? alerts, bool withAlerts = true}) => {
  'mode': 'pvp',
  'selectedMap': 'customs',
  'saveMarkerFilters': false,
  'markerFilters': <String, bool>{},
  'themeMode': 'dark',
  if (withAlerts) 'alerts': alerts,
};

void main() {
  test('default switches: raid four on, reminders off', () {
    final settings = AlertSettings();
    const on = {
      AlertKind.matchFound,
      AlertKind.raidStarting,
      AlertKind.runThroughOver,
      AlertKind.scavReady,
    };
    for (final kind in AlertKind.values) {
      expect(settings.itemFor(kind).on, on.contains(kind), reason: kind.id);
      expect(settings.itemFor(kind).sound, const SpeechSound());
    }
    expect(settings.voice, isNull);
    expect(settings.speed, 0);
    expect(settings.volume, 100);
  });

  test('stored speed 9 loads as 5', () {
    expect(AlertSettings.fromJson({'speed': 9}).speed, 5);
    expect(AlertSettings.fromJson({'speed': -9}).speed, -5);
    expect(AlertSettings.fromJson({'volume': 250}).volume, 100);
    expect(AlertSettings.fromJson({'volume': -3}).volume, 0);
  });

  test('unknown alert id in stored settings is ignored', () {
    final settings = AlertSettings.fromJson({
      'items': {
        'madeUp': {
          'on': true,
          'sound': {'kind': 'speech'},
        },
        'questItems': {
          'on': true,
          'sound': {'kind': 'speech'},
        },
      },
    });
    expect(settings.itemFor(AlertKind.questItems).on, isTrue);
    expect(settings.items.length, AlertKind.values.length);
    final loaded = AppSettings.fromJson(
      _record(
        alerts: {
          'items': {'madeUp': 1},
        },
      ),
    );
    expect(loaded.alerts, AlertSettings());
  });

  test('a bad item gives that item its default', () {
    final settings = AlertSettings.fromJson({
      'items': {
        'matchFound': 'junk',
        'scavReady': {
          'on': false,
          'sound': {'kind': 'file', 'path': 'a.mp3'},
        },
      },
    });
    expect(settings.itemFor(AlertKind.matchFound).on, isTrue);
    expect(settings.itemFor(AlertKind.scavReady).on, isFalse);
    expect(
      settings.itemFor(AlertKind.scavReady).sound,
      const FileSound('a.mp3'),
    );
  });

  test('settings round-trip through JSON', () {
    final settings = AlertSettings(voice: 'zira', speed: -2, volume: 40)
        .withItem(
          AlertKind.failedTasks,
          const AlertItem(on: true, sound: FileSound(r'C:\a.wav')),
        );
    expect(AlertSettings.fromJson(settings.toJson()), settings);
    expect(
      AlertSettings.fromJson(settings.toJson()).hashCode,
      settings.hashCode,
    );
  });

  test('a malformed alerts block gives defaults and other settings stay', () {
    for (final bad in <Object?>[
      'junk',
      5,
      [1],
      null,
    ]) {
      final loaded = AppSettings.fromJson(_record(alerts: bad));
      expect(loaded.alerts, AlertSettings(), reason: '$bad');
      expect(loaded.selectedMap, 'customs');
      expect(loaded.themeMode, ThemeChoice.dark);
    }
  });

  test('a record without alerts loads the defaults and writes them back', () {
    final loaded = AppSettings.fromJson(_record(withAlerts: false));
    expect(loaded.alerts, AlertSettings());
    expect(loaded.toJson()['alerts'], AlertSettings().toJson());
  });
}

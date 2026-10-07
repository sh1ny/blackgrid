import 'package:blackgrid/application/settings_controller.dart';
import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pre-M5 serialized preferences read defaults and new inputs roundtrip exactly', () {
    final legacy =
        AppSettings(mode: GameMode.pve, selectedMap: 'woods').toJson()
          ..remove('gameLogDirectory')
          ..remove('screenshotDirectory')
          ..remove('followGameLogs');
    final restored = AppSettings.fromJson(legacy);
    expect(restored.gameLogDirectory, '');
    expect(restored.screenshotDirectory, '');
    expect(restored.followGameLogs, isTrue);
    final configured = restored.copyWith(
      gameLogDirectory: 'configured/logs',
      screenshotDirectory: 'configured/screenshots',
      followGameLogs: false,
    );
    expect(
      AppSettings.fromJson(configured.toJson()).toJson(),
      configured.toJson(),
    );
  });
  test('manual map/follow-off save is atomic persistence first, failed save preserves both', () async {
    final db = BlackgridDatabase(NativeDatabase.memory());
    final settings = SettingsController(db);
    addTearDown(() async {
      settings.dispose();
      await db.close();
    });
    await settings.load();
    await settings.setMapInputs(
      gameLogDirectory: 'logs',
      screenshotDirectory: 'screenshots',
    );
    expect(await settings.setMap('woods'), isTrue);
    final saved = await db.readSettings();
    expect(saved.selectedMap, 'woods');
    expect(saved.followGameLogs, isFalse);
    expect(saved.gameLogDirectory, 'logs');
    await settings.setMapInputs(followGameLogs: true);
    await db.customStatement(
      "CREATE TRIGGER preference_failure BEFORE INSERT ON preferences BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
    );
    expect(await settings.setMap('thelab'), isFalse);
    expect(settings.settings.selectedMap, 'woods');
    expect(settings.settings.followGameLogs, isTrue);
    expect((await db.readSettings()).selectedMap, 'woods');
    expect((await db.readSettings()).followGameLogs, isTrue);
  });
  test('pin operations share busy protection and expose failures without replacing durable records', () async {
    final db = BlackgridDatabase(NativeDatabase.memory());
    final settings = SettingsController(db);
    addTearDown(() async {
      settings.dispose();
      await db.close();
    });
    await settings.load();
    final pin = CustomPin(
      id: 'pin',
      mapId: 'woods',
      x: 0,
      y: 0,
      frame: 'legacy-normalized',
      frameRevision: 0,
      label: 'Offline pin',
      updatedAt: DateTime(2026),
    );
    final saving = settings.savePin(pin);
    expect(settings.busy, isTrue);
    expect(await settings.setMap('thelab'), isFalse);
    expect(await settings.removePin(pin), isFalse);
    expect(await saving, isTrue);
    expect(settings.busy, isFalse);
    expect(settings.pins.single.id, 'pin');
    await db.customStatement(
      "CREATE TRIGGER pin_failure BEFORE DELETE ON pin_records BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
    );
    expect(await settings.removePin(pin), isFalse);
    expect(settings.error, isNotNull);
    expect(settings.pins.single.id, 'pin');
    expect((await db.readPins()).single.id, 'pin');
  });
}

import 'package:blackgrid/application/settings_controller.dart';
import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/domain/alerts.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// An in-memory database whose settings saves can be made to fail.
class _AlertsDatabase extends BlackgridDatabase {
  _AlertsDatabase() : super(NativeDatabase.memory());

  bool failSaves = false;

  @override
  Future<void> saveSettings(AppSettings settings) async {
    if (failSaves) throw StateError('synthetic save failure');
    await super.saveSettings(settings);
  }
}

void main() {
  late _AlertsDatabase db;
  late SettingsController controller;
  setUp(() {
    db = _AlertsDatabase();
    controller = SettingsController(db);
  });
  tearDown(() async {
    controller.dispose();
    await db.close();
  });

  test('alert settings survive a restart', () async {
    await controller.load();
    expect(await controller.setAlertOn(AlertKind.questItems, true), isTrue);
    expect(
      await controller.setAlertSound(
        AlertKind.scavReady,
        const FileSound(r'C:\sounds\Ready.MP3'),
      ),
      isNull,
    );
    expect(await controller.setAlertVolume(70), isTrue);
    expect(await controller.setAlertVoice('zira'), isTrue);
    expect(await controller.setAlertSpeed(3), isTrue);

    final restarted = SettingsController(db);
    addTearDown(restarted.dispose);
    await restarted.load();
    final alerts = restarted.settings.alerts;
    expect(alerts.itemFor(AlertKind.questItems).on, isTrue);
    expect(
      alerts.itemFor(AlertKind.scavReady).sound,
      const FileSound(r'C:\sounds\Ready.MP3'),
    );
    expect(alerts.volume, 70);
    expect(alerts.voice, 'zira');
    expect(alerts.speed, 3);
    expect(restarted.loadNotice, isNull);
  });

  test('a record without alerts loads the defaults', () async {
    await controller.load();
    final alerts = controller.settings.alerts;
    expect(alerts, AlertSettings());
    expect(alerts.itemFor(AlertKind.matchFound).on, isTrue);
    expect(alerts.itemFor(AlertKind.failedTasks).on, isFalse);
  });

  test('a failed volume save keeps the previous value', () async {
    await controller.load();
    await controller.setAlertVolume(60);
    db.failSaves = true;

    expect(await controller.setAlertVolume(20), isFalse);
    expect(controller.settings.alerts.volume, 60);
    expect(controller.error, isNotNull);
    expect(controller.busy, isFalse);
    expect((await db.readSettings()).settings.alerts.volume, 60);
  });

  test('speed and volume are clamped to their ranges', () async {
    await controller.load();
    await controller.setAlertSpeed(9);
    await controller.setAlertVolume(-4);
    expect(controller.settings.alerts.speed, 5);
    expect(controller.settings.alerts.volume, 0);
    await controller.setAlertVolume(400);
    expect(controller.settings.alerts.volume, 100);
  });

  test('a sound file that is not WAV or MP3 is refused', () async {
    await controller.load();
    await controller.setAlertSound(
      AlertKind.raidStarting,
      const FileSound(r'C:\a.wav'),
    );
    final message = await controller.setAlertSound(
      AlertKind.raidStarting,
      const FileSound(r'C:\a.ogg'),
    );
    expect(message, isNotNull);
    expect(
      controller.settings.alerts.itemFor(AlertKind.raidStarting).sound,
      const FileSound(r'C:\a.wav'),
    );
  });

  test('speech is always accepted as a sound', () async {
    await controller.load();
    expect(
      await controller.setAlertSound(
        AlertKind.raidStarting,
        const SpeechSound(),
      ),
      isNull,
    );
  });

  test('a failed sound save reports a message and keeps the old one', () async {
    await controller.load();
    db.failSaves = true;
    final message = await controller.setAlertSound(
      AlertKind.raidStarting,
      const FileSound(r'C:\a.wav'),
    );
    expect(message, isNotNull);
    expect(
      controller.settings.alerts.itemFor(AlertKind.raidStarting).sound,
      const SpeechSound(),
    );
  });
}

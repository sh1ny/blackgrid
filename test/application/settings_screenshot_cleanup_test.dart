import 'dart:convert';

import 'package:blackgrid/application/settings_controller.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/support/reopenable_database.dart';

void main() {
  late ReopenableDatabase store;
  late SettingsController controller;

  setUp(() async {
    store = await ReopenableDatabase.open();
    controller = SettingsController(store.db);
  });

  tearDown(() async {
    controller.dispose();
    await store.delete();
  });

  test('screenshot-cleanup: Off by default', () async {
    expect(AppSettings().cleanUpRaidScreenshots, isFalse);
    final base = AppSettings(mode: GameMode.pve).toJson()
      ..remove('cleanUpRaidScreenshots');
    for (final payload in [
      base,
      {...base, 'cleanUpRaidScreenshots': 'true'},
      {...base, 'cleanUpRaidScreenshots': 1},
      {...base, 'cleanUpRaidScreenshots': null},
    ]) {
      await store.writeRawRow(
        'INSERT OR REPLACE INTO preferences (id, payload) VALUES (1, ?)',
        [jsonEncode(payload)],
      );
      await controller.load();
      expect(
        controller.settings.cleanUpRaidScreenshots,
        isFalse,
        reason: '$payload',
      );
      expect(controller.settings.mode, GameMode.pve, reason: '$payload');
      expect(controller.loadNotice, isNull, reason: '$payload');
    }
  });

  test('screenshot-cleanup: The setting survives a restart', () async {
    await controller.load();
    expect(await controller.setCleanUpRaidScreenshots(true), isTrue);
    expect(controller.settings.cleanUpRaidScreenshots, isTrue);
    expect(controller.settings.toJson()['cleanUpRaidScreenshots'], isTrue);
    expect(
      controller.settings
          .copyWith(selectedMap: 'customs')
          .cleanUpRaidScreenshots,
      isTrue,
    );

    final db = await store.reopen();
    final reopened = SettingsController(db);
    addTearDown(reopened.dispose);
    await reopened.load();
    expect(reopened.settings.cleanUpRaidScreenshots, isTrue);
    expect(await reopened.setCleanUpRaidScreenshots(false), isTrue);
    expect(reopened.settings.cleanUpRaidScreenshots, isFalse);
    expect((await db.readSettings()).settings.cleanUpRaidScreenshots, isFalse);
  });

  test('failed cleanup setting save retains the setting in use', () async {
    await controller.load();
    await store.abortNextInsert('preferences');
    expect(await controller.setCleanUpRaidScreenshots(true), isFalse);
    expect(controller.settings.cleanUpRaidScreenshots, isFalse);
    expect(controller.error, isNotNull);
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:blackgrid/application/settings_controller.dart';
import 'package:blackgrid/data/legacy_import.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/support/reopenable_database.dart';
import '../fixtures/m1/legacy/legacy_fixture.dart';

const _settingsNotice =
    'Your saved settings could not be read. '
    'Default settings are in use until you change one.';

const _writeSettings = 'INSERT INTO preferences (id, payload) VALUES (1, ?)';
const _writePin =
    'INSERT INTO pin_records (map_id, pin_id, payload) VALUES (?, ?, ?)';

Map<String, Object?> _pinJson(
  String id, {
  String frame = 'legacy-normalized',
}) => CustomPin(
  id: id,
  mapId: 'customs',
  x: .5,
  y: .5,
  frame: frame,
  frameRevision: 0,
  label: id,
  updatedAt: DateTime.utc(2026, 10, 6),
).toJson();

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

  Future<String> storedSettingsPayload() async {
    final rows = await store.db
        .customSelect('SELECT payload FROM preferences WHERE id = 1')
        .get();
    return rows.single.read<String>('payload');
  }

  Future<int> storedPinCount() async =>
      (await store.db.customSelect('SELECT 1 FROM pin_records').get()).length;

  test('a settings row that is not JSON loads defaults, sets the notice and keeps the row bytes', () async {
    await store.writeRawRow(_writeSettings, ['{not json']);
    await controller.load();
    expect(controller.settings.mode, GameMode.unknown);
    expect(controller.settings.selectedMap, AppSettings().selectedMap);
    expect(controller.loadNotice, _settingsNotice);
    expect(controller.error, isNull);
    expect(await storedSettingsPayload(), '{not json');
  });

  test('a settings row naming an unknown mode or map loads defaults and sets the notice', () async {
    final good = AppSettings(mode: GameMode.pve).toJson();
    for (final changed in [
      {...good, 'mode': 'arena'},
      {...good, 'selectedMap': 'atlantis'},
    ]) {
      final payload = jsonEncode(changed);
      await store.writeRawRow(
        'INSERT OR REPLACE INTO preferences (id, payload) VALUES (1, ?)',
        [payload],
      );
      await controller.load();
      expect(controller.settings.mode, GameMode.unknown, reason: payload);
      expect(controller.loadNotice, _settingsNotice, reason: payload);
      expect(await storedSettingsPayload(), payload);
    }
  });

  test('a readable settings row loads as saved with no notice', () async {
    await store.db.saveSettings(AppSettings(mode: GameMode.pve));
    await controller.load();
    expect(controller.settings.mode, GameMode.pve);
    expect(controller.loadNotice, isNull);
  });

  test('the first save after a default start clears the notice and reads back after reopening', () async {
    await store.writeRawRow(_writeSettings, ['{not json']);
    await controller.load();
    expect(controller.loadNotice, _settingsNotice);
    expect(await controller.setMode(GameMode.pvp), isTrue);
    expect(controller.loadNotice, isNull);
    final db = await store.reopen();
    final reopened = SettingsController(db);
    addTearDown(reopened.dispose);
    await reopened.load();
    expect(reopened.settings.mode, GameMode.pvp);
    expect(reopened.loadNotice, isNull);
  });

  test('a Replace import after a default start clears the settings notice on reload', () async {
    final dir = await Directory.systemTemp.createTemp('blackgrid-load-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/legacy.json');
    await file.writeAsBytes(
      legacyBytes(settings: syntheticSettings())['settings']!,
    );
    await store.writeRawRow(_writeSettings, ['{not json']);
    await controller.load();
    expect(controller.loadNotice, _settingsNotice);

    final importer = LegacyImport(store.db);
    final preview = await importer.previewFiles(settingsPath: file.path);
    await importer.commit(preview, replaceExisting: true);
    await controller.load();

    expect(controller.settings.mode, GameMode.pve);
    expect(controller.settings.selectedMap, 'customs');
    expect(controller.loadNotice, isNull);
  });

  test(
    'one unreadable pin row is skipped, counted in the notice and kept on disk',
    () async {
      await store.db.savePin(CustomPin.fromJson(_pinJson('one')));
      await store.db.savePin(CustomPin.fromJson(_pinJson('two')));
      await store.writeRawRow(_writePin, ['customs', 'broken', 'not json']);
      await controller.load();
      expect(controller.pins.map((p) => p.id), unorderedEquals(['one', 'two']));
      expect(
        controller.loadNotice,
        '1 saved pin could not be read and is not shown.',
      );
      expect(await storedPinCount(), 3);

      // A pin the app would refuse to save counts as unreadable too.
      await store.writeRawRow(_writePin, [
        'customs',
        'framed',
        jsonEncode(_pinJson('framed', frame: 'unqualified')),
      ]);
      await controller.load();
      expect(controller.pins.map((p) => p.id), unorderedEquals(['one', 'two']));
      expect(
        controller.loadNotice,
        '2 saved pins could not be read and are not shown.',
      );
      expect(await storedPinCount(), 4);

      // A later pin save recomputes the pin sentence and keeps the rows.
      expect(
        await controller.savePin(CustomPin.fromJson(_pinJson('three'))),
        isTrue,
      );
      expect(
        controller.loadNotice,
        '2 saved pins could not be read and are not shown.',
      );
      expect(await storedPinCount(), 5);
    },
  );

  test('readable pins load with no pin notice', () async {
    await store.db.savePin(CustomPin.fromJson(_pinJson('one')));
    await controller.load();
    expect(controller.pins.map((p) => p.id), ['one']);
    expect(controller.loadNotice, isNull);
  });
}

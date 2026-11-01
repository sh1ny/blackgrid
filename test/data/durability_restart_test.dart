import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/data/legacy_import.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/import_preview.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:test/test.dart';

import '../fixtures/m1/catalog/fixture.dart';
import '../fixtures/m1/legacy/legacy_fixture.dart';
import 'support/reopenable_database.dart';

CustomPin _pin(String id) => CustomPin(
  id: id,
  mapId: 'customs',
  x: .5,
  y: .5,
  frame: 'legacy-normalized',
  frameRevision: 0,
  label: id,
  updatedAt: fixtureNow,
);

ImportPreview _twoPinsTwoEntries() {
  final settings = syntheticSettings()
    ..['CustomPinsByMap'] = {
      'customs': [
        {'id': 'first', 'normalizedX': .1, 'normalizedY': .2},
        {'id': 'second', 'normalizedX': .3, 'normalizedY': .4},
      ],
    };
  return parseLegacySources(
    legacyBytes(
      settings: settings,
      history: syntheticHistory(
        rows: [
          activity(id: 'item-a'),
          activity(id: 'item-b'),
        ],
      ),
    ),
  );
}

void main() {
  late ReopenableDatabase store;
  setUp(() async => store = await ReopenableDatabase.open());
  tearDown(() => store.delete());

  test('a removed pin stays removed after reopening', () async {
    final kept = _pin('kept');
    final removed = _pin('removed');
    await store.db.savePin(kept);
    await store.db.savePin(removed);
    await store.db.removePin(removed);
    final db = await store.reopen();
    expect((await db.readPins()).pins.map((p) => p.id), ['kept']);
  });

  test('a settings save aborted by the database reads back the earlier settings after reopening', () async {
    await store.db.saveSettings(AppSettings(mode: GameMode.pve));
    await store.abortNextInsert('preferences');
    await expectLater(
      store.db.saveSettings(AppSettings(mode: GameMode.pvp)),
      throwsA(anything),
    );
    final db = await store.reopen();
    expect((await db.readSettings()).settings.mode, GameMode.pve);
  });

  test('an import aborted at its import record leaves every table unchanged after reopening and can run again', () async {
    await store.db.saveSettings(AppSettings(mode: GameMode.pvp));
    await store.db.savePin(_pin('existing'));
    await store.db.recordActivity('existing-item', GameMode.pvp, fixtureNow);
    final before = await _snapshot(store.db);
    final preview = _twoPinsTwoEntries();
    await store.abortNextInsert('import_records');
    await expectLater(
      store.db.commitImport(preview, replaceExisting: true),
      throwsA(anything),
    );
    final db = await store.reopen();
    expect(await _snapshot(db), before);
    expect(await db.select(db.importRecords).get(), isEmpty);
    await db.commitImport(preview, replaceExisting: true);
    expect(await db.wasImported(preview.digest), isTrue);
  });

  test(
    'a committed import reads back pins history and its record after reopening',
    () async {
      final preview = _twoPinsTwoEntries();
      await store.db.commitImport(preview, replaceExisting: false);
      final db = await store.reopen();
      expect((await db.readSettings()).settings.mode, GameMode.pve);
      expect((await db.readPins()).pins.map((p) => p.id).toSet(), {
        'first',
        'second',
      });
      expect((await db.readActivity()).rows.map((r) => r.itemId).toSet(), {
        'item-a',
        'item-b',
      });
      expect(await db.wasImported(preview.digest), isTrue);
    },
  );
}

Future<List<List<Object>>> _snapshot(BlackgridDatabase db) async => [
  await db.select(db.preferences).get(),
  await db.select(db.pinRecords).get(),
  await db.select(db.activityRecords).get(),
];

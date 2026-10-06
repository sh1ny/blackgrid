import 'dart:io';

import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../fixtures/m1/catalog/fixture.dart';

void main() {
  test('fresh defaults and restart retain settings pins identity activity and full catalog', () async {
    final directory = await Directory.systemTemp.createTemp('blackgrid-store-');
    final file = File('${directory.path}/store.sqlite');
    var db = BlackgridDatabase(NativeDatabase(file));
    final defaults = await db.readSettings();
    expect(defaults.mode, GameMode.unknown);
    expect(await db.readActivity(), isEmpty);
    await db.saveSettings(
      AppSettings(
        mode: GameMode.pve,
        selectedMap: 'customs',
        trackerEnabled: true,
      ),
    );
    final pin = CustomPin(
      id: 'synthetic-pin',
      mapId: 'customs',
      x: 1.2,
      y: -.1,
      frame: 'legacy-normalized',
      frameRevision: 0,
      label: 'Synthetic pin',
      updatedAt: fixtureNow,
    );
    await db.savePin(pin);
    await db.recordActivity('item-a', GameMode.pvp, fixtureNow);
    await db.recordActivity(
      'item-a',
      GameMode.pvp,
      fixtureNow.add(const Duration(seconds: 1)),
    );
    await db.commitCatalog(fixtureCatalog());
    await db.close();
    db = BlackgridDatabase(NativeDatabase(file));
    expect((await db.readSettings()).mode, GameMode.pve);
    expect((await db.readPins()).single.x, 1.2);
    expect((await db.readActivity()).single.revision, 2);
    expect((await db.loadCatalog(GameMode.pvp))!.items, contains('item-a'));
    expect(await db.loadCatalog(GameMode.pve), isNull);
    final columns = await db
        .customSelect('PRAGMA table_info(activity_records)')
        .get();
    expect(
      columns.map((r) => r.read<String>('name')),
      unorderedEquals(['item_id', 'mode', 'source', 'observed_at', 'revision']),
    );
    await db.close();
    await directory.delete(recursive: true);
  });
  test(
    'unchanged catalog revision renews observation metadata across restart',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'blackgrid-renewed-catalog-',
      );
      final file = File('${directory.path}/store.sqlite');
      var db = BlackgridDatabase(NativeDatabase(file));
      addTearDown(() async {
        await db.close();
        await directory.delete(recursive: true);
      });
      final first = decisionCatalog();
      final later = fixtureNow.add(const Duration(hours: 1));
      final renewed = decisionCatalog(observedAt: later);
      expect(renewed.revision, first.revision);
      await db.commitCatalog(first);
      final originalId = (await db.select(db.catalogRecords).get()).single.id;
      await db.commitCatalog(renewed);
      final rows = await db.select(db.catalogRecords).get();
      expect(rows, hasLength(1));
      expect(rows.single.id, originalId);
      expect((await db.loadCatalog(GameMode.pvp))!.observedAt, later);
      await db.close();
      db = BlackgridDatabase(NativeDatabase(file));
      final restored = (await db.loadCatalog(GameMode.pvp))!;
      expect(restored.revision, first.revision);
      expect(restored.observedAt, later);
      expect(restored.toJson(), renewed.toJson());
    },
  );
  for (final table in ['catalog_records', 'active_catalogs']) {
    test(
      'failed reused catalog $table update rolls back renewed metadata across restart',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'blackgrid-renewal-rollback-',
        );
        final file = File('${directory.path}/store.sqlite');
        var db = BlackgridDatabase(NativeDatabase(file));
        addTearDown(() async {
          await db.close();
          await directory.delete(recursive: true);
        });
        final first = decisionCatalog();
        await db.commitCatalog(first);
        final originalRows = await db.select(db.catalogRecords).get();
        final originalPointer = await db.select(db.activeCatalogs).get();
        await db.customStatement(
          "CREATE TRIGGER fail_renewal BEFORE UPDATE ON $table BEGIN SELECT RAISE(ABORT, 'synthetic renewal failure'); END",
        );
        await expectLater(
          db.commitCatalog(
            decisionCatalog(
              observedAt: fixtureNow.add(const Duration(hours: 1)),
            ),
          ),
          throwsA(anything),
        );
        expect(await db.select(db.catalogRecords).get(), originalRows);
        expect(await db.select(db.activeCatalogs).get(), originalPointer);
        expect((await db.loadCatalog(GameMode.pvp))!.toJson(), first.toJson());
        await db.close();
        db = BlackgridDatabase(NativeDatabase(file));
        expect((await db.loadCatalog(GameMode.pvp))!.toJson(), first.toJson());
      },
    );
  }
  test('failed catalog pointer transaction retains old rows and restarted active revision', () async {
    final directory = await Directory.systemTemp.createTemp(
      'blackgrid-rollback-',
    );
    final file = File('${directory.path}/store.sqlite');
    var db = BlackgridDatabase(NativeDatabase(file));
    final old = decisionCatalog();
    await db.commitCatalog(old);
    await db.customStatement(
      "CREATE TRIGGER fail_catalog BEFORE UPDATE ON active_catalogs BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
    );
    final next = CatalogSnapshot(
      mode: old.mode,
      revision: 'synthetic-next',
      observedAt: fixtureNow,
      items: old.items,
      traders: old.traders,
      requirements: old.requirements,
      sourceTimestamps: old.sourceTimestamps,
    );
    await expectLater(db.commitCatalog(next), throwsA(anything));
    expect((await db.loadCatalog(GameMode.pvp))!.revision, old.revision);
    expect((await db.select(db.catalogRecords).get()).length, 1);
    await db.close();
    db = BlackgridDatabase(NativeDatabase(file));
    expect((await db.loadCatalog(GameMode.pvp))!.revision, old.revision);
    await db.close();
    await directory.delete(recursive: true);
  });
  test(
    'failed preference and identity writes do not publish durable changes',
    () async {
      final db = BlackgridDatabase(NativeDatabase.memory());
      await db.readSettings();
      await db.customStatement(
        "CREATE TRIGGER fail_settings BEFORE INSERT ON preferences BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
      );
      await expectLater(
        db.saveSettings(AppSettings(mode: GameMode.pvp)),
        throwsA(anything),
      );
      expect((await db.readSettings()).mode, GameMode.unknown);
      await db.customStatement(
        "CREATE TRIGGER fail_activity BEFORE INSERT ON activity_records BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
      );
      await expectLater(
        db.recordActivity('item-a', GameMode.pvp, fixtureNow),
        throwsA(anything),
      );
      expect(await db.readActivity(), isEmpty);
      await db.close();
    },
  );
}

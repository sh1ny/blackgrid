import 'dart:convert';
import 'dart:io';

import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:drift/drift.dart' show Value;
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
    'committing the same revision again replaces an icon-less projection',
    () async {
      final withIcons = fixtureCatalog();
      final stored = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(withIcons.toJson())) as Map,
      );
      for (final item in (stored['items'] as Map).values) {
        (item as Map).remove('iconLink');
      }
      final iconless = CatalogSnapshot.fromJson(stored);
      expect(iconless.revision, withIcons.revision);
      final db = BlackgridDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.commitCatalog(iconless);
      expect(
        (await db.loadCatalog(GameMode.pvp))!.items['item-a']!.iconLink,
        isNull,
      );
      await db.commitCatalog(withIcons);
      final loaded = (await db.loadCatalog(GameMode.pvp))!;
      expect(loaded.revision, withIcons.revision);
      expect(
        loaded.items['item-a']!.iconLink,
        'https://assets.tarkov.dev/item-a-icon.webp',
      );
    },
  );
  test('scan activity is one row per item and mode with source scan', () async {
    final db = BlackgridDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final second = fixtureNow.add(const Duration(seconds: 5));
    await db.recordActivity(
      'item-a',
      GameMode.pvp,
      fixtureNow,
      source: ActivitySource.scan,
    );
    await db.recordActivity(
      'item-a',
      GameMode.pvp,
      second,
      source: ActivitySource.scan,
    );
    final rows = await db.readActivity();
    expect(rows, hasLength(1));
    expect(rows.single.source, ActivitySource.scan);
    expect(rows.single.revision, 2);
    expect(rows.single.observedAt, second.toUtc());
  });
  test('a manual record after a scan row revises the same row', () async {
    final db = BlackgridDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final later = fixtureNow.add(const Duration(seconds: 5));
    await db.recordActivity(
      'item-a',
      GameMode.pvp,
      fixtureNow,
      source: ActivitySource.scan,
    );
    expect((await db.readActivity()).single.revision, 1);

    await db.recordActivity('item-a', GameMode.pvp, later);

    final rows = await db.readActivity();
    expect(rows, hasLength(1));
    expect(rows.single.source, ActivitySource.manual);
    expect(rows.single.revision, 2);
    expect(rows.single.observedAt, later.toUtc());
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
  test('item icon rows round-trip upsert touch and delete', () async {
    final db = BlackgridDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final shown = DateTime.utc(2026, 10, 1, 12);
    final validated = DateTime.utc(2026, 10, 2, 8);
    expect(await db.readItemIcons(), isEmpty);
    await db.upsertItemIcon(
      ItemIconRecordsCompanion.insert(
        itemId: 'item-a',
        iconLink: 'https://example.invalid/a.webp',
        lastShownAt: shown,
        fileName: const Value('a.webp'),
        byteSize: const Value(42),
        etag: const Value('"e1"'),
        validatedAt: Value(validated),
      ),
    );
    await db.upsertItemIcon(
      ItemIconRecordsCompanion.insert(
        itemId: 'item-b',
        iconLink: 'https://example.invalid/b.webp',
        lastShownAt: shown,
        failedUntil: Value(validated),
        failedLink: const Value('https://example.invalid/b.webp'),
      ),
    );
    var rows = {for (final r in await db.readItemIcons()) r.itemId: r};
    expect(rows.keys, unorderedEquals(['item-a', 'item-b']));
    final a = rows['item-a']!;
    expect(a.iconLink, 'https://example.invalid/a.webp');
    expect(a.fileName, 'a.webp');
    expect(a.byteSize, 42);
    expect(a.etag, '"e1"');
    expect(a.validatedAt?.toUtc(), validated);
    expect(a.lastShownAt.toUtc(), shown);
    expect(a.failedUntil, isNull);
    expect(a.failedLink, isNull);
    final b = rows['item-b']!;
    expect(b.fileName, isNull);
    expect(b.byteSize, 0);
    expect(b.failedUntil?.toUtc(), validated);
    expect(b.failedLink, 'https://example.invalid/b.webp');

    await db.upsertItemIcon(
      ItemIconRecordsCompanion.insert(
        itemId: 'item-a',
        iconLink: 'https://example.invalid/a2.webp',
        lastShownAt: shown,
      ),
    );
    final replaced = (await db.readItemIcons()).singleWhere(
      (r) => r.itemId == 'item-a',
    );
    expect(replaced.iconLink, 'https://example.invalid/a2.webp');
    expect(replaced.fileName, isNull);

    final later = shown.add(const Duration(days: 1));
    await db.touchItemIcon('item-b', later);
    await db.touchItemIcon('missing', later);
    rows = {for (final r in await db.readItemIcons()) r.itemId: r};
    expect(rows['item-b']!.lastShownAt.toUtc(), later);
    expect(rows['item-a']!.lastShownAt.toUtc(), shown);
    expect(rows, hasLength(2));

    await db.deleteItemIcons(['item-a', 'missing']);
    expect((await db.readItemIcons()).single.itemId, 'item-b');
    await db.deleteItemIcons(const []);
    expect(await db.readItemIcons(), hasLength(1));
  });
}

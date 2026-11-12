import 'dart:convert';

import 'package:blackgrid/application/catalog_controller.dart';
import 'package:blackgrid/data/catalog_client.dart';
import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../fixtures/m1/catalog/fixture.dart';
import 'support/reopenable_database.dart';

CatalogSnapshot _modeCatalog(GameMode mode, String taskId, bool kappa) {
  final wire = progressCatalogWireFixture();
  final tasks = wire['tasks']['data']['tasks'] as Map<String, dynamic>;
  final task = tasks.remove('task-a') as Map<String, dynamic>;
  task['id'] = taskId;
  task['kappaRequired'] = kappa;
  tasks[taskId] = task;
  return fixtureCatalog(mode: mode, wire: wire);
}

Future<void> _writePayload(
  BlackgridDatabase db,
  int id,
  Map<String, dynamic> payload,
) async {
  await (db.update(db.catalogRecords)..where((row) => row.id.equals(id))).write(
    CatalogRecordsCompanion(payload: Value(jsonEncode(payload))),
  );
}

void main() {
  test('stored task catalog survives reopen unchanged', () async {
    final store = await ReopenableDatabase.open();
    addTearDown(store.delete);
    final snapshot = fixtureCatalog(wire: progressCatalogWireFixture());
    final block = snapshot.toJson()['progressCatalog'];
    expect(snapshot.progressCatalog, isNotNull);
    expect(block, isNotNull);

    await store.db.commitCatalog(snapshot);
    final loaded = (await store.db.loadCatalog(GameMode.pvp))!;
    expect(loaded.toJson(), equals(snapshot.toJson()));
    expect(loaded.toJson()['progressCatalog'], equals(block));
    expect(loaded.progressCatalog, isNotNull);
    expect(
      loaded.progressCatalog!.toJson(),
      equals(snapshot.progressCatalog!.toJson()),
    );

    await store.reopen();
    final reopened = (await store.db.loadCatalog(GameMode.pvp))!;
    expect(reopened.toJson(), equals(snapshot.toJson()));
    expect(reopened.toJson()['progressCatalog'], equals(block));
    expect(reopened.progressCatalog, isNotNull);
    expect(
      reopened.progressCatalog!.toJson(),
      equals(snapshot.progressCatalog!.toJson()),
    );
  });

  test(
    'snapshot stored without a block loads with items and no task catalog',
    () async {
      final db = BlackgridDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final snapshot = fixtureCatalog(wire: progressCatalogWireFixture());
      expect(snapshot.toJson()['progressCatalog'], isNotNull);
      expect(snapshot.progressCatalog, isNotNull);
      await db.commitCatalog(snapshot);
      final row = (await db.select(db.catalogRecords).get()).single;
      final legacy = jsonDecode(row.payload) as Map<String, dynamic>;
      legacy.remove('progressCatalog');
      await _writePayload(db, row.id, legacy);

      final loaded = (await db.loadCatalog(GameMode.pvp))!;
      expect(loaded.progressCatalog, isNull);
      expect(loaded.toJson(), equals(legacy));
      expect(
        loaded.items['item-a']!.fleaPrice,
        snapshot.items['item-a']!.fleaPrice,
      );
      expect(
        loaded.authoritativeAt(fixtureNow),
        snapshot.authoritativeAt(fixtureNow),
      );
      final client = CatalogClient(
        client: MockClient((_) async => http.Response('', 500)),
      );
      final controller = CatalogController(
        store: db,
        client: client,
        clock: () => fixtureNow,
      );
      addTearDown(controller.dispose);
      await controller.setMode(GameMode.pvp);
      expect(controller.status, CatalogStatus.stale);
      expect(controller.snapshot!.toJson(), equals(legacy));

      // A refresh with identical wire bytes has the same revision and must
      // update the existing row, rather than leaving the old payload in place.
      await db.commitCatalog(snapshot);
      final updatedRows = await db.select(db.catalogRecords).get();
      expect(updatedRows, hasLength(1));
      expect(updatedRows.single.id, row.id);
      expect(updatedRows.single.revision, row.revision);
      expect(
        (await db.loadCatalog(GameMode.pvp))!.toJson(),
        equals(snapshot.toJson()),
      );
    },
  );

  test('damaged or other-version block loads as unavailable', () async {
    final db = BlackgridDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final snapshot = fixtureCatalog(wire: progressCatalogWireFixture());
    expect(snapshot.toJson()['progressCatalog'], isNotNull);
    await db.commitCatalog(snapshot);
    expect(snapshot.progressCatalog, isNotNull);
    final row = (await db.select(db.catalogRecords).get()).single;

    for (final damage in ['version', 'nested type']) {
      final payload = jsonDecode(row.payload) as Map<String, dynamic>;
      final block = payload['progressCatalog'] as Map<String, dynamic>;
      if (damage == 'version') {
        block['formatVersion'] = 2;
      } else {
        final tasks = block['tasks'] as List<dynamic>;
        final task = tasks.first as Map<String, dynamic>;
        task['objectives'] = 'not a list';
      }
      await _writePayload(db, row.id, payload);
      final loaded = (await db.loadCatalog(GameMode.pvp))!;
      expect(loaded.progressCatalog, isNull, reason: damage);
      final intact = Map<String, dynamic>.from(payload)
        ..remove('progressCatalog');
      expect(loaded.toJson(), equals(intact), reason: damage);
      expect(
        loaded.items['item-a']!.fleaPrice,
        snapshot.items['item-a']!.fleaPrice,
      );
    }
  });

  test(
    "committing one mode leaves other modes' task catalogs unchanged",
    () async {
      final store = await ReopenableDatabase.open();
      addTearDown(store.delete);
      final regular = _modeCatalog(GameMode.pvp, 'regular-task', true);
      final pve = _modeCatalog(GameMode.pve, 'pve-task', false);
      final seasonal = _modeCatalog(GameMode.seasonal, 'seasonal-task', true);
      expect(pve.progressCatalog!.tasks.single.id, 'pve-task');
      expect(pve.progressCatalog!.tasks.single.kappaRequired, isFalse);
      expect(seasonal.progressCatalog!.tasks.single.id, 'seasonal-task');
      expect(seasonal.progressCatalog!.tasks.single.kappaRequired, isTrue);
      for (final snapshot in [regular, pve, seasonal]) {
        expect(snapshot.progressCatalog, isNotNull);
        expect(snapshot.toJson()['progressCatalog'], isNotNull);
        await store.db.commitCatalog(snapshot);
      }
      final pveBefore = (await store.db.loadCatalog(GameMode.pve))!.toJson();
      final seasonalBefore = (await store.db.loadCatalog(GameMode.seasonal))!
          .toJson();
      expect(
        pveBefore['progressCatalog'],
        isNot(equals(seasonalBefore['progressCatalog'])),
      );
      final beforeRows = await store.db.select(store.db.catalogRecords).get();
      final otherRows = {
        for (final row in beforeRows.where(
          (row) => !row.cacheKey.endsWith(':pvp'),
        ))
          row.cacheKey: (row.id, row.revision, row.payload),
      };

      final refreshed = _modeCatalog(GameMode.pvp, 'new-regular-task', false);
      expect(refreshed.revision, isNot(regular.revision));
      await store.db.commitCatalog(refreshed);
      expect(
        (await store.db.loadCatalog(GameMode.pvp))!.toJson(),
        equals(refreshed.toJson()),
      );
      expect(
        (await store.db.loadCatalog(GameMode.pve))!.toJson(),
        equals(pveBefore),
      );
      expect(
        (await store.db.loadCatalog(GameMode.seasonal))!.toJson(),
        equals(seasonalBefore),
      );
      final afterRows = await store.db.select(store.db.catalogRecords).get();
      expect({
        for (final row in afterRows.where(
          (row) => !row.cacheKey.endsWith(':pvp'),
        ))
          row.cacheKey: (row.id, row.revision, row.payload),
      }, equals(otherRows));

      await store.reopen();
      expect(
        (await store.db.loadCatalog(GameMode.pve))!.toJson(),
        equals(pveBefore),
      );
      expect(
        (await store.db.loadCatalog(GameMode.seasonal))!.toJson(),
        equals(seasonalBefore),
      );
      expect(
        (await store.db.loadCatalog(GameMode.pvp))!.toJson(),
        equals(refreshed.toJson()),
      );
    },
  );
}

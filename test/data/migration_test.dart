import 'dart:convert';
import 'dart:io';

import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../fixtures/m1/catalog/fixture.dart';
import 'generated/schema.dart';

void main() {
  test('committed v1 schema migrates additively through v2 retaining preferences and activity', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final schema = await verifier.schemaAt(1);
    addTearDown(schema.close);
    expect(
      schema.rawDatabase.select(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'import_records'",
      ),
      isEmpty,
      reason: 'The v1 fixture must not contain the v2 import ledger.',
    );
    final settings = jsonEncode(
      AppSettings(mode: GameMode.pve, selectedMap: 'woods').toJson(),
    );
    schema.rawDatabase.execute(
      'INSERT INTO preferences(id,payload) VALUES (?,?)',
      [1, settings],
    );
    schema.rawDatabase.execute(
      'INSERT INTO activity_records(item_id,mode,source,observed_at,revision) VALUES (?,?,?,?,?)',
      ['synthetic-item', 'pve', 'importedManual', 1791244800, 7],
    );
    final db = BlackgridDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 3);
    expect(
      await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'import_records'",
          )
          .get(),
      hasLength(1),
    );
    expect((await db.readSettings()).mode, GameMode.pve);
    expect((await db.readSettings()).selectedMap, 'woods');
    final retained = (await db.readActivity()).single;
    expect(retained.itemId, 'synthetic-item');
    expect(retained.mode, GameMode.pve);
    expect(retained.source, ActivitySource.importedManual);
    expect(
      retained.observedAt,
      DateTime.fromMillisecondsSinceEpoch(1791244800 * 1000, isUtc: true),
    );
    expect(retained.revision, 7);
    expect((await db.select(db.importRecords).get()), isEmpty);
  });
  for (final from in [1, 2]) {
    test(
      'committed v$from schema migrates to v3 keeping data and creating item_icon_records',
      () async {
        final verifier = SchemaVerifier(GeneratedHelper());
        final schema = await verifier.schemaAt(from);
        addTearDown(schema.close);
        final raw = schema.rawDatabase;
        raw.execute('INSERT INTO preferences(id,payload) VALUES (?,?)', [
          1,
          jsonEncode(
            AppSettings(mode: GameMode.pve, selectedMap: 'woods').toJson(),
          ),
        ]);
        raw.execute(
          'INSERT INTO activity_records(item_id,mode,source,observed_at,revision) VALUES (?,?,?,?,?)',
          ['synthetic-item', 'pve', 'importedManual', 1791244800, 7],
        );
        final catalog = fixtureCatalog();
        final key = 'json.tarkov.dev:${catalog.mode.name}';
        raw.execute(
          'INSERT INTO catalog_records(id,cache_key,revision,payload) VALUES (?,?,?,?)',
          [1, key, catalog.revision, jsonEncode(catalog.toJson())],
        );
        raw.execute(
          'INSERT INTO active_catalogs(cache_key,record_id) VALUES (?,?)',
          [key, 1],
        );
        final db = BlackgridDatabase(schema.newConnection());
        addTearDown(db.close);
        await verifier.migrateAndValidate(db, 3);
        expect(
          await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'item_icon_records'",
              )
              .get(),
          hasLength(1),
        );
        expect((await db.readSettings()).selectedMap, 'woods');
        final retained = (await db.readActivity()).single;
        expect(retained.itemId, 'synthetic-item');
        expect(retained.revision, 7);
        final loaded = await db.loadCatalog(catalog.mode);
        expect(loaded, isNotNull);
        expect(loaded!.revision, catalog.revision);
        expect(loaded.items.keys, catalog.items.keys);
        expect(
          await db.customSelect('SELECT 1 FROM item_icon_records').get(),
          isEmpty,
        );
      },
    );
  }
  test(
    'newer schema refuses without downgrade reset deletion or byte mutation',
    () async {
      final dir = await Directory.systemTemp.createTemp('blackgrid-newer-');
      final file = File('${dir.path}/future.sqlite');
      final raw = sqlite3.open(file.path);
      raw.execute('CREATE TABLE future_user_data(value TEXT NOT NULL)');
      raw.execute(
        "INSERT INTO future_user_data VALUES ('synthetic durable record')",
      );
      raw.execute('PRAGMA user_version = 99');
      raw.close();
      final before = await file.readAsBytes();
      final db = BlackgridDatabase(NativeDatabase(file));
      await expectLater(db.readSettings(), throwsA(anything));
      await db.close();
      expect(await file.readAsBytes(), orderedEquals(before));
      final after = sqlite3.open(file.path);
      expect(after.select('PRAGMA user_version').single.values.single, 99);
      expect(
        after.select('SELECT value FROM future_user_data').single['value'],
        'synthetic durable record',
      );
      after.close();
      await dir.delete(recursive: true);
    },
  );
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:blackgrid/ui/app.dart' show isNewerDatabaseError;
import 'package:drift/native.dart';
// ignore: experimental_member_use
import 'package:drift/remote.dart';
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
    await verifier.migrateAndValidate(db, db.schemaVersion);
    expect(
      await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'import_records'",
          )
          .get(),
      hasLength(1),
    );
    expect((await db.readSettings()).settings.mode, GameMode.pve);
    expect((await db.readSettings()).settings.selectedMap, 'woods');
    final retained = (await db.readActivity()).rows.single;
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
        await verifier.migrateAndValidate(db, db.schemaVersion);
        expect(
          await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'item_icon_records'",
              )
              .get(),
          hasLength(1),
        );
        expect((await db.readSettings()).settings.selectedMap, 'woods');
        final retained = (await db.readActivity()).rows.single;
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
  test('3 to 4 and 1 to 4 keep data and start with empty stats', () async {
    for (final from in [3, 1]) {
      final verifier = SchemaVerifier(GeneratedHelper());
      final schema = await verifier.schemaAt(from);
      final raw = schema.rawDatabase;
      raw.execute('INSERT INTO preferences(id,payload) VALUES (?,?)', [
        1,
        jsonEncode(
          AppSettings(mode: GameMode.pve, selectedMap: 'woods').toJson(),
        ),
      ]);
      raw.execute(
        'INSERT INTO pin_records(map_id,pin_id,payload) VALUES (?,?,?)',
        [
          'woods',
          'pin-1',
          jsonEncode(
            CustomPin(
              id: 'pin-1',
              mapId: 'woods',
              x: 0.25,
              y: 0.5,
              frame: 'legacy-normalized',
              frameRevision: 0,
              label: 'synthetic',
              updatedAt: DateTime.utc(2026, 10, 1),
            ).toJson(),
          ),
        ],
      );
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
      addTearDown(schema.close);
      await verifier.migrateAndValidate(db, db.schemaVersion);
      expect((await db.readSettings()).settings.selectedMap, 'woods');
      expect((await db.readPins()).pins.single.id, 'pin-1');
      expect((await db.readActivity()).rows.single.revision, 7);
      expect((await db.loadCatalog(catalog.mode))!.revision, catalog.revision);
      for (final table in [
        'raid_stat_records',
        'flea_sale_records',
        'stats_meta',
      ]) {
        expect(
          await db.customSelect('SELECT 1 FROM $table').get(),
          isEmpty,
          reason: '$table must exist and start empty from v$from.',
        );
      }
    }
  });
  test('5 to 6 recreates the map-data cache and keeps user records', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final schema = await verifier.schemaAt(5);
    addTearDown(schema.close);
    final raw = schema.rawDatabase;
    raw.execute('INSERT INTO preferences(id,payload) VALUES (?,?)', [
      1,
      jsonEncode(
        AppSettings(mode: GameMode.pve, selectedMap: 'woods').toJson(),
      ),
    ]);
    raw.execute(
      'INSERT INTO live_map_snapshots(mode,checked_at,format_version,'
      'normalizer_version,compatibility_fingerprint,normalized_payload,'
      'normalized_sha256) VALUES (?,?,?,?,?,?,?)',
      [1, 1, 2, 1, 'old', Uint8List(0), 'old'],
    );
    final db = BlackgridDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, db.schemaVersion);
    expect((await db.readSettings()).settings.selectedMap, 'woods');
    expect(await db.select(db.liveMapSnapshots).get(), isEmpty);
    expect(await db.select(db.liveMapSources).get(), isEmpty);
  });
  test('newer schema reaches the second query as NewerDatabaseException without byte mutation', () async {
    final dir = await Directory.systemTemp.createTemp('blackgrid-newer-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/future.sqlite');
    final raw = sqlite3.open(file.path);
    raw.execute('CREATE TABLE future_user_data(value TEXT NOT NULL)');
    raw.execute(
      "INSERT INTO future_user_data VALUES ('synthetic durable record')",
    );
    raw.execute('PRAGMA user_version = 99');
    raw.close();
    final before = await file.readAsBytes();
    final db = BlackgridDatabase.open(file);
    // The first query fails and is ignored, as itemIcons.open() does.
    try {
      await db.readSettings();
      fail('The first query must fail.');
    } on TestFailure {
      rethrow;
    } on Object {
      // Ignored on purpose.
    }
    Object? second;
    try {
      await db.readSettings();
    } on Object catch (error) {
      second = error;
    }
    await db.close();
    expect(
      second,
      isA<DriftRemoteException>().having(
        (e) => e.remoteCause,
        'remoteCause',
        isA<DriftRemoteException>().having(
          (e) => e.remoteCause,
          'inner remoteCause',
          isA<NewerDatabaseException>()
              .having((e) => e.onDisk, 'onDisk', 99)
              .having((e) => e.supported, 'supported', db.schemaVersion),
        ),
      ),
    );
    // The startup screen recognises exactly the form that arrives.
    expect(isNewerDatabaseError(second), isTrue);
    expect(await file.readAsBytes(), orderedEquals(before));
    final after = sqlite3.open(file.path);
    expect(after.select('PRAGMA user_version').single.values.single, 99);
    expect(
      after.select('SELECT value FROM future_user_data').single['value'],
      'synthetic durable record',
    );
    after.close();
  });
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

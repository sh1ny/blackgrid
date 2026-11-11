import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/local_progress.dart';
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
  test('schema 7 upgrades to 8 preserving existing records and permitting scoped progress writes', () async {
    final directory = await Directory.systemTemp.createTemp(
      'blackgrid-v7-progress-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/data.sqlite');
    final schema = await SchemaVerifier(GeneratedHelper()).schemaAt(7);
    var schemaOpen = true;
    addTearDown(() {
      if (schemaOpen) schema.close();
    });
    final raw = schema.rawDatabase;
    final settings = jsonEncode(
      AppSettings(mode: GameMode.pve, selectedMap: 'woods').toJson(),
    );
    final pin = jsonEncode(
      CustomPin(
        id: 'pin-7',
        mapId: 'woods',
        x: 0.2,
        y: 0.3,
        frame: 'legacy-normalized',
        frameRevision: 0,
        label: 'retained',
        updatedAt: fixtureNow,
      ).toJson(),
    );
    final catalog = fixtureCatalog();
    final catalogKey = 'json.tarkov.dev:${catalog.mode.name}';
    raw.execute('INSERT INTO preferences VALUES (?, ?)', [1, settings]);
    raw.execute('INSERT INTO pin_records VALUES (?, ?, ?)', [
      'woods',
      'pin-7',
      pin,
    ]);
    raw.execute(
      'INSERT INTO activity_records '
      '(item_id, mode, source, observed_at, revision, verdict) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      ['item-7', 'pve', 'manual', 1791244800, 7, 'needed'],
    );
    raw.execute('INSERT INTO catalog_records VALUES (?, ?, ?, ?)', [
      7,
      catalogKey,
      catalog.revision,
      jsonEncode(catalog.toJson()),
    ]);
    raw.execute('INSERT INTO active_catalogs VALUES (?, ?)', [catalogKey, 7]);
    raw.execute('INSERT INTO import_records VALUES (?, ?, ?, ?)', [
      'digest-7',
      1,
      1791244800,
      3,
    ]);
    raw.execute(
      'INSERT INTO item_icon_records '
      '(item_id, icon_link, file_name, byte_size, etag, validated_at, '
      'last_shown_at, failed_until, failed_link) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        'item-7',
        'icon-url',
        'icon.png',
        42,
        'icon-etag',
        10,
        11,
        12,
        'old-url',
      ],
    );
    raw.execute('INSERT INTO raid_stat_records VALUES (?, ?, ?, ?, ?, ?, ?)', [
      'folder',
      'log',
      123,
      'pve',
      'woods',
      1791244800123,
      'online',
    ]);
    raw.execute(
      'INSERT INTO flea_sale_records VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      ['folder', 'log', 456, 'pve', 1791244800456, 'item-7', 2, 300],
    );
    raw.execute('INSERT INTO stats_meta VALUES (?, ?)', [0, 1791244800789]);
    raw.execute('INSERT INTO live_map_snapshots VALUES (?, ?)', [1, 123456]);
    raw.execute('INSERT INTO live_map_sources VALUES (?, ?, ?, ?, ?)', [
      1,
      'locations',
      Uint8List.fromList([0, 1, 127, 255]),
      'map-etag',
      'last-modified',
    ]);
    const retainedTables = [
      'preferences',
      'pin_records',
      'activity_records',
      'catalog_records',
      'active_catalogs',
      'import_records',
      'item_icon_records',
      'raid_stat_records',
      'flea_sale_records',
      'stats_meta',
      'live_map_snapshots',
      'live_map_sources',
    ];
    final retained = {
      for (final table in retainedTables)
        table: raw
            .select('SELECT * FROM $table')
            .map(Map<String, Object?>.from)
            .toList(),
    };
    raw.execute('PRAGMA user_version = 7');
    raw.execute('VACUUM INTO ?', [file.path]);
    schema.close();
    schemaOpen = false;

    Future<void> expectRetained(BlackgridDatabase db) async {
      for (final table in retainedTables) {
        final rows = await db.customSelect('SELECT * FROM $table').get();
        expect(
          rows.map((row) => row.data).toList(),
          retained[table],
          reason: '$table must retain every value.',
        );
      }
    }

    var db = BlackgridDatabase(NativeDatabase(file));
    var dbOpen = true;
    addTearDown(() async {
      if (dbOpen) await db.close();
    });
    await expectRetained(db);
    for (final table in [
      'progress_meta',
      'progress_cycles',
      'progress_events',
      'progress_heads',
    ]) {
      expect(await db.customSelect('SELECT * FROM $table').get(), isEmpty);
    }
    await db.customStatement(
      'INSERT INTO progress_cycles (cycle_id, mode, created_at_ms) VALUES (?, ?, ?)',
      ['cycle-7', 'pve', 123],
    );
    const insertEvent =
        'INSERT INTO progress_events '
        '(event_id, mode, cycle_id, occurred_at_ms, source_rank, device_id, '
        'entity_kind, entity_id, field, format_version, canonical_payload) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';
    final payload = ProgressEventCodec.encode(
      const ProgressEvent(
        eventId: 'event-7',
        deviceId: 'device-7',
        occurredAtMs: 123,
        scope: ProgressScope(mode: GameMode.pve, cycleId: 'cycle-7'),
        source: ProgressSource.manual,
        target: ProgressTarget(
          kind: ProgressEntityKind.task,
          id: 'task-7',
          field: ProgressField.state,
        ),
        value: ProgressTaskState(ProgressTaskStatus.started),
      ),
    );
    await db.customStatement(insertEvent, [
      'event-7',
      'pve',
      'cycle-7',
      123,
      0,
      'device-7',
      'task',
      'task-7',
      'state',
      1,
      payload,
    ]);
    await expectLater(
      db.customStatement(insertEvent, [
        'event-wrong-mode',
        'pvp',
        'cycle-7',
        123,
        0,
        'device-7',
        'task',
        'task-7',
        'state',
        1,
        payload,
      ]),
      throwsA(
        isA<SqliteException>().having(
          (error) => error.extendedResultCode,
          'extendedResultCode',
          787,
        ),
      ),
    );
    await db.close();
    dbOpen = false;
    db = BlackgridDatabase(NativeDatabase(file));
    dbOpen = true;
    await expectRetained(db);
    expect(
      (await db.customSelect('SELECT event_id FROM progress_events').get())
          .single
          .data['event_id'],
      'event-7',
    );
    await db.close();
    dbOpen = false;
  });
  test('local-data-durability: Upgrade and reopen', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final schema = await verifier.schemaAt(6);
    addTearDown(schema.close);
    schema.rawDatabase.execute(
      'INSERT INTO preferences(id,payload) VALUES (?,?)',
      [
        1,
        jsonEncode(
          AppSettings(mode: GameMode.pve, selectedMap: 'woods').toJson(),
        ),
      ],
    );
    final pin = CustomPin(
      id: 'p',
      mapId: 'woods',
      x: 0.2,
      y: 0.3,
      frame: 'legacy-normalized',
      frameRevision: 0,
      label: 'pin',
      updatedAt: fixtureNow,
    );
    schema.rawDatabase.execute(
      'INSERT INTO pin_records(map_id,pin_id,payload) VALUES (?,?,?)',
      ['woods', 'p', jsonEncode(pin.toJson())],
    );
    schema.rawDatabase.execute(
      'INSERT INTO activity_records(item_id,mode,source,observed_at,revision) VALUES (?,?,?,?,?)',
      ['legacy', 'pvp', 'manual', 1791244800, 3],
    );
    final db = BlackgridDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, db.schemaVersion);
    expect((await db.readActivity()).rows.single.toJson()['verdict'], isNull);
    expect((await db.readSettings()).settings.selectedMap, 'woods');
    expect((await db.readPins()).pins.single.id, 'p');
  });
  test(
    'v6 upgrade survives reopening with settings pins and unknown verdict',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'blackgrid-v6-verdict-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/data.sqlite');
      final schema = await SchemaVerifier(GeneratedHelper()).schemaAt(6);
      final raw = schema.rawDatabase;
      raw.execute('INSERT INTO preferences (id, payload) VALUES (?, ?)', [
        1,
        jsonEncode(
          AppSettings(mode: GameMode.pve, selectedMap: 'woods').toJson(),
        ),
      ]);
      raw.execute(
        'INSERT INTO pin_records (map_id, pin_id, payload) VALUES (?, ?, ?)',
        [
          'woods',
          'p',
          jsonEncode(
            CustomPin(
              id: 'p',
              mapId: 'woods',
              x: 0.2,
              y: 0.3,
              frame: 'legacy-normalized',
              frameRevision: 0,
              label: 'pin',
              updatedAt: fixtureNow,
            ).toJson(),
          ),
        ],
      );
      raw.execute(
        'INSERT INTO activity_records '
        '(item_id, mode, source, observed_at, revision) VALUES (?, ?, ?, ?, ?)',
        [
          'legacy',
          'pve',
          'manual',
          fixtureNow.millisecondsSinceEpoch ~/ 1000,
          1,
        ],
      );
      raw.execute('PRAGMA user_version = 6');
      raw.execute('VACUUM INTO ?', [file.path]);
      schema.close();
      var db = BlackgridDatabase(NativeDatabase(file));
      expect((await db.readActivity()).rows.single.verdict, isNull);
      await db.close();
      db = BlackgridDatabase(NativeDatabase(file));
      expect((await db.readActivity()).rows.single.verdict, isNull);
      expect((await db.readSettings()).settings.selectedMap, 'woods');
      expect((await db.readPins()).pins.single.id, 'p');
      await db.close();
    },
  );
  for (final from in [1, 2, 3, 4, 5, 6, 7]) {
    test(
      'schema $from upgrades to the current schema with empty progress storage',
      () async {
        final verifier = SchemaVerifier(GeneratedHelper());
        final schema = await verifier.schemaAt(from);
        addTearDown(schema.close);
        final db = BlackgridDatabase(schema.newConnection());
        addTearDown(db.close);
        await verifier.migrateAndValidate(db, db.schemaVersion);
        for (final table in [
          'progress_meta',
          'progress_cycles',
          'progress_events',
          'progress_heads',
        ]) {
          expect(
            await db.customSelect('SELECT * FROM $table').get(),
            isEmpty,
            reason: '$table must start empty when upgrading schema $from.',
          );
        }
      },
    );
  }
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

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../domain/catalog.dart';
import '../domain/catalog_store.dart';
import '../domain/settings.dart';
import '../domain/import_preview.dart';
import '../domain/local_stats.dart';
import '../domain/raid_lifecycle.dart';

part 'database.g.dart';

class Preferences extends Table {
  IntColumn get id => integer()();
  TextColumn get payload => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class PinRecords extends Table {
  TextColumn get mapId => text()();
  TextColumn get pinId => text()();
  TextColumn get payload => text()();
  @override
  Set<Column> get primaryKey => {mapId, pinId};
}

class ActivityRecords extends Table {
  TextColumn get itemId => text()();
  TextColumn get mode => text()();
  TextColumn get source => text()();
  DateTimeColumn get observedAt => dateTime()();
  IntColumn get revision => integer()();
  @override
  Set<Column> get primaryKey => {itemId, mode};
}

class CatalogRecords extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get cacheKey => text()();
  TextColumn get revision => text()();
  TextColumn get payload => text()();
  @override
  List<Set<Column>> get uniqueKeys => [
    {cacheKey, revision},
  ];
}

class ActiveCatalogs extends Table {
  TextColumn get cacheKey => text()();
  IntColumn get recordId => integer().references(CatalogRecords, #id)();
  @override
  Set<Column> get primaryKey => {cacheKey};
}

class ImportRecords extends Table {
  TextColumn get digest => text()();
  IntColumn get formatVersion => integer()();
  DateTimeColumn get importedAt => dateTime()();
  IntColumn get recordCount => integer()();
  @override
  Set<Column> get primaryKey => {digest};
}

/// One cached item icon: its source link, stored file and revalidation state.
class ItemIconRecords extends Table {
  TextColumn get itemId => text()();
  TextColumn get iconLink => text()();
  TextColumn get fileName => text().nullable()();
  IntColumn get byteSize => integer().withDefault(const Constant(0))();
  TextColumn get etag => text().nullable()();
  DateTimeColumn get validatedAt => dateTime().nullable()();
  DateTimeColumn get lastShownAt => dateTime()();
  DateTimeColumn get failedUntil => dateTime().nullable()();
  TextColumn get failedLink => text().nullable()();
  @override
  Set<Column> get primaryKey => {itemId};
}

/// One counted raid start; the key is the log record that announced it.
///
/// Times are integer milliseconds since the epoch so the clear watermark
/// compares at millisecond precision. `mode` is a [GameMode] name, `unknown`
/// when none was known; `file` and `entry` are enum names.
@TableIndex(name: 'raid_stat_records_mode_start', columns: {#mode, #startMs})
class RaidStatRecords extends Table {
  TextColumn get folder => text()();
  TextColumn get file => text()();
  IntColumn get offset => integer()();
  TextColumn get mode => text()();
  TextColumn get mapId => text().nullable()();
  IntColumn get startMs => integer()();
  TextColumn get entry => text()();
  @override
  Set<Column> get primaryKey => {folder, file, offset};
}

/// One counted flea-market sale; the key is the log record that announced it.
@TableIndex(name: 'flea_sale_records_mode', columns: {#mode})
class FleaSaleRecords extends Table {
  TextColumn get folder => text()();
  TextColumn get file => text()();
  IntColumn get offset => integer()();
  TextColumn get mode => text()();
  IntColumn get timeMs => integer()();
  TextColumn get itemId => text()();
  IntColumn get count => integer()();
  IntColumn get roubles => integer().nullable()();
  @override
  Set<Column> get primaryKey => {folder, file, offset};
}

/// The single row (id 0) holding when the local stats were last cleared.
class StatsMeta extends Table {
  IntColumn get id => integer()();
  IntColumn get clearedAtMs => integer().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

/// One complete normalized live-map snapshot for a game mode.
@DataClassName('LiveMapSnapshotRecord')
class LiveMapSnapshots extends Table {
  IntColumn get mode => integer()();
  IntColumn get checkedAt => integer()();
  IntColumn get formatVersion => integer()();
  IntColumn get normalizerVersion => integer()();
  TextColumn get compatibilityFingerprint => text()();
  BlobColumn get normalizedPayload => blob()();
  TextColumn get normalizedSha256 => text()();
  @override
  Set<Column> get primaryKey => {mode};
}

/// One exact upstream response body belonging to a live-map snapshot.
class LiveMapSources extends Table {
  IntColumn get mode => integer().references(LiveMapSnapshots, #mode)();
  TextColumn get dataset => text()();
  BlobColumn get body => blob()();
  TextColumn get bodySha256 => text()();
  TextColumn get etag => text().nullable()();
  TextColumn get lastModified => text().nullable()();
  @override
  Set<Column> get primaryKey => {mode, dataset};
}

/// The settings read from the database and whether the stored record was
/// unreadable.
class StoredSettings {
  /// Creates the result of a settings read.
  const StoredSettings(this.settings, {required this.unreadable});

  /// The decoded settings, or the defaults when the record is missing or
  /// [unreadable].
  final AppSettings settings;

  /// Whether a record exists but could not be decoded.
  final bool unreadable;
}

/// Thrown when the database on disk was written by a newer Blackgrid version.
///
/// The file is left untouched: no migration, downgrade, reset or deletion runs.
class NewerDatabaseException implements Exception {
  /// Creates the exception for a file at schema version [onDisk] opened by a
  /// build that supports up to [supported].
  const NewerDatabaseException({required this.onDisk, required this.supported});

  /// The schema version stored in the database file.
  final int onDisk;

  /// The newest schema version this build can open.
  final int supported;

  @override
  String toString() =>
      'NewerDatabaseException: database schema $onDisk is newer than the '
      'supported $supported.';
}

@DriftDatabase(
  tables: [
    Preferences,
    PinRecords,
    ActivityRecords,
    CatalogRecords,
    ActiveCatalogs,
    ImportRecords,
    ItemIconRecords,
    RaidStatRecords,
    FleaSaleRecords,
    StatsMeta,
    LiveMapSnapshots,
    LiveMapSources,
  ],
)
class BlackgridDatabase extends _$BlackgridDatabase
    implements CatalogStore, LocalStatsStore {
  BlackgridDatabase(super.executor);
  factory BlackgridDatabase.open(File file) =>
      BlackgridDatabase(NativeDatabase.createInBackground(file));
  @override
  int get schemaVersion => 5;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from > to) throw NewerDatabaseException(onDisk: from, supported: to);
      if (from < 1 || to != 5 || from >= to) {
        throw StateError('Unsupported database upgrade.');
      }
      await transaction(() async {
        if (from < 2) await m.createTable(importRecords);
        if (from < 3) await m.createTable(itemIconRecords);
        if (from < 4) {
          await m.createTable(raidStatRecords);
          await m.createTable(fleaSaleRecords);
          await m.createTable(statsMeta);
          await m.createIndex(raidStatRecordsModeStart);
          await m.createIndex(fleaSaleRecordsMode);
        }
        if (from < 5) {
          await m.createTable(liveMapSnapshots);
          await m.createTable(liveMapSources);
        }
      });
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  String _catalogKey(GameMode mode) => 'json.tarkov.dev:${mode.name}';
  @override
  Future<CatalogSnapshot?> loadCatalog(GameMode mode) async {
    if (mode == GameMode.unknown) return null;
    final pointer = await (select(
      activeCatalogs,
    )..where((p) => p.cacheKey.equals(_catalogKey(mode)))).getSingleOrNull();
    if (pointer == null) return null;
    final row = await (select(
      catalogRecords,
    )..where((p) => p.id.equals(pointer.recordId))).getSingle();
    final payload = row.payload;
    return _decodeCatalogOffRender(payload);
  }

  @override
  Future<void> commitCatalog(CatalogSnapshot snapshot) async {
    if (snapshot.mode == GameMode.unknown ||
        snapshot.source != 'json.tarkov.dev') {
      throw ArgumentError('Unsupported catalog authority.');
    }
    final payload = await _encodeCatalogOffRender(snapshot);
    final key = _catalogKey(snapshot.mode);
    await transaction(() async {
      final existing =
          await (select(catalogRecords)..where(
                (r) =>
                    r.cacheKey.equals(key) &
                    r.revision.equals(snapshot.revision),
              ))
              .getSingleOrNull();
      final id =
          existing?.id ??
          await into(catalogRecords).insert(
            CatalogRecordsCompanion.insert(
              cacheKey: key,
              revision: snapshot.revision,
              payload: payload,
            ),
          );
      if (existing != null) {
        await (update(catalogRecords)..where((r) => r.id.equals(id))).write(
          CatalogRecordsCompanion(payload: Value(payload)),
        );
      }
      await into(activeCatalogs).insertOnConflictUpdate(
        ActiveCatalogsCompanion.insert(cacheKey: key, recordId: id),
      );
      await (delete(
        catalogRecords,
      )..where((r) => r.cacheKey.equals(key) & r.id.isNotValue(id))).go();
    });
  }

  static const _statsMetaId = 0;

  Future<int?> _clearedAtMs() async {
    final row = await (select(
      statsMeta,
    )..where((m) => m.id.equals(_statsMetaId))).getSingleOrNull();
    return row?.clearedAtMs;
  }

  @override
  Future<void> recordRaid(RaidStatRow row) => transaction(() async {
    final startMs = row.start.millisecondsSinceEpoch;
    final cleared = await _clearedAtMs();
    if (cleared != null && startMs <= cleared) return;
    final modeName = (row.mode ?? GameMode.unknown).name;
    if (row.entry == RaidEntry.reconnect) {
      final newest =
          await (select(raidStatRecords)
                ..where(
                  (r) =>
                      r.mode.equals(modeName) &
                      r.startMs.isSmallerThanValue(startMs),
                )
                ..orderBy([(r) => OrderingTerm.desc(r.startMs)])
                ..limit(1))
              .getSingleOrNull();
      final previous = newest == null
          ? null
          : RaidStatRow(
              id: LogRecordId(
                newest.folder,
                LogFile.values.byName(newest.file),
                newest.offset,
              ),
              // The query matched the candidate's stored mode, so share it:
              // `null` and `GameMode.unknown` are both stored as `unknown`.
              mode: row.mode,
              mapId: newest.mapId,
              start: DateTime.fromMillisecondsSinceEpoch(
                newest.startMs,
                isUtc: true,
              ),
              entry: RaidEntry.values.byName(newest.entry),
            );
      if (!countsReconnect(previous, row)) return;
    }
    await into(raidStatRecords).insert(
      RaidStatRecordsCompanion.insert(
        folder: row.id.folder,
        file: row.id.file.name,
        offset: row.id.offset,
        mode: modeName,
        mapId: Value(row.mapId),
        startMs: startMs,
        entry: row.entry.name,
      ),
      mode: InsertMode.insertOrIgnore,
    );
  });

  @override
  Future<void> recordSale(FleaSaleRow row) => transaction(() async {
    final timeMs = row.time.millisecondsSinceEpoch;
    final cleared = await _clearedAtMs();
    if (cleared != null && timeMs <= cleared) return;
    await into(fleaSaleRecords).insert(
      FleaSaleRecordsCompanion.insert(
        folder: row.id.folder,
        file: row.id.file.name,
        offset: row.id.offset,
        mode: (row.mode ?? GameMode.unknown).name,
        timeMs: timeMs,
        itemId: row.itemId,
        count: row.count,
        roubles: Value(row.roubles),
      ),
      mode: InsertMode.insertOrIgnore,
    );
  });

  @override
  Future<LocalStatsTotals> readTotals(GameMode mode) async {
    final raids =
        await (selectOnly(raidStatRecords)
              ..addColumns([
                raidStatRecords.mapId,
                raidStatRecords.folder.count(),
              ])
              ..where(raidStatRecords.mode.equals(mode.name))
              ..groupBy([raidStatRecords.mapId]))
            .map(
              (r) => (
                r.read(raidStatRecords.mapId),
                r.read(raidStatRecords.folder.count())!,
              ),
            )
            .get();
    final sales = await customSelect(
      'SELECT COUNT(*) AS sales, COALESCE(SUM(count), 0) AS items, '
      'COALESCE(SUM(roubles), 0) AS roubles, '
      'COALESCE(SUM(roubles IS NULL), 0) AS not_roubles '
      'FROM flea_sale_records WHERE mode = ?',
      variables: [Variable.withString(mode.name)],
      readsFrom: {fleaSaleRecords},
    ).getSingle();
    return LocalStatsTotals(
      raidsByMap: {for (final (map, count) in raids) map: count},
      raidTotal: raids.fold(0, (sum, r) => sum + r.$2),
      sales: sales.read<int>('sales'),
      items: sales.read<int>('items'),
      roubles: sales.read<int>('roubles'),
      salesNotInRoubles: sales.read<int>('not_roubles'),
    );
  }

  @override
  Future<DateTime?> readSince() async {
    final ms = await _clearedAtMs();
    return ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  @override
  Future<void> clear(DateTime now) => transaction(() async {
    await delete(raidStatRecords).go();
    await delete(fleaSaleRecords).go();
    await into(statsMeta).insertOnConflictUpdate(
      StatsMetaCompanion.insert(
        id: const Value(_statsMetaId),
        clearedAtMs: Value(now.millisecondsSinceEpoch),
      ),
    );
  });

  /// Reads the stored settings, or defaults when there is no record.
  ///
  /// A record that cannot be decoded, because it is damaged or was written by
  /// a newer version, gives default settings with
  /// [StoredSettings.unreadable] set. Reading never writes, so the record
  /// stays until a save replaces it. Query and open errors still throw.
  Future<StoredSettings> readSettings() async {
    final row = await (select(
      preferences,
    )..where((p) => p.id.equals(1))).getSingleOrNull();
    if (row == null) return StoredSettings(AppSettings(), unreadable: false);
    try {
      return StoredSettings(
        AppSettings.fromJson(
          Map<String, Object?>.from(jsonDecode(row.payload) as Map),
        ),
        unreadable: false,
      );
    } on Object {
      return StoredSettings(AppSettings(), unreadable: true);
    }
  }

  Future<void> saveSettings(AppSettings settings) => transaction(() async {
    await into(preferences).insertOnConflictUpdate(
      PreferencesCompanion.insert(
        id: const Value(1),
        payload: jsonEncode(settings.toJson()),
      ),
    );
  });

  /// Reads every stored pin that can be decoded and passes
  /// [CustomPin.validate].
  ///
  /// Returns the readable [pins] and the number of rows [skipped]. Skipped
  /// rows are neither deleted nor rewritten. Query errors still throw.
  Future<({List<CustomPin> pins, int skipped})> readPins() async {
    final rows = await select(pinRecords).get();
    final pins = <CustomPin>[];
    var skipped = 0;
    for (final row in rows) {
      try {
        final pin = CustomPin.fromJson(
          Map<String, Object?>.from(jsonDecode(row.payload) as Map),
        )..validate();
        pins.add(pin);
      } on Object {
        skipped++;
      }
    }
    return (pins: pins, skipped: skipped);
  }

  Future<void> savePin(CustomPin pin) => transaction(() async {
    pin.validate();
    await into(pinRecords).insertOnConflictUpdate(
      PinRecordsCompanion.insert(
        mapId: pin.mapId,
        pinId: pin.id,
        payload: jsonEncode(pin.toJson()),
      ),
    );
  });
  Future<void> removePin(CustomPin pin) => transaction(() async {
    await (delete(
      pinRecords,
    )..where((p) => p.mapId.equals(pin.mapId) & p.pinId.equals(pin.id))).go();
  });

  /// Reads the activity rows whose mode and source this version knows,
  /// newest first.
  ///
  /// Returns the readable [rows] and the number of rows [skipped]. Skipped
  /// rows are neither deleted nor rewritten. Query errors still throw.
  Future<({List<ItemActivity> rows, int skipped})> readActivity() async {
    final records =
        await (select(activityRecords)..orderBy([
              (p) => OrderingTerm.desc(p.observedAt),
              (p) => OrderingTerm.asc(p.itemId),
            ]))
            .get();
    final rows = <ItemActivity>[];
    var skipped = 0;
    for (final row in records) {
      try {
        rows.add(
          ItemActivity(
            itemId: row.itemId,
            mode: GameMode.values.byName(row.mode),
            source: ActivitySource.values.byName(row.source),
            observedAt: row.observedAt.toUtc(),
            revision: row.revision,
          ),
        );
      } on Object {
        skipped++;
      }
    }
    return (rows: rows, skipped: skipped);
  }

  Future<ItemActivity> recordActivity(
    String itemId,
    GameMode mode,
    DateTime time, {
    ActivitySource source = ActivitySource.manual,
  }) => transaction(() async {
    if (itemId.isEmpty || mode == GameMode.unknown) {
      throw ArgumentError('Activity requires a known identity and mode.');
    }
    final old =
        await (select(
              activityRecords,
            )..where((a) => a.itemId.equals(itemId) & a.mode.equals(mode.name)))
            .getSingleOrNull();
    final row = ItemActivity(
      itemId: itemId,
      mode: mode,
      source: source,
      observedAt: time.toUtc(),
      revision: (old?.revision ?? 0) + 1,
    );
    await _writeActivity(row);
    return row;
  });
  Future<void> _writeActivity(ItemActivity row) async {
    await into(activityRecords).insertOnConflictUpdate(
      ActivityRecordsCompanion.insert(
        itemId: row.itemId,
        mode: row.mode.name,
        source: row.source.name,
        observedAt: row.observedAt.toUtc(),
        revision: row.revision,
      ),
    );
  }

  /// Reads every cached item icon row.
  Future<List<ItemIconRecord>> readItemIcons() => select(itemIconRecords).get();

  /// Inserts [row], or fully replaces the existing row for the same item id.
  ///
  /// Columns absent from [row] take their defaults, not the old values.
  Future<void> upsertItemIcon(ItemIconRecordsCompanion row) => transaction(
    () async =>
        into(itemIconRecords).insert(row, mode: InsertMode.insertOrReplace),
  );

  /// Deletes the icon rows for [itemIds] in one transaction.
  Future<void> deleteItemIcons(Iterable<String> itemIds) {
    final ids = itemIds.toList();
    return transaction(() async {
      await (delete(itemIconRecords)..where((r) => r.itemId.isIn(ids))).go();
    });
  }

  /// Sets the last-shown time of the icon row for [itemId] to [lastShownAt].
  Future<void> touchItemIcon(String itemId, DateTime lastShownAt) =>
      transaction(() async {
        await (update(itemIconRecords)..where((r) => r.itemId.equals(itemId)))
            .write(ItemIconRecordsCompanion(lastShownAt: Value(lastShownAt)));
      });

  Future<bool> wasImported(String digest) async =>
      await (select(
        importRecords,
      )..where((r) => r.digest.equals(digest))).getSingleOrNull() !=
      null;

  /// Writes [preview] and its import record in one transaction.
  ///
  /// Throws [ImportAlreadyCommitted] when the record for the preview's digest
  /// exists. Any other failure rolls every write back.
  ///
  /// Imported preferences are merged into the settings stored at commit time,
  /// read through the tolerant [readSettings], so local inputs (folders, follow
  /// switch, live scan and scan hotkey) always keep their stored values. With
  /// [replaceExisting] off and a settings row present, nothing is written to
  /// settings. A settings save that lands between this commit and the app's
  /// reload can still overwrite the imported preferences; that is existing
  /// behaviour.
  Future<void> commitImport(
    ImportPreview preview, {
    required bool replaceExisting,
  }) => transaction(() async {
    if (await wasImported(preview.digest)) {
      throw const ImportAlreadyCommitted();
    }
    if (preview.settings case final imported?) {
      final present = await (select(
        preferences,
      )..where((p) => p.id.equals(1))).getSingleOrNull();
      if (replaceExisting || present == null) {
        final stored = await readSettings();
        await saveSettings(imported.applyTo(stored.settings));
      }
    }
    for (final pin in preview.pins) {
      pin.validate();
      final present =
          await (select(pinRecords)..where(
                (p) => p.mapId.equals(pin.mapId) & p.pinId.equals(pin.id),
              ))
              .getSingleOrNull();
      if (replaceExisting || present == null) await savePin(pin);
    }
    for (final row in preview.winningActivity) {
      final present =
          await (select(activityRecords)..where(
                (a) =>
                    a.itemId.equals(row.itemId) & a.mode.equals(row.mode.name),
              ))
              .getSingleOrNull();
      if (replaceExisting || present == null) await _writeActivity(row);
    }
    await into(importRecords).insert(
      ImportRecordsCompanion.insert(
        digest: preview.digest,
        formatVersion: preview.formatVersion,
        importedAt: DateTime.now().toUtc(),
        recordCount:
            preview.pins.length +
            preview.winningActivity.length +
            (preview.settings == null ? 0 : 1),
      ),
    );
  });
}

/// Thrown by [BlackgridDatabase.commitImport] when the same files were already
/// imported.
class ImportAlreadyCommitted implements Exception {
  /// Creates the exception.
  const ImportAlreadyCommitted();

  @override
  String toString() => 'These files were already imported.';
}

// A database method's shared async closure context can retain its unsendable
// SQLite executor. These separate top-level scopes capture only their inputs.
Future<CatalogSnapshot> _decodeCatalogOffRender(String payload) => Isolate.run(
  () => CatalogSnapshot.fromJson(
    Map<String, dynamic>.from(jsonDecode(payload) as Map),
  ),
);

Future<String> _encodeCatalogOffRender(CatalogSnapshot snapshot) =>
    Isolate.run(() => jsonEncode(snapshot.toJson()));

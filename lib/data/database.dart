import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../domain/catalog.dart';
import '../domain/catalog_store.dart';
import '../domain/settings.dart';
import '../domain/import_preview.dart';

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

@DriftDatabase(
  tables: [
    Preferences,
    PinRecords,
    ActivityRecords,
    CatalogRecords,
    ActiveCatalogs,
    ImportRecords,
    ItemIconRecords,
  ],
)
class BlackgridDatabase extends _$BlackgridDatabase implements CatalogStore {
  BlackgridDatabase(super.executor);
  factory BlackgridDatabase.open(File file) =>
      BlackgridDatabase(NativeDatabase.createInBackground(file));
  @override
  int get schemaVersion => 3;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 1 || to != 3 || from >= to) {
        throw StateError('Unsupported database upgrade.');
      }
      await transaction(() async {
        if (from < 2) await m.createTable(importRecords);
        if (from < 3) await m.createTable(itemIconRecords);
      });
    },
    beforeOpen: (details) async {
      if (details.versionBefore != null &&
          details.versionBefore! > schemaVersion) {
        throw StateError(
          'This database was created by a newer Blackgrid version.',
        );
      }
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

  Future<AppSettings> readSettings() async {
    final row = await (select(
      preferences,
    )..where((p) => p.id.equals(1))).getSingleOrNull();
    return row == null
        ? AppSettings()
        : AppSettings.fromJson(
            Map<String, Object?>.from(jsonDecode(row.payload) as Map),
          );
  }

  Future<void> saveSettings(AppSettings settings) => transaction(() async {
    await into(preferences).insertOnConflictUpdate(
      PreferencesCompanion.insert(
        id: const Value(1),
        payload: jsonEncode(settings.toJson()),
      ),
    );
  });
  Future<List<CustomPin>> readPins() async => (await select(pinRecords).get())
      .map(
        (row) => CustomPin.fromJson(
          Map<String, Object?>.from(jsonDecode(row.payload) as Map),
        ),
      )
      .toList();
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
  Future<List<ItemActivity>> readActivity() async {
    final rows =
        await (select(activityRecords)..orderBy([
              (p) => OrderingTerm.desc(p.observedAt),
              (p) => OrderingTerm.asc(p.itemId),
            ]))
            .get();
    return rows
        .map(
          (row) => ItemActivity(
            itemId: row.itemId,
            mode: GameMode.values.byName(row.mode),
            source: ActivitySource.values.byName(row.source),
            observedAt: row.observedAt.toUtc(),
            revision: row.revision,
          ),
        )
        .toList();
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
  Future<void> commitImport(
    ImportPreview preview, {
    required bool replaceExisting,
  }) => transaction(() async {
    if (await wasImported(preview.digest)) {
      throw StateError('These source bytes were already imported.');
    }
    if (preview.settings != null) {
      final present = await (select(
        preferences,
      )..where((p) => p.id.equals(1))).getSingleOrNull();
      if (replaceExisting || present == null) {
        await saveSettings(preview.settings!);
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

// A database method's shared async closure context can retain its unsendable
// SQLite executor. These separate top-level scopes capture only their inputs.
Future<CatalogSnapshot> _decodeCatalogOffRender(String payload) => Isolate.run(
  () => CatalogSnapshot.fromJson(
    Map<String, dynamic>.from(jsonDecode(payload) as Map),
  ),
);

Future<String> _encodeCatalogOffRender(CatalogSnapshot snapshot) =>
    Isolate.run(() => jsonEncode(snapshot.toJson()));

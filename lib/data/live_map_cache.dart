import 'package:drift/drift.dart';

import '../domain/catalog.dart';
import '../maps/live_map_snapshot.dart';
import 'database.dart';

/// Stores one last-good live-map snapshot per game mode in SQLite.
class LiveMapCacheStore implements LiveMapStore {
  /// Creates a store over the application database.
  LiveMapCacheStore({required this.database});

  /// The application database.
  final BlackgridDatabase database;

  @override
  Future<LiveMapSnapshot?> read(GameMode mode) async {
    if (mode == GameMode.unknown) return null;
    return database.transaction(() async {
      final record = await (database.select(
        database.liveMapSnapshots,
      )..where((row) => row.mode.equals(mode.index))).getSingleOrNull();
      if (record == null) return null;
      final rows = await (database.select(
        database.liveMapSources,
      )..where((row) => row.mode.equals(mode.index))).get();
      final sources = <LiveMapSourceBody>[];
      for (final row in rows) {
        final dataset = LiveMapSourceDataset.values
            .where((value) => value.name == row.dataset)
            .firstOrNull;
        if (dataset == null) return null;
        sources.add(
          LiveMapSourceBody(
            dataset: dataset,
            bytes: row.body,
            etag: row.etag,
            lastModified: row.lastModified,
          ),
        );
      }
      if (sources.length != LiveMapSourceDataset.values.length) return null;
      return LiveMapSnapshot(
        mode: mode,
        checkedAt: DateTime.fromMicrosecondsSinceEpoch(
          record.checkedAt,
          isUtc: true,
        ),
        sources: sources,
      );
    });
  }

  @override
  Future<void> commit(LiveMapSnapshot snapshot) {
    final mode = snapshot.mode.index;
    return database.transaction(() async {
      await (database.delete(
        database.liveMapSources,
      )..where((row) => row.mode.equals(mode))).go();
      await database
          .into(database.liveMapSnapshots)
          .insertOnConflictUpdate(
            LiveMapSnapshotsCompanion.insert(
              mode: Value(mode),
              checkedAt: snapshot.checkedAt.toUtc().microsecondsSinceEpoch,
            ),
          );
      for (final source in snapshot.sources.values) {
        await database
            .into(database.liveMapSources)
            .insert(
              LiveMapSourcesCompanion.insert(
                mode: mode,
                dataset: source.dataset.name,
                body: source.bytes,
                etag: Value(source.etag),
                lastModified: Value(source.lastModified),
              ),
            );
      }
    });
  }
}

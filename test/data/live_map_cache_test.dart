import 'dart:convert';
import 'dart:typed_data';

import 'package:blackgrid/data/live_map_cache.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/maps/live_map_snapshot.dart';
import 'package:test/test.dart';

import 'support/reopenable_database.dart';

void main() {
  late ReopenableDatabase database;
  late LiveMapCacheStore store;

  setUp(() async {
    database = await ReopenableDatabase.open();
    store = LiveMapCacheStore(database: database.db);
  });

  tearDown(() => database.delete());

  test(
    'a committed snapshot survives reopening with bodies and validators',
    () async {
      await store.commit(_snapshot(GameMode.pve, 'a', DateTime.utc(2020)));

      final reopened = LiveMapCacheStore(database: await database.reopen());
      final read = (await reopened.read(GameMode.pve))!;

      expect(read.mode, GameMode.pve);
      expect(read.checkedAt, DateTime.utc(2020));
      for (final dataset in LiveMapSourceDataset.values) {
        final source = read.sources[dataset]!;
        expect(utf8.decode(source.bytes), 'a:${dataset.name}');
        expect(source.etag, '"a-${dataset.name}"');
        expect(source.lastModified, dataset == .maps ? 'Mon' : null);
      }
    },
  );

  test('modes are stored independently', () async {
    await store.commit(_snapshot(GameMode.pve, 'pve', DateTime.utc(2021)));
    await store.commit(
      _snapshot(GameMode.seasonal, 'season', DateTime.utc(2022)),
    );

    expect(await store.read(GameMode.pvp), isNull);
    expect(
      utf8.decode(
        (await store.read(GameMode.pve))!
            .sources[LiveMapSourceDataset.maps]!
            .bytes,
      ),
      'pve:maps',
    );
    expect(
      utf8.decode(
        (await store.read(GameMode.seasonal))!
            .sources[LiveMapSourceDataset.maps]!
            .bytes,
      ),
      'season:maps',
    );
  });

  test('a commit replaces every body of its mode', () async {
    await store.commit(_snapshot(GameMode.pvp, 'old', DateTime.utc(2020)));
    await store.commit(_snapshot(GameMode.pvp, 'new', DateTime.utc(2021)));

    final read = (await store.read(GameMode.pvp))!;
    expect(read.checkedAt, DateTime.utc(2021));
    expect(
      read.sources.values.map((source) => utf8.decode(source.bytes)),
      everyElement(startsWith('new:')),
    );
  });

  test('a failed commit keeps the previous snapshot whole', () async {
    await store.commit(_snapshot(GameMode.pvp, 'old', DateTime.utc(2020)));
    await database.abortNextInsert('live_map_sources');

    await expectLater(
      store.commit(_snapshot(GameMode.pvp, 'new', DateTime.utc(2021))),
      throwsA(anything),
    );

    final read = (await LiveMapCacheStore(database: await database.reopen())
        .read(GameMode.pvp))!;
    expect(read.checkedAt, DateTime.utc(2020));
    expect(
      read.sources.values.map((source) => utf8.decode(source.bytes)),
      everyElement(startsWith('old:')),
    );
  });

  test('an incomplete stored snapshot reads as absent', () async {
    await store.commit(_snapshot(GameMode.pve, 'a', DateTime.utc(2020)));
    await database.db.customStatement(
      "DELETE FROM live_map_sources WHERE dataset = 'traders'",
    );

    expect(await store.read(GameMode.pve), isNull);
  });

  test('the unknown mode has no snapshot', () async {
    expect(await store.read(GameMode.unknown), isNull);
  });
}

LiveMapSnapshot _snapshot(GameMode mode, String tag, DateTime checkedAt) =>
    LiveMapSnapshot(
      mode: mode,
      checkedAt: checkedAt,
      sources: [
        for (final dataset in LiveMapSourceDataset.values)
          LiveMapSourceBody(
            dataset: dataset,
            bytes: Uint8List.fromList(utf8.encode('$tag:${dataset.name}')),
            etag: '"$tag-${dataset.name}"',
            lastModified: dataset == .maps ? 'Mon' : null,
          ),
      ],
    );

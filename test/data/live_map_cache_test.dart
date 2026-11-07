import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/data/live_map_cache.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:blackgrid/maps/live_map_budget.dart';
import 'package:blackgrid/maps/live_map_inventory.dart';
import 'package:blackgrid/maps/live_map_normalizer.dart';
import 'package:blackgrid/maps/live_map_snapshot.dart';
import 'package:blackgrid/maps/prepared_map.dart';
import 'package:blackgrid/maps/prepared_map_loader.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart'
    show QueryExecutor, QueryInterceptor, TransactionExecutor;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:test/test.dart';

import '../../tool/maps/calibration.dart' show calibrationFor;
import '../../tool/maps/inventory.dart' show supportedMapSources;
import '../fixtures/m1/catalog/fixture.dart';
import '../support/prepared_pack_manifest.dart';
import 'generated/schema.dart';
import 'support/reopenable_database.dart';

void main() {
  group('durable live-map caches', () {
    late ReopenableDatabase database;
    late PreparedMapPack pack;
    late List<LiveMapBinding> bindings;
    late LiveMapCompatibility compatibility;
    late LiveMapCacheStore cache;

    setUp(() async {
      database = await ReopenableDatabase.open();
      pack = await _preparedPack(version: 'cache-pack-a', artworkRevision: 'a');
      bindings = _bindings();
      compatibility = LiveMapCompatibility.fromPreparedPack(pack, bindings);
      cache = LiveMapCacheStore(database: database.db);
    });

    tearDown(() => database.delete());

    test('read remains one generation across a concurrent commit', () async {
      final prior = _snapshot(
        mode: GameMode.pve,
        compatibility: compatibility,
        checkedAt: DateTime.utc(2020),
        contentTag: 'before',
      );
      final replacement = _snapshot(
        mode: GameMode.pve,
        compatibility: compatibility,
        checkedAt: DateTime.utc(2026),
        contentTag: 'after',
      );
      await cache.commit(prior);
      final barrier = _SnapshotReadBarrier();
      final actual = await database.db.runWithInterceptor(
        interceptor: barrier,
        () async {
          final reading = cache.read(
            GameMode.pve,
            compatibility: compatibility,
          );
          await barrier.headerRead.future;
          final writing = cache.commit(replacement);
          try {
            await barrier.writerQueued.future;
          } finally {
            barrier.resume.complete();
          }
          final result = await reading;
          await writing;
          return result;
        },
      );
      expect(actual, isNotNull);
      expect(actual!.checkedAt, prior.checkedAt);
      expect(actual.normalizedPayload, orderedEquals(prior.normalizedPayload));
      for (final source in prior.sources) {
        final observed = actual.sources.singleWhere(
          (value) => value.dataset == source.dataset,
        );
        expect(observed.bytes, orderedEquals(source.bytes));
        expect(observed.etag, source.etag);
        expect(observed.lastModified, source.lastModified);
      }
      final current = await cache.read(
        GameMode.pve,
        compatibility: compatibility,
      );
      expect(current!.checkedAt, replacement.checkedAt);
      expect(
        {for (final source in current.sources) source.dataset: source.sha256},
        {
          for (final source in replacement.sources)
            source.dataset: source.sha256,
        },
      );
    });

    test(
      'storage preparation respects the caller budget before writing',
      () async {
        final mapId = pack.maps.first.id;
        final compatibility = LiveMapCompatibility.fromPreparedPack(
          PreparedMapPack(
            version: pack.version,
            assetRoot: pack.assetRoot,
            maps: [pack.maps.first],
          ),
          bindings.where((binding) => binding.mapId == mapId),
        );
        final prior = _snapshot(
          mode: GameMode.pve,
          compatibility: compatibility,
          checkedAt: DateTime.utc(2020),
          contentTag: 'before',
        );
        await cache.commit(prior);
        final compactReplacement = _snapshot(
          mode: GameMode.pve,
          compatibility: compatibility,
          checkedAt: DateTime.utc(2026),
          contentTag: 'after-storage-budget',
        );
        final paddedSourceBody = Uint8List.fromList(
          utf8.encode(jsonEncode({'body': List.filled(16 * 1024, 'x').join()})),
        );
        final replacement = LiveMapSnapshot(
          mode: compactReplacement.mode,
          checkedAt: compactReplacement.checkedAt,
          normalizedPayload: compactReplacement.normalizedPayload,
          sources: [
            for (final source in compactReplacement.sources)
              if (source.dataset == LiveMapSourceDataset.maps)
                LiveMapSourceBody(
                  dataset: source.dataset,
                  bytes: paddedSourceBody,
                  etag: source.etag,
                  lastModified: source.lastModified,
                )
              else
                source,
          ],
          formatVersion: compactReplacement.formatVersion,
          normalizerVersion: compactReplacement.normalizerVersion,
          compatibility: compactReplacement.compatibility,
        );
        expect(
          replacement.normalizedPayload,
          isNot(orderedEquals(prior.normalizedPayload)),
        );
        final storageCharge =
            replacement.normalizedPayload.length +
            replacement.sources.fold<int>(
              0,
              (total, source) => total + source.bytes.length,
            ) +
            256 * (replacement.sources.length + 1);
        final maxMaterializedBytes = storageCharge - 1;
        final decodeBudget = LiveMapBudget(
          maxMaterializedBytes: maxMaterializedBytes,
        );
        final decoded = replacement.decodeInventory(budget: decodeBudget);
        expect(decoded.maps.keys.toSet(), compatibility.preparedMapIds);
        expect(
          decoded.maps.values.single.single.details['content'],
          'after-storage-budget',
        );
        await expectLater(
          cache.commit(
            replacement,
            budget: LiveMapBudget(maxMaterializedBytes: maxMaterializedBytes),
          ),
          throwsA(isA<LiveMapResourceLimitException>()),
        );
        final actual = await cache.read(
          GameMode.pve,
          compatibility: compatibility,
        );
        expect(actual!.checkedAt, prior.checkedAt);
        expect(
          actual.normalizedPayload,
          orderedEquals(prior.normalizedPayload),
        );
        for (final source in prior.sources) {
          final retained = actual.sources.singleWhere(
            (candidate) => candidate.dataset == source.dataset,
          );
          expect(retained.bytes, orderedEquals(source.bytes));
          expect(retained.etag, source.etag);
          expect(retained.lastModified, source.lastModified);
        }
      },
    );

    test('validator replacement reuses immutable source bytes', () {
      final budget = LiveMapBudget();
      final bytes = Uint8List.fromList(utf8.encode('{"small":true}'));
      final source = LiveMapSourceBody(
        dataset: LiveMapSourceDataset.maps,
        bytes: bytes,
        etag: 'old-etag',
        budget: budget,
      );
      final ownedBytes = source.bytes;
      final beforeReplacement = budget.materializedBytes;

      expect(
        source.withValidators(etag: 'old-etag', lastModified: null),
        same(source),
      );
      final updated = source.withValidators(
        etag: 'new-etag',
        lastModified: 'modified',
        budget: budget,
      );
      expect(updated.bytes, same(ownedBytes));
      expect(updated.sha256, source.sha256);
      expect(updated.etag, 'new-etag');
      expect(updated.lastModified, 'modified');
      expect(source.etag, 'old-etag');
      expect(budget.materializedBytes - beforeReplacement, 64);
    });

    test(
      'intact compatible mode cache survives restart regardless of age',
      () async {
        final oldCheckedAt = DateTime.utc(2019, 4, 12, 7, 8, 9, 123, 456);
        final expectedByMode = <GameMode, LiveMapSnapshot>{};
        for (final mode in [GameMode.pvp, GameMode.pve, GameMode.seasonal]) {
          final snapshot = _snapshot(
            mode: mode,
            compatibility: compatibility,
            checkedAt: oldCheckedAt,
            contentTag: mode.name,
          );
          await cache.commit(snapshot);
          expectedByMode[mode] = snapshot;
        }

        final reopened = await database.reopen();
        cache = LiveMapCacheStore(database: reopened);
        expect(
          await cache.read(GameMode.unknown, compatibility: compatibility),
          isNull,
        );

        for (final mode in [GameMode.pvp, GameMode.pve, GameMode.seasonal]) {
          final expected = expectedByMode[mode]!;
          final actual = await cache.read(mode, compatibility: compatibility);
          expect(
            actual,
            isNotNull,
            reason: '${mode.name} cache should survive reopen.',
          );
          expect(actual!.mode, mode);
          expect(actual.checkedAt, oldCheckedAt);
          expect(
            actual.normalizedPayload,
            orderedEquals(expected.normalizedPayload),
          );
          expect(actual.normalizedSha256, _digest(expected.normalizedPayload));
          expect(actual.compatibility.fingerprint, compatibility.fingerprint);
          expect(
            actual.compatibility.preparedMapIds,
            compatibility.preparedMapIds,
          );
          expect(actual.sources, hasLength(6));
          expect(
            actual.sources.map((source) => source.dataset).toSet(),
            LiveMapSourceDataset.values.toSet(),
          );
          for (final source in expected.sources) {
            final persisted = actual.sources.singleWhere(
              (candidate) => candidate.dataset == source.dataset,
            );
            expect(persisted.bytes, orderedEquals(source.bytes));
            expect(persisted.sha256, _digest(source.bytes));
            expect(persisted.etag, source.etag);
            expect(persisted.lastModified, source.lastModified);
          }
        }

        final pvp = (await cache.read(
          GameMode.pvp,
          compatibility: compatibility,
        ))!;
        final pve = (await cache.read(
          GameMode.pve,
          compatibility: compatibility,
        ))!;
        final seasonal = (await cache.read(
          GameMode.seasonal,
          compatibility: compatibility,
        ))!;
        expect(pvp.sources.first.bytes, isNot(equals(pve.sources.first.bytes)));
        expect(
          pve.sources.first.bytes,
          isNot(equals(seasonal.sources.first.bytes)),
        );
      },
    );

    test(
      'obsolete inventory format does not alter source validators',
      () async {
        final snapshot = _snapshot(
          mode: GameMode.pve,
          compatibility: compatibility,
          checkedAt: DateTime.utc(2020, 1, 2),
          contentTag: 'obsolete',
        );
        await cache.commit(snapshot);
        await database.writeRawRow(
          'UPDATE live_map_snapshots SET format_version = 1 WHERE mode = ?',
          [GameMode.pve.index],
        );

        expect(
          await cache.read(GameMode.pve, compatibility: compatibility),
          isNull,
        );

        await database.writeRawRow(
          'UPDATE live_map_snapshots SET format_version = ? WHERE mode = ?',
          [liveMapSnapshotFormatVersion, GameMode.pve.index],
        );
        final restored = await cache.read(
          GameMode.pve,
          compatibility: compatibility,
        );
        expect(restored, isNotNull);
        for (final source in snapshot.sources) {
          final retained = restored!.sources.singleWhere(
            (item) => item.dataset == source.dataset,
          );
          expect(retained.bytes, orderedEquals(source.bytes));
          expect(retained.etag, source.etag);
          expect(retained.lastModified, source.lastModified);
        }
        final malformedWire = Uint8List.fromList(
          utf8.encode('{"version":2,"facts":[]}'),
        );
        await database.writeRawRow(
          'UPDATE live_map_snapshots SET normalized_payload = ?, '
          'normalized_sha256 = ? WHERE mode = ?',
          [malformedWire, _digest(malformedWire), GameMode.pve.index],
        );
        expect(
          await cache.read(GameMode.pve, compatibility: compatibility),
          isNull,
        );
        await database.writeRawRow(
          'UPDATE live_map_snapshots SET normalized_payload = ?, '
          'normalized_sha256 = ? WHERE mode = ?',
          [
            snapshot.normalizedPayload,
            _digest(snapshot.normalizedPayload),
            GameMode.pve.index,
          ],
        );
        final repaired = await cache.read(
          GameMode.pve,
          compatibility: compatibility,
        );
        expect(repaired, isNotNull);
        for (final source in snapshot.sources) {
          final retained = repaired!.sources.singleWhere(
            (item) => item.dataset == source.dataset,
          );
          expect(retained.bytes, orderedEquals(source.bytes));
          expect(retained.etag, source.etag);
          expect(retained.lastModified, source.lastModified);
        }
      },
    );

    test(
      'malformed compact reference cannot replace durable facts or validators',
      () async {
        final prior = _snapshot(
          mode: GameMode.pve,
          compatibility: compatibility,
          checkedAt: DateTime.utc(2020),
          contentTag: 'retained-reference-authority',
        );
        await cache.commit(prior);
        prior.decodeInventory(budget: LiveMapBudget());
        expect(prior.inventoryValidation, isNotNull);
        final replacement = _snapshot(
          mode: GameMode.pve,
          compatibility: compatibility,
          checkedAt: DateTime.utc(2026),
          contentTag: 'rejected-reference-authority',
        );
        final wire = jsonDecode(
          utf8.decode(replacement.normalizedPayload),
        ) as Map<String, dynamic>;
        final maps = wire['maps'] as Map<String, dynamic>;
        final row = (maps.values.first as List).single as Map<String, dynamic>;
        row['detailsRef'] = (wire['facts'] as List).length;
        final malformed = LiveMapSnapshot(
          mode: replacement.mode,
          checkedAt: replacement.checkedAt,
          normalizedPayload: Uint8List.fromList(utf8.encode(jsonEncode(wire))),
          sources: replacement.sources,
          formatVersion: replacement.formatVersion,
          normalizerVersion: replacement.normalizerVersion,
          compatibility: replacement.compatibility,
        );
        expect(
          malformed.reuseInventoryValidation(prior.inventoryValidation),
          isFalse,
        );

        await expectLater(
          cache.commit(malformed),
          throwsA(isA<ArgumentError>()),
        );
        final retained = await cache.read(
          GameMode.pve,
          compatibility: compatibility,
        );
        expect(retained, isNotNull);
        expect(retained!.checkedAt, prior.checkedAt);
        expect(
          retained.normalizedPayload,
          orderedEquals(prior.normalizedPayload),
        );
        for (final source in prior.sources) {
          final actual = retained.sources.singleWhere(
            (item) => item.dataset == source.dataset,
          );
          expect(actual.bytes, orderedEquals(source.bytes));
          expect(actual.etag, source.etag);
          expect(actual.lastModified, source.lastModified);
        }
      },
    );

    test('reports rejected authority but not an absent cache', () async {
      final failures = <Object>[];
      expect(
        await cache.read(
          GameMode.pve,
          compatibility: compatibility,
          onRejected: failures.add,
        ),
        isNull,
      );
      expect(failures, isEmpty, reason: 'A cache miss is not a rejection.');

      final snapshot = _snapshot(
        mode: GameMode.pve,
        compatibility: compatibility,
        checkedAt: DateTime.utc(2020, 1, 2),
        contentTag: 'diagnostic',
      );
      await cache.commit(snapshot);
      await database.writeRawRow(
        "UPDATE live_map_sources SET body = ? WHERE mode = ? AND dataset = ?",
        [
          Uint8List.fromList(utf8.encode('{"changed":true}')),
          GameMode.pve.index,
          'maps',
        ],
      );
      expect(
        await cache.read(
          GameMode.pve,
          compatibility: compatibility,
          onRejected: failures.add,
        ),
        isNull,
      );
      expect(failures, hasLength(1));
      expect(failures.single, isA<FormatException>());

      failures.clear();
      final incompatible = LiveMapCompatibility.fromPreparedPack(
        pack,
        bindings,
        normalizerVersion: liveMapNormalizerVersion + 1,
      );
      expect(
        await cache.read(
          GameMode.pve,
          compatibility: incompatible,
          onRejected: failures.add,
        ),
        isNull,
      );
      expect(failures, hasLength(1));
      expect(failures.single, isA<FormatException>());
    });

    test('corrupt or incompatible cache and validators lose authority', () async {
      final snapshot = _snapshot(
        mode: GameMode.pve,
        compatibility: compatibility,
        checkedAt: DateTime.utc(2020, 1, 2),
        contentTag: 'authority',
      );
      await cache.commit(snapshot);
      await expectLater(
        cache.commit(
          _snapshot(
            mode: GameMode.unknown,
            compatibility: compatibility,
            checkedAt: DateTime.utc(2020, 1, 2),
            contentTag: 'unknown',
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        () => cache.commit(
          LiveMapSnapshot(
            mode: snapshot.mode,
            checkedAt: snapshot.checkedAt,
            normalizedPayload: snapshot.normalizedPayload,
            sources: [...snapshot.sources, snapshot.sources.first],
            formatVersion: snapshot.formatVersion,
            normalizerVersion: snapshot.normalizerVersion,
            compatibility: snapshot.compatibility,
          ),
        ),
        throwsFormatException,
        reason: 'Duplicate source identities must reject the entire candidate.',
      );
      expect(
        await cache.read(GameMode.pve, compatibility: compatibility),
        isNotNull,
        reason: 'Rejected candidates must leave the prior cache authoritative.',
      );
      await cache.commit(
        _snapshot(
          mode: GameMode.seasonal,
          compatibility: compatibility,
          checkedAt: DateTime.utc(2020, 1, 2),
          contentTag: 'other-mode',
        ),
      );

      final versionMismatch = LiveMapCompatibility.fromPreparedPack(
        pack,
        bindings,
        formatVersion: liveMapSnapshotFormatVersion + 1,
      );
      final normalizerMismatch = LiveMapCompatibility.fromPreparedPack(
        pack,
        bindings,
        normalizerVersion: liveMapNormalizerVersion + 1,
      );
      final changedMapping = LiveMapCompatibility.fromPreparedPack(pack, [
        for (final binding in bindings)
          if (binding.sourceKey == 'customs')
            LiveMapBinding(
              sourceKey: 'customs-revised',
              mapId: binding.mapId,
              calibration: binding.calibration,
            )
          else
            binding,
      ]);
      final changedCalibration = LiveMapCompatibility.fromPreparedPack(
        pack,
        _bindings(
          change: (sourceKey, calibration) {
            if (sourceKey == 'customs') {
              final geometry = calibration['geometry']! as Map<String, Object?>;
              final affine = geometry['affine']! as List<Object?>;
              affine[0] = (affine[0] as num) + 0.25;
            }
            return calibration;
          },
        ),
      );
      final changedOverride = LiveMapCompatibility.fromPreparedPack(
        pack,
        _bindings(
          change: (sourceKey, calibration) {
            if (sourceKey == 'interchange') {
              final assignments =
                  calibration['markerFloorAssignments']!
                      as Map<String, Object?>;
              final assignment =
                  assignments.values.first as Map<String, Object?>;
              assignment['floorId'] = 'Ground_Floor';
            }
            return calibration;
          },
        ),
      );
      for (final incompatible in [
        versionMismatch,
        normalizerMismatch,
        changedMapping,
        changedCalibration,
        changedOverride,
      ]) {
        expect(
          await cache.read(GameMode.pve, compatibility: incompatible),
          isNull,
          reason: 'An incompatible cache must not expose its validators.',
        );
      }

      final projectionChangedPack = await _preparedPack(
        version: 'cache-pack-projection',
        artworkRevision: 'a',
        changeProjection: true,
      );
      final projectionChangedCompatibility =
          LiveMapCompatibility.fromPreparedPack(
            projectionChangedPack,
            bindings,
          );
      expect(
        projectionChangedCompatibility.fingerprint,
        isNot(compatibility.fingerprint),
        reason: 'Actual prepared projection changes invalidate compatibility.',
      );
      final floorPolicyChangedPack = await _preparedPack(
        version: 'cache-pack-floor-policy',
        artworkRevision: 'a',
        changeFloorPolicy: true,
      );
      final floorPolicyChangedCompatibility =
          LiveMapCompatibility.fromPreparedPack(
            floorPolicyChangedPack,
            bindings,
          );
      expect(
        floorPolicyChangedCompatibility.fingerprint,
        isNot(compatibility.fingerprint),
        reason:
            'Actual prepared floor policy changes invalidate compatibility.',
      );
      expect(
        await cache.read(
          GameMode.pve,
          compatibility: projectionChangedCompatibility,
        ),
        isNull,
      );
      expect(
        await cache.read(
          GameMode.pve,
          compatibility: floorPolicyChangedCompatibility,
        ),
        isNull,
      );
      final artworkOnlyPack = await _preparedPack(
        version: 'cache-pack-b',
        artworkRevision: 'b',
      );
      final artworkOnlyCompatibility = LiveMapCompatibility.fromPreparedPack(
        artworkOnlyPack,
        bindings,
      );
      expect(artworkOnlyCompatibility.fingerprint, compatibility.fingerprint);
      expect(
        await cache.read(GameMode.pve, compatibility: artworkOnlyCompatibility),
        isNotNull,
        reason: 'Pack generation and artwork paths do not govern marker compatibility.',
      );

      Future<void> restore() => cache.commit(snapshot);
      Future<void> expectNoAuthority(String description) async {
        expect(
          await cache.read(GameMode.pve, compatibility: compatibility),
          isNull,
          reason: description,
        );
        await restore();
        expect(
          await cache.read(GameMode.pve, compatibility: compatibility),
          isNotNull,
          reason:
              'A fresh complete snapshot restores authority after $description.',
        );
      }

      await database.writeRawRow(
        "UPDATE live_map_sources SET body = ? WHERE mode = ? AND dataset = ?",
        [
          Uint8List.fromList(utf8.encode('{"changed":true}')),
          GameMode.pve.index,
          'maps',
        ],
      );
      await expectNoAuthority('a raw source body digest mismatch');

      await database.writeRawRow(
        'UPDATE live_map_snapshots SET normalized_payload = ? WHERE mode = ?',
        [Uint8List.fromList(utf8.encode('{"factory":[]}')), GameMode.pve.index],
      );
      await expectNoAuthority('a normalized payload digest mismatch');

      final truncated = Uint8List.fromList(utf8.encode('{"factory":'));
      await database.writeRawRow(
        'UPDATE live_map_snapshots SET normalized_payload = ?, normalized_sha256 = ? WHERE mode = ?',
        [truncated, _digest(truncated), GameMode.pve.index],
      );
      await expectNoAuthority(
        'a truncated normalized payload with a matching digest',
      );

      final incompleteInventory = Uint8List.fromList(
        utf8.encode(canonicalJson({'factory': []})),
      );
      await database.writeRawRow(
        'UPDATE live_map_snapshots SET normalized_payload = ?, normalized_sha256 = ? WHERE mode = ?',
        [incompleteInventory, _digest(incompleteInventory), GameMode.pve.index],
      );
      await expectNoAuthority(
        'a decodable normalized inventory missing prepared maps',
      );

      await database.writeRawRow(
        'DELETE FROM live_map_sources WHERE mode = ? AND dataset = ?',
        [GameMode.pve.index, LiveMapSourceDataset.tasks.name],
      );
      await expectNoAuthority('a missing source and validator record');

      await database.writeRawRow(
        'DELETE FROM live_map_sources WHERE mode = ? AND dataset = ?',
        [GameMode.seasonal.index, LiveMapSourceDataset.tasks.name],
      );
      await database.writeRawRow(
        "UPDATE live_map_sources SET mode = ? WHERE mode = ? AND dataset = ?",
        [
          GameMode.seasonal.index,
          GameMode.pve.index,
          LiveMapSourceDataset.tasks.name,
        ],
      );
      await expectNoAuthority(
        'a source and validator row assigned to another mode',
      );

      await database.writeRawRow(
        "INSERT INTO live_map_sources(mode,dataset,body,body_sha256,etag,last_modified) VALUES (?,?,?,?,?,?)",
        [
          GameMode.pve.index,
          'unsupported-source',
          Uint8List.fromList(utf8.encode('{}')),
          _digest(utf8.encode('{}')),
          null,
          null,
        ],
      );
      await expectNoAuthority('an extra unknown source and validator row');

      final duplicate = snapshot.sources.first;
      await expectLater(
        database.writeRawRow(
          'INSERT INTO live_map_sources(mode,dataset,body,body_sha256,etag,last_modified) VALUES (?,?,?,?,?,?)',
          [
            GameMode.pve.index,
            duplicate.dataset.name,
            duplicate.bytes,
            duplicate.sha256,
            duplicate.etag,
            duplicate.lastModified,
          ],
        ),
        throwsA(anything),
        reason: 'SQLite must reject duplicate mode/dataset source identities.',
      );
      expect(
        await cache.read(GameMode.pve, compatibility: compatibility),
        isNotNull,
        reason: 'A rejected duplicate insert must not damage valid authority.',
      );
    });

    test(
      'failed mode replacement rolls back old snapshot and all validators',
      () async {
        final oldSnapshot = _snapshot(
          mode: GameMode.seasonal,
          compatibility: compatibility,
          checkedAt: DateTime.utc(2021, 2, 3),
          contentTag: 'old',
        );
        final replacement = _snapshot(
          mode: GameMode.seasonal,
          compatibility: compatibility,
          checkedAt: DateTime.utc(2026, 11, 6),
          contentTag: 'replacement',
        );
        await cache.commit(oldSnapshot);
        await database.abortNextInsert('live_map_sources');
        await expectLater(cache.commit(replacement), throwsA(anything));

        final reopened = await database.reopen();
        cache = LiveMapCacheStore(database: reopened);
        final actual = await cache.read(
          GameMode.seasonal,
          compatibility: compatibility,
        );
        expect(actual, isNotNull);
        expect(actual!.checkedAt, oldSnapshot.checkedAt);
        expect(
          actual.normalizedPayload,
          orderedEquals(oldSnapshot.normalizedPayload),
        );
        expect(actual.normalizedSha256, oldSnapshot.normalizedSha256);
        expect(actual.sources, hasLength(6));
        for (final expected in oldSnapshot.sources) {
          final persisted = actual.sources.singleWhere(
            (source) => source.dataset == expected.dataset,
          );
          expect(persisted.bytes, orderedEquals(expected.bytes));
          expect(persisted.sha256, expected.sha256);
          expect(persisted.etag, expected.etag);
          expect(persisted.lastModified, expected.lastModified);
        }
      },
    );
  });

  test('v4 migration retains every existing user table row', () async {
    final schema = await SchemaVerifier(GeneratedHelper()).schemaAt(4);
    addTearDown(schema.close);
    final raw = schema.rawDatabase;
    final settings = jsonEncode(
      AppSettings(mode: GameMode.pve, selectedMap: 'woods').toJson(),
    );
    raw.execute('INSERT INTO preferences(id,payload) VALUES (?,?)', [
      1,
      settings,
    ]);
    raw.execute(
      'INSERT INTO pin_records(map_id,pin_id,payload) VALUES (?,?,?)',
      ['woods', 'migration-pin', '{"id":"migration-pin"}'],
    );
    raw.execute(
      'INSERT INTO activity_records(item_id,mode,source,observed_at,revision) VALUES (?,?,?,?,?)',
      ['migration-item', 'pve', 'importedManual', 1791244800, 7],
    );
    final catalog = fixtureCatalog();
    final catalogKey = 'json.tarkov.dev:${catalog.mode.name}';
    raw.execute(
      'INSERT INTO catalog_records(id,cache_key,revision,payload) VALUES (?,?,?,?)',
      [1, catalogKey, catalog.revision, jsonEncode(catalog.toJson())],
    );
    raw.execute(
      'INSERT INTO active_catalogs(cache_key,record_id) VALUES (?,?)',
      [catalogKey, 1],
    );
    raw.execute(
      'INSERT INTO import_records(digest,format_version,imported_at,record_count) VALUES (?,?,?,?)',
      ['migration-import', 1, 1791244800, 2],
    );
    raw.execute(
      'INSERT INTO item_icon_records(item_id,icon_link,file_name,byte_size,etag,validated_at,last_shown_at,failed_until,failed_link) VALUES (?,?,?,?,?,?,?,?,?)',
      [
        'migration-icon',
        'https://example.invalid/icon.png',
        'icon.png',
        13,
        'icon-etag',
        1791244800,
        1791244801,
        null,
        null,
      ],
    );
    raw.execute(
      'INSERT INTO raid_stat_records(folder,file,"offset",mode,map_id,start_ms,entry) VALUES (?,?,?,?,?,?,?)',
      ['logs', 'raid.log', 42, 'pve', 'woods', 1791244800000, 'raidStart'],
    );
    raw.execute(
      'INSERT INTO flea_sale_records(folder,file,"offset",mode,time_ms,item_id,count,roubles) VALUES (?,?,?,?,?,?,?,?)',
      ['logs', 'flea.log', 43, 'pve', 1791244801000, 'migration-item', 2, 2400],
    );
    raw.execute('INSERT INTO stats_meta(id,cleared_at_ms) VALUES (?,?)', [
      0,
      1791244700000,
    ]);

    final db = BlackgridDatabase(schema.newConnection());
    addTearDown(db.close);
    expect(db.schemaVersion, 5);
    await db.select(db.preferences).get();

    final cacheTables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('live_map_snapshots', 'live_map_sources') ORDER BY name",
        )
        .get();
    expect(cacheTables.map((row) => row.data['name']), [
      'live_map_snapshots',
      'live_map_sources',
    ]);
    expect(
      await db.customSelect('SELECT 1 FROM live_map_snapshots').get(),
      isEmpty,
    );
    expect(
      await db.customSelect('SELECT 1 FROM live_map_sources').get(),
      isEmpty,
    );
    expect((await db.readSettings()).settings.mode, GameMode.pve);
    expect((await db.readSettings()).settings.selectedMap, 'woods');
    expect(
      (await db.customSelect('SELECT pin_id FROM pin_records').get())
          .single
          .data['pin_id'],
      'migration-pin',
    );
    expect((await db.readActivity()).rows.single.itemId, 'migration-item');
    expect((await db.loadCatalog(catalog.mode))!.revision, catalog.revision);
    expect(
      (await db.select(db.importRecords).get()).single.digest,
      'migration-import',
    );
    expect(
      (await db.select(db.itemIconRecords).get()).single.etag,
      'icon-etag',
    );
    expect((await db.select(db.raidStatRecords).get()).single.mapId, 'woods');
    expect((await db.select(db.fleaSaleRecords).get()).single.roubles, 2400);
    expect(
      (await db.select(db.statsMeta).get()).single.clearedAtMs,
      1791244700000,
    );
  });
}

class _SnapshotReadBarrier extends QueryInterceptor {
  final headerRead = Completer<void>();
  final writerQueued = Completer<void>();
  final resume = Completer<void>();
  bool _held = false;

  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    if (_held && !writerQueued.isCompleted) writerQueued.complete();
    return super.beginTransaction(parent);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await executor.runSelect(statement, args);
    if (!_held &&
        statement.contains('FROM live_map_snapshots') &&
        statement.contains('AS payload_length')) {
      _held = true;
      headerRead.complete();
      await resume.future;
    }
    return rows;
  }
}

Future<PreparedMapPack> _preparedPack({
  required String version,
  required String artworkRevision,
  bool changeProjection = false,
  bool changeFloorPolicy = false,
}) async {
  final map = minimalPreparedMap('factory');
  if (changeProjection) {
    final geometry = map['geometry']! as Map<String, dynamic>;
    geometry['rotation'] = 90;
  }
  if (changeFloorPolicy) {
    final floors = map['floors']! as List<Object?>;
    final floor = floors.single as Map<String, dynamic>;
    floor['exclusive'] = true;
  }
  final floors = map['floors']! as List<Object?>;
  final firstFloor = floors.single as Map<String, Object?>;
  final artwork = firstFloor['artwork']! as Map<String, Object?>;
  final components = artwork['components']! as List<Object?>;
  final component = components.single as Map<String, Object?>;
  component['path'] = '$artworkRevision/factory.vec';
  final manifest = preparedPackManifest(maps: [map]);
  final loader = PreparedMapPackLoader(
    loadBytes: (path) async {
      if (path.endsWith('active.json')) {
        return preparedJsonBytes({
          'schemaVersion': 1,
          'version': version,
          'manifest': 'versions/$version/manifest.json',
        });
      }
      if (path.endsWith('manifest.json')) return preparedJsonBytes(manifest);
      throw StateError('Pack metadata must not load artwork: $path');
    },
  );
  return loader.load();
}

List<LiveMapBinding> _bindings({
  Map<String, Object?> Function(String sourceKey, Map<String, Object?> value)?
  change,
}) => [
  for (final entry in supportedMapSources.entries)
    LiveMapBinding(
      sourceKey: entry.value,
      mapId: entry.key,
      calibration: _bindingCalibration(entry.value, change),
    ),
];

Map<String, Object?> _bindingCalibration(
  String sourceKey,
  Map<String, Object?> Function(String sourceKey, Map<String, Object?> value)?
  change,
) {
  final calibration = calibrationFor(sourceKey);
  return change?.call(sourceKey, calibration) ?? calibration;
}

LiveMapSnapshot _snapshot({
  required GameMode mode,
  required LiveMapCompatibility compatibility,
  required DateTime checkedAt,
  required String contentTag,
  bool includeMarkers = true,
}) {
  final budget = LiveMapBudget();
  final payload = LiveMapInventory.fromMarkers(
    maps: {
      for (final mapId in compatibility.preparedMapIds)
        mapId: [
          if (includeMarkers)
            PreparedMarker.fromJson({
              'id': 'marker-$contentTag',
              'category': 'switches',
              'filterKey': 'Switches',
              'name': 'Marker $contentTag',
              'position': {'x': 1, 'z': 2},
              'details': {'content': contentTag},
              'source': {'mapId': mapId},
            }),
        ],
    },
    budget: budget,
  ).encode(budget: budget);
  final sources = [
    for (final dataset in LiveMapSourceDataset.values)
      LiveMapSourceBody(
        dataset: dataset,
        bytes: Uint8List.fromList(
          utf8.encode('{"body":"$contentTag:${mode.name}:${dataset.name}"}'),
        ),
        etag: dataset.index.isEven ? 'etag-$contentTag-${dataset.name}' : null,
        lastModified: dataset.index.isOdd
            ? 'modified-$contentTag-${dataset.name}'
            : null,
      ),
  ];
  return LiveMapSnapshot(
    mode: mode,
    checkedAt: checkedAt,
    normalizedPayload: payload,
    sources: sources,
    formatVersion: liveMapSnapshotFormatVersion,
    normalizerVersion: liveMapNormalizerVersion,
    compatibility: compatibility,
  );
}

String _digest(List<int> bytes) => sha256.convert(bytes).toString();

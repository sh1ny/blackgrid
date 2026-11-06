@Tags(['qualification'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../../tool/maps/pack.dart';

import 'package:blackgrid/maps/live_map_normalizer.dart'
    show canonicalJson, prepareMarkers;

import '../support/map_preparation_fixtures.dart';

const _assetBegin =
    '    # BEGIN generated map pack assets (mise run maps:rebuild)';
const _assetEnd = '    # END generated map pack assets';
const _metadataPaths = [
  'markers/maps.json',
  'markers/maps_en.json',
  'quests/tasks.json',
  'quests/tasks_en.json',
  'quests/traders.json',
  'quests/traders_en.json',
];

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'blackgrid-artwork-compatibility-case-',
    );
  });

  tearDown(() => temporary.delete(recursive: true));

  test('pendingConfigDoesNotContaminateBaseline', () async {
    final fixtureRoot = await Directory('${temporary.path}/fixtures')
        .create(recursive: true);
    final fixtures = await MapPreparationFixtures.create(fixtureRoot);
    final baseline = Directory('${temporary.path}/baseline');
    await copyPack(fixtures.first, baseline);
    const baselineNotice =
        'Frozen baseline notice, not pending configuration.\n';
    await packFile(baseline, 'NOTICE.txt').writeAsString(baselineNotice);
    final calibrationFile = packFile(baseline, 'evidence/calibration.json');
    final calibration = jsonDecode(
      await calibrationFile.readAsString(),
    ) as Map<String, dynamic>;
    final iceCalibration = (calibration['maps'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((map) => map['id'] == 'icebreaker');
    iceCalibration.remove('markerFloorAssignments');
    final calibrationBytes = utf8.encode(canonicalJson(calibration));
    await calibrationFile.writeAsBytes(calibrationBytes);

    final sourceIndexFile = packFile(baseline, 'evidence/sources.json');
    final sourceIndex = jsonDecode(
      await sourceIndexFile.readAsString(),
    ) as Map<String, dynamic>;
    (sourceIndex['sources'] as List).cast<Map<String, dynamic>>().singleWhere(
      (source) => source['path'] == 'calibration.json',
    )['sha256'] = sha256
        .convert(calibrationBytes)
        .toString();
    final sourceIndexBytes = utf8.encode(canonicalJson(sourceIndex));
    await sourceIndexFile.writeAsBytes(sourceIndexBytes);

    final manifest = await readManifest(baseline);
    manifest['sourceGeneration'] = sha256.convert(sourceIndexBytes).toString();
    final markerSnapshot = jsonDecode(
      await packFile(baseline, 'evidence/markers/maps.json').readAsString(),
    ) as Map<String, dynamic>;
    final translations =
        (jsonDecode(
              await packFile(
                baseline,
                'evidence/markers/maps_en.json',
              ).readAsString(),
            ) as Map<String, dynamic>)['data']
            as Map<String, dynamic>;
    final iceMap = (manifest['maps'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((map) => map['id'] == 'icebreaker');
    iceMap.remove('markerFloorAssignments');
    iceMap['markers'] = prepareMarkers(
      markerSnapshot,
      translations,
      iceCalibration,
    );
    manifest['sourceLock'] = {
      'vectorSourceRevision': 'frozen-baseline-revision',
      'vectorSourceUrl': 'https://example.invalid/frozen-baseline.svg',
      'vectorSourceBlob': 'frozen-baseline-blob',
      'metadataRepositoryRevision': 'frozen-baseline-metadata-revision',
      'metadataBlob': 'frozen-baseline-metadata-blob',
      'primaryHashes': {'frozen-baseline-source': 'frozen-baseline-hash'},
    };
    await saveManifest(baseline, manifest, refreshOutputs: true);

    final packs = Directory('${temporary.path}/packs');
    await promoteCandidate(baseline, packs);
    final before = await _snapshot(packs);
    final active = await verifyCommittedGeneration(packs);
    final checkTemp = await Directory('${temporary.path}/check').create();
    final check = await checkActive(
      packs,
      toolchain: fixtureToolchain,
      tempParent: checkTemp,
    );

    expect(check, contains('reproduced byte-identically'));
    expect(await _snapshot(packs), before);
    expect(
      await packFile(active.directory, 'NOTICE.txt').readAsString(),
      baselineNotice,
    );
    expect(
      (await readManifest(active.directory))['sourceLock'],
      manifest['sourceLock'],
    );

    const pubspecBefore =
        'name: compatibility\nflutter:\n  assets:\n'
        '    - assets/app_icon/\n$_assetBegin\n'
        '    - assets/maps/stale/\n$_assetEnd\n    - assets/other/\n';
    final pubspec = File('${temporary.path}/pubspec.yaml');
    await pubspec.writeAsString(pubspecBefore);
    final offlineRefresh = await refreshActive(
      packs,
      pubspec,
      toolchain: {...fixtureToolchain, 'vector_graphics_compiler': '1.3.4'},
      assetRoot: 'assets/maps',
      candidateParent: Directory('${temporary.path}/offline-refresh'),
      now: DateTime.utc(2026, 11, 5, 10),
    );
    final offlineGeneration = await verifyCommittedGeneration(packs);
    expect(offlineRefresh.changed, isFalse);
    expect(
      await packFile(offlineGeneration.directory, 'NOTICE.txt').readAsString(),
      baselineNotice,
    );
    expect(offlineGeneration.manifest['sourceLock'], manifest['sourceLock']);
    expect(
      await packFile(
        offlineGeneration.directory,
        'evidence/calibration.json',
      ).readAsString(),
      await packFile(baseline, 'evidence/calibration.json').readAsString(),
    );

    final replacements = Directory('${temporary.path}/six-source-replacements');
    for (final path in _metadataPaths) {
      final target = packFile(replacements, path);
      await target.parent.create(recursive: true);
      await packFile(fixtures.raw, path).copy(target.path);
    }
    final markerFile = packFile(replacements, 'markers/maps.json');
    final renewalMarkerSnapshot =
        jsonDecode(await markerFile.readAsString()) as Map<String, dynamic>;
    final mapRecords =
        (renewalMarkerSnapshot['data'] as Map<String, dynamic>)['maps']
            as Map<String, dynamic>;
    final woods = mapRecords.values.singleWhere(
      (map) => map['normalizedName'] == 'woods',
    ) as Map<String, dynamic>;
    final spawnPosition =
        ((woods['spawns'] as List).first as Map<String, dynamic>)['position']
            as Map<String, dynamic>;
    spawnPosition['x'] = (spawnPosition['x'] as num).toDouble() + 0.25;
    await markerFile.writeAsString(canonicalJson(renewalMarkerSnapshot));
    final baselineInputs = await FrozenInputs.fromGeneration(
      offlineGeneration.directory,
    );
    final refreshedInputs = await baselineInputs.withMetadata(replacements);
    final result = await refreshActive(
      packs,
      pubspec,
      toolchain: fixtureToolchain,
      assetRoot: 'assets/maps',
      candidateParent: Directory('${temporary.path}/renewal'),
      metadataInputs: refreshedInputs,
      now: DateTime.utc(2026, 11, 5),
    );
    final renewed = Directory('${packs.path}/versions/${result.id}');

    expect(
      await packFile(renewed, 'NOTICE.txt').readAsString(),
      baselineNotice,
    );
    expect((await readManifest(renewed))['sourceLock'], manifest['sourceLock']);
    expect(
      (await readManifest(renewed))['sourceGeneration'],
      isNot(offlineGeneration.manifest['sourceGeneration']),
    );
  });

  test('metadataPreservationRejectsDrift', () {
    final baseline = <String, dynamic>{
      'schemaVersion': 1,
      'preparationVersion': 3,
      'sourceGeneration': 'baseline-generation',
      'sourceLock': {'reviewed': 'baseline'},
      'supportedMapIds': ['map'],
      'vectorCodecFormat': 1,
      'toolchain': {'compiler': 'baseline'},
      'maps': [
        {
          'id': 'map',
          'floorIds': ['ground'],
          'markers': [
            {
              'id': 'marker',
              'floorId': 'ground',
              'position': {'x': 1, 'y': 2},
              'heightBand': 'ground',
              'outline': null,
              'source': {
                'floorAssignment': {
                  'floorId': 'ground',
                  'volume': {'min': 0, 'max': 1},
                },
              },
            },
          ],
        },
      ],
      'outputs': [
        {'path': 'NOTICE.txt', 'sha256': 'baseline-notice'},
        {'path': 'evidence/sources.json', 'sha256': 'baseline-index'},
        {'path': 'evidence/calibration.json', 'sha256': 'baseline-calibration'},
        {'path': 'artwork/map/ground.vec', 'sha256': 'baseline-artwork'},
      ],
    };
    final mutations = <String, void Function(Map<String, dynamic>)>{
      'artwork': (candidate) =>
          _output(candidate, 'artwork/map/ground.vec')['sha256'] =
              'drifted-artwork',
      'calibration': (candidate) =>
          _output(candidate, 'evidence/calibration.json')['sha256'] =
              'drifted-calibration',
      'notice': (candidate) =>
          _output(candidate, 'NOTICE.txt')['sha256'] = 'drifted-notice',
    };

    for (final entry in mutations.entries) {
      final candidate =
          jsonDecode(jsonEncode(baseline)) as Map<String, dynamic>;
      entry.value(candidate);
      expect(
        () => validateMetadataPreservation(baseline, candidate),
        throwsFormatException,
        reason: entry.key,
      );
    }

    final baselineIndex = <String, dynamic>{
      'schemaVersion': 1,
      'sources': [
        for (final path in _metadataPaths)
          {
            'path': path,
            'url': 'https://example.invalid/$path',
            'sha256': 'old',
          },
        {
          'path': 'calibration.json',
          'url': 'https://example.invalid/calibration.json',
          'sha256': 'baseline-calibration',
        },
      ],
    };
    final driftedIndex =
        jsonDecode(jsonEncode(baselineIndex)) as Map<String, dynamic>;
    final calibration = (driftedIndex['sources'] as List).last;
    calibration['sha256'] = 'drifted-calibration';
    expect(
      () => validateMetadataSourceIndex(baselineIndex, driftedIndex),
      throwsFormatException,
      reason: 'non-six source record',
    );
  });
}

Map<String, dynamic> _output(Map<String, dynamic> manifest, String path) =>
    (manifest['outputs'] as List).cast<Map<String, dynamic>>().singleWhere(
      (output) => output['path'] == path,
    );

Future<Map<String, List<int>>> _snapshot(Directory root) async {
  final files = <String, List<int>>{};
  if (!await root.exists()) return files;
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is File) {
      final relative = entity.path
          .replaceAll('\\', '/')
          .substring(root.path.replaceAll('\\', '/').length + 1);
      files[relative] = await entity.readAsBytes();
    }
  }
  return files;
}

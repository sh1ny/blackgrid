import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image;
import 'package:test/test.dart';

import '../../tool/maps/calibration.dart';
import '../../tool/maps/pack.dart';
import '../support/map_preparation_fixtures.dart';

String _sha256(List<int> bytes) => sha256.convert(bytes).toString();

class _StageTransport {
  _StageTransport(this.raw, this.routes);

  final Directory raw;
  final Map<Uri, String> routes;
  final Map<String, List<int>> overrides = {};
  Uri? changedTile;

  Future<Uint8List> fetch(Uri uri) async {
    final path = routes[uri];
    if (path == null) {
      throw HttpException('unexpected source request: $uri', uri: uri);
    }
    final bytes = overrides[path] ?? await packFile(raw, path).readAsBytes();
    if (uri != changedTile) return Uint8List.fromList(bytes);
    final decoded = image.decodePng(Uint8List.fromList(bytes))!;
    decoded.setPixelRgba(1, 1, 240, 30, 20, 255);
    return Uint8List.fromList(image.encodePng(decoded));
  }
}

class _AdmittedStage {
  const _AdmittedStage({
    required this.candidate,
    required this.context,
    required this.baseline,
  });

  final Directory candidate;
  final MapBuildContext context;
  final Directory baseline;
}

Future<_AdmittedStage> _createAdmittedStage(Directory root) async {
  final fixtures = await MapPreparationFixtures.create(root);
  final packs = Directory('${root.path}/packs');
  final versions = Directory('${packs.path}/versions')
    ..createSync(recursive: true);
  final baselineId = _sha256(
    await packFile(fixtures.first, 'manifest.json').readAsBytes(),
  );
  final baseline = Directory('${versions.path}/$baselineId');
  await copyPack(fixtures.first, baseline);
  await File('${packs.path}/active.json').writeAsString(
    canonicalJson({
      'schemaVersion': 1,
      'version': baselineId,
      'manifest': 'versions/$baselineId/manifest.json',
    }),
  );
  final pubspec = File('${root.path}/pubspec.yaml');
  await pubspec.writeAsString(_pubspecText('old'));

  final baseContext = MapBuildContext.reviewedConfiguration();
  final extraSources = <String, List<int>>{
    'terms/tarkov-dev-README.md': utf8.encode('Reviewed fixture README'),
    'terms/tarkov-dev-software-LICENSE.txt': utf8.encode(
      'Reviewed fixture software license',
    ),
    'terms/tarkovbot-creator.html': utf8.encode('Reviewed fixture terms page'),
  };
  final hashes = Map<String, String>.from(
    (baseContext.sourceLock['primaryHashes'] as Map).cast<String, String>(),
  );
  for (final path in hashes.keys.toList()) {
    hashes[path] = _sha256(
      extraSources[path] ?? await packFile(fixtures.raw, path).readAsBytes(),
    );
  }
  final sourceLock =
      jsonDecode(canonicalJson(baseContext.sourceLock)) as Map<String, dynamic>;
  sourceLock['primaryHashes'] = hashes;
  final context = MapBuildContext.reviewed(
    calibration: baseContext.calibration,
    sourceLock: sourceLock,
    noticeBytes: baseContext.noticeBytes,
  );
  final routes = <Uri, String>{
    for (final entry in primarySourceUrls.entries)
      Uri.parse(entry.value): entry.key,
  };
  final metadata = jsonDecode(
    await packFile(fixtures.raw, 'metadata/maps.json').readAsString(),
  ) as List;
  for (final rawLocal in context.calibration['maps'] as List) {
    final local = Map<String, Object?>.from(rawLocal as Map);
    final upstream = interactiveMetadata(
      metadata,
      local['sourceKey'] as String,
    );
    final resources = <Map<String, Object?>>[
      for (final floor in reconcileFloors(local, upstream))
        if (floor['sourceTileUrl'] != null) floor,
      for (final dependency
          in (local['rasterDependencies'] as List? ?? const []))
        {
          ...Map<String, Object?>.from(dependency as Map),
          'id': 'dependency-${dependency['id']}',
        },
    ];
    for (final resource in resources) {
      final tileBase = resource['sourceTileUrl'] as String;
      for (var x = 0; x < 16; x++) {
        for (var y = 0; y < 16; y++) {
          routes.putIfAbsent(
            Uri.parse(tileUrl(tileBase, x, y)),
            () => rawTilePath(
              local['id'] as String,
              resource['id'] as String,
              x,
              y,
            ),
          );
        }
      }
    }
  }
  final transport = _StageTransport(fixtures.raw, routes)
    ..overrides.addAll(extraSources);
  transport.changedTile = routes.entries
      .where(
        (entry) =>
            entry.value.startsWith('tiles/') &&
            entry.value.endsWith('/0/0.png'),
      )
      .first
      .key;
  final candidate = Directory('${root.path}/stage');
  await stageArtworkRefresh(
    packs,
    pubspec,
    stage: candidate,
    toolchain: fixtureToolchain,
    reviewedContext: context,
    fetch: transport.fetch,
  );
  return _AdmittedStage(
    candidate: candidate,
    context: context,
    baseline: baseline,
  );
}

String _pubspecText(String generation) => [
  'name: fixture',
  'flutter:',
  '  assets:',
  '    - assets/app_icon/',
  mapPackAssetsBegin,
  '    - assets/maps/versions/$generation/',
  mapPackAssetsEnd,
  '    - assets/other/',
  '',
].join('\n');

Future<void> _copyDirectory(Directory source, Directory destination) async {
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final relative = entity.path
        .replaceAll('\\', '/')
        .substring(source.path.replaceAll('\\', '/').length + 1);
    final target = packFile(destination, relative);
    await target.parent.create(recursive: true);
    await entity.copy(target.path);
  }
}

Future<void> _changeBaselineAfterStaging(
  _PublicationHarness harness, {
  bool changeOwnership = false,
}) async {
  final previous = Directory(
    '${harness.packs.path}/versions/${harness.baselineId}',
  );
  final manifest = await readManifest(previous);
  (manifest['toolchain'] as Map<String, dynamic>)['xml'] =
      'changed-after-staging';
  if (changeOwnership) {
    final maps = (manifest['maps'] as List).cast<Map<String, dynamic>>();
    final marker = maps
        .expand((map) => (map['markers'] as List).cast<Map<String, dynamic>>())
        .firstWhere((marker) => marker['source']['floorAssignment'] != null);
    final assignment = marker['source']['floorAssignment'] as Map;
    final oldFloorId = assignment['floorId'] as String;
    final newFloorId = oldFloorId == 'Second_Floor'
        ? 'Third_Floor'
        : 'Second_Floor';
    assignment['floorId'] = newFloorId;
    marker['floorId'] = newFloorId;
  }
  await saveManifest(previous, manifest, refreshOutputs: true);
  final nextId = _sha256(
    await packFile(previous, 'manifest.json').readAsBytes(),
  );
  final next = Directory('${harness.packs.path}/versions/$nextId');
  await previous.rename(next.path);
  final pointer = File('${harness.packs.path}/active.json');
  await pointer.writeAsString(
    canonicalJson({
      'schemaVersion': 1,
      'version': nextId,
      'manifest': 'versions/$nextId/manifest.json',
    }),
  );
  harness
    ..baselineId = nextId
    ..baselineManifest = await readManifest(next)
    ..pointerBefore = await pointer.readAsString();
  await verifyCommittedGeneration(harness.packs);
}

class _PublicationHarness {
  _PublicationHarness({
    required this.packs,
    required this.pubspec,
    required this.candidate,
    required this.baselineId,
    required this.baselineManifest,
    required this.candidateId,
    required this.pointerBefore,
    required this.pubspecBefore,
  });

  final Directory packs;
  final File pubspec;
  final Directory candidate;
  String baselineId;
  Map<String, dynamic> baselineManifest;
  final String candidateId;
  String pointerBefore;
  final String pubspecBefore;
}

Future<_PublicationHarness> _privateHarness(
  _AdmittedStage admitted,
  Directory root, {
  bool corruptEvidence = false,
  bool corruptOutput = false,
}) async {
  final packs = Directory('${root.path}/packs');
  await Directory('${packs.path}/versions').create(recursive: true);
  final baselineManifest = await packFile(
    admitted.baseline,
    'manifest.json',
  ).readAsBytes();
  final baselineId = _sha256(baselineManifest);
  final baseline = Directory('${packs.path}/versions/$baselineId');
  await _copyDirectory(admitted.baseline, baseline);
  await File('${packs.path}/active.json').writeAsString(
    canonicalJson({
      'schemaVersion': 1,
      'version': baselineId,
      'manifest': 'versions/$baselineId/manifest.json',
    }),
  );
  final candidate = Directory('${root.path}/staged-candidate');
  await _copyDirectory(admitted.candidate, candidate);
  if (corruptEvidence) {
    await packFile(candidate, 'evidence/calibration.json').writeAsBytes([0]);
  }
  if (corruptOutput) {
    final manifest = await readManifest(candidate);
    final raster = (manifest['outputs'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere(
          (output) => (output['path'] as String).endsWith('/0/0.png'),
        );
    await packFile(candidate, raster['path'] as String).writeAsBytes([0]);
  }
  final candidateId = _sha256(
    await packFile(candidate, 'manifest.json').readAsBytes(),
  );
  final pubspec = File('${root.path}/pubspec.yaml')
    ..writeAsStringSync(_pubspecText('old'));
  return _PublicationHarness(
    packs: packs,
    pubspec: pubspec,
    candidate: candidate,
    baselineId: baselineId,
    baselineManifest:
        jsonDecode(utf8.decode(baselineManifest)) as Map<String, dynamic>,
    candidateId: candidateId,
    pointerBefore: await File('${packs.path}/active.json').readAsString(),
    pubspecBefore: await pubspec.readAsString(),
  );
}

Future<_MinimalTransactionHarness> _minimalTransactionHarness(
  Directory root,
) async {
  final packs = Directory('${root.path}/packs');
  final versions = Directory('${packs.path}/versions')
    ..createSync(recursive: true);
  final baselineNotice = utf8.encode('old');
  final baselineManifest = canonicalJson({
    'outputs': [
      {'path': 'NOTICE.txt', 'sha256': _sha256(baselineNotice)},
    ],
  });
  final baselineId = _sha256(utf8.encode(baselineManifest));
  final baseline = Directory('${versions.path}/$baselineId')..createSync();
  await File('${baseline.path}/NOTICE.txt').writeAsBytes(baselineNotice);
  await File('${baseline.path}/manifest.json').writeAsString(baselineManifest);
  final active = File('${packs.path}/active.json');
  await active.writeAsString(
    canonicalJson({
      'schemaVersion': 1,
      'version': baselineId,
      'manifest': 'versions/$baselineId/manifest.json',
    }),
  );
  final candidate = Directory('${root.path}/candidate')..createSync();
  final candidateNotice = utf8.encode('staged');
  final candidateManifest = canonicalJson({
    'outputs': [
      {'path': 'NOTICE.txt', 'sha256': _sha256(candidateNotice)},
    ],
  });
  await File('${candidate.path}/NOTICE.txt').writeAsBytes(candidateNotice);
  await File('${candidate.path}/manifest.json')
      .writeAsString(candidateManifest);
  final pubspec = File('${root.path}/pubspec.yaml')
    ..writeAsStringSync(_pubspecText('old-generation'));
  return _MinimalTransactionHarness(
    packs: packs,
    candidate: candidate,
    pubspec: pubspec,
    baselineId: baselineId,
    candidateId: _sha256(
      await File('${candidate.path}/manifest.json').readAsBytes(),
    ),
    pointerBefore: await active.readAsString(),
    pubspecBefore: await pubspec.readAsString(),
  );
}

class _MinimalTransactionHarness {
  const _MinimalTransactionHarness({
    required this.packs,
    required this.candidate,
    required this.pubspec,
    required this.baselineId,
    required this.candidateId,
    required this.pointerBefore,
    required this.pubspecBefore,
  });

  final Directory packs;
  final Directory candidate;
  final File pubspec;
  final String baselineId;
  final String candidateId;
  final String pointerBefore;
  final String pubspecBefore;
}

enum _PublicationFault {
  beforePointer,
  afterPointer,
  beforePruneSideEffect,
  duringPrune,
}

class _PublicationOperationsFake implements MapPackPublicationOperations {
  _PublicationOperationsFake(this.harness, this.fault);

  final _MinimalTransactionHarness harness;
  final _PublicationFault fault;

  @override
  Future<void> stagePubspec(File temporary, String contents) async {
    await temporary.writeAsString(contents, flush: true);
  }

  @override
  Future<String> promote(Directory candidate, Directory packs) async {
    if (fault == _PublicationFault.beforePointer) {
      throw StateError('injected promotion failure');
    }
    final version = _sha256(
      await packFile(candidate, 'manifest.json').readAsBytes(),
    );
    final destination = Directory('${packs.path}/versions/$version');
    await _copyDirectory(candidate, destination);
    await File('${packs.path}/active.json').writeAsString(
      canonicalJson({
        'schemaVersion': 1,
        'version': version,
        'manifest': 'versions/$version/manifest.json',
      }),
    );
    if (fault == _PublicationFault.afterPointer) {
      throw StateError('injected post-pointer failure');
    }
    return version;
  }

  @override
  Future<void> renamePubspec(File temporary, File destination) async {
    await temporary.rename(destination.path);
  }

  @override
  Future<List<String>> prune(Directory packs, String activeId) async {
    final old = Directory('${packs.path}/versions/${harness.baselineId}');
    if (fault != _PublicationFault.beforePruneSideEffect) {
      await old.delete(recursive: true);
    }
    if (fault == _PublicationFault.duringPrune ||
        fault == _PublicationFault.beforePruneSideEffect) {
      throw StateError('injected prune failure');
    }
    return [harness.baselineId];
  }

  @override
  Future<void> cleanup(Directory candidate) async {
    await candidate.delete(recursive: true);
  }
}

class _BaselineChangeOperations implements MapPackPublicationOperations {
  _BaselineChangeOperations(this.harness);

  final _PublicationHarness harness;
  var promotionCalled = false;

  @override
  Future<void> stagePubspec(File temporary, String contents) async {
    final version = Directory(
      '${harness.packs.path}/versions/${harness.candidateId}',
    );
    await _copyDirectory(harness.candidate, version);
    await File('${harness.packs.path}/active.json').writeAsString(
      canonicalJson({
        'schemaVersion': 1,
        'version': harness.candidateId,
        'manifest': 'versions/${harness.candidateId}/manifest.json',
      }),
    );
    await temporary.writeAsString(contents, flush: true);
  }

  @override
  Future<String> promote(Directory candidate, Directory packs) async {
    promotionCalled = true;
    throw StateError('publication should reject the changed baseline');
  }

  @override
  Future<void> renamePubspec(File temporary, File destination) async {
    throw StateError('pubspec replacement was not expected');
  }

  @override
  Future<List<String>> prune(Directory packs, String activeId) async {
    throw StateError('pruning was not expected');
  }

  @override
  Future<void> cleanup(Directory candidate) async {
    throw StateError('candidate cleanup was not expected');
  }
}

void main() {
  group('validated staged-candidate publication', () {
    late Directory fixtureRoot;
    late Directory temporary;
    late _AdmittedStage admitted;

    setUpAll(() async {
      fixtureRoot = await Directory.systemTemp.createTemp(
        'blackgrid-artwork-publication-fixtures-',
      );
      admitted = await _createAdmittedStage(fixtureRoot);
    });

    tearDownAll(() => fixtureRoot.delete(recursive: true));

    setUp(() async {
      temporary = await Directory.systemTemp.createTemp(
        'blackgrid-artwork-publication-',
      );
    });

    tearDown(() => temporary.delete(recursive: true));

    test('publishesStagedCandidate', () async {
      final harness = await _privateHarness(admitted, temporary);
      await _changeBaselineAfterStaging(harness);
      final stagedManifest = await packFile(
        harness.candidate,
        'manifest.json',
      ).readAsBytes();
      final candidateManifest = await readManifest(harness.candidate);
      final reported = <String>[];

      final result = await publishStagedCandidate(
        harness.candidate,
        harness.packs,
        harness.pubspec,
        assetRoot: 'assets/maps',
        reviewedContext: admitted.context,
        log: reported.add,
      );

      expect(result.id, harness.candidateId);
      expect(result.changed, isTrue);
      expect(
        await File('${harness.packs.path}/active.json').readAsString(),
        canonicalJson({
          'schemaVersion': 1,
          'version': harness.candidateId,
          'manifest': 'versions/${harness.candidateId}/manifest.json',
        }),
      );
      final promoted = Directory(
        '${harness.packs.path}/versions/${harness.candidateId}',
      );
      expect(
        await packFile(promoted, 'manifest.json').readAsBytes(),
        stagedManifest,
      );
      for (final output in candidateManifest['outputs'] as List) {
        final path = output['path'] as String;
        expect(
          await packFile(promoted, path).readAsBytes(),
          await packFile(harness.candidate, path).readAsBytes(),
          reason: path,
        );
      }
      expect(await harness.candidate.exists(), isTrue);
      expect(
        await Directory('${harness.packs.path}/versions/${harness.baselineId}')
            .exists(),
        isFalse,
      );
      expect(
        await harness.pubspec.readAsString(),
        contains(harness.candidateId),
      );
      expect(
        reported,
        containsAll(
          packChangeReport(harness.baselineManifest, candidateManifest).lines,
        ),
      );
      final ownerInstruction = reported.singleWhere(
        (line) => line.contains('owner'),
      );
      expect(ownerInstruction, contains('before-merge'));
      expect(ownerInstruction, contains('check'));

      final pointerAfterPublication = await File(
        '${harness.packs.path}/active.json',
      ).readAsString();
      final pubspecAfterPublication = await harness.pubspec.readAsString();
      final replayLog = <String>[];
      final replay = await publishStagedCandidate(
        harness.candidate,
        harness.packs,
        harness.pubspec,
        assetRoot: 'assets/maps',
        reviewedContext: admitted.context,
        log: replayLog.add,
      );
      expect(replay.id, harness.candidateId);
      expect(replay.changed, isFalse);
      expect(
        await File('${harness.packs.path}/active.json').readAsString(),
        pointerAfterPublication,
      );
      expect(await harness.pubspec.readAsString(), pubspecAfterPublication);
      expect(await harness.candidate.exists(), isTrue);
      final noChangeInstruction = replayLog.singleWhere(
        (line) => line.contains('owner'),
      );
      expect(noChangeInstruction, contains('toolchain'));
      expect(noChangeInstruction, contains('no owner check is needed'));
    }, tags: ['qualification']);

    test('changedCurrentBaselineOwnershipRejectsBeforeWrites', () async {
      final root = Directory('${temporary.path}/baseline-ownership')
        ..createSync(recursive: true);
      final harness = await _privateHarness(admitted, root);
      await _changeBaselineAfterStaging(harness, changeOwnership: true);

      await expectLater(
        publishStagedCandidate(
          harness.candidate,
          harness.packs,
          harness.pubspec,
          assetRoot: 'assets/maps',
          reviewedContext: admitted.context,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'current baseline ownership',
            contains('changed reviewed marker ownership'),
          ),
        ),
      );

      expect(
        await File('${harness.packs.path}/active.json').readAsString(),
        harness.pointerBefore,
      );
      expect(await harness.pubspec.readAsString(), harness.pubspecBefore);
      expect(await File('${harness.pubspec.path}.tmp').exists(), isFalse);
      expect(await harness.candidate.exists(), isTrue);
      expect(
        await verifyCommittedGeneration(harness.packs)
            .then((active) => active.id),
        harness.baselineId,
      );
    }, tags: ['qualification']);

    test('invalidCandidateOrBaselineDoesNotWrite', () async {
      for (final corruption in ['evidence', 'output']) {
        final root = Directory('${temporary.path}/$corruption')
          ..createSync(recursive: true);
        final harness = await _privateHarness(
          admitted,
          root,
          corruptEvidence: corruption == 'evidence',
          corruptOutput: corruption == 'output',
        );
        final outputPath =
            ((await readManifest(harness.candidate))['outputs'] as List)
                    .cast<Map<String, dynamic>>()
                    .firstWhere(
                      (output) =>
                          (output['path'] as String).endsWith('/0/0.png'),
                    )['path']
                as String;
        await expectLater(
          publishStagedCandidate(
            harness.candidate,
            harness.packs,
            harness.pubspec,
            assetRoot: 'assets/maps',
            reviewedContext: admitted.context,
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'affected evidence or output',
              contains(
                corruption == 'evidence' ? 'calibration.json' : outputPath,
              ),
            ),
          ),
        );
        expect(
          await File('${harness.packs.path}/active.json').readAsString(),
          harness.pointerBefore,
        );
        expect(await harness.pubspec.readAsString(), harness.pubspecBefore);
        expect(
          await verifyCommittedGeneration(harness.packs)
              .then((active) => active.id),
          harness.baselineId,
        );
      }

      for (final field in [
        'primaryUrls',
        'primaryRepositoryRevisions',
        'primaryGitBlobs',
        'primaryHashes',
        'primaryProvenance',
      ]) {
        final root = Directory('${temporary.path}/reviewed-$field')
          ..createSync(recursive: true);
        final harness = await _privateHarness(admitted, root);
        final sourceLock = jsonDecode(
          canonicalJson(admitted.context.sourceLock),
        ) as Map<String, dynamic>;
        final values = (sourceLock[field] as Map).cast<String, dynamic>();
        values['metadata/maps.json'] = 'altered-reviewed-$field';
        final alteredContext = MapBuildContext.reviewed(
          calibration: admitted.context.calibration,
          sourceLock: sourceLock,
          noticeBytes: admitted.context.noticeBytes,
        );
        await expectLater(
          publishStagedCandidate(
            harness.candidate,
            harness.packs,
            harness.pubspec,
            assetRoot: 'assets/maps',
            reviewedContext: alteredContext,
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'current reviewed source admission',
              contains('metadata/maps.json'),
            ),
          ),
        );
        expect(
          await File('${harness.packs.path}/active.json').readAsString(),
          harness.pointerBefore,
        );
        expect(await harness.pubspec.readAsString(), harness.pubspecBefore);
      }

      final invalidRoot = Directory('${temporary.path}/invalid-baseline')
        ..createSync(recursive: true);
      final invalid = await _privateHarness(admitted, invalidRoot);
      await packFile(
        Directory('${invalid.packs.path}/versions/${invalid.baselineId}'),
        'NOTICE.txt',
      ).writeAsBytes([0]);
      await expectLater(
        publishStagedCandidate(
          invalid.candidate,
          invalid.packs,
          invalid.pubspec,
          assetRoot: 'assets/maps',
          reviewedContext: admitted.context,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'invalid baseline output',
            contains('NOTICE.txt'),
          ),
        ),
      );
      expect(
        await File('${invalid.packs.path}/active.json').readAsString(),
        invalid.pointerBefore,
      );
      expect(await invalid.pubspec.readAsString(), invalid.pubspecBefore);
    }, tags: ['qualification']);
    test('sequentialBaselineChangeDuringPublicationIsRefused', () async {
      final harness = await _privateHarness(
        admitted,
        Directory('${temporary.path}/baseline-race')
          ..createSync(recursive: true),
      );
      final operations = _BaselineChangeOperations(harness);
      await expectLater(
        publishStagedCandidate(
          harness.candidate,
          harness.packs,
          harness.pubspec,
          assetRoot: 'assets/maps',
          reviewedContext: admitted.context,
          operations: operations,
        ),
        throwsA(
          isA<MapPackRefreshFailure>().having(
            (error) => error.message,
            'sequential baseline recheck',
            allOf(
              contains('baseline changed'),
              contains('Candidate kept at ${harness.candidate.path}'),
            ),
          ),
        ),
      );
      final active = jsonDecode(
        await File('${harness.packs.path}/active.json').readAsString(),
      ) as Map<String, dynamic>;
      expect(active['version'], harness.candidateId);
      expect(operations.promotionCalled, isFalse);
      expect(await harness.pubspec.readAsString(), harness.pubspecBefore);
      expect(await File('${harness.pubspec.path}.tmp').exists(), isFalse);
      expect(await harness.candidate.exists(), isTrue);
    }, tags: ['qualification']);
  });

  test('reportsPublicationRecoveryPhases', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'blackgrid-publication-transaction-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    for (final fault in _PublicationFault.values) {
      final root = Directory('${temporary.path}/${fault.name}')
        ..createSync(recursive: true);
      final harness = await _minimalTransactionHarness(root);
      await expectLater(
        runMapPackPublicationTransaction(
          candidate: harness.candidate,
          packs: harness.packs,
          pubspec: harness.pubspec,
          assetRoot: 'custom/maps',
          operations: _PublicationOperationsFake(harness, fault),
        ),
        throwsA(
          isA<MapPackRefreshFailure>().having(
            (error) => error.message,
            'actual publication phase and recovery',
            allOf(
              contains(switch (fault) {
                _PublicationFault.beforePointer =>
                  'active pointer remains unchanged',
                _PublicationFault.afterPointer => 'active.json already names',
                _PublicationFault.beforePruneSideEffect ||
                _PublicationFault.duringPrune =>
                  'active.json and pubspec.yaml already name',
              }),
              contains('Candidate kept at ${harness.candidate.path}'),
              predicate<String>(
                (message) =>
                    message.contains(harness.packs.path) &&
                    message.contains(harness.pubspec.path) &&
                    !message.contains('mise run maps:rebuild'),
              ),
              predicate<String>(
                (message) =>
                    fault != _PublicationFault.beforePruneSideEffect ||
                    message.contains(
                      'Remaining generations: ${harness.baselineId}',
                    ),
              ),
            ),
          ),
        ),
      );
      expect(await harness.candidate.exists(), isTrue);
      final pointer = jsonDecode(
        await File('${harness.packs.path}/active.json').readAsString(),
      ) as Map<String, dynamic>;
      if (fault == _PublicationFault.beforePointer) {
        expect(pointer['version'], harness.baselineId);
        expect(await harness.pubspec.readAsString(), harness.pubspecBefore);
      } else if (fault == _PublicationFault.afterPointer) {
        expect(pointer['version'], harness.candidateId);
        expect(await harness.pubspec.readAsString(), harness.pubspecBefore);
      } else {
        expect(pointer['version'], harness.candidateId);
        expect(
          await harness.pubspec.readAsString(),
          contains(harness.candidateId),
        );
        expect(
          await Directory(
            '${harness.packs.path}/versions/${harness.baselineId}',
          ).exists(),
          fault == _PublicationFault.beforePruneSideEffect,
        );
      }
    }
  });
}

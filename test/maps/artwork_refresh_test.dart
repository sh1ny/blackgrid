import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image;
import 'package:test/test.dart';

import '../../tool/maps/calibration.dart';
import '../../tool/maps/pack.dart';
import '../support/map_preparation_fixtures.dart';

String _hash(List<int> bytes) => sha256.convert(bytes).toString();
Map<String, dynamic> _identity(String name) => {
  'normalizedName': name,
  'maps': [
    {'key': name, 'projection': 'interactive'},
  ],
};

Future<MapPreparationFixtures>? _fixturesFuture;
Directory? _fixtureRoot;

Future<MapPreparationFixtures> _fixtures() =>
    _fixturesFuture ??= MapPreparationFixtures.create(_fixtureRoot!);

class _StageTransport {
  _StageTransport(this.raw, this.routes);

  final Directory raw;
  final Map<Uri, String> routes;
  final Map<String, List<int>> overrides = {};
  final requested = <Uri>[];
  Uri? changedTile;
  Uri? failingUri;

  Future<Uint8List> call(Uri uri) async {
    requested.add(uri);
    if (uri == failingUri) {
      throw HttpException('injected source failure: $uri', uri: uri);
    }
    final path = routes[uri];
    if (path == null) {
      throw HttpException('unexpected source request: $uri', uri: uri);
    }
    final override = overrides[path];
    final bytes = override == null
        ? await File('${raw.path}/$path').readAsBytes()
        : Uint8List.fromList(override);
    if (uri != changedTile) return bytes;
    final decoded = image.decodePng(bytes)!;
    decoded.setPixelRgba(1, 1, 240, 30, 20, 255);
    return Uint8List.fromList(image.encodePng(decoded));
  }
}

class _StageHarness {
  _StageHarness({
    required this.root,
    required this.packs,
    required this.pubspec,
    required this.stage,
    required this.context,
    required this.transport,
    required this.baseline,
  });

  final Directory root;
  final Directory packs;
  final File pubspec;
  final Directory stage;
  final MapBuildContext context;
  final _StageTransport transport;
  final CommittedGeneration baseline;

  Future<String> activePointer() =>
      File('${packs.path}/active.json').readAsString();

  Future<String> baselineManifest() =>
      packFile(baseline.directory, 'manifest.json').readAsString();

  Future<void> expectUnchanged({
    required String pointer,
    required String manifest,
    required String pubspecText,
  }) async {
    expect(await activePointer(), pointer);
    expect(await baselineManifest(), manifest);
    expect(await pubspec.readAsString(), pubspecText);
    expect((await verifyCommittedGeneration(packs)).id, baseline.id);
  }
}

Future<_StageHarness> _stageHarness({
  bool isolatedRaw = false,
  bool nonCanonicalBaselineCalibration = false,
}) async {
  final fixtures = await _fixtures();
  final root = await Directory.systemTemp.createTemp(
    'blackgrid-artwork-refresh-stage-',
  );
  addTearDown(() => root.delete(recursive: true));
  final packs = Directory('${root.path}/packs');
  final versions = Directory('${packs.path}/versions');
  await versions.create(recursive: true);
  final sourceManifest = File('${fixtures.first.path}/manifest.json');
  final manifestBytes = await sourceManifest.readAsBytes();
  var id = _hash(manifestBytes);
  var baselineDirectory = Directory('${versions.path}/$id');
  await copyPack(fixtures.first, baselineDirectory);
  if (nonCanonicalBaselineCalibration) {
    final calibrationFile = packFile(
      baselineDirectory,
      'evidence/calibration.json',
    );
    final calibration = jsonDecode(await calibrationFile.readAsString());
    final calibrationBytes = utf8.encode('${canonicalJson(calibration)}\n');
    await calibrationFile.writeAsBytes(calibrationBytes);
    final sourceIndexFile = packFile(
      baselineDirectory,
      'evidence/sources.json',
    );
    final sourceIndex = jsonDecode(
      await sourceIndexFile.readAsString(),
    ) as Map<String, dynamic>;
    final calibrationRecord = (sourceIndex['sources'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((source) => source['path'] == 'calibration.json');
    calibrationRecord['sha256'] = _hash(calibrationBytes);
    final sourceIndexBytes = utf8.encode(canonicalJson(sourceIndex));
    await sourceIndexFile.writeAsBytes(sourceIndexBytes);
    final manifest = jsonDecode(
      await packFile(baselineDirectory, 'manifest.json').readAsString(),
    ) as Map<String, dynamic>;
    manifest['sourceGeneration'] = _hash(sourceIndexBytes);
    await saveManifest(baselineDirectory, manifest, refreshOutputs: true);
    id = _hash(
      await packFile(baselineDirectory, 'manifest.json').readAsBytes(),
    );
    final rehashedDirectory = Directory('${versions.path}/$id');
    await baselineDirectory.rename(rehashedDirectory.path);
    baselineDirectory = rehashedDirectory;
  }
  await File('${packs.path}/active.json').writeAsString(
    canonicalJson({
      'schemaVersion': 1,
      'version': id,
      'manifest': 'versions/$id/manifest.json',
    }),
  );
  final pubspec = File('${root.path}/pubspec.yaml');
  await pubspec.writeAsString(
    [
      'name: fixture',
      'flutter:',
      '  assets:',
      '    - assets/app_icon/',
      mapPackAssetsBegin,
      '    - assets/maps/versions/old/',
      mapPackAssetsEnd,
      '    - assets/other/',
      '',
    ].join(String.fromCharCode(10)),
  );
  final stage = Directory('${root.path}/stage');

  final raw = isolatedRaw ? Directory('${root.path}/raw') : fixtures.raw;
  if (isolatedRaw) await copyPack(fixtures.raw, raw);
  final extraSources = {
    'terms/tarkov-dev-README.md': utf8.encode(
      'Fixture reviewed project README',
    ),
    'terms/tarkov-dev-software-LICENSE.txt': utf8.encode(
      'Fixture reviewed software license',
    ),
    'terms/tarkovbot-creator.html': utf8.encode('Fixture reviewed terms page'),
  };
  final baseContext = MapBuildContext.reviewedConfiguration();
  final primaryHashes = <String, String>{
    for (final path
        in (baseContext.sourceLock['primaryHashes'] as Map<String, dynamic>)
            .entries)
      path.key: path.value as String,
  };
  for (final path in primaryHashes.keys.toList()) {
    final bytes = extraSources[path] ?? await packFile(raw, path).readAsBytes();
    primaryHashes[path] = _hash(bytes);
  }
  final sourceLock =
      jsonDecode(canonicalJson(baseContext.sourceLock)) as Map<String, dynamic>;
  sourceLock['primaryHashes'] = primaryHashes;
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
    await packFile(raw, 'metadata/maps.json').readAsString(),
  ) as List;
  for (final rawLocal in context.calibration['maps'] as List) {
    final local = Map<String, Object?>.from(rawLocal as Map);
    final upstream = interactiveMetadata(
      metadata,
      local['sourceKey'] as String,
    );
    final floors = reconcileFloors(local, upstream);
    final resources = [
      for (final floor in floors)
        if (floor['sourceTileUrl'] != null) floor,
      for (final dependency in (local['rasterDependencies'] as List? ?? []))
        {
          ...Map<String, Object?>.from(dependency as Map),
          'id': 'dependency-${dependency['id']}',
        },
    ];
    for (final floor in resources) {
      for (var x = 0; x < 16; x++) {
        for (var y = 0; y < 16; y++) {
          routes.putIfAbsent(
            Uri.parse(tileUrl(floor['sourceTileUrl'] as String, x, y)),
            () =>
                rawTilePath(local['id'] as String, floor['id'] as String, x, y),
          );
        }
      }
    }
  }
  final transport = _StageTransport(raw, routes)
    ..overrides.addAll(extraSources);
  final tileEntry = routes.entries
      .where(
        (entry) =>
            entry.value.startsWith('tiles/') &&
            entry.value.endsWith('/0/0.png'),
      )
      .first;
  transport.changedTile = tileEntry.key;
  return _StageHarness(
    root: root,
    packs: packs,
    pubspec: pubspec,
    stage: stage,
    context: context,
    transport: transport,
    baseline: await verifyCommittedGeneration(packs),
  );
}

Future<
  ({
    Directory candidate,
    Map<String, dynamic> manifest,
    PackChangeReport report,
    List<String> diagnostics,
  })
>
_runStage(
  _StageHarness harness, {
  MapBuildContext? context,
  bool reviewedCalibrationUpdate = false,
  Directory? stage,
}) => stageArtworkRefresh(
  harness.packs,
  harness.pubspec,
  stage: stage ?? harness.stage,
  toolchain: fixtureToolchain,
  fetch: harness.transport.call,
  reviewedContext: context ?? harness.context,
  reviewedCalibrationUpdate: reviewedCalibrationUpdate,
);

void main() {
  group('fresh artwork source admission', () {
    test('changedLockNamesBothHashes', () {
      final bytes = utf8.encode('observed bytes');
      final observedHash = _hash(bytes);
      final approvedHash = _hash(utf8.encode('approved bytes'));
      final record = <String, dynamic>{
        'path': 'metadata/maps.json',
        'url': 'https://reviewed.example/maps.json',
        'sha256': observedHash,
        'repositoryRevision': 'reviewed-revision',
        'gitBlobSha1': 'reviewed-blob',
      };
      final mismatchRecords = <(String, Map<String, dynamic>, String)>[
        ('path', {...record, 'path': 'metadata/other.json'}, 'identity'),
        (
          'URL',
          {...record, 'url': 'https://reviewed.example/other.json'},
          'URL',
        ),
        (
          'revision',
          {...record, 'repositoryRevision': 'other-revision'},
          'repository revision',
        ),
        ('blob', {...record, 'gitBlobSha1': 'other-blob'}, 'Git blob'),
        (
          'recorded hash',
          {...record, 'sha256': approvedHash},
          'recorded SHA-256',
        ),
      ];
      for (final (name, source, detail) in mismatchRecords) {
        expect(
          () => validateLockedSourceRecord(
            path: 'metadata/maps.json',
            source: source,
            bytes: bytes,
            expectedUrl: 'https://reviewed.example/maps.json',
            expectedSha256: observedHash,
            expectedRepositoryRevision: 'reviewed-revision',
            expectedGitBlobSha1: 'reviewed-blob',
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              allOf(contains('metadata/maps.json'), contains(detail)),
            ),
          ),
          reason: name,
        );
      }

      expect(
        () => validateLockedSourceRecord(
          path: 'metadata/maps.json',
          source: record,
          bytes: bytes,
          expectedUrl: 'https://reviewed.example/maps.json',
          expectedSha256: approvedHash,
          expectedRepositoryRevision: 'reviewed-revision',
          expectedGitBlobSha1: 'reviewed-blob',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('metadata/maps.json'),
              contains(approvedHash),
              contains(observedHash),
            ),
          ),
        ),
      );
    });

    test('lockedSourceIdentityValidator', () {
      final bytes = utf8.encode('reviewed bytes');
      final hash = _hash(bytes);
      expect(
        () => validateLockedSourceRecord(
          path: 'terms/example-LICENSE.txt',
          source: {
            'path': 'terms/example-LICENSE.txt',
            'url': 'https://reviewed.example/LICENSE.txt',
            'sha256': hash,
            'repositoryRevision': 'reviewed-revision',
            'gitBlobSha1': 'reviewed-blob',
            'provenance': 'reviewed repository source',
          },
          bytes: bytes,
          expectedUrl: 'https://reviewed.example/LICENSE.txt',
          expectedSha256: hash,
          expectedRepositoryRevision: 'reviewed-revision',
          expectedGitBlobSha1: 'reviewed-blob',
        ),
        returnsNormally,
      );

      expect(
        () => validateLockedSourceRecord(
          path: 'terms/example-LICENSE.txt',
          source: {
            'path': 'terms/example-LICENSE.txt',
            'url': 'https://reviewed.example/other-LICENSE.txt',
            'sha256': hash,
            'repositoryRevision': 'reviewed-revision',
            'gitBlobSha1': 'reviewed-blob',
          },
          bytes: bytes,
          expectedUrl: 'https://reviewed.example/LICENSE.txt',
          expectedSha256: hash,
          expectedRepositoryRevision: 'reviewed-revision',
          expectedGitBlobSha1: 'reviewed-blob',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('terms/example-LICENSE.txt'),
          ),
        ),
      );
      expect(
        () => validateRasterTileSourceUrl(
          path: 'tiles/customs/Fourth_Floor/0/0.png',
          observedUrl: 'https://assets.example/4/1/0.png',
          expectedUrl: 'https://assets.example/4/0/0.png',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('tiles/customs/Fourth_Floor/0/0.png'),
          ),
        ),
      );
      final interchangeBytes = utf8.encode('pinned repository bytes');
      final revision = '0123456789012345678901234567890123456789';
      final blob = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final pinnedUrl =
          'https://raw.githubusercontent.com/the-hideout/tarkov-dev-svg-maps/'
          '$revision/Interchange.svg';
      expect(
        () => validateLockedSourceRecord(
          path: 'interchange/Interchange.svg',
          source: {
            'path': 'interchange/Interchange.svg',
            'url': pinnedUrl,
            'sha256': _hash(interchangeBytes),
            'repositoryRevision': revision,
            'gitBlobSha1': blob,
            'servedUrl': 'https://assets.tarkov.dev/maps/svg/Interchange.svg',
          },
          bytes: interchangeBytes,
          expectedUrl: pinnedUrl,
          expectedSha256: _hash(interchangeBytes),
          expectedRepositoryRevision: revision,
          expectedGitBlobSha1: blob,
        ),
        returnsNormally,
      );
    });

    test('calibrationSelectionNamesDefaultMismatch', () {
      final baseline = {
        'schemaVersion': 1,
        'maps': [
          {
            'id': 'interchange',
            'sourceKey': 'interchange',
            'geometry': {
              'affine': [1, 2, 3, 4],
            },
          },
        ],
      };
      final reviewed = {
        'schemaVersion': 1,
        'maps': [
          {
            'id': 'interchange',
            'sourceKey': 'interchange',
            'geometry': {
              'affine': [5, 2, 3, 4],
            },
          },
        ],
      };

      expect(
        selectArtworkRefreshCalibration(baseline: baseline, reviewed: baseline),
        baseline,
      );
      expect(
        () => selectArtworkRefreshCalibration(
          baseline: baseline,
          reviewed: reviewed,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            allOf(contains('interchange'), contains('geometry.affine')),
          ),
        ),
      );
      expect(
        selectArtworkRefreshCalibration(
          baseline: baseline,
          reviewed: reviewed,
          reviewedCalibrationUpdate: true,
        ),
        reviewed,
      );
    });

    test('freshIdentityDiagnostics', () {
      const supported = ['customs', 'interchange'];
      final baseline = [_identity('customs'), _identity('legacy-unsupported')];
      final current = [
        _identity('customs'),
        _identity('interchange'),
        _identity('new-upstream-map'),
        _identity('legacy-unsupported'),
      ];

      final diagnostics = validateFreshMapIdentities(
        current,
        baseline,
        supportedSourceKeys: supported,
      );
      expect(diagnostics, hasLength(1));
      expect(diagnostics.single, contains('new-upstream-map'));
      expect(diagnostics.single, contains('authored tool'));
      expect(diagnostics.single, contains('runtime integration'));
      expect(diagnostics.single, contains('before it can be selected'));

      final invalid = <(String, List<dynamic>, String)>[
        ('missing', [_identity('customs')], 'interchange'),
        (
          'duplicate',
          [
            _identity('customs'),
            _identity('customs'),
            _identity('interchange'),
          ],
          'customs',
        ),
        (
          'malformed identity',
          [
            _identity('customs'),
            {'normalizedName': 42},
          ],
          '42',
        ),
        (
          'missing interactive projection',
          [
            _identity('customs'),
            {'normalizedName': 'interchange', 'maps': []},
          ],
          'interchange',
        ),
        (
          'ambiguous interactive projection',
          [
            _identity('customs'),
            {
              'normalizedName': 'interchange',
              'maps': [
                {'key': 'interchange', 'projection': 'interactive'},
                {'key': 'interchange', 'projection': 'interactive'},
              ],
            },
          ],
          'interchange',
        ),
      ];
      for (final (reason, metadata, identity) in invalid) {
        expect(
          () => validateFreshMapIdentities(
            metadata,
            baseline,
            supportedSourceKeys: supported,
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains(identity),
            ),
          ),
          reason: reason,
        );
      }
    });
  });

  group('fresh artwork staging', () {
    setUpAll(() async {
      _fixtureRoot = await Directory.systemTemp.createTemp(
        'blackgrid-artwork-refresh-fixtures-',
      );
      _fixturesFuture = MapPreparationFixtures.create(_fixtureRoot!);
      await _fixturesFuture;
    });
    tearDownAll(() async {
      await _fixtureRoot?.delete(recursive: true);
      _fixtureRoot = null;
      _fixturesFuture = null;
    });
    test('calibrationAndOwnershipMismatchRejected', () async {
      final harness = await _stageHarness();
      final pointer = await harness.activePointer();
      final activeManifest = await harness.baselineManifest();
      final pubspec = await harness.pubspec.readAsString();
      final changedCalibration = jsonDecode(
        canonicalJson(harness.context.calibration),
      ) as Map<String, dynamic>;
      final interchangeCalibration = (changedCalibration['maps'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((map) => map['sourceKey'] == 'interchange');
      (interchangeCalibration['geometry']['affine'] as List)[0] =
          (interchangeCalibration['geometry']['affine'][0] as num) + 1;
      final changedContext = MapBuildContext.reviewed(
        calibration: changedCalibration,
        sourceLock: harness.context.sourceLock,
        noticeBytes: harness.context.noticeBytes,
      );
      await expectLater(
        _runStage(harness, context: changedContext),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            allOf(contains('interchange'), contains('geometry.affine')),
          ),
        ),
      );
      await harness.expectUnchanged(
        pointer: pointer,
        manifest: activeManifest,
        pubspecText: pubspec,
      );

      final fixtures = await _fixtures();
      final baseline = await readManifest(fixtures.first);
      final baselineMap = (baseline['maps'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((map) => map['id'] == 'interchange');
      final mapId = baselineMap['id'] as String;
      final baselineMarker = (baselineMap['markers'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((marker) => marker['source']['floorAssignment'] != null);
      final markerId = baselineMarker['id'] as String;
      final originalFloorId =
          baselineMarker['source']['floorAssignment']['floorId'] as String;
      final changedFloorId = originalFloorId == 'Second_Floor'
          ? 'Third_Floor'
          : 'Second_Floor';

      Map<String, dynamic> copy() =>
          jsonDecode(canonicalJson(baseline)) as Map<String, dynamic>;
      Map<String, dynamic> selectedMarker(Map<String, dynamic> manifest) =>
          ((manifest['maps'] as List).cast<Map<String, dynamic>>().singleWhere(
                    (map) => map['id'] == mapId,
                  )['markers']
                  as List)
              .cast<Map<String, dynamic>>()
              .singleWhere((marker) => marker['id'] == markerId);

      expect(
        () => validateArtworkOwnershipPreservation(baseline, baseline),
        returnsNormally,
      );

      final removed = copy();
      ((removed['maps'] as List).cast<Map<String, dynamic>>().singleWhere(
                (map) => map['id'] == mapId,
              )['markers']
              as List)
          .removeWhere((marker) => marker['id'] == markerId);
      final assignmentRemoved = copy();
      selectedMarker(assignmentRemoved)['source']['floorAssignment'] = null;
      selectedMarker(assignmentRemoved).remove('floorId');
      final changedAssignment = copy();
      selectedMarker(
        changedAssignment,
      )['source']['floorAssignment']['floorId'] = changedFloorId;
      selectedMarker(changedAssignment)['floorId'] = changedFloorId;
      final changedVolume = copy();
      selectedMarker(changedVolume)['position']['x'] =
          (selectedMarker(changedVolume)['position']['x'] as num) + 1;

      for (final (label, candidate) in [
        ('removed', removed),
        ('assignment removed', assignmentRemoved),
        ('assignment changed', changedAssignment),
        ('owned volume changed', changedVolume),
      ]) {
        await expectLater(
          Future<void>.sync(
            () => validateArtworkOwnershipPreservation(baseline, candidate),
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              allOf(contains(mapId), contains(markerId)),
            ),
          ),
          reason: label,
        );
      }
      harness.transport.changedTile = null;
      final reviewedCalibration = jsonDecode(
        canonicalJson(harness.context.calibration),
      ) as Map<String, dynamic>;
      final reviewedInterchange = (reviewedCalibration['maps'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((map) => map['sourceKey'] == 'interchange');
      final assignments = Map<String, Object?>.from(
        reviewedInterchange['markerFloorAssignments'] as Map,
      );
      final reviewedAssignment = Map<String, Object?>.from(
        assignments.values.single as Map,
      );
      reviewedAssignment['floorId'] = changedFloorId;
      assignments[assignments.keys.single] = reviewedAssignment;
      reviewedInterchange['markerFloorAssignments'] = assignments;
      final ownershipContext = MapBuildContext.reviewed(
        calibration: reviewedCalibration,
        sourceLock: harness.context.sourceLock,
        noticeBytes: harness.context.noticeBytes,
      );
      await expectLater(
        _runStage(
          harness,
          context: ownershipContext,
          reviewedCalibrationUpdate: true,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('reviewed marker ownership'),
              contains('interchange'),
              contains(markerId),
            ),
          ),
        ),
      );
      expect(
        await packFile(harness.stage, 'manifest.json').exists(),
        isFalse,
        reason: 'an ownership-rejected build is not a ready candidate',
      );
      await harness.expectUnchanged(
        pointer: pointer,
        manifest: activeManifest,
        pubspecText: pubspec,
      );
    }, tags: ['qualification']);

    test('changedArtworkStages', () async {
      final harness = await _stageHarness();
      final pointer = await harness.activePointer();
      final activeManifest = await harness.baselineManifest();
      final pubspec = await harness.pubspec.readAsString();
      final sourcePath =
          harness.transport.routes[harness.transport.changedTile]!;
      final parts = sourcePath.split('/');
      final artworkPath =
          'artwork/${parts[1]}/${parts[2]}/${parts[3]}/${parts[4]}';

      final staged = await _runStage(
        harness,
        stage: Directory('${harness.stage.path}${Platform.pathSeparator}'),
      );

      expect(staged.diagnostics, isEmpty);
      expect(staged.report.changed, isTrue);
      expect(staged.report.paths, contains(artworkPath));
      expect(
        staged.report.lines,
        contains(contains('${parts[1]} ${parts[2]}: 1 changed file(s)')),
      );
      expect(
        staged.report.valueKeys,
        contains('${parts[1]} ${parts[2]} values'),
      );
      expect(await packFile(staged.candidate, artworkPath).exists(), isTrue);
      expect(
        (staged.manifest['maps'] as List).map((map) => map['id']).toList(),
        supportedMapSources.keys.toList(),
      );
      await harness.expectUnchanged(
        pointer: pointer,
        manifest: activeManifest,
        pubspecText: pubspec,
      );
    }, tags: ['qualification']);

    group('unchangedAndEvidenceOnlyStage', () {
      late _StageHarness sharedHarness;
      late String pointer;
      late String activeManifest;
      late String pubspec;
      late Uint8List baselineCalibrationBytes;
      late ({
        Directory candidate,
        Map<String, dynamic> manifest,
        PackChangeReport report,
        List<String> diagnostics,
      })
      staged;

      setUpAll(() async {
        sharedHarness = await _stageHarness(
          nonCanonicalBaselineCalibration: true,
        );
        sharedHarness.transport.changedTile = null;
        pointer = await sharedHarness.activePointer();
        activeManifest = await sharedHarness.baselineManifest();
        baselineCalibrationBytes = await packFile(
          sharedHarness.baseline.directory,
          'evidence/calibration.json',
        ).readAsBytes();
        pubspec = await sharedHarness.pubspec.readAsString();
        staged = await _runStage(sharedHarness);
      });

      test('evidenceOnlyStage', () async {
        expect(staged.report.changed, isTrue);
        expect(staged.report.paths, contains('evidence/sources.json'));
        expect(
          staged.report.paths.every((path) => !path.startsWith('artwork/')),
          isTrue,
        );
        expect(staged.report.valueKeys, contains('sourceGeneration'));
        expect(staged.diagnostics, isEmpty);
        expect(
          await packFile(
            staged.candidate,
            'evidence/calibration.json',
          ).readAsBytes(),
          baselineCalibrationBytes,
        );
        await sharedHarness.expectUnchanged(
          pointer: pointer,
          manifest: activeManifest,
          pubspecText: pubspec,
        );
      }, tags: ['qualification']);

      test('unchangedStage', () async {
        final harness = await _stageHarness();
        harness.transport.changedTile = null;
        final promotedId = await promoteCandidate(
          staged.candidate,
          harness.packs,
        );
        final promotedPointer = await harness.activePointer();
        final promoted = await verifyCommittedGeneration(harness.packs);
        final promotedManifest = await packFile(
          promoted.directory,
          'manifest.json',
        ).readAsBytes();
        final promotedPubspec = await harness.pubspec.readAsBytes();
        final unchanged = await _runStage(harness);
        expect(unchanged.report.changed, isFalse);
        expect(unchanged.report.paths, isEmpty);
        expect(unchanged.report.valueKeys, isEmpty);
        expect(await harness.activePointer(), promotedPointer);
        expect(
          await packFile(promoted.directory, 'manifest.json').readAsBytes(),
          promotedManifest,
        );
        expect(await harness.pubspec.readAsBytes(), promotedPubspec);
        expect(promoted.id, promotedId);
        expect((await verifyCommittedGeneration(harness.packs)).id, promotedId);
      }, tags: ['qualification']);
    });

    test('retainsSixAndSelectsReviewedCalibration', () async {
      final harness = await _stageHarness();
      harness.transport.changedTile = null;
      final updatedCalibration = jsonDecode(
        canonicalJson(harness.context.calibration),
      ) as Map<String, dynamic>;
      final updatedMap = (updatedCalibration['maps'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((map) => map['sourceKey'] == 'interchange');
      final updatedFloor = (updatedMap['floors'] as List)
          .cast<Map<String, dynamic>>()
          .first;
      updatedFloor['label'] = 'Reviewed fixture calibration update';
      final reviewedNoticeBytes = utf8.encode(
        'Reviewed artwork refresh notice bytes\n',
      );
      final updatedContext = MapBuildContext.reviewed(
        calibration: updatedCalibration,
        sourceLock: harness.context.sourceLock,
        noticeBytes: reviewedNoticeBytes,
      );
      final staged = await _runStage(
        harness,
        context: updatedContext,
        reviewedCalibrationUpdate: true,
      );
      const retained = [
        'markers/maps.json',
        'markers/maps_en.json',
        'quests/tasks.json',
        'quests/tasks_en.json',
        'quests/traders.json',
        'quests/traders_en.json',
      ];
      for (final path in retained) {
        expect(
          await packFile(staged.candidate, 'evidence/$path').readAsBytes(),
          await packFile(
            harness.baseline.directory,
            'evidence/$path',
          ).readAsBytes(),
          reason: path,
        );
      }
      expect(
        await packFile(
          staged.candidate,
          'evidence/calibration.json',
        ).readAsBytes(),
        utf8.encode(canonicalJson(updatedCalibration)),
      );
      expect(
        await packFile(staged.candidate, 'NOTICE.txt').readAsBytes(),
        reviewedNoticeBytes,
      );
      expect(
        harness.transport.requested.any(
          (uri) => uri.toString().contains('/regular/'),
        ),
        isFalse,
      );
    }, tags: ['qualification']);

    test('supportedAndNewIdentities', () async {
      final harness = await _stageHarness();
      harness.transport.changedTile = null;
      final metadataFile = packFile(
        harness.transport.raw,
        'metadata/maps.json',
      );
      final metadata = jsonDecode(await metadataFile.readAsString()) as List;
      metadata.add(_identity('new-upstream-map'));
      final metadataBytes = utf8.encode(jsonEncode(metadata));
      harness.transport.overrides['metadata/maps.json'] = metadataBytes;
      final sourceLock = jsonDecode(
        canonicalJson(harness.context.sourceLock),
      ) as Map<String, dynamic>;
      final hashes = Map<String, String>.from(
        (sourceLock['primaryHashes'] as Map).cast<String, String>(),
      )..['metadata/maps.json'] = _hash(metadataBytes);
      sourceLock['primaryHashes'] = hashes;
      final context = MapBuildContext.reviewed(
        calibration: harness.context.calibration,
        sourceLock: sourceLock,
        noticeBytes: harness.context.noticeBytes,
      );

      final staged = await _runStage(harness, context: context);

      expect(
        staged.diagnostics,
        contains(
          allOf(
            contains('new-upstream-map'),
            contains('authored tool'),
            contains('runtime'),
          ),
        ),
      );
      expect(
        (staged.manifest['supportedMapIds'] as List),
        supportedMapSources.keys.toList(),
      );
      expect(
        (staged.manifest['maps'] as List).any(
          (map) => map['sourceKey'] == 'new-upstream-map',
        ),
        isFalse,
      );
    }, tags: ['qualification']);

    test('distinctInvalidTileIsRejectedAfterValidTiles', () async {
      final harness = await _stageHarness();
      harness.transport.changedTile = null;
      final tiles = harness.transport.routes.entries
          .where((entry) => entry.value.startsWith('tiles/'))
          .toList();
      final invalidTile = tiles.last;
      harness.transport.overrides[invalidTile.value] = png(1, 1);
      final pointer = await harness.activePointer();
      final manifest = await harness.baselineManifest();
      final pubspec = await harness.pubspec.readAsString();

      await expectLater(_runStage(harness), throwsA(isA<FormatException>()));
      expect(harness.transport.requested, contains(tiles.first.key));
      expect(harness.transport.requested, contains(invalidTile.key));
      expect(await packFile(harness.stage, 'manifest.json').exists(), isFalse);
      await harness.expectUnchanged(
        pointer: pointer,
        manifest: manifest,
        pubspecText: pubspec,
      );
    }, tags: ['qualification']);

    test('failuresDoNotPublish', () async {
      final harness = await _stageHarness();
      final metadataUrl = Uri.parse(primarySourceUrls['metadata/maps.json']!);
      harness.transport.failingUri = metadataUrl;
      final pointer = await harness.activePointer();
      final activeManifest = await harness.baselineManifest();
      final pubspec = await harness.pubspec.readAsString();

      await expectLater(
        _runStage(harness),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('metadata/maps.json'),
          ),
        ),
      );
      await harness.expectUnchanged(
        pointer: pointer,
        manifest: activeManifest,
        pubspecText: pubspec,
      );

      final buildHarness = await _stageHarness();
      buildHarness.transport.changedTile = null;
      final invalidSvg = utf8.encode('<svg><path>');
      buildHarness.transport.overrides['interchange/Interchange.svg'] =
          invalidSvg;
      final sourceLock = jsonDecode(
        canonicalJson(buildHarness.context.sourceLock),
      ) as Map<String, dynamic>;
      final hashes = Map<String, String>.from(
        (sourceLock['primaryHashes'] as Map).cast<String, String>(),
      )..['interchange/Interchange.svg'] = _hash(invalidSvg);
      sourceLock['primaryHashes'] = hashes;
      final buildContext = MapBuildContext.reviewed(
        calibration: buildHarness.context.calibration,
        sourceLock: sourceLock,
        noticeBytes: buildHarness.context.noticeBytes,
      );
      final buildPointer = await buildHarness.activePointer();
      final buildManifest = await buildHarness.baselineManifest();
      final buildPubspec = await buildHarness.pubspec.readAsString();

      await expectLater(
        _runStage(buildHarness, context: buildContext),
        throwsA(predicate<Object>((error) => error is! HttpException)),
      );
      expect(
        buildHarness.transport.requested,
        contains(Uri.parse(primarySourceUrls['interchange/Interchange.svg']!)),
      );
      expect(
        await packFile(buildHarness.stage, 'manifest.json').exists(),
        isFalse,
        reason: 'a failed build must not leave a ready candidate manifest',
      );
      await buildHarness.expectUnchanged(
        pointer: buildPointer,
        manifest: buildManifest,
        pubspecText: buildPubspec,
      );
    }, tags: ['qualification']);

    test('reviewedSourceAdmitted', () async {
      final missingHarness = await _stageHarness();
      final missingPointer = await missingHarness.activePointer();
      final missingManifest = await missingHarness.baselineManifest();
      final missingPubspec = await missingHarness.pubspec.readAsString();
      final missingSourceLock = jsonDecode(
        canonicalJson(missingHarness.context.sourceLock),
      ) as Map<String, dynamic>;
      final missingHashes = Map<String, String>.from(
        (missingSourceLock['primaryHashes'] as Map).cast<String, String>(),
      )..remove('terms/tarkov-dev-README.md');
      missingSourceLock['primaryHashes'] = missingHashes;
      final missingContext = MapBuildContext.reviewed(
        calibration: missingHarness.context.calibration,
        sourceLock: missingSourceLock,
        noticeBytes: missingHarness.context.noticeBytes,
      );
      await expectLater(
        _runStage(missingHarness, context: missingContext),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('terms/tarkov-dev-README.md'),
          ),
        ),
      );
      expect(missingHarness.transport.requested, isEmpty);
      await missingHarness.expectUnchanged(
        pointer: missingPointer,
        manifest: missingManifest,
        pubspecText: missingPubspec,
      );

      final harness = await _stageHarness();
      harness.transport.changedTile = null;
      final staged = await _runStage(harness);
      final sourceIndex = jsonDecode(
        await packFile(
          staged.candidate,
          'evidence/sources.json',
        ).readAsString(),
      ) as Map<String, dynamic>;
      final records = (sourceIndex['sources'] as List)
          .cast<Map<String, dynamic>>();
      Map<String, dynamic> source(String path) =>
          records.singleWhere((record) => record['path'] == path);

      final interchange = source('interchange/Interchange.svg');
      final interchangeUrl = primarySourceUrls['interchange/Interchange.svg']!;
      expect(harness.transport.requested, contains(Uri.parse(interchangeUrl)));
      expect(
        harness.transport.requested,
        isNot(
          contains(
            Uri.parse('https://assets.tarkov.dev/maps/svg/Interchange.svg'),
          ),
        ),
      );
      expect(interchange['url'], interchangeUrl);
      expect(interchange['repositoryRevision'], vectorSourceRevision);
      expect(interchange['gitBlobSha1'], vectorSourceBlob);
      expect(
        source('metadata/maps.json')['repositoryRevision'],
        metadataRepositoryRevision,
      );
      expect(source('metadata/maps.json')['gitBlobSha1'], metadataBlob);
      expect(
        interchange['sha256'],
        harness
            .context
            .sourceLock['primaryHashes']['interchange/Interchange.svg'],
      );

      expect(
        source('metadata/maps.json')['url'],
        primarySourceUrls['metadata/maps.json'],
      );
      expect(
        harness.transport.requested,
        contains(Uri.parse(primarySourceUrls['metadata/maps.json']!)),
      );
      for (final path in const [
        'terms/svg-maps-README.md',
        'terms/svg-maps-LICENSE.md',
        'terms/tarkov-dev-README.md',
        'terms/tarkov-dev-software-LICENSE.txt',
        'terms/tarkovbot-creator.html',
      ]) {
        final record = source(path);
        expect(record['url'], primarySourceUrls[path]);
        expect(
          harness.transport.requested,
          contains(Uri.parse(primarySourceUrls[path]!)),
        );
        expect(
          record['sha256'],
          harness.context.sourceLock['primaryHashes'][path],
        );
        expect(
          record['provenance'],
          isA<String>().having((value) => value, 'value', isNotEmpty),
        );
        final revision = primarySourceRepositoryRevisions[path];
        if (revision != null) {
          expect(record['repositoryRevision'], revision);
        } else {
          expect(record.containsKey('repositoryRevision'), isFalse);
        }
      }
      final tileUrlsByPath = {
        for (final entry in harness.transport.routes.entries)
          if (entry.value.startsWith('tiles/')) entry.value: entry.key,
      };
      final tileRecords = records.where(
        (record) => (record['path'] as String).startsWith('tiles/'),
      );
      for (final record in tileRecords) {
        final path = record['path'] as String;
        final expectedUrl = tileUrlsByPath[path]!.toString();
        expect(record['url'], expectedUrl, reason: path);
      }
      final tileRecord = tileRecords.first;
      final tileHash = tileRecord['sha256'] as String;
      final carrier = (staged.manifest['outputs'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((output) => output['sha256'] == tileHash);
      await packFile(
        staged.candidate,
        carrier['path'] as String,
      ).writeAsBytes(utf8.encode('corrupt tile carrier'));
      final frozen = await FrozenInputs.fromGeneration(staged.candidate);
      await expectLater(
        frozen.bytes(tileRecord['path'] as String),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains(tileRecord['path'] as String),
          ),
        ),
      );
    }, tags: ['qualification']);
    test('artworkReproducesWithoutRawStage', () async {
      final harness = await _stageHarness(isolatedRaw: true);
      final staged = await _runStage(harness);
      await harness.transport.raw.delete(recursive: true);

      final packs = Directory('${harness.root.path}/reproduced-packs');
      await packs.create();
      await promoteCandidate(staged.candidate, packs);
      final active = await verifyCommittedGeneration(packs);
      final context = await MapBuildContext.fromGeneration(active);
      final rebuiltCandidate = Directory(
        '${harness.root.path}/reproduced-candidate',
      );
      expect(await rebuiltCandidate.exists(), isFalse);
      final rebuilt = await rebuildCandidate(
        await FrozenInputs.fromGeneration(active.directory),
        rebuiltCandidate,
        context: context,
        toolchain: fixtureToolchain,
      );
      final report = packChangeReport(active.manifest, rebuilt);

      expect(report.changed, isFalse);
      expect(report.paths, isEmpty);
      expect(report.valueKeys, isEmpty);
    }, tags: ['qualification']);
  });
}

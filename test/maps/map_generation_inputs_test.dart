import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../../tool/maps/pack.dart';

import 'package:blackgrid/maps/live_map_normalizer.dart' show canonicalJson;

String _hash(List<int> bytes) => sha256.convert(bytes).toString();

/// A tiny committed generation: one evidence source, one visible tile, one
/// empty-tile witness and a notice, with a hand-built manifest and index.
class _Generation {
  _Generation._(this.packs, this.id);

  final Directory packs;
  final String id;

  Directory get directory => Directory('${packs.path}/versions/$id');

  File file(String relative) => File('${directory.path}/$relative');

  static final visible = utf8.encode('visible tile');
  static final empty = utf8.encode('empty tile');
  static final terms = utf8.encode('terms');

  static String get emptyPath => 'evidence/tile-alpha/${_hash(empty)}.png';

  static Future<_Generation> create(
    Directory packs, {
    bool includeMetadata = false,
  }) async {
    final stage = Directory('${packs.path}/stage');
    final metadataPaths = [
      'markers/maps.json',
      'markers/maps_en.json',
      'quests/tasks.json',
      'quests/tasks_en.json',
      'quests/traders.json',
      'quests/traders_en.json',
    ];
    final metadata = {
      for (final path in metadataPaths) path: utf8.encode('baseline:$path'),
    };
    final files = <String, List<int>>{
      'NOTICE.txt': utf8.encode('notice'),
      'artwork/m/F/0/0.png': visible,
      emptyPath: empty,
      'evidence/terms/a.md': terms,
      if (includeMetadata)
        for (final entry in metadata.entries)
          'evidence/${entry.key}': entry.value,
    };
    final index = {
      'schemaVersion': 1,
      'sources': [
        {
          'path': 'terms/a.md',
          'url': 'https://example.invalid/a.md',
          'sha256': _hash(terms),
        },
        {
          'path': 'tiles/m/F/0_0.png',
          'url': 'https://example.invalid/0_0.png',
          'sha256': _hash(visible),
        },
        {
          'path': 'tiles/m/F/1_0.png',
          'url': 'https://example.invalid/1_0.png',
          'sha256': _hash(empty),
        },
        {
          'path': 'tiles/m/F/2_0.png',
          'url': 'https://example.invalid/2_0.png',
          'sha256': _hash(utf8.encode('never carried')),
        },
        if (includeMetadata)
          for (final entry in metadata.entries)
            {
              'path': entry.key,
              'url': 'https://example.invalid/${entry.key}',
              'sha256': _hash(entry.value),
            },
      ],
    };
    files['evidence/sources.json'] = utf8.encode(canonicalJson(index));
    for (final entry in files.entries) {
      final file = File('${stage.path}/${entry.key}');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(entry.value);
    }
    final paths = files.keys.toList()..sort();
    await File('${stage.path}/manifest.json').writeAsString(
      canonicalJson({
        'schemaVersion': 1,
        'outputs': [
          for (final path in paths)
            {'path': path, 'sha256': _hash(files[path]!)},
        ],
      }),
    );
    final id = _hash(await File('${stage.path}/manifest.json').readAsBytes());
    await Directory('${packs.path}/versions').create();
    await stage.rename('${packs.path}/versions/$id');
    await File('${packs.path}/active.json').writeAsString(
      canonicalJson({
        'schemaVersion': 1,
        'version': id,
        'manifest': 'versions/$id/manifest.json',
      }),
    );
    return _Generation._(packs, id);
  }
}

Matcher _formatMessage(Matcher message) => throwsA(
  isA<FormatException>().having((e) => e.message, 'message', message),
);

const _preservedOutputPaths = [
  'NOTICE.txt',
  'evidence/sources.json',
  'evidence/calibration.json',
  'evidence/metadata/maps.json',
  'evidence/markers/maps.json',
  'evidence/markers/maps_en.json',
  'evidence/quests/tasks.json',
  'evidence/quests/tasks_en.json',
  'evidence/quests/traders.json',
  'evidence/quests/traders_en.json',
  'artwork/m/ground.svg',
  'artwork/m/ground.compiler.svg',
  'artwork/m/ground.vec',
  'artwork/m/F/0/0.png',
  'evidence/tile-alpha/empty.png',
];

const _metadataReplacementPaths = {
  'markers/maps.json',
  'markers/maps_en.json',
  'quests/tasks.json',
  'quests/tasks_en.json',
  'quests/traders.json',
  'quests/traders_en.json',
};

Map<String, dynamic> _sourceIndex({
  Map<String, String> hashes = const {},
  Map<String, String> urls = const {},
  Map<String, Object?> extras = const {},
}) => {
  'schemaVersion': 1,
  ...extras,
  'sources': [
    for (final path in [
      ..._metadataReplacementPaths,
      'calibration.json',
      'metadata/maps.json',
      'tiles/m/F/0_0.png',
    ])
      {
        'path': path,
        'url': urls[path] ?? 'https://example.invalid/$path',
        'sha256': hashes[path] ?? _hash(utf8.encode('baseline:$path')),
      },
  ],
};

Map<String, dynamic> _preservedManifest({
  Map<String, String> hashes = const {},
  Map<String, Object?> mapValues = const {},
  Map<String, Object?> packValues = const {},
  List<Map<String, dynamic>>? markers,
  List<String>? outputs,
}) {
  final markerList =
      markers ??
      [
        {
          'id': 'switch:console:0',
          'category': 'switch',
          'position': {'x': 1, 'z': 2, 'height': 3},
          'floorId': 'Ground',
          'source': {
            'floorAssignment': {
              'floorId': 'Ground',
              'sourceVolume': {
                'position': {'x': 1, 'y': 3, 'z': 2},
                'heightBand': [2, 4],
                'outline': [
                  {'x': 0, 'y': 3, 'z': 1},
                  {'x': 2, 'y': 3, 'z': 1},
                  {'x': 2, 'y': 3, 'z': 3},
                ],
              },
            },
          },
        },
      ];
  return {
    'schemaVersion': 1,
    'preparationVersion': 4,
    'supportedMapIds': ['m'],
    'sourceLock': {
      'primaryHashes': {'artwork': 'same'},
    },
    'vectorCodecFormat': 1,
    'toolchain': {'vector_graphics_compiler': '1.3.3'},
    ...packValues,
    'maps': [
      {
        'id': 'm',
        'markers': markerList,
        'labels': <Object>[],
        'geometry': {
          'affine': [1, 0, 0, 1, 0, 0],
        },
        'artworkFrame': {'width': 100, 'height': 100},
        'displayCrop': {'left': 0, 'top': 0, 'right': 100, 'bottom': 100},
        'floors': [
          {
            'id': 'Ground',
            'renderOrder': 1,
            'artwork': {
              'components': [
                {
                  'id': 'ground',
                  'sourceSvg': 'artwork/m/ground.svg',
                  'compilerSvg': 'artwork/m/ground.compiler.svg',
                  'path': 'artwork/m/ground.vec',
                  'effects': [],
                },
              ],
            },
          },
        ],
        'layerOrder': ['ground'],
        ...mapValues,
      },
    ],
    'outputs': [
      for (final path in outputs ?? _preservedOutputPaths)
        {
          'path': path,
          'sha256': hashes[path] ?? _hash(utf8.encode('baseline:$path')),
        },
    ],
  };
}

void main() {
  late Directory packs;
  late _Generation generation;

  setUp(() async {
    packs = await Directory.systemTemp.createTemp('blackgrid-generation-');
    addTearDown(() => packs.delete(recursive: true));
    generation = await _Generation.create(packs);
  });

  group('metadata refresh admission and preservation', () {
    test(
      'metadata admission accepts only the six replacement source records',
      () {
        final baseline = _sourceIndex();
        final admitted = _sourceIndex(
          hashes: {
            for (final path in _metadataReplacementPaths)
              path: _hash(utf8.encode('replacement:$path')),
          },
        );
        expect(
          () => validateMetadataSourceIndex(baseline, admitted),
          returnsNormally,
        );

        final forbidden = <(String, Map<String, dynamic>)>[
          (
            'added path',
            {
              ...admitted,
              'sources': [
                ...(admitted['sources'] as List),
                {
                  'path': 'unexpected.json',
                  'url': 'https://example.invalid/unexpected.json',
                  'sha256': _hash(utf8.encode('unexpected')),
                },
              ],
            },
          ),
          (
            'removed path',
            {
              ...admitted,
              'sources': (admitted['sources'] as List)
                  .where((source) => source['path'] != 'metadata/maps.json')
                  .toList(),
            },
          ),
          (
            'removed replacement path',
            {
              ...admitted,
              'sources': (admitted['sources'] as List)
                  .where((source) => source['path'] != 'markers/maps.json')
                  .toList(),
            },
          ),
          (
            'replacement URL',
            _sourceIndex(
              hashes: {
                for (final path in _metadataReplacementPaths)
                  path: _hash(utf8.encode('replacement:$path')),
              },
              urls: {'markers/maps.json': 'https://example.invalid/other.json'},
            ),
          ),
          (
            'non-replacement hash',
            _sourceIndex(
              hashes: {'calibration.json': _hash(utf8.encode('changed'))},
            ),
          ),
          (
            'non-replacement record field',
            {
              ...baseline,
              'sources': [
                for (final source in baseline['sources'] as List)
                  if (source['path'] == 'metadata/maps.json')
                    {
                      ...Map<String, dynamic>.from(source as Map),
                      'url': 'https://example.invalid/changed',
                    }
                  else
                    source,
              ],
            },
          ),
          (
            'non-replacement extra record field',
            {
              ...baseline,
              'sources': [
                for (final source in baseline['sources'] as List)
                  if (source['path'] == 'metadata/maps.json')
                    {
                      ...Map<String, dynamic>.from(source as Map),
                      'provenance': 'changed',
                    }
                  else
                    source,
              ],
            },
          ),
          (
            'replacement extra record field',
            {
              ...admitted,
              'sources': [
                for (final source in admitted['sources'] as List)
                  if (source['path'] == 'markers/maps.json')
                    {
                      ...Map<String, dynamic>.from(source as Map),
                      'provenance': 'unexpected',
                    }
                  else
                    source,
              ],
            },
          ),
          (
            'source record order',
            {
              ...baseline,
              'sources': (baseline['sources'] as List).reversed.toList(),
            },
          ),
          ('index field', {...baseline, 'schemaVersion': 2}),
        ];

        for (final (name, candidate) in forbidden) {
          expect(
            () => validateMetadataSourceIndex(baseline, candidate),
            throwsFormatException,
            reason: name,
          );
        }
      },
    );

    test('metadata preservation rejects forbidden artifact differences', () {
      final baseline = _preservedManifest();
      final forbidden = <(String, Map<String, dynamic>)>[
        (
          'notice hash',
          _preservedManifest(
            hashes: {'NOTICE.txt': _hash(utf8.encode('changed notice'))},
          ),
        ),
        (
          'new toolchain with changed output',
          _preservedManifest(
            hashes: {'NOTICE.txt': _hash(utf8.encode('changed notice'))},
            packValues: {
              'toolchain': {'vector_graphics_compiler': '1.3.4'},
            },
          ),
        ),
        (
          'notice inventory addition',
          _preservedManifest(
            outputs: [..._preservedOutputPaths, 'extra-notice.txt'],
          ),
        ),
        (
          'vector source path',
          _preservedManifest(
            mapValues: {
              'layerOrder': ['other'],
            },
          ),
        ),
        (
          'vector output hash',
          _preservedManifest(
            hashes: {'artwork/m/ground.vec': _hash(utf8.encode('changed vec'))},
          ),
        ),
        (
          'raster output path addition',
          _preservedManifest(
            outputs: [..._preservedOutputPaths, 'artwork/m/F/1/0.png'],
          ),
        ),
        (
          'raster output path removal',
          _preservedManifest(
            outputs: _preservedOutputPaths
                .where((path) => path != 'artwork/m/F/0/0.png')
                .toList(),
          ),
        ),
        (
          'compiler input hash',
          _preservedManifest(
            hashes: {
              'artwork/m/ground.compiler.svg': _hash(utf8.encode('changed')),
            },
          ),
        ),
        (
          'witness output path addition',
          _preservedManifest(
            outputs: [
              ..._preservedOutputPaths,
              'evidence/tile-alpha/other.png',
            ],
          ),
        ),
        (
          'witness output path removal',
          _preservedManifest(
            outputs: _preservedOutputPaths
                .where((path) => path != 'evidence/tile-alpha/empty.png')
                .toList(),
          ),
        ),
        (
          'vector source output hash',
          _preservedManifest(
            hashes: {'artwork/m/ground.svg': _hash(utf8.encode('changed svg'))},
          ),
        ),
        (
          'raster output hash',
          _preservedManifest(
            hashes: {
              'artwork/m/F/0/0.png': _hash(utf8.encode('changed raster')),
            },
          ),
        ),
        (
          'witness output hash',
          _preservedManifest(
            hashes: {
              'evidence/tile-alpha/empty.png': _hash(
                utf8.encode('changed witness'),
              ),
            },
          ),
        ),
        ...[
          for (final (family, path, existingPath) in const [
            ('notice', 'NOTICE.extra.txt', 'NOTICE.txt'),
            ('source SVG', 'artwork/m/other.svg', 'artwork/m/ground.svg'),
            (
              'compiler input',
              'artwork/m/other.compiler.svg',
              'artwork/m/ground.compiler.svg',
            ),
            ('compiled vector', 'artwork/m/other.vec', 'artwork/m/ground.vec'),
            ('raster tile', 'artwork/m/F/1/0.png', 'artwork/m/F/0/0.png'),
            (
              'empty-tile witness',
              'evidence/tile-alpha/other.png',
              'evidence/tile-alpha/empty.png',
            ),
          ]) ...[
            (
              '$family output path addition',
              _preservedManifest(outputs: [..._preservedOutputPaths, path]),
            ),
            (
              '$family output path removal',
              _preservedManifest(
                outputs: _preservedOutputPaths
                    .where((existing) => existing != existingPath)
                    .toList(),
              ),
            ),
          ],
        ],
        (
          'map geometry',
          _preservedManifest(
            mapValues: {
              'geometry': {
                'affine': [2, 0, 0, 2, 0, 0],
              },
            },
          ),
        ),
        (
          'map frame',
          _preservedManifest(
            mapValues: {
              'artworkFrame': {'width': 101, 'height': 100},
            },
          ),
        ),
        (
          'display crop',
          _preservedManifest(
            mapValues: {
              'displayCrop': {'left': 0, 'top': 0, 'right': 99, 'bottom': 100},
            },
          ),
        ),
        ('floor inventory', _preservedManifest(mapValues: {'floors': []})),
        (
          'floor artwork component path',
          _preservedManifest(
            mapValues: {
              'floors': [
                {
                  'id': 'Ground',
                  'renderOrder': 1,
                  'artwork': {
                    'components': [
                      {
                        'id': 'ground',
                        'sourceSvg': 'artwork/m/other.svg',
                        'compilerSvg': 'artwork/m/ground.compiler.svg',
                        'path': 'artwork/m/ground.vec',
                        'effects': [],
                      },
                    ],
                  },
                },
              ],
            },
          ),
        ),
        (
          'rendering metadata',
          _preservedManifest(
            mapValues: {
              'layerOrder': ['ground', 'new-layer'],
            },
          ),
        ),
        (
          'place labels',
          _preservedManifest(
            mapValues: {
              'labels': [
                {
                  'text': 'Gate',
                  'position': {'x': 1, 'z': 2},
                  'rotation': 0,
                  'size': 80,
                  'floorIds': ['Ground'],
                },
              ],
            },
          ),
        ),
        (
          'floor metadata',
          _preservedManifest(
            mapValues: {
              'floors': [
                {
                  'id': 'Ground',
                  'renderOrder': 2,
                  'artwork': {
                    'components': [
                      {
                        'id': 'ground',
                        'sourceSvg': 'artwork/m/ground.svg',
                        'compilerSvg': 'artwork/m/ground.compiler.svg',
                        'path': 'artwork/m/ground.vec',
                        'effects': [],
                      },
                    ],
                  },
                },
              ],
            },
          ),
        ),
        (
          'calibration output',
          _preservedManifest(
            hashes: {
              'evidence/calibration.json': _hash(utf8.encode('changed')),
            },
          ),
        ),
        (
          'non-replacement source evidence hash',
          _preservedManifest(
            hashes: {
              'evidence/metadata/maps.json': _hash(utf8.encode('changed')),
            },
          ),
        ),
        (
          'schema version',
          _preservedManifest(packValues: {'schemaVersion': 2}),
        ),
        (
          'source lock',
          _preservedManifest(
            packValues: {
              'sourceLock': {
                'primaryHashes': {'artwork': 'changed'},
              },
            },
          ),
        ),
        (
          'codec format',
          _preservedManifest(packValues: {'vectorCodecFormat': 2}),
        ),
        (
          'preparation version',
          _preservedManifest(packValues: {'preparationVersion': 3}),
        ),
        (
          'supported inventory',
          _preservedManifest(
            packValues: {
              'supportedMapIds': ['m', 'new'],
            },
          ),
        ),
      ];

      for (final (name, candidate) in forbidden) {
        expect(
          () => validateMetadataPreservation(baseline, candidate),
          throwsFormatException,
          reason: name,
        );
      }
    });

    test(
      'metadata preservation permits a new toolchain with unchanged outputs',
      () {
        final baseline = _preservedManifest();
        final candidate = _preservedManifest(
          packValues: {
            'toolchain': {'vector_graphics_compiler': '1.3.4'},
          },
        );

        expect(
          () => validateMetadataPreservation(baseline, candidate),
          returnsNormally,
        );
      },
    );

    test(
      'metadata preservation accepts only metadata evidence and marker changes',
      () {
        final baseline = _preservedManifest();
        final marker = Map<String, dynamic>.from(
          ((baseline['maps'] as List).single['markers'] as List).single,
        )..['name'] = 'Updated metadata';
        final candidate = _preservedManifest(
          hashes: {
            for (final path in _metadataReplacementPaths)
              'evidence/$path': _hash(utf8.encode('replacement:$path')),
            'evidence/sources.json': _hash(utf8.encode('replacement index')),
          },
          markers: [marker],
          packValues: {'sourceGeneration': 'replacement-generation'},
        );
        expect(
          () => validateMetadataPreservation(baseline, candidate),
          returnsNormally,
        );
      },
    );

    test(
      'renewal accepts upstream content evolution and omits stale overrides',
      () {
        final baselineMarker = Map<String, dynamic>.from(
          ((_preservedManifest()['maps'] as List).single['markers'] as List)
              .single,
        );
        final baseline = _preservedManifest(markers: [baselineMarker]);

        final changedMarker = Map<String, dynamic>.from(baselineMarker)
          ..['id'] = 'switch:changed:0'
          ..['name'] = 'Updated source name'
          ..['position'] = {'x': 4, 'z': 2, 'height': 5}
          ..remove('floorId')
          ..['source'] = {'floorAssignment': null};
        final evolved = _preservedManifest(
          markers: [
            changedMarker,
            {
              'id': 'switch:new:0',
              'category': 'switch',
              'name': 'New source marker',
              'position': {'x': 7, 'z': 8, 'height': 9},
              'source': {'floorAssignment': null},
            },
          ],
        );
        final removed = _preservedManifest(markers: const []);

        expect(
          () => validateMetadataPreservation(baseline, evolved),
          returnsNormally,
        );
        expect(
          () => validateMetadataPreservation(baseline, removed),
          returnsNormally,
        );
        final report = packChangeReport(baseline, evolved);
        expect(report.paths, isEmpty);
        expect(
          report.valueKeys,
          contains('m markers'),
          reason:
              'metadata evolution reports the affected map without '
              'claiming an artwork change',
        );
      },
    );
  });

  group('verifyCommittedGeneration', () {
    test('consistent generation passes and names its id', () async {
      final verified = await verifyCommittedGeneration(packs);
      expect(verified.id, generation.id);
      expect(verified.directory.path, generation.directory.path);
      expect(verified.manifest['outputs'], hasLength(5));
    });

    test('manifest hash differing from the id fails naming the id', () async {
      final manifest = generation.file('manifest.json');
      await manifest.writeAsString('${await manifest.readAsString()} ');
      await expectLater(
        verifyCommittedGeneration(packs),
        _formatMessage(contains(generation.id)),
      );
    });

    test('edited or extra generation file fails naming it', () async {
      await generation.file('NOTICE.txt').writeAsString('edited');
      await expectLater(
        verifyCommittedGeneration(packs),
        _formatMessage(contains('NOTICE.txt')),
      );
      await generation.file('NOTICE.txt').writeAsString('notice');
      await generation.file('extra/stray.txt').parent.create();
      await generation.file('extra/stray.txt').writeAsString('stray');
      await expectLater(
        verifyCommittedGeneration(packs),
        _formatMessage(contains('extra/stray.txt')),
      );
    });

    test('missing generation file fails naming it', () async {
      await generation.file('artwork/m/F/0/0.png').delete();
      await expectLater(
        verifyCommittedGeneration(packs),
        throwsA(predicate((error) => '$error'.contains('artwork/m/F/0/0.png'))),
      );
    });

    test('malformed active pointer fails', () async {
      await File('${packs.path}/active.json').writeAsString(
        canonicalJson({
          'schemaVersion': 1,
          'version': 'not-a-generation',
          'manifest': 'versions/not-a-generation/manifest.json',
        }),
      );
      await expectLater(
        verifyCommittedGeneration(packs),
        _formatMessage(contains('active pointer')),
      );
    });
  });

  group('FrozenInputs.fromGeneration', () {
    test('requiredEvidenceCorruptionRejected', () async {
      final terms = generation.file('evidence/terms/a.md');
      await terms.delete();
      await expectLater(
        FrozenInputs.fromGeneration(generation.directory),
        throwsA(
          predicate<Object>((error) => error.toString().contains('terms/a.md')),
        ),
      );
      await terms.writeAsBytes(_Generation.terms);
      await terms.writeAsString('corrupt');
      await expectLater(
        FrozenInputs.fromGeneration(generation.directory),
        _formatMessage(contains('terms/a.md')),
      );

      await terms.writeAsBytes(_Generation.terms);
      final frozen = await FrozenInputs.fromGeneration(generation.directory);
      await generation.file('artwork/m/F/0/0.png').writeAsString('corrupt');
      await expectLater(
        frozen.bytes('tiles/m/F/0_0.png'),
        _formatMessage(contains('tiles/m/F/0_0.png')),
      );
    });

    test('evidence sources resolve under evidence and tiles by hash', () async {
      final frozen = await FrozenInputs.fromGeneration(generation.directory);
      expect(await frozen.bytes('terms/a.md'), _Generation.terms);
      expect(await frozen.bytes('tiles/m/F/0_0.png'), _Generation.visible);
      expect(await frozen.bytes('tiles/m/F/1_0.png'), _Generation.empty);
      expect(
        canonicalJson(frozen.index),
        await generation.file('evidence/sources.json').readAsString(),
      );
    });

    test('edited evidence fails naming the file', () async {
      await generation.file('evidence/terms/a.md').writeAsString('edited');
      await expectLater(
        FrozenInputs.fromGeneration(generation.directory),
        _formatMessage(contains('terms/a.md')),
      );
    });

    test('reading an uncarried source names its path', () async {
      final frozen = await FrozenInputs.fromGeneration(generation.directory);
      await expectLater(
        frozen.bytes('tiles/m/F/2_0.png'),
        _formatMessage(
          allOf(
            contains('tiles/m/F/2_0.png'),
            contains(generation.id),
            contains('rebuild --raw'),
          ),
        ),
      );
      await expectLater(
        frozen.bytes('tiles/never/listed.png'),
        throwsFormatException,
      );
    });

    test(
      'tile carrier that no longer matches its hash fails naming it',
      () async {
        final frozen = await FrozenInputs.fromGeneration(generation.directory);
        await generation.file('artwork/m/F/0/0.png').writeAsString('edited');
        await expectLater(
          frozen.bytes('tiles/m/F/0_0.png'),
          _formatMessage(contains('tiles/m/F/0_0.png')),
        );
      },
    );
  });

  group('FrozenInputs.withMetadata', () {
    test('generation metadata view preserves missing inputs and detects replacement mutation', () async {
      final root = await Directory.systemTemp.createTemp(
        'blackgrid-metadata-view-',
      );
      addTearDown(() => root.delete(recursive: true));
      final packs = Directory('${root.path}/packs');
      await packs.create();
      final generation = await _Generation.create(packs, includeMetadata: true);
      final before = <String, List<int>>{};
      await for (final entity in generation.directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final relative = entity.path
            .replaceAll('\\', '/')
            .substring(
              generation.directory.path.replaceAll('\\', '/').length + 1,
            );
        before[relative] = await entity.readAsBytes();
      }
      final indexBefore = jsonDecode(
        utf8.decode(before['evidence/sources.json']!),
      ) as Map<String, dynamic>;
      final replacements = Directory('${root.path}/replacements');
      const paths = [
        'markers/maps.json',
        'markers/maps_en.json',
        'quests/tasks.json',
        'quests/tasks_en.json',
        'quests/traders.json',
        'quests/traders_en.json',
      ];
      final replacementBytes = <String, List<int>>{};
      for (final path in paths) {
        final bytes = utf8.encode('replacement:$path');
        replacementBytes[path] = bytes;
        final file = File('${replacements.path}/$path');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes);
      }

      final frozen = await FrozenInputs.fromGeneration(generation.directory);
      final metadata = await frozen.withMetadata(replacements);
      final expectedIndex =
          jsonDecode(jsonEncode(indexBefore)) as Map<String, dynamic>;
      for (final source in expectedIndex['sources'] as List) {
        if (paths.contains(source['path'])) {
          source['sha256'] = _hash(replacementBytes[source['path']]!);
        }
      }
      expect(canonicalJson(metadata.index), canonicalJson(expectedIndex));
      for (final path in paths) {
        expect(await metadata.bytes(path), replacementBytes[path]);
      }
      await expectLater(
        metadata.bytes('tiles/m/F/2_0.png'),
        _formatMessage(
          allOf(
            contains('tiles/m/F/2_0.png'),
            contains(generation.id),
            contains('rebuild --raw'),
          ),
        ),
      );
      expect(
        await generation.file('evidence/sources.json').readAsBytes(),
        before['evidence/sources.json'],
      );
      for (final entry in before.entries) {
        expect(
          await generation.file(entry.key).readAsBytes(),
          entry.value,
          reason: entry.key,
        );
      }
      expect(
        (metadata.index['sources'] as List).where(
          (source) => !paths.contains(source['path']),
        ),
        equals(
          (indexBefore['sources'] as List).where(
            (source) => !paths.contains(source['path']),
          ),
        ),
      );

      await File('${replacements.path}/markers/maps.json')
          .writeAsString('mutated after view creation');
      await expectLater(
        metadata.bytes('markers/maps.json'),
        _formatMessage(contains('markers/maps.json')),
      );
    });
  });

  group('pruneSupersededGenerations', () {
    test('pruning deletes only 64-hex non-active generations', () async {
      final versions = Directory('${packs.path}/versions');
      final old = 'ab' * 32;
      final names = {
        'old': old,
        'old2': 'cd' * 32,
        'upper': 'FE' * 32,
        'short': 'ab' * 31,
        'long': '${'ab' * 32}0',
        'staging': '.${'ef' * 32}.staging',
        'plain': 'notes',
      };
      for (final name in names.values) {
        await File('${versions.path}/$name/keep.txt').create(recursive: true);
      }
      // A plain file whose name looks like an id is not a generation folder.
      await File('${versions.path}/${'12' * 32}').writeAsString('x');

      final deleted = await pruneSupersededGenerations(packs, generation.id);

      expect(deleted, unorderedEquals([old, 'cd' * 32]));
      final remaining = {
        await for (final entity in versions.list())
          entity.path.replaceAll('\\', '/').split('/').last,
      };
      expect(remaining, {
        generation.id,
        names['upper']!,
        names['short']!,
        names['long']!,
        names['staging']!,
        names['plain']!,
        '12' * 32,
      });
      expect(generation.file('manifest.json').existsSync(), isTrue);
    });

    test('a packs folder without versions prunes nothing', () async {
      final empty = await Directory.systemTemp.createTemp('blackgrid-prune-');
      addTearDown(() => empty.delete(recursive: true));
      expect(await pruneSupersededGenerations(empty, 'ab' * 32), isEmpty);
    });
  });

  group('requireNoInterruptedPromotion', () {
    test('clean packs folder passes', () async {
      await requireNoInterruptedPromotion(packs);
      await requireNoInterruptedPromotion(Directory('${packs.path}/absent'));
    });

    test(
      'leftover precheck names a staging folder of any id or active.next.json',
      () async {
        final staging = Directory(
          '${packs.path}/versions/.${'ab' * 32}.staging',
        );
        await staging.create();
        await expectLater(
          requireNoInterruptedPromotion(packs),
          _formatMessage(
            equals(
              'Interrupted map pack promotion left '
              '${staging.path.replaceAll('\\', '/')}; '
              'inspect and remove it, then rerun.',
            ),
          ),
        );
        await staging.delete();
        await File('${packs.path}/active.next.json').writeAsString('x');
        await expectLater(
          requireNoInterruptedPromotion(packs),
          _formatMessage(
            allOf(
              startsWith('Interrupted map pack promotion left '),
              contains('active.next.json'),
              endsWith('inspect and remove it, then rerun.'),
            ),
          ),
        );
      },
    );
  });
}

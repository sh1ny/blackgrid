import 'dart:convert';

import 'package:test/test.dart';

import '../../tool/maps/pack.dart';

const _toolchain = {
  'xml': '6.6.1',
  'image': '4.12.0',
  'vector_graphics_compiler': '1.3.0',
  'vector_graphics': '1.2.5',
  'vector_graphics_codec': '1.1.13',
};

/// Output hash per path; the builders below derive `outputs` from it.
typedef _Hashes = Map<String, String>;

_Hashes _hashes() => {
  'NOTICE.txt': 'n0',
  'evidence/sources.json': 's0',
  'artwork/woods/Ground_Level.svg': 'w-svg',
  'artwork/woods/Ground_Level.compiler.svg': 'w-compiler',
  'artwork/woods/Ground_Level.vec': 'w-vec',
  'artwork/thelab/First_Level/0/0.png': 't00',
  'artwork/thelab/First_Level/1/0.png': 't10',
  'evidence/tile-alpha/e0.png': 'e0',
  'artwork/dependencies/woods/d/0/0.png': 'd00',
};

/// A small hand-built manifest in map order woods, thelab.
Map<String, dynamic> _manifest(
  _Hashes hashes, {
  Map<String, String> toolchain = _toolchain,
  Object? displayCrop,
  bool tileEmpty = false,
  Object? effects,
  Map<String, Object?> extra = const {},
}) {
  final paths = hashes.keys.toList()..sort();
  return {
    'schemaVersion': 1,
    'preparationVersion': 3,
    'toolchain': toolchain,
    ...extra,
    'maps': [
      {
        'id': 'woods',
        'kind': 'vector',
        'displayCrop': {'left': 0, 'top': 0, 'right': 10, 'bottom': 10},
        'layerOrder': ['Ground_Level'],
        'floors': [
          {
            'id': 'Ground_Level',
            'artwork': {
              'components': [
                {
                  'id': 'Ground_Level',
                  'sourceSvg': 'artwork/woods/Ground_Level.svg',
                  'compilerSvg': 'artwork/woods/Ground_Level.compiler.svg',
                  'path': 'artwork/woods/Ground_Level.vec',
                  'effects': effects ?? <Object>[],
                },
              ],
            },
          },
        ],
        'rasterDependencies': [
          {
            'id': 'd',
            'artwork': {
              'tiles': [
                {
                  'x': 0,
                  'y': 0,
                  'empty': false,
                  'path': 'artwork/dependencies/woods/d/0/0.png',
                  'alphaBounds': [0, 0, 1, 1],
                },
              ],
            },
          },
        ],
      },
      {
        'id': 'thelab',
        'kind': 'raster',
        'displayCrop':
            displayCrop ?? {'left': 0, 'top': 0, 'right': 8, 'bottom': 8},
        'floors': [
          {
            'id': 'First_Level',
            'artwork': {
              'tiles': [
                {
                  'x': 0,
                  'y': 0,
                  'empty': false,
                  'path': 'artwork/thelab/First_Level/0/0.png',
                  'alphaBounds': [0, 0, 1, 1],
                },
                if (tileEmpty)
                  {'x': 1, 'y': 0, 'empty': true, 'sourceSha256': 'e0'}
                else
                  {
                    'x': 1,
                    'y': 0,
                    'empty': false,
                    'path': 'artwork/thelab/First_Level/1/0.png',
                    'alphaBounds': [0, 0, 1, 1],
                  },
              ],
            },
          },
        ],
      },
    ],
    'outputs': [
      for (final path in paths) {'path': path, 'sha256': hashes[path]},
    ],
  };
}

void main() {
  test('success line names the generation and the five versions', () {
    expect(
      packReproducedLine('abc123', _toolchain),
      'Map pack abc123 reproduced byte-identically with xml 6.6.1, '
      'image 4.12.0, vector_graphics_compiler 1.3.0, vector_graphics 1.2.5, '
      'vector_graphics_codec 1.1.13.',
    );
  });

  test(
    'toolchain-only difference reports nothing and needs no owner check',
    () {
      final report = packChangeReport(
        _manifest(_hashes()),
        _manifest(
          _hashes(),
          toolchain: {..._toolchain, 'vector_graphics_compiler': '1.3.4'},
        ),
      );
      expect(report.lines, isEmpty);
      expect(report.paths, isEmpty);
      expect(report.changed, isFalse);
    },
  );

  test('changed vec is counted under its map and floor', () {
    final report = packChangeReport(
      _manifest(_hashes()),
      _manifest(_hashes()..['artwork/woods/Ground_Level.vec'] = 'w-vec-2'),
    );
    expect(report.lines, ['woods Ground_Level: 1 changed file(s)']);
    expect(report.paths, ['artwork/woods/Ground_Level.vec']);
    expect(report.changed, isTrue);
  });

  test(
    'one vec and two tiles print woods Ground_Level 1 and thelab First_Level 2',
    () {
      final report = packChangeReport(
        _manifest(_hashes()),
        _manifest(
          _hashes()
            ..['artwork/woods/Ground_Level.vec'] = 'w-vec-2'
            ..['artwork/thelab/First_Level/0/0.png'] = 't00-2'
            ..['artwork/thelab/First_Level/1/0.png'] = 't10-2',
        ),
      );
      expect(report.lines, [
        'woods Ground_Level: 1 changed file(s)',
        'thelab First_Level: 2 changed file(s)',
      ]);
    },
  );

  test('raster dependency files are grouped under their dependency', () {
    final report = packChangeReport(
      _manifest(_hashes()),
      _manifest(_hashes()..['artwork/dependencies/woods/d/0/0.png'] = 'd00-2'),
    );
    expect(report.lines, ['woods dependency d: 1 changed file(s)']);
  });

  test(
    'displayCrop-only difference reports the map and needs the owner check',
    () {
      final report = packChangeReport(
        _manifest(_hashes()),
        _manifest(
          _hashes(),
          displayCrop: {'left': 1, 'top': 0, 'right': 8, 'bottom': 8},
        ),
      );
      expect(report.lines, ['thelab: manifest values changed']);
      expect(report.paths, isEmpty);
      expect(report.valueKeys, ['thelab displayCrop']);
      expect(report.changed, isTrue);
    },
  );

  test(
    'tile empty flag difference marks its floor; witness paths go to other',
    () {
      final rebuilt = _hashes()..remove('artwork/thelab/First_Level/1/0.png');
      final committed = _hashes()..remove('evidence/tile-alpha/e0.png');
      final report = packChangeReport(
        _manifest(committed),
        _manifest(rebuilt, tileEmpty: true),
      );
      expect(report.lines, [
        'thelab First_Level: 1 changed file(s), manifest values changed',
        'other: 1 changed file(s)',
      ]);
      expect(report.paths, [
        'artwork/thelab/First_Level/1/0.png',
        'evidence/tile-alpha/e0.png',
      ]);
    },
  );

  test('component effects difference marks its floor', () {
    final report = packChangeReport(
      _manifest(_hashes()),
      _manifest(_hashes(), effects: [jsonDecode('{"kind":"shadow"}')]),
    );
    expect(report.lines, [
      'woods Ground_Level: 0 changed file(s), manifest values changed',
    ]);
  });

  test('unattributed evidence and top-level values go to other and pack', () {
    final report = packChangeReport(
      _manifest(_hashes()),
      _manifest(
        _hashes()..['NOTICE.txt'] = 'n1',
        extra: {'vectorCodecFormat': 1},
      ),
    );
    expect(report.lines, [
      'pack: manifest values changed',
      'other: 1 changed file(s)',
    ]);
    expect(report.valueKeys, ['vectorCodecFormat']);
    expect(report.paths, ['NOTICE.txt']);
  });

  test('added and removed outputs count as changed files', () {
    final report = packChangeReport(
      _manifest(_hashes()),
      _manifest(
        _hashes()
          ..remove('artwork/woods/Ground_Level.svg')
          ..['artwork/woods/Ground_Level.extra'] = 'x',
      ),
    );
    expect(report.paths, [
      'artwork/woods/Ground_Level.extra',
      'artwork/woods/Ground_Level.svg',
    ]);
    expect(report.changed, isTrue);
  });
}

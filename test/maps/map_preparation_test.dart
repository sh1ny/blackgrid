import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import '../../tool/maps/pack.dart';
import '../../tool/maps/svg.dart';
import '../../tool/maps/calibration.dart';
import '../support/map_preparation_fixtures.dart' show png;

void main() {
  late Directory temporary;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('blackgrid-map-test-');
  });
  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  test('decoded alpha, not HTTP length, identifies empty tiles', () {
    expect(inspectPng(png(2, 2, empty: true), expectedSize: 2).empty, isTrue);
    expect(inspectPng(png(2, 2), expectedSize: 2).empty, isFalse);
    expect(
      () => inspectPng(Uint8List.fromList([137, 80, 78, 71]), expectedSize: 2),
      throwsFormatException,
    );
    expect(() => inspectPng(png(3, 2), expectedSize: 2), throwsFormatException);
  });

  test('frozen source hash changes and missing files fail', () async {
    final root = Directory('${temporary.path}/raw');
    await root.create();
    final bytes = png(2, 2);
    final tile = File('${root.path}/tile.png');
    await tile.writeAsBytes(bytes);
    await File('${root.path}/sources.json').writeAsString(
      canonicalJson({
        'schemaVersion': 1,
        'sources': [
          {
            'path': 'tile.png',
            'url': 'https://example.invalid/tile.png',
            'sha256': sha256.convert(bytes).toString(),
          },
        ],
      }),
    );
    final frozen = await FrozenInputs.open(root);
    expect(await frozen.bytes('tile.png'), bytes);
    // An on-disk file is not a dependency unless the frozen index declares it.
    await File('${root.path}/unfrozen.png').writeAsBytes(bytes);
    await expectLater(frozen.bytes('unfrozen.png'), throwsFormatException);
    final indexFile = File('${root.path}/sources.json');
    final originalIndex =
        jsonDecode(await indexFile.readAsString()) as Map<String, dynamic>;
    final entry =
        (originalIndex['sources'] as List).single as Map<String, dynamic>;
    await indexFile.writeAsString(
      canonicalJson({
        'schemaVersion': 1,
        'sources': [entry, Map<String, dynamic>.from(entry)],
      }),
    );
    await expectLater(
      FrozenInputs.open(root),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Duplicate frozen path tile.png',
        ),
      ),
    );
    await indexFile.writeAsString(
      canonicalJson({
        'schemaVersion': 1,
        'sources': [
          {...entry, 'url': 'http://example.invalid/tile.png'},
        ],
      }),
    );
    await expectLater(
      FrozenInputs.open(root),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Invalid frozen source URL: tile.png',
        ),
      ),
    );
    await indexFile.writeAsString(canonicalJson(originalIndex));
    await tile.writeAsBytes(png(2, 2, empty: true));
    await expectLater(FrozenInputs.open(root), throwsFormatException);
    await tile.delete();
    await expectLater(
      FrozenInputs.open(root),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('known Interchange console ownership is identity and full-volume bound, not height inference', () {
    final console = <String, dynamic>{
      'id': '6b9023f26446d73433823e872e6d69688083beaf',
      'name': 'Non-Kiba Alarms Switch',
      'position': {'x': -46.555, 'y': 37.347, 'z': -55.202},
      'bottom': 37.187,
      'top': 37.507,
      'outline': [
        {'x': -46.81, 'y': 37.347, 'z': -55.517},
        {'x': -46.3, 'y': 37.347, 'z': -55.517},
        {'x': -46.3, 'y': 37.347, 'z': -54.887},
        {'x': -46.81, 'y': 37.347, 'z': -54.887},
      ],
    };
    final snapshot = <String, dynamic>{
      'data': {
        'maps': {
          'interchange': {
            'id': '5714dbc024597771384a510d',
            'normalizedName': 'interchange',
            'switches': [
              console,
              {...console, 'id': 'unreviewed-same-name'},
              {...console, 'id': 'cross-floor-volume', 'bottom': 27, 'top': 38},
              {
                'id': 'unknown-height',
                'position': {'x': 0, 'y': null, 'z': 0},
              },
            ],
            'bosses': <Object>[],
          },
        },
      },
    };
    final calibration = calibrationFor('interchange');
    final markers = prepareMarkers(snapshot, {}, calibration);
    expect(markers.first['floorId'], 'Second_Floor');
    expect(markers.first['details'], console);
    expect(markers.first['position'], {
      'x': -46.555,
      'z': -55.202,
      'height': 37.347,
    });
    expect(markers.first['heightBand'], [37.187, 37.507]);
    expect(
      markers.skip(1).map((marker) => marker['floorId']),
      everyElement(isNull),
    );
    expect((markers.last['position'] as Map)['height'], isNull);

    // A later changed snapshot must not reuse a stale reviewed annotation.
    console['top'] = 1001;
    expect(
      () => prepareMarkers(snapshot, {}, calibration),
      throwsFormatException,
    );
    console['top'] = 37.507;
    (console['outline'] as List).first['x'] = 121.0;
    expect(
      () => prepareMarkers(snapshot, {}, calibration),
      throwsFormatException,
    );
  });

  test('canonical manifest bytes do not depend on insertion order', () {
    expect(
      canonicalJson({
        'b': 1,
        'a': {'z': 2, 'y': 3},
      }),
      canonicalJson({
        'a': {'y': 3, 'z': 2},
        'b': 1,
      }),
    );
  });

  test('local floor identities and bands survive changed upstream labels', () {
    final local = calibrationFor('the-lab');
    final upstream = {
      'tilePath': labsTiles.first,
      'layers': [
        {'name': 'Renamed technical', 'tilePath': labsTiles[2]},
        {'name': 'Renamed upper', 'tilePath': labsTiles[1]},
      ],
    };
    final floors = reconcileFloors(local, upstream);
    expect(floors.map((f) => f['id']), [
      'First_Level',
      'Second_Level',
      'Technical_Level',
    ]);
    expect(floors[1]['heightBand'], [3, 1000]);
    expect(
      () => reconcileFloors(local, {'tilePath': labsTiles.first, 'layers': []}),
      throwsFormatException,
    );
    final interchange = calibrationFor('interchange');
    final refreshedVector = reconcileFloors(interchange, {
      'svgLayer': 'Ground_Level',
      'tilePath': 'https://example.invalid/unselected-raster/{z}/{x}/{y}.png',
      'layers': [
        {'name': 'Renamed upper', 'svgLayer': 'Second_Floor'},
        {'name': 'Renamed middle', 'svgLayer': 'First_Floor'},
      ],
    });
    expect(refreshedVector.map((f) => f['id']), [
      'Ground_Level',
      'First_Floor',
      'Second_Floor',
    ]);
    expect(refreshedVector[1]['label'], '2nd Floor');
    expect(refreshedVector[1]['heightBand'], [25, 34]);
    expect(refreshedVector[2]['heightBand'], [34, 1000]);
    expect(calibrationFor('icebreaker')['floors'], hasLength(16));
    final ice = calibrationFor('icebreaker');
    final iceFloors = (ice['floors'] as List).cast<Map<String, Object?>>();
    final refreshedIce = reconcileFloors(ice, {
      'tilePath': iceFloors.singleWhere(
        (f) => f['base'] == true,
      )['sourceTileUrl'],
      'layers': [
        for (final f in iceFloors.reversed)
          {'name': 'Changed display label', 'tilePath': f['sourceTileUrl']},
      ],
    });
    expect(refreshedIce.map((f) => f['id']), icebreakerSources.keys);
    expect(refreshedIce.every((f) => f['exclusive'] == true), isTrue);
    expect(
      refreshedIce.singleWhere(
        (f) => f['id'] == 'Storage_Security',
      )['heightBand'],
      [15, 18.92],
    );
    expect(
      refreshedIce
          .singleWhere((f) => f['id'] == 'Infirmary')
          .containsKey('heightBand'),
      isFalse,
    );
    expect(
      () => reconcileFloors(local, {
        ...upstream,
        'layers': [
          ...(upstream['layers'] as List),
          {'tilePath': 'https://example.invalid/unknown/{z}/{x}/{y}.png'},
        ],
      }),
      throwsFormatException,
    );
  });

  test('exact source drop-shadow transfers to explicit native vector effect', () {
    const source =
        '<svg width="10" height="10" viewBox="0 0 10 10"><style>.shadow {filter:drop-shadow(0 0 2px #000)}</style><g id="First_Floor" class="shadow"><path d="M0 0L1 1"/></g></svg>';
    final normalized = normalizeSvgFloor(
      source,
      {'First_Floor'},
      {'First_Floor'},
    );
    final compiled = compilerSvg(normalized, 'First_Floor');
    expect(compiled.effects, [
      {
        'type': 'drop-shadow',
        'dx': 0,
        'dy': 0,
        'sigma': 2,
        'color': '#000000',
        'sourceDeclaration': 'drop-shadow(0 0 2px #000)',
      },
    ]);
    expect(
      () => normalizeSvgFloor(
        source.replaceAll('2px', '3px'),
        {'First_Floor'},
        {'First_Floor'},
      ),
      throwsFormatException,
    );
  });

  test('attached content retains dependency targets without painting another floor', () {
    const source =
        '<svg viewBox="0 0 10 10"><g id="Ground_Level" fill="#123456"><use href="#Other"/></g><g id="Attached"><path d="M0 0L1 1"/></g><g id="Other"><g id="OtherPart"><path id="shared" d="M1 1L2 2"/></g></g></svg>';
    final document = XmlDocument.parse(
      normalizeSvgFloor(
        source,
        {'Ground_Level', 'Attached'},
        {'Ground_Level', 'Attached', 'Other', 'OtherPart'},
      ),
    );
    final elements = document.descendantElements.toList();
    expect(
      elements
          .singleWhere((e) => e.getAttribute('id') == 'shared')
          .ancestors
          .whereType<XmlElement>()
          .any((e) => e.name.local == 'defs'),
      isTrue,
    );
    final dependency = elements.singleWhere(
      (e) => e.getAttribute('id') == 'Other',
    );
    expect(dependency.childElements.single.getAttribute('id'), 'OtherPart');
    expect(
      dependency.descendantElements
          .singleWhere((e) => e.name.local == 'path')
          .getAttribute('d'),
      'M1 1L2 2',
    );
    expect(
      elements
          .singleWhere((e) => e.getAttribute('id') == 'Attached')
          .ancestors
          .whereType<XmlElement>()
          .any((e) => e.name.local == 'defs'),
      isFalse,
    );
    expect(svgLayerOrder(source, {'Ground_Level', 'Attached', 'Other'}), [
      'Ground_Level',
      'Attached',
      'Other',
    ]);
  });

  test('unsafe href, missing use target and excluded content fail closure', () {
    for (final source in [
      '<svg><g id="Ground_Level"><use href="https://bad.invalid/x.svg#x"/></g></svg>',
      '<svg><g id="Ground_Level"><use href="#missing"/></g></svg>',
      '<svg><g id="Second_Floor"/></svg>',
      '<svg><g id="Ground_Level"><image href="data:image/png;base64,AA=="/></g></svg>',
      '<svg><style>.floor {fill:url(https://bad.invalid/paint)}</style><g id="Ground_Level" class="floor"/></svg>',
    ]) {
      expect(
        () => normalizeSvgFloor(
          source,
          {'Ground_Level'},
          {'Ground_Level', 'Second_Floor'},
        ),
        throwsFormatException,
      );
    }
  });

  test('invalid candidate preserves active pointer and prior pack', () async {
    final packs = Directory('${temporary.path}/packs');
    await packs.create();
    final active = File('${packs.path}/active.json');
    await active.writeAsString('{"version":"A"}');
    final bad = Directory('${temporary.path}/bad');
    await bad.create();
    await File('${bad.path}/manifest.json').writeAsString(
      canonicalJson({'schemaVersion': 1, 'maps': [], 'outputs': []}),
    );
    await expectLater(promoteCandidate(bad, packs), throwsFormatException);
    expect(jsonDecode(await active.readAsString()), {'version': 'A'});
  });
}

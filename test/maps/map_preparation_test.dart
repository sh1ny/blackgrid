import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'package:blackgrid/domain/settings.dart' show supportedMaps;

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

  test(
    'preparation source identities cover every unchanged selector exactly once',
    () {
      expect(supportedMapSources.keys, supportedMaps);
      expect(supportedMapSources.values.toSet(), hasLength(13));
      for (final entry in supportedMapSources.entries) {
        final local = calibrationFor(entry.value);
        expect(local['id'], entry.key);
        expect(local['sourceKey'], entry.value);
      }
      expect(supportedMapSources['thelab'], 'the-lab');
      expect(supportedMapSources['streetsoftarkov'], 'streets-of-tarkov');
      expect(supportedMapSources['groundzero'], 'ground-zero');
      expect(supportedMapSources['labyrinth'], 'the-labyrinth');
      for (final alias in [
        'lab',
        'labs',
        'thelab',
        'streetsoftarkov',
        'groundzero',
      ]) {
        expect(() => calibrationFor(alias), throwsFormatException);
      }
    },
  );

  for (final entry in <String, (List<String>, Set<String>, num)>{
    'customs': (
      [
        'Ground_Level',
        'Second_Floor',
        'Third_Floor',
        'Fourth_Floor',
        'Underground_Level',
      ],
      {'Fourth_Floor'},
      1062.4827,
    ),
    'reserve': (
      [
        'Ground_Level',
        'Second_Floor',
        'Third_Floor',
        'Fourth_Floor',
        'Fifth_Floor',
        'Bunkers',
      ],
      {'Second_Floor', 'Third_Floor', 'Fourth_Floor', 'Fifth_Floor'},
      827.28742,
    ),
  }.entries) {
    final (ids, tileOnly, width) = entry.value;
    test(
      '${entry.key} abstract SVG keeps every declared tile-only floor as an overlay',
      () {
        final local = calibrationFor(entry.key);
        final floors = (local['floors'] as List).cast<Map<String, Object?>>();
        expect(local['kind'], 'vector');
        expect(floors.map((floor) => floor['id']), ids);
        expect(
          floors.where((f) => f['sourceTileUrl'] != null).map((f) => f['id']),
          tileOnly,
        );
        expect((local['artworkFrame'] as Map)['width'], width);
        expect((local['geometry'] as Map)['projection'], 'bounds-normalized');
        expect((local['rasterOverlayFrame'] as Map)['nativeZoom'], 4);
        // The SVG frame is the original revision-0 pin basis again.
        expect((local['geometry'] as Map)['legacyPinBounds'], isNull);
        expect(
          (local['geometry'] as Map)['bounds'],
          entry.key == 'customs'
              ? [
                  [698, -307],
                  [-372, 237],
                ]
              : [
                  [289, -274],
                  [-303, 272],
                ],
        );
        final upstream = <String, dynamic>{
          'svgLayer': 'Ground_Level',
          'tilePath': 'https://example.invalid/main/{z}/{x}/{y}.png',
          'layers': [
            for (final floor in floors.skip(1))
              {
                'name': floor['id'],
                // Actual publisher has no svgLayer for the tile-only floors;
                // binding must not depend on inventing those groups.
                if (floor['sourceTileUrl'] != null)
                  'tilePath': floor['sourceTileUrl']
                else ...{
                  'svgLayer': floor['id'],
                  'tilePath': 'https://example.invalid/${floor['id']}.png',
                },
              },
          ],
        };
        expect(
          reconcileFloors(local, upstream).map((floor) => floor['id']),
          ids,
        );
        for (var index = 0; index < ids.length - 1; index++) {
          final changed = {
            ...upstream,
            'layers': [
              for (var i = 0; i < (upstream['layers'] as List).length; i++)
                if (i != index) (upstream['layers'] as List)[i],
            ],
          };
          expect(() => reconcileFloors(local, changed), throwsFormatException);
        }
        expect(
          () => reconcileFloors(local, {
            ...upstream,
            'layers': [
              ...(upstream['layers'] as List),
              {'tilePath': 'https://example.invalid/added/{z}/{x}/{y}.png'},
            ],
          }),
          throwsFormatException,
        );
      },
    );
  }

  test('SVG root floor closure and publisher attachments reject lost unowned or renamed groups', () {
    const source =
        '<svg viewBox="0 0 10 10">'
        '<g id="Ground_Level"/><g id="First_Floor" data-keep-with-group="Ground_Level"/>'
        '<g id="Second_Floor"/></svg>';
    final floors = <Map<String, Object?>>[
      {
        'id': 'Ground_Level',
        'attachedIds': ['First_Floor'],
      },
      {'id': 'Second_Floor', 'attachedIds': <String>[]},
    ];
    validateSvgFloorInventory(source, floors);
    expect(
      svgLayerOrder(source, {'Ground_Level', 'First_Floor', 'Second_Floor'}),
      ['Ground_Level', 'First_Floor', 'Second_Floor'],
    );
    for (final changed in [
      source.replaceFirst('<g id="Second_Floor"/>', ''),
      source.replaceFirst('</svg>', '<g id="Uncalibrated_Level"/></svg>'),
      source.replaceFirst('data-keep-with-group="Ground_Level"', ''),
      source.replaceFirst(
        'data-keep-with-group="Ground_Level"',
        'data-keep-with-group="Second_Floor"',
      ),
      source.replaceFirst('id="First_Floor"', 'id="Different_Floor"'),
      source.replaceFirst('<g id="Second_Floor"/>', '<g/>'),
      source.replaceFirst(
        '</svg>',
        '<defs><g data-keep-with-group="Ground_Level"/></defs></svg>',
      ),
      source.replaceFirst(
        '</svg>',
        '<defs><g id="First_Floor" data-keep-with-group="Ground_Level"/></defs></svg>',
      ),
    ]) {
      expect(
        () => validateSvgFloorInventory(changed, floors),
        throwsFormatException,
      );
    }
  });

  test(
    'Ground Zero requires exactly every metadata-declared raster alternative',
    () {
      final local = calibrationFor('ground-zero');
      final dependencies = (local['rasterDependencies'] as List).cast<Map>();
      final upstream = <String, dynamic>{
        'svgLayer': 'Ground_Level',
        'tilePath': dependencies.first['sourceTileUrl'],
        'layers': [
          for (final dependency in dependencies.skip(1))
            {
              'svgLayer': dependency['id'],
              'tilePath': dependency['sourceTileUrl'],
            },
        ],
      };
      final floors = reconcileFloors(local, upstream);
      expect(floors.map((floor) => floor['id']), [
        'Ground_Level',
        'Second_Floor',
        'Third_Floor',
        'Underground_Level',
      ]);
      expect(floors.first['attachedIds'], ['First_Floor']);
      for (final changed in [
        {...upstream, 'tilePath': null},
        {
          ...upstream,
          'layers': [
            ...(upstream['layers'] as List).skip(1),
            {'svgLayer': 'Second_Floor'},
          ],
        },
        {
          ...upstream,
          'layers': [
            ...(upstream['layers'] as List),
            {'tilePath': 'https://example.invalid/unknown/{z}/{x}/{y}.png'},
          ],
        },
      ]) {
        expect(() => reconcileFloors(local, changed), throwsFormatException);
      }
    },
  );

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

  test('use with a missing local target renders nothing, like a browser', () {
    const source =
        '<svg viewBox="0 0 10 10"><defs><path id="kept" d="M0 0L1 1"/></defs><g id="Ground_Level"><use xlink:href="#kept" xmlns:xlink="http://www.w3.org/1999/xlink"/><use xlink:href="#stairs-86" xmlns:xlink="http://www.w3.org/1999/xlink"/></g></svg>';
    final uses = XmlDocument.parse(
      normalizeSvgFloor(source, {'Ground_Level'}, {'Ground_Level'}),
    ).findAllElements('use').toList();
    expect(uses.map((e) => e.getAttribute('href', namespace: '*')), ['#kept']);
    expect(
      () => normalizeSvgFloor(
        source.replaceAll('#stairs-86', '#stairs-1'),
        {'Ground_Level'},
        {'Ground_Level'},
      ),
      throwsFormatException,
      reason: 'only the known deleted Streets stair symbols are dropped',
    );
  });

  test(
    'unsafe href, missing paint target and excluded content fail closure',
    () {
      for (final source in [
        '<svg><g id="Ground_Level"><use href="https://bad.invalid/x.svg#x"/></g></svg>',
        '<svg><g id="Ground_Level"><path fill="url(#missing)"/></g></svg>',
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
    },
  );

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

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image;
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import '../../tool/maps/pack.dart';
import '../../tool/maps/svg.dart';
import '../../tool/maps/calibration.dart';

void main() {
  late Directory temporary;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('blackgrid-map-test-');
  });
  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  Uint8List png(int width, int height, {bool empty = false}) {
    final picture = image.Image(width: width, height: height, numChannels: 4);
    if (!empty) picture.setPixelRgba(0, 0, 20, 40, 60, 255);
    return image.encodePng(picture);
  }

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
    await FrozenInputs.open(root);
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

  Future<Directory> fixture({bool additionalVisibleTile = false}) async {
    final raw = Directory('${temporary.path}/raw');
    await raw.create();
    final sources = <Map<String, Object?>>[];
    Future<void> put(String path, List<int> bytes) async {
      final file = File('${raw.path}/$path');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      sources.add({
        'path': path,
        'url': 'https://example.invalid/$path',
        'sha256': sha256.convert(bytes).toString(),
      });
    }

    final locals = [
      for (final key in ['interchange', 'the-lab', 'icebreaker'])
        calibrationFor(key),
    ];
    await put(
      'calibration.json',
      utf8.encode(canonicalJson({'schemaVersion': 1, 'maps': locals})),
    );
    final metadata = [];
    final mapData = <String, Object?>{};
    final solid = png(256, 256), empty = png(256, 256, empty: true);
    for (final local in locals) {
      final floors = (local['floors'] as List).cast<Map<String, Object?>>();
      metadata.add({
        'normalizedName': local['sourceKey'],
        'maps': [
          {
            'key': local['sourceKey'],
            'projection': 'interactive',
            'author': 'Synthetic fixture author',
            'authorLink': 'https://example.invalid/',
            if (local['kind'] == 'vector')
              'svgLayer': floors.first['id']
            else
              'tilePath': floors.first['sourceTileUrl'],
            'layers': [
              for (final floor in floors.skip(1))
                {
                  if (local['kind'] == 'vector')
                    'svgLayer': floor['id']
                  else
                    'tilePath': floor['sourceTileUrl'],
                },
            ],
          },
        ],
      });
      mapData[local['id'] as String] = {
        'id': local['id'],
        'normalizedName': local['sourceKey'],
        if (local['id'] == 'icebreaker')
          'extracts': [
            {
              'id': '9bf65c4c24d0153f1542a90ddabadb37198ab9ff',
              'name': 'Heli',
              'position': {'x': .28, 'y': 22.56, 'z': -66.03},
            },
          ],
        'spawns': [
          {
            'position': {'x': 2, 'y': null, 'z': 3},
            'zoneName': 'Independently authored offline fixture',
          },
        ],
        'bosses': [],
      };
      if (local['kind'] == 'raster') {
        for (final floor in floors) {
          for (var x = 0; x < 16; x++) {
            for (var y = 0; y < 16; y++) {
              await put(
                rawTilePath(local['id'] as String, floor['id'] as String, x, y),
                y == 0 && (x == 0 || (additionalVisibleTile && x == 1))
                    ? solid
                    : empty,
              );
            }
          }
        }
      }
    }
    await put('metadata/maps.json', utf8.encode(jsonEncode(metadata)));
    await put(
      'markers/maps.json',
      utf8.encode(
        jsonEncode({
          'data': {'maps': mapData},
        }),
      ),
    );
    await put('markers/maps_en.json', utf8.encode('{"data":{}}'));
    const svg = '''<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 1127.6852 947.02582">
<style>.shadow {filter:drop-shadow(0 0 2px #000)} .paint {stroke:url(#ramp)}</style>
<defs><linearGradient id="base"><stop offset="0" stop-color="#fff"/><stop offset="1" stop-color="#000"/></linearGradient><linearGradient id="ramp" xlink:href="#base" x1="0" x2="1"/></defs>
<g id="Ground_Level"><path d="M0 0L1 0L1 1Z"/></g>
<g id="First_Floor" fill="#123456"><g id="Structure-1" class="shadow"><path d="M1 1L2 1L2 2Z"/></g><g id="Pavament-1"><path d="M2 2L3 2L3 3Z"/></g><g id="Floor-1"><path d="M3 3L4 3L4 4Z"/></g><g id="Ramps-1" class="paint"><path d="M4 4L5 5"/></g></g>
<g id="Second_Floor"><g id="Structure-2" class="shadow"><path d="M5 5L6 5L6 6Z"/></g><g id="Floor-2"><path d="M6 6L7 6L7 7Z"/></g><g id="Ramps-2" class="paint"><path d="M7 7L8 8"/></g></g>
</svg>''';
    await put('interchange/Interchange.svg', utf8.encode(svg));
    await put(
      'terms/svg-maps-README.md',
      utf8.encode('Independently authored test terms, not production artwork'),
    );
    await put(
      'terms/svg-maps-LICENSE.md',
      utf8.encode('Independently authored test terms'),
    );
    sources.sort(
      (a, b) => (a['path'] as String).compareTo(b['path'] as String),
    );
    await File('${raw.path}/sources.json')
        .writeAsString(canonicalJson({'schemaVersion': 1, 'sources': sources}));
    return raw;
  }

  test('two offline rebuilds are byte-identical and keep original crop/frame units', () async {
    final raw = await fixture();
    final a = await rebuildCandidate(raw, Directory('${temporary.path}/a'));
    final b = await rebuildCandidate(raw, Directory('${temporary.path}/b'));
    expect(canonicalJson(a), canonicalJson(b));
    final maps = (a['maps'] as List).cast<Map<String, dynamic>>();
    final labs = maps.singleWhere((m) => m['id'] == 'thelab');
    expect(labs['artworkFrame']['width'], 2800);
    expect(labs['artworkFrame']['tileStride'], 175);
    expect(labs['displayCrop'], {'left': 0, 'top': 0, 'right': 1, 'bottom': 1});
    expect(labs['markers'][0]['position']['height'], isNull);
    expect(a['preparationVersion'], 2);
    final emptyTile = (labs['floors'][0]['artwork']['tiles'] as List)
        .singleWhere((tile) => tile['x'] == 0 && tile['y'] == 1);
    final witness = 'evidence/tile-alpha/${emptyTile['sourceSha256']}.png';
    final witnessBytes = await packFile(
      Directory('${temporary.path}/a'),
      witness,
    ).readAsBytes();
    expect(inspectPng(witnessBytes).empty, isTrue);
    expect(sha256.convert(witnessBytes).toString(), emptyTile['sourceSha256']);
    expect(
      (a['outputs'] as List).where(
        (output) =>
            (output['path'] as String).startsWith('evidence/tile-alpha/'),
      ),
      hasLength(1),
    );
    final interchange = maps.singleWhere((m) => m['id'] == 'interchange');
    final ground = interchange['floors'][0]['artwork']['components'] as List;
    expect(ground.map((c) => c['id']), ['Ground_Level']);
    expect(ground.single['effects'], isEmpty);
    final middle = interchange['floors'][1]['artwork']['components'] as List;
    expect(middle.map((c) => c['id']), [
      'Structure-1',
      'Pavament-1',
      'Floor-1',
      'Ramps-1',
    ]);
    expect(middle.first['effects'].single['sigma'], 2);
    expect(middle.skip(1).every((c) => (c['effects'] as List).isEmpty), isTrue);
    expect(interchange['layerOrder'], [
      'Ground_Level',
      'Structure-1',
      'Pavament-1',
      'Floor-1',
      'Ramps-1',
      'Structure-2',
      'Floor-2',
      'Ramps-2',
    ]);
    final rampDocument = XmlDocument.parse(
      await File('${temporary.path}/a/${middle.last['sourceSvg']}')
          .readAsString(),
    );
    final rampElements = rampDocument.descendantElements.toList();
    expect(
      rampDocument.rootElement.getAttribute('viewBox'),
      '0 0 1127.6852 947.02582',
    );
    expect(
      rampElements
          .singleWhere((e) => e.getAttribute('id') == 'First_Floor')
          .getAttribute('fill'),
      '#123456',
    );
    expect(rampElements.where((e) => e.name.local == 'path').length, 1);
    expect(
      rampElements
          .singleWhere((e) => e.getAttribute('id') == 'ramp')
          .getAttribute('href', namespace: 'http://www.w3.org/1999/xlink'),
      '#base',
    );
  });

  Future<void> saveManifest(
    Directory candidate,
    Map<String, dynamic> manifest, {
    bool refreshOutputs = false,
  }) async {
    if (refreshOutputs) {
      for (final output in manifest['outputs'] as List) {
        output['sha256'] = sha256
            .convert(
              await packFile(candidate, output['path'] as String).readAsBytes(),
            )
            .toString();
      }
      (manifest['outputs'] as List).sort(
        (a, b) => (a['path'] as String).compareTo(b['path'] as String),
      );
    }
    await packFile(
      candidate,
      'manifest.json',
    ).writeAsString(canonicalJson(manifest));
  }

  test('promotion rejects an existing compiled layer substituted for another component', () async {
    final candidate = Directory('${temporary.path}/candidate');
    final manifest = await rebuildCandidate(await fixture(), candidate);
    final vectorMap = (manifest['maps'] as List).singleWhere(
      (map) => map['id'] == 'interchange',
    );
    final ground = vectorMap['floors'][0]['artwork']['components'][0];
    final upper = (vectorMap['floors'][2]['artwork']['components'] as List)
        .singleWhere((component) => component['id'] == 'Floor-2');
    final originalPath = ground['path'];
    ground['path'] = upper['path'];
    await saveManifest(candidate, manifest);
    await expectLater(
      promoteCandidate(candidate, Directory('${temporary.path}/packs')),
      throwsFormatException,
    );

    // Correcting the path is insufficient if the wrong picture bytes replace
    // the canonical payload and the attacker refreshes the manifest checksum.
    ground['path'] = originalPath;
    await packFile(candidate, originalPath as String).writeAsBytes(
      await packFile(candidate, upper['path'] as String).readAsBytes(),
    );
    await saveManifest(candidate, manifest, refreshOutputs: true);
    await expectLater(
      promoteCandidate(candidate, Directory('${temporary.path}/packs')),
      throwsFormatException,
    );
  });

  test('promotion rejects a forged transparent tile against its decoded frozen PNG witness', () async {
    final candidate = Directory('${temporary.path}/candidate');
    final manifest = await rebuildCandidate(
      await fixture(additionalVisibleTile: true),
      candidate,
    );
    final labs = (manifest['maps'] as List).singleWhere(
      (map) => map['id'] == 'thelab',
    );
    final tiles = labs['floors'][0]['artwork']['tiles'] as List;
    final solid = tiles.singleWhere((tile) => tile['x'] == 0 && tile['y'] == 0);
    final transparent = tiles.singleWhere(
      (tile) => tile['x'] == 0 && tile['y'] == 1,
    );
    expect(transparent['empty'], isTrue);
    final emptyWitness = packFile(
      candidate,
      'evidence/tile-alpha/${transparent['sourceSha256']}.png',
    );
    final originalWitnessBytes = await emptyWitness.readAsBytes();
    expect(inspectPng(originalWitnessBytes).empty, isTrue);
    await emptyWitness.delete();
    await expectLater(
      validateCandidate(candidate),
      throwsA(isA<FileSystemException>()),
    );
    await emptyWitness.writeAsBytes([137, 80, 78, 71]);
    await expectLater(validateCandidate(candidate), throwsFormatException);
    await emptyWitness.writeAsBytes(originalWitnessBytes);
    await validateCandidate(candidate);
    final originalPath = solid.remove('path') as String;
    solid['empty'] = true;
    solid.remove('alphaBounds');
    await saveManifest(candidate, manifest);
    await expectLater(
      promoteCandidate(candidate, Directory('${temporary.path}/packs')),
      throwsFormatException,
    );

    // Even a hash-consistent witness cannot declare an opaque source empty.
    final witness = 'evidence/tile-alpha/${solid['sourceSha256']}.png';
    final witnessFile = packFile(candidate, witness);
    await witnessFile.parent.create(recursive: true);
    await witnessFile.writeAsBytes(
      await packFile(candidate, originalPath).readAsBytes(),
    );
    (manifest['outputs'] as List).add({'path': witness, 'sha256': ''});
    await saveManifest(candidate, manifest, refreshOutputs: true);
    await expectLater(
      promoteCandidate(candidate, Directory('${temporary.path}/packs')),
      throwsFormatException,
    );
  });

  test('promotion rejects negative and out-of-frame crops without changing frame or pins', () async {
    final candidate = Directory('${temporary.path}/candidate');
    final manifest = await rebuildCandidate(await fixture(), candidate);
    final labs = (manifest['maps'] as List).singleWhere(
      (map) => map['id'] == 'thelab',
    );
    final originalCrop = Map<String, dynamic>.from(labs['displayCrop'] as Map);
    for (final mutation in [
      {'left': -1},
      {'top': -1},
      {'right': 2801},
      {'bottom': 2801},
    ]) {
      labs['displayCrop'] = {...originalCrop, ...mutation};
      await saveManifest(candidate, manifest);
      await expectLater(
        promoteCandidate(candidate, Directory('${temporary.path}/packs')),
        throwsFormatException,
      );
    }
    labs['displayCrop'] = originalCrop;
    await saveManifest(candidate, manifest);
    await validateCandidate(candidate);
    expect(labs['geometry']['coordinateRevision'], 1);
    expect(labs['geometry']['pinFrame'], 'labs-native-normalized');
    final ice = (manifest['maps'] as List).singleWhere(
      (map) => map['id'] == 'icebreaker',
    );
    expect(ice['geometry'], calibrationFor('icebreaker')['geometry']);
  });

  test('failed new generation preserves asset discovery for an older frozen floor calibration', () async {
    final raw = await fixture();
    final older = Directory('${temporary.path}/older');
    final olderManifest = await rebuildCandidate(raw, older);

    // Represent a previously published generation with no evidence-owned
    // marker floors. Its calibration, source index and output hashes remain
    // coherent; only the authoring code now knows the newer assignments.
    final calibrationFile = File('${older.path}/evidence/calibration.json');
    final olderCalibration = jsonDecode(
      await calibrationFile.readAsString(),
    ) as Map<String, dynamic>;
    final olderIceCalibration = (olderCalibration['maps'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((map) => map['id'] == 'icebreaker');
    olderIceCalibration.remove('markerFloorAssignments');
    final calibrationBytes = utf8.encode(canonicalJson(olderCalibration));
    await calibrationFile.writeAsBytes(calibrationBytes);

    final indexFile = File('${older.path}/evidence/sources.json');
    final olderIndex =
        jsonDecode(await indexFile.readAsString()) as Map<String, dynamic>;
    final calibrationSource = (olderIndex['sources'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((source) => source['path'] == 'calibration.json');
    calibrationSource['sha256'] = sha256.convert(calibrationBytes).toString();
    final indexBytes = utf8.encode(canonicalJson(olderIndex));
    await indexFile.writeAsBytes(indexBytes);
    olderManifest['sourceGeneration'] = sha256.convert(indexBytes).toString();
    for (final output in olderManifest['outputs'] as List) {
      if (output['path'] == 'evidence/calibration.json') {
        output['sha256'] = sha256.convert(calibrationBytes).toString();
      }
      if (output['path'] == 'evidence/sources.json') {
        output['sha256'] = sha256.convert(indexBytes).toString();
      }
    }
    final sourceMarkers = jsonDecode(
      await File('${older.path}/evidence/markers/maps.json').readAsString(),
    ) as Map<String, dynamic>;
    final translations =
        (jsonDecode(
              await File('${older.path}/evidence/markers/maps_en.json')
                  .readAsString(),
            ) as Map<String, dynamic>)['data']
            as Map<String, dynamic>;
    final olderIce = (olderManifest['maps'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((map) => map['id'] == 'icebreaker');
    olderIce.remove('markerFloorAssignments');
    olderIce['markers'] = prepareMarkers(
      sourceMarkers,
      translations,
      olderIceCalibration,
    );
    expect((olderIce['markers'] as List).first.containsKey('floorId'), isFalse);
    final olderManifestFile = File('${older.path}/manifest.json');
    await olderManifestFile.writeAsString(canonicalJson(olderManifest));

    final packs = Directory('${temporary.path}/packs');
    final version = await promoteCandidate(older, packs);
    final active = File('${packs.path}/active.json');
    final originalPointer = await active.readAsString();
    final originalDirectories = await preparedAssetDirectories(packs);
    expect(originalDirectories, contains('versions/$version/'));

    final newer = Directory('${temporary.path}/newer');
    final newerManifest = await rebuildCandidate(raw, newer);
    final newerIce = (newerManifest['maps'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((map) => map['id'] == 'icebreaker');
    expect((newerIce['markers'] as List).first['floorId'], 'Helipad');
    await File('${newer.path}/artwork/thelab/First_Level/0/0.png')
        .writeAsBytes([1, 2, 3]);
    await expectLater(promoteCandidate(newer, packs), throwsFormatException);
    expect(await active.readAsString(), originalPointer);
    expect(await preparedAssetDirectories(packs), originalDirectories);

    // A newer assignment cannot be inserted into the older generation's
    // manifest without its own matching frozen calibration evidence.
    (olderIce['markers'] as List).first['floorId'] = 'Helipad';
    await olderManifestFile.writeAsString(canonicalJson(olderManifest));
    await expectLater(
      validateCandidate(older),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Markers differ from independently frozen source',
        ),
      ),
    );
    expect(await active.readAsString(), originalPointer);
    expect(await preparedAssetDirectories(packs), originalDirectories);
  });

  test('missing tile rejects offline rebuild without publishing', () async {
    final raw = await fixture();
    final tile = File(
      '${raw.path}/${rawTilePath('thelab', 'First_Level', 15, 15)}',
    );
    await tile.delete();
    final packs = Directory('${temporary.path}/packs');
    await packs.create();
    await File('${packs.path}/active.json').writeAsString('{"version":"A"}');
    await expectLater(
      rebuildCandidate(raw, Directory('${temporary.path}/candidate')),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      await File('${packs.path}/active.json').readAsString(),
      '{"version":"A"}',
    );
  });

  test('promotion publishes one complete version and interruption retains A', () async {
    final raw = await fixture();
    final candidate = Directory('${temporary.path}/candidate');
    await rebuildCandidate(raw, candidate);
    final packs = Directory('${temporary.path}/packs');
    final version = await promoteCandidate(candidate, packs);
    final active = File('${packs.path}/active.json');
    final original = await active.readAsString();
    expect(jsonDecode(original)['version'], version);
    await validateCandidate(Directory('${packs.path}/versions/$version'));
    // A user-supplied directory with a trailing separator has the same closure.
    await validateCandidate(Directory('${packs.path}/versions/$version/'));
    // Simulate interruption immediately before the single pointer boundary.
    await File('${packs.path}/active.next.json').writeAsString('incomplete');
    await expectLater(
      promoteCandidate(candidate, packs),
      throwsFormatException,
    );
    expect(await active.readAsString(), original);
    // Required raster corruption fails even though a previous version exists.
    await File('${candidate.path}/artwork/thelab/First_Level/0/0.png')
        .writeAsBytes([1, 2, 3]);
    await expectLater(
      promoteCandidate(candidate, packs),
      throwsFormatException,
    );
    expect(await active.readAsString(), original);
  });

  test(
    'normalization-only candidate cannot be promoted before compilation',
    () async {
      final raw = await fixture();
      final candidate = Directory('${temporary.path}/candidate');
      await rebuildCandidate(raw, candidate, compileVectors: false);
      await expectLater(
        promoteCandidate(candidate, Directory('${temporary.path}/packs')),
        throwsFormatException,
      );
      await compileCandidate(candidate);
      await validateCandidate(candidate);
    },
  );
}

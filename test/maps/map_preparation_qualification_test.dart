@Tags(['qualification'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import '../../tool/maps/pack.dart';
import '../../tool/maps/calibration.dart';

import '../support/map_preparation_fixtures.dart';

Future<void> _refreezeEvidence(
  Directory candidate,
  Map<String, dynamic> manifest,
  String sourcePath,
) async {
  final indexFile = packFile(candidate, 'evidence/sources.json');
  final index =
      jsonDecode(await indexFile.readAsString()) as Map<String, dynamic>;
  final source = (index['sources'] as List).singleWhere(
    (source) => source['path'] == sourcePath,
  );
  source['sha256'] = sha256
      .convert(await packFile(candidate, 'evidence/$sourcePath').readAsBytes())
      .toString();
  final bytes = utf8.encode(canonicalJson(index));
  await indexFile.writeAsBytes(bytes);
  manifest['sourceGeneration'] = sha256.convert(bytes).toString();
}

void main() {
  late Directory suiteRoot;
  late MapPreparationFixtures fixtures;
  late Directory temporary;
  setUpAll(() async {
    suiteRoot = await Directory.systemTemp.createTemp(
      'blackgrid-map-qualification-',
    );
    addTearDown(() => suiteRoot.delete(recursive: true));
    fixtures = await MapPreparationFixtures.create(suiteRoot);
  });
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'blackgrid-map-candidate-',
    );
  });
  tearDown(() => temporary.delete(recursive: true));

  Future<Directory> candidate(String name) =>
      fixtures.copyCandidate(Directory('${temporary.path}/$name'));

  test('two offline all-map rebuilds are byte-identical and keep original crop/frame units', () async {
    final a = await readManifest(fixtures.first);
    final b = await readManifest(fixtures.second);
    expect(canonicalJson(a), canonicalJson(b));
    const expectedMapIds = [
      'factory',
      'customs',
      'woods',
      'shoreline',
      'interchange',
      'thelab',
      'reserve',
      'lighthouse',
      'streetsoftarkov',
      'groundzero',
      'terminal',
      'icebreaker',
      'labyrinth',
    ];
    final expectedFloorIds = {
      'factory': ['Ground_Floor', 'Second_Floor', 'Third_Floor', 'Basement'],
      'customs': [
        'Ground_Level',
        'Second_Floor',
        'Third_Floor',
        'Fourth_Floor',
        'Underground_Level',
      ],
      for (final id in ['shoreline', 'groundzero'])
        id: [
          'Ground_Level',
          'Second_Floor',
          'Third_Floor',
          'Underground_Level',
        ],
      'woods': ['Ground_Level'],
      'interchange': ['Ground_Level', 'First_Floor', 'Second_Floor'],
      'thelab': ['First_Level', 'Second_Level', 'Technical_Level'],
      'reserve': [
        'Ground_Level',
        'Second_Floor',
        'Third_Floor',
        'Fourth_Floor',
        'Fifth_Floor',
        'Bunkers',
      ],
      'lighthouse': ['Ground_Level'],
      'streetsoftarkov': [
        'Ground_Level',
        'Second_Floor',
        'Third_Floor',
        'Fourth_Floor',
        'Fifth_Floor',
        'Underground_Level',
      ],
      'terminal': ['Ground_Level'],
      'icebreaker': icebreakerSources.keys.toList(),
      'labyrinth': ['Main_Level'],
    };
    const attachedFirstFloorMaps = {
      'customs',
      'shoreline',
      'streetsoftarkov',
      'groundzero',
      'terminal',
    };
    var rasterFloors = 0;
    var rasterTiles = 0;
    for (final manifest in [a, b]) {
      expect(
        (manifest['maps'] as List).map((map) => map['id']),
        expectedMapIds,
      );
      expect(manifest['preparationVersion'], 3);
      for (final map in manifest['maps'] as List) {
        final floors = map['floors'] as List;
        expect(floors.map((floor) => floor['id']), expectedFloorIds[map['id']]);
        expect(floors.where((floor) => floor['base'] == true), hasLength(1));
        if (map['kind'] != 'vector') continue;
        final svgFloors = [
          for (final floor in floors)
            if (floor['sourceTileUrl'] == null) floor,
        ];
        final expectedComponents = <String>[
          for (final floor in svgFloors) ...[
            if (map['id'] == 'interchange' && floor['id'] == 'First_Floor') ...[
              'Structure-1',
              'Pavament-1',
              'Floor-1',
              'Ramps-1',
            ] else if (map['id'] == 'interchange' &&
                floor['id'] == 'Second_Floor') ...[
              'Structure-2',
              'Floor-2',
              'Ramps-2',
            ] else
              floor['id'] as String,
            if (floor['id'] == 'Ground_Level' &&
                attachedFirstFloorMaps.contains(map['id']))
              'First_Floor',
          ],
        ];
        expect(map['layerOrder'], expectedComponents);
        expect([
          for (final floor in svgFloors)
            for (final component in floor['artwork']['components'] as List)
              component['id'],
        ], expectedComponents);
        final sourcePath = map['sourceSvgPath'] as String? ?? vectorSourcePath;
        final document = XmlDocument.parse(
          await packFile(fixtures.first, 'evidence/$sourcePath').readAsString(),
        );
        expect(
          document.rootElement
              .getAttribute('viewBox')!
              .split(RegExp(r'\s+'))
              .map(double.parse),
          map['artworkFrame']['viewBox'],
        );
        if (attachedFirstFloorMaps.contains(map['id'])) {
          expect(
            document.rootElement.childElements
                .singleWhere(
                  (element) => element.getAttribute('id') == 'First_Floor',
                )
                .getAttribute('data-keep-with-group'),
            'Ground_Level',
          );
        }
      }
      for (final map in manifest['maps'] as List) {
        // Raster maps, and tile-only floors drawn over an abstract SVG.
        final floors = [
          for (final floor in map['floors'] as List)
            if (map['kind'] == 'raster' || floor['sourceTileUrl'] != null)
              floor,
        ];
        for (final floor in floors) {
          final tiles = floor['artwork']['tiles'] as List;
          expect(tiles, hasLength(256));
          expect(tiles.map((tile) => '${tile['x']}/${tile['y']}').toSet(), {
            for (var x = 0; x < 16; x++)
              for (var y = 0; y < 16; y++) '$x/$y',
          });
          rasterFloors++;
          rasterTiles += tiles.length;
        }
      }
    }
    expect(rasterFloors, 2 * 25);
    expect(rasterTiles, 2 * 25 * 256);
    for (final output in a['outputs'] as List) {
      expect(
        await packFile(fixtures.first, output['path'] as String).readAsBytes(),
        await packFile(fixtures.second, output['path'] as String).readAsBytes(),
        reason: output['path'] as String,
      );
    }
    final groundZero = (a['maps'] as List).singleWhere(
      (map) => map['id'] == 'groundzero',
    );
    expect(groundZero['kind'], 'vector');
    final dependencies = groundZero['rasterDependencies'] as List;
    expect(dependencies.map((dependency) => dependency['id']), [
      'Ground_Level',
      'Second_Floor',
      'Third_Floor',
      'Underground_Level',
    ]);
    for (final dependency in dependencies) {
      expect(dependency['displayFrame']['width'], 4096);
      expect(dependency['displayFrame']['height'], 4096);
      final tiles = dependency['artwork']['tiles'] as List;
      expect(tiles, hasLength(256));
      expect(tiles.map((tile) => '${tile['x']}/${tile['y']}').toSet(), {
        for (var x = 0; x < 16; x++)
          for (var y = 0; y < 16; y++) '$x/$y',
      });
      expect(tiles.where((tile) => tile['empty'] == false), hasLength(1));
      final solid = tiles.singleWhere((tile) => tile['empty'] == false);
      expect(
        solid['sourcePath'],
        rawTilePath('groundzero', 'dependency-${dependency['id']}', 0, 0),
      );
      expect(
        solid['path'],
        'artwork/dependencies/groundzero/${dependency['id']}/0/0.png',
      );
    }
    for (final name in [
      'tasks.json',
      'tasks_en.json',
      'traders.json',
      'traders_en.json',
    ]) {
      expect(
        (a['outputs'] as List).where(
          (output) => output['path'] == 'evidence/quests/$name',
        ),
        hasLength(1),
      );
    }
    // Full production inventories cannot be shortened or filled with duplicate
    // coordinates. Private candidates copy only prepared outputs, never raw.
    for (final duplicate in [false, true]) {
      final private = Directory('${temporary.path}/inventory-$duplicate');
      await copyPack(fixtures.first, private);
      final manifest = await readManifest(private);
      final labs = (manifest['maps'] as List).singleWhere(
        (map) => map['id'] == 'thelab',
      );
      final tiles = labs['floors'][0]['artwork']['tiles'] as List;
      if (duplicate) {
        tiles[tiles.length - 1] = Map<String, dynamic>.from(tiles.first as Map);
      } else {
        tiles.removeLast();
      }
      await saveManifest(private, manifest);
      await expectLater(
        validateCandidate(private),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            duplicate
                ? 'Invalid raster tile closure'
                : 'Raster floor requires full z4 grid',
          ),
        ),
      );
    }
    final maps = (a['maps'] as List).cast<Map<String, dynamic>>();
    final labs = maps.singleWhere((m) => m['id'] == 'thelab');
    final frozenMetadata = jsonDecode(
      await packFile(
        fixtures.first,
        'evidence/metadata/maps.json',
      ).readAsString(),
    ) as List;
    final labsScene = interactiveMetadata(frozenMetadata, 'the-lab');
    expect(labsScene['transform'], [0.575, 281.2, 0.575, 193.7]);
    expect(labsScene['coordinateRotation'], 270);
    expect(labsScene['bounds'], [
      [-80, -477],
      [-287, -193],
    ]);
    expect((labs['geometry']['affine'] as List)[0], 0.575 * 256 / 175);
    expect(labs['artworkFrame']['width'], 2800);
    expect(labs['artworkFrame']['tileStride'], 175);
    expect(labs['displayCrop'], {'left': 0, 'top': 0, 'right': 1, 'bottom': 1});
    expect(labs['markers'][0]['position']['height'], isNull);
    expect(a['preparationVersion'], 3);
    final emptyTile = (labs['floors'][0]['artwork']['tiles'] as List)
        .singleWhere((tile) => tile['x'] == 0 && tile['y'] == 1);
    final witness = 'evidence/tile-alpha/${emptyTile['sourceSha256']}.png';
    final witnessBytes = await packFile(fixtures.first, witness).readAsBytes();
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
      await packFile(
        fixtures.first,
        middle.last['sourceSvg'] as String,
      ).readAsString(),
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

  test('private mutation templates retain complete vector and dependency inventories with one raster base', () async {
    final private = await candidate('template-inventory');
    final manifest = await validateCandidate(private);
    final full = await readManifest(fixtures.first);
    final maps = manifest['maps'] as List;
    expect(maps, hasLength(13));
    expect(
      maps.map((map) => map['id']),
      (full['maps'] as List).map((map) => map['id']),
    );
    for (final map in maps) {
      final floors = map['floors'] as List;
      expect(floors.where((floor) => floor['base'] == true), hasLength(1));
      final complete = (full['maps'] as List).singleWhere(
        (complete) => complete['id'] == map['id'],
      );
      if (map['kind'] == 'raster') {
        expect(floors, hasLength(1));
        expect(floors.single['artwork']['tiles'] as List, hasLength(256));
      } else {
        expect(floors, complete['floors']);
        expect(map['layerOrder'], complete['layerOrder']);
      }
      expect(map['rasterDependencies'], complete['rasterDependencies']);
      final assignments = map['markerFloorAssignments'] as Map?;
      if (assignments != null) {
        final ids = floors.map((floor) => floor['id']).toSet();
        expect(
          assignments.values.every(
            (assignment) => ids.contains(assignment['floorId']),
          ),
          isTrue,
        );
      }
    }
    final ice = maps.singleWhere((map) => map['id'] == 'icebreaker');
    expect(ice['floors'][0]['id'], 'Helipad');
    expect((ice['markers'] as List).first['floorId'], 'Helipad');
  });

  test(
    'all-map closure rejection leaves the active generation readable',
    () async {
      final published = await candidate('closure-published');
      final packs = Directory('${temporary.path}/closure-packs');
      final version = await promoteCandidate(published, packs);
      final active = packFile(packs, 'active.json');
      final pointer = await active.readAsString();
      final directories = await preparedAssetDirectories(packs);

      for (final mutation in [
        'missing-map',
        'duplicate-map',
        'legacy-version-with-new-inventory',
        'missing-vector-floor',
        'missing-calibration',
        'changed-calibration',
        'changed-frozen-transform',
        'changed-vector-source-path',
        'missing-vector-source',
        'changed-vector-frame',
        'missing-vector-source-floor',
        'extra-vector-source-floor',
        'changed-vector-attachment',
        'missing-labyrinth-backing',
      ]) {
        final private = await candidate('closure-$mutation');
        final manifest = await readManifest(private);
        final maps = manifest['maps'] as List;
        final factory = maps.singleWhere((map) => map['id'] == 'factory');
        if (mutation == 'missing-map') {
          maps.removeWhere((map) => map['id'] == 'terminal');
        } else if (mutation == 'duplicate-map') {
          final terminal = maps.indexWhere((map) => map['id'] == 'terminal');
          maps[terminal] = jsonDecode(jsonEncode(factory));
        } else if (mutation == 'legacy-version-with-new-inventory') {
          manifest['preparationVersion'] = 2;
        } else if (mutation == 'missing-vector-floor') {
          (factory['floors'] as List).removeLast();
        } else if (mutation == 'missing-calibration') {
          final path = 'evidence/calibration.json';
          final calibration = jsonDecode(
            await packFile(private, path).readAsString(),
          ) as Map<String, dynamic>;
          (calibration['maps'] as List).removeWhere(
            (map) => map['id'] == 'factory',
          );
          await packFile(
            private,
            path,
          ).writeAsString(canonicalJson(calibration));
          await _refreezeEvidence(private, manifest, 'calibration.json');
        } else if (mutation == 'changed-calibration') {
          (factory['geometry']['affine'] as List)[0] = -123;
        } else if (mutation == 'changed-frozen-transform') {
          final calibrationFile = packFile(
            private,
            'evidence/calibration.json',
          );
          final calibration = jsonDecode(
            await calibrationFile.readAsString(),
          ) as Map<String, dynamic>;
          final local = (calibration['maps'] as List).singleWhere(
            (map) => map['id'] == 'factory',
          );
          (local['geometry']['affine'] as List)[0] = -123;
          factory['geometry'] = local['geometry'];
          await calibrationFile.writeAsString(canonicalJson(calibration));
          await _refreezeEvidence(private, manifest, 'calibration.json');
        } else if (mutation == 'changed-vector-source-path') {
          factory['sourceSvgPath'] = vectorSourcePath;
        } else if (mutation == 'missing-vector-source') {
          final path = factory['sourceSvgPath'] as String;
          final indexFile = packFile(private, 'evidence/sources.json');
          final index = jsonDecode(
            await indexFile.readAsString(),
          ) as Map<String, dynamic>;
          (index['sources'] as List).removeWhere(
            (source) => source['path'] == path,
          );
          await indexFile.writeAsString(canonicalJson(index));
          manifest['sourceGeneration'] = sha256
              .convert(utf8.encode(canonicalJson(index)))
              .toString();
          (manifest['outputs'] as List).removeWhere(
            (output) => output['path'] == 'evidence/$path',
          );
          await packFile(private, 'evidence/$path').delete();
        } else if (mutation == 'changed-vector-frame') {
          final path = factory['sourceSvgPath'] as String;
          final file = packFile(private, 'evidence/$path');
          final document = XmlDocument.parse(await file.readAsString());
          final frame = (factory['artworkFrame']['viewBox'] as List).toList();
          frame[2] = (frame[2] as num) + 1;
          document.rootElement.setAttribute('viewBox', frame.join(' '));
          await file.writeAsString(document.toXmlString());
          await _refreezeEvidence(private, manifest, path);
        } else if (mutation == 'missing-vector-source-floor' ||
            mutation == 'extra-vector-source-floor' ||
            mutation == 'changed-vector-attachment') {
          final map = mutation == 'changed-vector-attachment'
              ? maps.singleWhere((map) => map['id'] == 'shoreline')
              : factory;
          final path = map['sourceSvgPath'] as String;
          final file = packFile(private, 'evidence/$path');
          final document = XmlDocument.parse(await file.readAsString());
          final root = document.rootElement;
          if (mutation == 'extra-vector-source-floor') {
            root.children.add(
              XmlElement(XmlName('g'), [
                XmlAttribute(XmlName('id'), 'Uncalibrated_Floor'),
              ]),
            );
          } else if (mutation == 'missing-vector-source-floor') {
            root.children.remove(root.childElements.last);
          } else {
            root.childElements
                .singleWhere(
                  (element) => element.getAttribute('id') == 'First_Floor',
                )
                .setAttribute('data-keep-with-group', 'Second_Floor');
          }
          await file.writeAsString(document.toXmlString());
          await _refreezeEvidence(private, manifest, path);
        } else {
          final labyrinth = maps.singleWhere((map) => map['id'] == 'labyrinth');
          final solid = (labyrinth['floors'][0]['artwork']['tiles'] as List)
              .singleWhere((tile) => tile['empty'] == false);
          final path = solid['path'] as String;
          (manifest['outputs'] as List).removeWhere(
            (output) => output['path'] == path,
          );
          await packFile(private, path).delete();
        }
        await saveManifest(private, manifest, refreshOutputs: true);
        await expectLater(
          promoteCandidate(private, packs),
          throwsFormatException,
          reason: mutation,
        );
        expect(await active.readAsString(), pointer, reason: mutation);
        expect(
          await preparedAssetDirectories(packs),
          directories,
          reason: mutation,
        );
        final stillActive = await validateCandidate(
          Directory('${packs.path}/versions/$version'),
        );
        expect(stillActive['maps'] as List, hasLength(13));
      }
    },
  );

  test('Ground Zero declared raster backing cannot lose or substitute dependencies', () async {
    final published = await candidate('dependency-published');
    final packs = Directory('${temporary.path}/dependency-packs');
    await promoteCandidate(published, packs);
    final active = packFile(packs, 'active.json');
    final pointer = await active.readAsString();
    final directories = await preparedAssetDirectories(packs);

    for (final mutation in [
      'missing-family',
      'missing-tile',
      'duplicate-tile',
      'wrong-output-path',
      'missing-output-bytes',
      'changed-native-frame',
    ]) {
      final private = await candidate('dependency-$mutation');
      final manifest = await readManifest(private);
      final groundZero = (manifest['maps'] as List).singleWhere(
        (map) => map['id'] == 'groundzero',
      );
      final dependencies = groundZero['rasterDependencies'] as List;
      final dependency = dependencies.first;
      final tiles = dependency['artwork']['tiles'] as List;
      if (mutation == 'missing-family') {
        dependencies.removeLast();
      } else if (mutation == 'missing-tile') {
        tiles.removeLast();
      } else if (mutation == 'duplicate-tile') {
        tiles[tiles.length - 1] = Map<String, dynamic>.from(tiles.first as Map);
      } else if (mutation == 'changed-native-frame') {
        dependency['displayFrame']['width'] = 4095;
      } else {
        final solid = tiles.singleWhere((tile) => tile['empty'] == false);
        if (mutation == 'wrong-output-path') {
          final otherTiles = dependencies[1]['artwork']['tiles'] as List;
          solid['path'] = otherTiles.singleWhere(
            (tile) => tile['empty'] == false,
          )['path'];
        } else {
          final path = solid['path'] as String;
          (manifest['outputs'] as List).removeWhere(
            (output) => output['path'] == path,
          );
          await packFile(private, path).delete();
        }
      }
      await saveManifest(private, manifest);
      await expectLater(
        promoteCandidate(private, packs),
        throwsFormatException,
        reason: mutation,
      );
      expect(await active.readAsString(), pointer, reason: mutation);
      expect(
        await preparedAssetDirectories(packs),
        directories,
        reason: mutation,
      );
    }
  });

  test('promotion rejects an existing compiled layer substituted for another component', () async {
    for (final replaceBytes in [false, true]) {
      final private = await candidate('component-$replaceBytes');
      final manifest = await readManifest(private);
      final vectorMap = (manifest['maps'] as List).singleWhere(
        (map) => map['id'] == 'interchange',
      );
      final ground = vectorMap['floors'][0]['artwork']['components'][0];
      final upper = (vectorMap['floors'][2]['artwork']['components'] as List)
          .singleWhere((component) => component['id'] == 'Floor-2');
      if (replaceBytes) {
        // A corrected canonical path still cannot carry another valid picture,
        // even after an attacker refreshes its output checksum.
        await packFile(private, ground['path'] as String).writeAsBytes(
          await packFile(private, upper['path'] as String).readAsBytes(),
        );
      } else {
        ground['path'] = upper['path'];
      }
      await saveManifest(private, manifest, refreshOutputs: replaceBytes);
      await expectLater(
        promoteCandidate(private, Directory('${temporary.path}/packs')),
        throwsFormatException,
      );
    }
  });

  test('promotion rejects a forged transparent tile against its decoded frozen PNG witness', () async {
    for (final corruption in ['missing', 'truncated']) {
      final private = await candidate('witness-$corruption');
      final manifest = await readManifest(private);
      final labs = (manifest['maps'] as List).singleWhere(
        (map) => map['id'] == 'thelab',
      );
      final transparent = (labs['floors'][0]['artwork']['tiles'] as List)
          .singleWhere((tile) => tile['x'] == 0 && tile['y'] == 1);
      expect(transparent['empty'], isTrue);
      final witness = packFile(
        private,
        'evidence/tile-alpha/${transparent['sourceSha256']}.png',
      );
      expect(inspectPng(await witness.readAsBytes()).empty, isTrue);
      if (corruption == 'missing') {
        await witness.delete();
        await expectLater(
          validateCandidate(private),
          throwsA(isA<FileSystemException>()),
        );
      } else {
        await witness.writeAsBytes([137, 80, 78, 71]);
        await expectLater(validateCandidate(private), throwsFormatException);
      }
    }
    // An intact private copy still validates independently of the corrupt ones.
    await validateCandidate(await candidate('intact-witness'));
    for (final addWitness in [false, true]) {
      final private = await candidate('forged-$addWitness');
      final manifest = await readManifest(private);
      final labs = (manifest['maps'] as List).singleWhere(
        (map) => map['id'] == 'thelab',
      );
      final tiles = labs['floors'][0]['artwork']['tiles'] as List;
      final solid = tiles.singleWhere(
        (tile) => tile['x'] == 0 && tile['y'] == 0,
      );
      expect(
        tiles.singleWhere((tile) => tile['x'] == 1 && tile['y'] == 0)['empty'],
        isFalse,
      );
      final originalPath = solid.remove('path') as String;
      solid['empty'] = true;
      solid.remove('alphaBounds');
      if (addWitness) {
        // Even a hash-consistent witness cannot declare an opaque source empty.
        final witness = 'evidence/tile-alpha/${solid['sourceSha256']}.png';
        final file = packFile(private, witness);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(
          await packFile(private, originalPath).readAsBytes(),
        );
        (manifest['outputs'] as List).add({'path': witness, 'sha256': ''});
      }
      await saveManifest(private, manifest, refreshOutputs: addWitness);
      await expectLater(
        promoteCandidate(private, Directory('${temporary.path}/packs')),
        throwsFormatException,
      );
    }
  });

  test('promotion rejects negative and out-of-frame crops without changing frame or pins', () async {
    final mutations = [
      {'left': -1},
      {'top': -1},
      {'right': 2801},
      {'bottom': 2801},
    ];
    for (var i = 0; i < mutations.length; i++) {
      final private = await candidate('crop-$i');
      final manifest = await readManifest(private);
      final labs = (manifest['maps'] as List).singleWhere(
        (map) => map['id'] == 'thelab',
      );
      labs['displayCrop'] = {...labs['displayCrop'] as Map, ...mutations[i]};
      await saveManifest(private, manifest);
      await expectLater(
        promoteCandidate(private, Directory('${temporary.path}/packs')),
        throwsFormatException,
      );
    }
    final intact = await candidate('intact-crop');
    final manifest = await validateCandidate(intact);
    final labs = (manifest['maps'] as List).singleWhere(
      (map) => map['id'] == 'thelab',
    );
    expect(labs['geometry']['coordinateRevision'], 1);
    expect(labs['geometry']['pinFrame'], 'labs-native-normalized');
    final ice = (manifest['maps'] as List).singleWhere(
      (map) => map['id'] == 'icebreaker',
    );
    expect(ice['geometry'], calibrationFor('icebreaker')['geometry']);
  });

  test('failed new generation preserves asset discovery for an older frozen floor calibration', () async {
    final older = await candidate('older');
    final olderManifest = await readManifest(older);
    const legacyIds = {'interchange', 'thelab', 'icebreaker'};
    olderManifest['preparationVersion'] = 2;
    olderManifest.remove('supportedMapIds');
    (olderManifest['maps'] as List).removeWhere(
      (map) => !legacyIds.contains(map['id']),
    );
    expect((olderManifest['maps'] as List).map((map) => map['id']), [
      'interchange',
      'thelab',
      'icebreaker',
    ]);

    // Represent a previously published three-map generation with no evidence-owned
    // marker floors. Its calibration, source index and output hashes remain
    // coherent; only the authoring code now knows the newer assignments.
    final calibrationFile = File('${older.path}/evidence/calibration.json');
    final olderCalibration = jsonDecode(
      await calibrationFile.readAsString(),
    ) as Map<String, dynamic>;
    (olderCalibration['maps'] as List).removeWhere(
      (map) => !legacyIds.contains(map['id']),
    );
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
    final publishedOlder = Directory('${packs.path}/versions/$version');
    final validatedOlder = await validateCandidate(publishedOlder);
    expect(validatedOlder['preparationVersion'], 2);
    expect(validatedOlder['maps'] as List, hasLength(3));
    expect(
      calibrationFor('icebreaker').containsKey('markerFloorAssignments'),
      isTrue,
    );
    expect(olderIceCalibration.containsKey('markerFloorAssignments'), isFalse);

    final newer = await candidate('newer');
    final newerManifest = await readManifest(newer);
    expect(newerManifest['preparationVersion'], 3);
    expect(newerManifest['maps'] as List, hasLength(13));
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
    final forged = Directory('${temporary.path}/forged-older');
    await copyPack(older, forged);
    final forgedManifest = await readManifest(forged);
    final forgedIce = (forgedManifest['maps'] as List).singleWhere(
      (map) => map['id'] == 'icebreaker',
    );
    (forgedIce['markers'] as List).first['floorId'] = 'Helipad';
    await saveManifest(forged, forgedManifest);
    await expectLater(
      validateCandidate(forged),
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

  test('missing frozen vector, raster or dependency source rejects offline rebuild without publishing', () async {
    final index = jsonDecode(
      await packFile(fixtures.raw, 'sources.json').readAsString(),
    ) as Map<String, dynamic>;
    final packs = Directory('${temporary.path}/packs');
    await packs.create();
    final active = packFile(packs, 'active.json');
    await active.writeAsString('{"version":"A"}');
    final missingPaths = [
      rawTilePath('thelab', 'First_Level', 15, 15),
      calibrationFor('factory')['sourceSvgPath'] as String,
      rawTilePath('groundzero', 'dependency-Ground_Level', 15, 15),
      rawTilePath('labyrinth', 'Main_Level', 15, 15),
    ];
    for (var i = 0; i < missingPaths.length; i++) {
      final path = missingPaths[i];
      final raw = Directory('${temporary.path}/missing-source-$i');
      await raw.create();
      final missing = (index['sources'] as List).singleWhere(
        (source) => source['path'] == path,
      );
      // Freeze the real required entry, but omit its physical source file.
      // FrozenInputs.open rejects it before rebuilding; no full raw clone
      // is needed to exercise this missing-source trust boundary.
      await packFile(raw, 'sources.json').writeAsString(
        canonicalJson({
          'schemaVersion': 1,
          'sources': [missing],
        }),
      );
      final output = Directory('${temporary.path}/missing-candidate-$i');
      await expectLater(
        rebuildCandidate(raw, output),
        throwsA(isA<FileSystemException>()),
        reason: path,
      );
      expect(await active.readAsString(), '{"version":"A"}', reason: path);
      expect(await output.exists(), isFalse, reason: path);
    }
  });

  test('promotion publishes one complete version and interruption retains A', () async {
    final published = await candidate('published');
    final packs = Directory('${temporary.path}/packs');
    final version = await promoteCandidate(published, packs);
    final active = File('${packs.path}/active.json');
    final original = await active.readAsString();
    expect(jsonDecode(original)['version'], version);
    await validateCandidate(Directory('${packs.path}/versions/$version'));
    // A user-supplied directory with a trailing separator has the same closure.
    await validateCandidate(Directory('${packs.path}/versions/$version/'));
    // Simulate interruption immediately before the single pointer boundary.
    await File('${packs.path}/active.next.json').writeAsString('incomplete');
    await expectLater(
      promoteCandidate(published, packs),
      throwsFormatException,
    );
    expect(await active.readAsString(), original);
    // Required raster corruption fails even though a previous version exists.
    final corrupt = await candidate('corrupt-raster');
    await File('${corrupt.path}/artwork/thelab/First_Level/0/0.png')
        .writeAsBytes([1, 2, 3]);
    await expectLater(promoteCandidate(corrupt, packs), throwsFormatException);
    expect(await active.readAsString(), original);
    for (final mutation in [
      'untracked',
      'duplicate-output',
      'missing-output',
    ]) {
      final private = await candidate('inventory-$mutation');
      final manifest = await readManifest(private);
      if (mutation == 'untracked') {
        await packFile(
          private,
          'untracked.txt',
        ).writeAsString('not in the frozen output inventory');
      } else if (mutation == 'duplicate-output') {
        (manifest['outputs'] as List).add(
          Map<String, dynamic>.from((manifest['outputs'] as List).first as Map),
        );
        await saveManifest(private, manifest);
      } else {
        await packFile(private, 'NOTICE.txt').delete();
      }
      await expectLater(
        validateCandidate(private),
        mutation == 'missing-output'
            ? throwsA(isA<FileSystemException>())
            : throwsFormatException,
      );
      await expectLater(
        promoteCandidate(private, packs),
        mutation == 'missing-output'
            ? throwsA(isA<FileSystemException>())
            : throwsFormatException,
      );
      expect(await active.readAsString(), original);
    }
    // Remove the interruption artifact so it cannot mask destination validation.
    await File('${packs.path}/active.next.json').delete();
    await packFile(
      Directory('${packs.path}/versions/$version'),
      'artwork/thelab/First_Level/0/0.png',
    ).writeAsBytes([1, 2, 3]);
    // The candidate remains intact; only the already-published copy is corrupt.
    await validateCandidate(published);
    await expectLater(
      promoteCandidate(published, packs),
      throwsFormatException,
    );
    await expectLater(preparedAssetDirectories(packs), throwsFormatException);
    expect(await active.readAsString(), original);
  });

  test(
    'normalization-only candidate cannot be promoted before compilation',
    () async {
      final private = Directory('${temporary.path}/uncompiled');
      // Normalization is a real current-calibration rebuild, not a compiled
      // pack with its flag edited. Reuse raw inputs without rewriting tiles.
      final manifest = await rebuildCandidate(
        fixtures.raw,
        private,
        compileVectors: false,
      );
      expect(manifest['vectorsCompiled'], isFalse);
      await validateCandidate(private, requireCompiled: false);
      await expectLater(
        promoteCandidate(private, Directory('${temporary.path}/packs')),
        throwsFormatException,
      );
      await compileCandidate(private);
      await validateCandidate(private);
    },
  );
}

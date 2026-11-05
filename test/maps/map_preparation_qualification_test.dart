@Tags(['qualification'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

  test('full-map source fixture retains boss occurrences and explicit empty coverage', () async {
    final manifest = await readManifest(fixtures.first);
    final customs = (manifest['maps'] as List).singleWhere(
      (map) => map['id'] == 'customs',
    );
    final bosses = (customs['markers'] as List)
        .where((marker) => marker['category'] == 'bosses')
        .map((marker) => marker['details'] as Map)
        .toList();
    expect(bosses, hasLength(2));
    expect(bosses.map((boss) => boss['mob']), everyElement('fixture-alpha'));
    expect(
      bosses.map((boss) => boss['position']),
      everyElement({'x': 11.25, 'y': null, 'z': -4.5}),
    );
    expect(bosses.map((boss) => boss['spawnChance']), [.37, .23]);

    final snapshot = jsonDecode(
      await packFile(
        fixtures.first,
        'evidence/markers/maps.json',
      ).readAsString(),
    ) as Map<String, dynamic>;
    final sourceBosses =
        ((snapshot['data'] as Map<String, dynamic>)['maps']
                as Map<String, dynamic>)['customs']['bosses']
            as List;
    expect((sourceBosses[2] as Map)['spawnLocations'], isEmpty);
    expect(
      ((sourceBosses[3] as Map)['spawnLocations'] as List).single['positions'],
      isEmpty,
    );
  });

  test('boss candidate corruption is rejected per map', () async {
    for (final mutation in [
      'missing position',
      'extra position',
      'moved map',
      'changed mob',
      'changed name',
      'changed location',
      'changed coordinate',
      'changed rate',
    ]) {
      final private = await candidate('boss-$mutation');
      final manifest = await readManifest(private);
      final sourcePath = 'markers/maps.json';
      final sourceFile = packFile(private, 'evidence/$sourcePath');
      final snapshot =
          jsonDecode(await sourceFile.readAsString()) as Map<String, dynamic>;
      final data = snapshot['data'] as Map<String, dynamic>;
      final maps = data['maps'] as Map<String, dynamic>;
      final customs = maps['customs'] as Map<String, dynamic>;
      final reserve = maps['reserve'] as Map<String, dynamic>;
      final bosses = customs['bosses'] as List;
      final boss = bosses.first as Map<String, dynamic>;
      final location =
          (boss['spawnLocations'] as List).first as Map<String, dynamic>;
      final positions = location['positions'] as List;
      switch (mutation) {
        case 'missing position':
          positions.removeAt(0);
        case 'extra position':
          positions.add({
            ...(positions.first as Map<String, dynamic>),
            'x': 21.5,
          });
        case 'moved map':
          final moved = bosses.removeAt(0);
          (reserve['bosses'] as List).add(moved);
        case 'changed mob':
          boss['mob'] = 'fixture-beta';
        case 'changed name':
          ((data['mobs'] as Map<String, dynamic>)['fixture-alpha']
                  as Map<String, dynamic>)['name'] =
              'CHANGED_FIXTURE_ALPHA';
        case 'changed location':
          location['name'] = 'Changed Customs stronghold';
        case 'changed coordinate':
          (positions.first as Map<String, dynamic>)['x'] = 11.5;
        case 'changed rate':
          boss['spawnChance'] = .38;
      }
      await sourceFile.writeAsString(canonicalJson(snapshot));
      await _refreezeEvidence(private, manifest, sourcePath);
      await saveManifest(private, manifest, refreshOutputs: true);
      await expectLater(
        validateCandidate(private),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('Markers'),
              contains('markers/maps.json'),
              anyOf(contains('customs'), contains('reserve')),
            ),
          ),
        ),
        reason:
            '$mutation must identify the affected map after hashes are refreshed',
      );
    }
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
    expect(olderManifest['preparationVersion'], 3);
    expect(olderManifest['maps'] as List, hasLength(13));

    // Represent an earlier full generation whose frozen calibration has no
    // evidence-owned marker floors for Icebreaker. Its calibration, source index
    // and output hashes remain coherent; only the authoring code now knows the
    // newer assignments.
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
    final publishedOlder = Directory('${packs.path}/versions/$version');
    final validatedOlder = await validateCandidate(publishedOlder);
    expect(validatedOlder['preparationVersion'], 3);
    expect(validatedOlder['maps'] as List, hasLength(13));
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
      throwsA(isA<FormatException>()),
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
        FrozenInputs.open(raw).then(
          (frozen) =>
              rebuildCandidate(frozen, output, toolchain: fixtureToolchain),
        ),
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
        await FrozenInputs.open(fixtures.raw),
        private,
        compileVectors: false,
        toolchain: fixtureToolchain,
      );
      expect(manifest['vectorsCompiled'], isFalse);
      await validateCandidate(private, requireCompiled: false);
      await expectLater(
        promoteCandidate(private, Directory('${temporary.path}/packs')),
        throwsFormatException,
      );
      await compileCandidate(private, toolchain: fixtureToolchain);
      await validateCandidate(private);
    },
  );

  group('toolchain, determinism and vector format', () {
    String vecPath(Map<String, dynamic> manifest, int floor) {
      final map = (manifest['maps'] as List).singleWhere(
        (map) => map['id'] == 'interchange',
      );
      return map['floors'][floor]['artwork']['components'][0]['path'] as String;
    }

    test('rebuild records the given toolchain and no fixed versions', () async {
      final manifest = await readManifest(fixtures.first);
      expect(manifest['toolchain'], fixtureToolchain);
      for (final key in [
        'dependencies',
        'compilerVersion',
        'runtimeVectorVersion',
      ]) {
        expect(manifest.containsKey(key), isFalse, reason: key);
      }
    });

    test(
      'pack recording compiler 1.3.0 validates when vectors reproduce',
      () async {
        final private = await candidate('old-compiler');
        final manifest = await validateCandidate(private);
        expect(manifest['toolchain']['vector_graphics_compiler'], '1.3.0');
        expect(manifest['vectorCodecFormat'], 1);
      },
    );

    test('compile step replaces the normalize-time toolchain', () async {
      final private = Directory('${temporary.path}/replace-toolchain');
      final normalized = await rebuildCandidate(
        await FrozenInputs.open(fixtures.raw),
        private,
        compileVectors: false,
        toolchain: {...fixtureToolchain, 'vector_graphics_compiler': '1.3.0'},
      );
      expect(normalized.containsKey('vectorCodecFormat'), isFalse);
      await compileCandidate(
        private,
        toolchain: {...fixtureToolchain, 'vector_graphics_compiler': '1.3.4'},
      );
      final compiled = await readManifest(private);
      expect(compiled['toolchain']['vector_graphics_compiler'], '1.3.4');
      expect(compiled['vectorCodecFormat'], 1);
      expect(compiled['vectorsCompiled'], isTrue);
    });

    test('unstable encoder leaves the candidate without a manifest', () async {
      final private = Directory('${temporary.path}/unstable');
      var calls = 0;
      await expectLater(
        rebuildCandidate(
          await FrozenInputs.open(fixtures.raw),
          private,
          toolchain: fixtureToolchain,
          encode: (xml, name) => Uint8List.fromList([++calls]),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('.vec'),
          ),
        ),
      );
      expect(File('${private.path}/manifest.json').existsSync(), isFalse);
    });

    test(
      'substituted vec with matching output hash fails naming the path',
      () async {
        final private = await candidate('substituted');
        final manifest = await readManifest(private);
        final victim = vecPath(manifest, 0);
        await packFile(private, victim).writeAsBytes(
          await packFile(private, vecPath(manifest, 2)).readAsBytes(),
        );
        await saveManifest(private, manifest, refreshOutputs: true);
        await expectLater(
          validateCandidate(private),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains(victim),
            ),
          ),
        );
      },
    );

    test('compiled pack records vectorCodecFormat 1', () async {
      expect((await readManifest(fixtures.first))['vectorCodecFormat'], 1);
    });

    test('vec header format 2 against record 1 fails naming payload and both formats', () async {
      final private = await candidate('header-two');
      final manifest = await readManifest(private);
      final path = vecPath(manifest, 0);
      final file = packFile(private, path);
      final bytes = await file.readAsBytes();
      bytes[4] = 2;
      await file.writeAsBytes(bytes);
      await saveManifest(private, manifest, refreshOutputs: true);
      await expectLater(
        validateCandidate(private),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            allOf(contains(path), contains('format 2'), contains('format 1')),
          ),
        ),
      );
    });

    test(
      'compiled pack without vectorCodecFormat fails as not recorded',
      () async {
        for (final value in <Object?>[null, '1']) {
          final private = await candidate('no-format-$value');
          final manifest = await readManifest(private);
          if (value == null) {
            manifest.remove('vectorCodecFormat');
          } else {
            manifest['vectorCodecFormat'] = value;
          }
          await saveManifest(private, manifest);
          await expectLater(
            validateCandidate(private),
            throwsA(
              isA<FormatException>().having(
                (error) => error.message,
                'message',
                contains('not recorded'),
              ),
            ),
            reason: '$value',
          );
        }
      },
    );

    test(
      'normalized candidate has no format record and cannot be promoted',
      () async {
        final private = Directory('${temporary.path}/normalized');
        final manifest = await rebuildCandidate(
          await FrozenInputs.open(fixtures.raw),
          private,
          compileVectors: false,
          toolchain: fixtureToolchain,
        );
        expect(manifest.containsKey('vectorCodecFormat'), isFalse);
        await validateCandidate(private, requireCompiled: false);
        await expectLater(
          promoteCandidate(private, Directory('${temporary.path}/packs')),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('Uncompiled'),
            ),
          ),
        );
      },
    );

    test('validator refuses preparation version 2', () async {
      final private = await candidate('version-two');
      final manifest = await readManifest(private);
      manifest['preparationVersion'] = 2;
      await saveManifest(private, manifest);
      await expectLater(
        validateCandidate(private),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            allOf(contains('Unsupported preparation version'), contains('2')),
          ),
        ),
      );
    });
  });

  Future<Map<String, String>> snapshot(Directory root) async => {
    await for (final entity in root.list(recursive: true))
      if (entity is File)
        entity.path.replaceAll('\\', '/'): sha256
            .convert(await entity.readAsBytes())
            .toString(),
  };

  // Assembled directly, not through promoteCandidate (which would recompile
  // and refuse it): one .vec is another component's valid bytes. Returns the
  // floor id and the substituted path.
  Future<(String, String)> assembleOtherCompiler(Directory packs) async {
    final other = Directory('${temporary.path}/other-compiler');
    await copyPack(fixtures.first, other);
    final manifest = await readManifest(other);
    final map = (manifest['maps'] as List).singleWhere(
      (map) => map['id'] == 'interchange',
    );
    final floorId = map['floors'][0]['id'] as String;
    final victim =
        map['floors'][0]['artwork']['components'][0]['path'] as String;
    final donor =
        map['floors'][2]['artwork']['components'][0]['path'] as String;
    await packFile(
      other,
      victim,
    ).writeAsBytes(await packFile(other, donor).readAsBytes());
    await saveManifest(other, manifest, refreshOutputs: true);
    final id = sha256
        .convert(await packFile(other, 'manifest.json').readAsBytes())
        .toString();
    await copyPack(other, Directory('${packs.path}/versions/$id'));
    await File('${packs.path}/active.json').writeAsString(
      canonicalJson({
        'schemaVersion': 1,
        'version': id,
        'manifest': 'versions/$id/manifest.json',
      }),
    );
    return (floorId, victim);
  }

  group('committed pack check', () {
    Future<List<String>> leftovers(Directory checkTemp) async => [
      await for (final entity in checkTemp.list()) entity.path,
    ];

    late Directory packs;
    late Directory checkTemp;
    setUp(() async {
      packs = Directory('${temporary.path}/packs');
      checkTemp = await Directory('${temporary.path}/check-temp').create();
    });

    test('check passes when only the toolchain record differs and prints the reproduced line', () async {
      await promoteCandidate(fixtures.first, packs);
      final before = await snapshot(packs);
      final newer = {...fixtureToolchain, 'vector_graphics_compiler': '1.3.4'};
      final line = await checkActive(
        packs,
        toolchain: newer,
        tempParent: checkTemp,
      );
      final id = jsonDecode(
        await File('${packs.path}/active.json').readAsString(),
      )['version'];
      expect(
        line,
        'Map pack $id reproduced byte-identically with xml 6.6.1, '
        'image 4.12.0, vector_graphics_compiler 1.3.4, vector_graphics 1.2.5, '
        'vector_graphics_codec 1.1.13.',
      );
      expect(await snapshot(packs), before);
      expect(await leftovers(checkTemp), isEmpty);
    });

    test('check fails with the per-map summary listing a vec built by another compiler and names maps:rebuild', () async {
      final (floorId, victim) = await assembleOtherCompiler(packs);
      final before = await snapshot(packs);
      await expectLater(
        checkActive(packs, toolchain: fixtureToolchain, tempParent: checkTemp),
        throwsA(
          isA<MapPackCheckFailure>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('interchange $floorId: 1 changed file(s)'),
              contains(victim),
              endsWith(
                'Map pack is not reproducible with the installed toolchain. '
                'Run: mise run maps:rebuild',
              ),
            ),
          ),
        ),
      );
      expect(await snapshot(packs), before);
      expect(await leftovers(checkTemp), isEmpty);
    });
  });

  group('refresh', () {
    const begin =
        '    # BEGIN generated map pack assets (mise run maps:rebuild)';
    const end = '    # END generated map pack assets';
    final stamp = DateTime.utc(2026, 11, 2, 10, 30, 15);
    const candidateName = 'refresh-20261102T103015Z';
    const owner =
        'Artwork changed: the owner must check the maps listed above in the '
        'app before merge.';
    final newer = {...fixtureToolchain, 'vector_graphics_compiler': '1.3.4'};

    late Directory packs;
    late Directory work;
    late File pubspec;
    late List<String> log;
    const pubspecText =
        'name: x\nflutter:\n  assets:\n    - assets/app_icon/\n'
        '$begin\n    - assets/maps/stale/\n$end\n    - assets/other/\n';
    setUp(() async {
      packs = Directory('${temporary.path}/refresh-packs');
      work = Directory('${temporary.path}/work');
      pubspec = File('${temporary.path}/pubspec.yaml');
      await pubspec.writeAsString(pubspecText);
      log = [];
    });

    Future<MapPackRefresh> refresh({
      Map<String, String>? toolchain,
      VectorEncoder? encode,
    }) => refreshActive(
      packs,
      pubspec,
      toolchain: toolchain ?? newer,
      assetRoot: 'assets/maps',
      candidateParent: work,
      now: stamp,
      encode: encode,
      log: log.add,
    );

    Future<List<String>> versions() async => [
      await for (final entity in Directory('${packs.path}/versions').list())
        entity.path.replaceAll('\\', '/').split('/').last,
    ]..sort();

    Future<String> activeId() async =>
        jsonDecode(
              await File('${packs.path}/active.json').readAsString(),
            )['version']
            as String;

    test('refresh with identical artwork promotes a new generation, rewrites the asset block and prunes the old generation', () async {
      await promoteCandidate(fixtures.first, packs);
      final oldId = await activeId();
      final oldDirectory = Directory('${packs.path}/versions/$oldId');
      final oldFiles = await snapshot(oldDirectory);

      final result = await refresh();

      final newId = await activeId();
      expect(newId, isNot(oldId));
      expect(result.id, newId);
      expect(result.pruned, [oldId]);
      expect(await versions(), [newId]);
      final newDirectory = Directory('${packs.path}/versions/$newId');
      final newFiles = await snapshot(newDirectory);
      Map<String, String> relative(Map<String, String> files, Directory root) =>
          {
            for (final entry in files.entries)
              entry.key.substring(root.path.replaceAll('\\', '/').length + 1):
                  entry.value,
          };
      final before = relative(oldFiles, oldDirectory);
      final after = relative(newFiles, newDirectory);
      expect(after.keys.toSet(), before.keys.toSet());
      expect(
        [
          for (final key in after.keys)
            if (after[key] != before[key]) key,
        ],
        ['manifest.json'],
      );

      final block = mapPackAssetLines(
        'assets/maps',
        await preparedAssetDirectories(packs),
      );
      expect(
        await pubspec.readAsString(),
        'name: x\nflutter:\n  assets:\n    - assets/app_icon/\n'
        '$begin\n${block.join('\n')}\n$end\n    - assets/other/\n',
      );
      expect(block, contains('    - assets/maps/versions/$newId/'));
      expect(block.join('\n'), isNot(contains(oldId)));

      expect(log, isNot(contains(owner)));
      expect(
        log.last,
        'Only the toolchain record changed: no owner check is needed.',
      );
      expect(result.changed, isFalse);
      expect(work.existsSync() ? await work.list().toList() : [], isEmpty);
    });

    test('refresh reports changed artwork and the owner check', () async {
      final (floorId, victim) = await assembleOtherCompiler(packs);
      final oldId = await activeId();

      final result = await refresh(toolchain: fixtureToolchain);

      expect(result.changed, isTrue);
      expect(log, contains('interchange $floorId: 1 changed file(s)'));
      expect(log, contains('  $victim'));
      expect(log.last, owner);
      expect(log.indexOf('  $victim'), lessThan(log.indexOf(owner)));
      final newId = await activeId();
      expect(newId, isNot(oldId));
      expect(await versions(), [newId]);
      expect(await pubspec.readAsString(), contains('versions/$newId/'));
      expect(await pubspec.readAsString(), isNot(contains(oldId)));
      await validateCandidate(Directory('${packs.path}/versions/$newId'));
    });

    test('refresh with an invalid candidate deletes nothing and keeps active, pubspec and the named candidate', () async {
      await promoteCandidate(fixtures.first, packs);
      final before = await snapshot(packs);
      final candidate = '${work.path}/$candidateName';

      await expectLater(
        // Stable but wrong payloads: the real encoder in validation disagrees.
        refresh(
          encode: (xml, name) =>
              Uint8List.fromList([0x62, 0x2d, 0x88, 0x00, 1, 7]),
        ),
        throwsA(
          isA<MapPackRefreshFailure>().having(
            (error) => error.message,
            'message',
            allOf(contains('.vec'), contains(candidate)),
          ),
        ),
      );

      expect(await snapshot(packs), before);
      expect(await pubspec.readAsString(), pubspecText);
      expect(Directory(candidate).existsSync(), isTrue);
    });

    test(
      'refresh whose promotion fails deletes the staged pubspec file',
      () async {
        await promoteCandidate(fixtures.first, packs);
        final blocker = File('${packs.path}/active.next.json');

        await expectLater(
          refreshActive(
            packs,
            pubspec,
            toolchain: newer,
            assetRoot: 'assets/maps',
            candidateParent: work,
            now: stamp,
            // The report runs after the leftover precheck and before staging,
            // so the pointer swap in promotion finds a leftover and refuses.
            log: (line) {
              if (!blocker.existsSync()) blocker.writeAsStringSync('{}');
            },
          ),
          throwsA(
            isA<MapPackRefreshFailure>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('${work.path}/$candidateName'),
                isNot(contains('already name')),
              ),
            ),
          ),
        );

        expect(File('${pubspec.path}.tmp').existsSync(), isFalse);
        expect(await pubspec.readAsString(), pubspecText);
      },
    );

    test(
      'refresh that cannot stage the pubspec rewrite promotes nothing',
      () async {
        await promoteCandidate(fixtures.first, packs);
        final before = await snapshot(packs);
        // A directory where the staged pubspec goes makes the write fail.
        await Directory('${pubspec.path}.tmp').create();

        await expectLater(
          refresh(),
          throwsA(
            isA<MapPackRefreshFailure>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('${work.path}/$candidateName'),
                isNot(contains('active.json already names')),
              ),
            ),
          ),
        );

        expect(await snapshot(packs), before);
        expect(await pubspec.readAsString(), pubspecText);
      },
    );

    test(
      'refresh with a leftover fails before rebuilding and changes nothing',
      () async {
        await promoteCandidate(fixtures.first, packs);
        final staging = Directory(
          '${packs.path}/versions/.${'ab' * 32}.staging',
        );
        await staging.create();
        final before = await snapshot(packs);

        await expectLater(
          refresh(),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              allOf(
                startsWith('Interrupted map pack promotion left '),
                contains('.staging'),
              ),
            ),
          ),
        );
        await staging.delete();
        await File('${packs.path}/active.next.json').writeAsString('{}');
        await expectLater(
          refresh(),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('active.next.json'),
            ),
          ),
        );
        await File('${packs.path}/active.next.json').delete();

        expect(await snapshot(packs), before);
        expect(await pubspec.readAsString(), pubspecText);
        expect(work.existsSync(), isFalse);
        expect(log, isEmpty);
      },
    );

    test(
      'refresh with missing pubspec markers fails before rebuilding',
      () async {
        await promoteCandidate(fixtures.first, packs);
        final before = await snapshot(packs);
        await pubspec.writeAsString(pubspecText.replaceAll('$end\n', ''));

        await expectLater(
          refresh(),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('END generated map pack assets'),
            ),
          ),
        );
        expect(await snapshot(packs), before);
        expect(work.existsSync(), isFalse);
      },
    );
  });
}

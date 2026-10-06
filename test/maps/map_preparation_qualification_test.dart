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

  test('two offline rebuilds are byte-identical and keep original crop/frame units', () async {
    final a = await readManifest(fixtures.first);
    final b = await readManifest(fixtures.second);
    expect(canonicalJson(a), canonicalJson(b));
    final expectedFloorIds = {
      'thelab': ['First_Level', 'Second_Level', 'Technical_Level'],
      'icebreaker': icebreakerSources.keys.toList(),
    };
    var rasterFloors = 0;
    var rasterTiles = 0;
    for (final manifest in [a, b]) {
      for (final map in (manifest['maps'] as List).where(
        (map) => map['kind'] == 'raster',
      )) {
        final floors = map['floors'] as List;
        expect(floors.map((floor) => floor['id']), expectedFloorIds[map['id']]);
        expect(floors, hasLength(map['id'] == 'thelab' ? 3 : 16));
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
    expect(rasterFloors, 2 * 19);
    expect(rasterTiles, 2 * 19 * 256);
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
    expect(labs['artworkFrame']['width'], 2800);
    expect(labs['artworkFrame']['tileStride'], 175);
    expect(labs['displayCrop'], {'left': 0, 'top': 0, 'right': 1, 'bottom': 1});
    expect(labs['markers'][0]['position']['height'], isNull);
    expect(a['preparationVersion'], 2);
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

    final newer = await candidate('newer');
    final newerManifest = await readManifest(newer);
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

  test('missing tile rejects offline rebuild without publishing', () async {
    final raw = Directory('${temporary.path}/missing-source');
    await raw.create();
    final index = jsonDecode(
      await packFile(fixtures.raw, 'sources.json').readAsString(),
    ) as Map<String, dynamic>;
    final missing = (index['sources'] as List).singleWhere(
      (source) =>
          source['path'] == rawTilePath('thelab', 'First_Level', 15, 15),
    );
    // Freeze the real required tile entry, but omit its physical source file.
    // FrozenInputs.open rejects it before rebuilding; no 4864-file raw clone
    // is needed to exercise this missing-source trust boundary.
    await packFile(raw, 'sources.json').writeAsString(
      canonicalJson({
        'schemaVersion': 1,
        'sources': [missing],
      }),
    );
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

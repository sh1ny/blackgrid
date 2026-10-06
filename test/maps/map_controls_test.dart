import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:blackgrid/application/map_controller.dart';
import 'package:blackgrid/domain/map_floors.dart';
import 'package:blackgrid/maps/native_map_scene.dart';
import 'package:blackgrid/maps/prepared_map.dart';
import 'package:blackgrid/maps/prepared_map_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixture = jsonDecode(
    File('test/fixtures/m3/placement_controls.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  late PreparedMapPack pack;
  late Map<String, dynamic> manifest;

  setUpAll(() async {
    pack = await _loader().load();
    manifest = jsonDecode(
      File('${pack.assetRoot}manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  test('controls refer to the frozen actual artwork and metadata sources', () {
    expect(
      pack.byId.keys,
      containsAll(['interchange', 'thelab', 'icebreaker']),
    );
    final lock = manifest['sourceLock'] as Map<String, dynamic>;
    final hashes = lock['primaryHashes'] as Map<String, dynamic>;
    final expected = fixture['sources'] as Map<String, dynamic>;
    for (final path in ['interchange/Interchange.svg', 'metadata/maps.json']) {
      expect(hashes[path], expected[path], reason: 'Source identity: $path');
    }
    expect(
      pack.byId['interchange']!.displayFrame.originalArtwork.width,
      1127.6852,
    );
    expect(
      pack.byId['interchange']!.displayFrame.originalArtwork.height,
      947.02582,
    );
    expect(pack.byId['thelab']!.displayFrame.originalArtwork.width, 2800);
    expect(pack.byId['icebreaker']!.displayFrame.originalArtwork.width, 4096);
  });

  for (final raw in fixture['landmarks'] as List) {
    final control = raw as Map<String, dynamic>;
    test('independently labelled placement: ${control['id']}', () {
      final map = pack.byId[control['mapId']]!;
      final marker = map.markers.singleWhere(
        (marker) => marker.id == control['markerId'],
      );
      if (control['sourceTile'] != null) {
        final rawMap = (manifest['maps'] as List)
            .cast<Map<String, dynamic>>()
            .singleWhere((rawMap) => rawMap['id'] == map.id);
        final rawFloor = (rawMap['floors'] as List)
            .cast<Map<String, dynamic>>()
            .singleWhere((floor) => floor['id'] == control['artworkFloor']);
        final art = rawFloor['artwork'] as Map<String, dynamic>;
        final sourceTile = (art['tiles'] as List)
            .cast<Map<String, dynamic>>()
            .singleWhere((tile) => tile['sourcePath'] == control['sourceTile']);
        expect(sourceTile['sourceSha256'], control['sourceTileSha256']);
        expect(sourceTile['empty'], isFalse);
      }
      _expectSourceMarker(marker, control);
      final label = control['artwork'] as List;
      // Only the explicitly documented artwork-unit conversion is applied to
      // manual labels. Neither geometry nor its inverse supplies expectations.
      final factor = _labelScale(map, control);
      final expectedX = (label[0] as num).toDouble() * factor;
      final expectedY = (label[1] as num).toDouble() * factor;
      final tolerance = (control['tolerance'] as num).toDouble() * factor;
      final projected = map.geometry.gameToArtwork(marker.position);
      final actual = map.displayFrame.artworkToPixels(projected);
      final residual = math.sqrt(
        math.pow(actual.x - expectedX, 2) + math.pow(actual.y - expectedY, 2),
      );
      expect(
        residual,
        lessThanOrEqualTo(tolerance),
        reason:
            '${control['label']} Manual label ($expectedX, $expectedY); '
            'actual (${actual.x}, ${actual.y}); radial residual $residual.',
      );

      // Independent point and crop subtraction also constrain the shared scene
      // path, catching omission or double application of display cropping.
      final scene = map.gameToScene(marker.position);
      final crop = map.displayFrame.crop;
      final sceneResidual = math.sqrt(
        math.pow(scene.x - (expectedX - crop.left), 2) +
            math.pow(scene.y - (expectedY - crop.top), 2),
      );
      expect(sceneResidual, lessThanOrEqualTo(tolerance));
    });
  }

  for (final raw in fixture['observedSourceParity'] as List) {
    final control = raw as Map<String, dynamic>;
    test('observed source identity: ${control['id']}', () {
      final map = pack.byId[control['mapId']]!;
      final marker = map.markers.singleWhere(
        (marker) => marker.id == control['markerId'],
      );
      _expectSourceMarker(marker, control);
    });
  }

  for (final raw in fixture['floorControls'] as List) {
    final control = raw as Map<String, dynamic>;
    test(
      'real source height policy: ${control['mapId']} ${control['markerId']}',
      () {
        final map = pack.byId[control['mapId']]!;
        final marker = map.markers.singleWhere(
          (marker) => marker.id == control['markerId'],
        );
        expect(marker.position.height, control['height']);
        expect(
          marker.details.containsKey('floorId'),
          isFalse,
          reason: 'The frozen public dataset does not explicitly label floors.',
        );
        expect(
          marker.floorId,
          control['preparedFloorId'],
          reason:
              'Prepared physical ownership needs independent evidence, '
              'not merely the automatic height result.',
        );
        final floor = map.floorPolicy.floorForHeight(marker.position.height);
        expect(
          floor?.id,
          control['floorId'],
          reason: control['basis'] as String,
        );
        if (floor != null) {
          final selection = map.floorPolicy.selectionForHeight(
            marker.position.height,
          );
          expect(selection.isLayerVisible(floor.id), isTrue);
          if (map.floorPolicy.exclusive) {
            expect(selection.visibleLayerIds, [floor.id]);
          }
        }
      },
    );
  }

  test(
    'actual Interchange floor identity is manual and preserves base art',
    () {
      final map = pack.byId['interchange']!;
      final floor = map.floorPolicy.floors.singleWhere(
        (floor) => floor.id == 'First_Floor',
      );
      expect(floor.label, '2nd Floor');
      final selection = map.floorPolicy.reset().select('First_Floor');
      expect(selection.isLayerVisible('Ground_Level'), isTrue);
      expect(selection.isLayerVisible('First_Floor'), isTrue);
      expect(selection.isLayerVisible('Second_Floor'), isFalse);
      expect(map.floorPolicy.floorForHeight(27.9506), isNull);
    },
  );

  test('lower crew-door controls preserve the unique frozen source group', () {
    final map = pack.byId['icebreaker']!;
    final sourceGroup = map.markers.where(
      (marker) =>
          marker.details['key'] == '69bb3ec9f609db77390b0e1a' &&
          marker.position.height == 27.54,
    );
    final frozenGroup = (fixture['observedSourceParity'] as List)
        .cast<Map<String, dynamic>>()
        .where(
          (control) =>
              control['mapId'] == 'icebreaker' &&
              control['keyId'] == '69bb3ec9f609db77390b0e1a' &&
              (control['game'] as List)[2] == 27.54,
        );
    expect(sourceGroup, hasLength(3));
    expect(frozenGroup, hasLength(3));
    expect(
      sourceGroup.map((marker) => marker.id),
      unorderedEquals(frozenGroup.map((control) => control['markerId'])),
    );
    expect(sourceGroup.where((marker) => marker.position.x > 0), hasLength(1));
    expect(sourceGroup.where((marker) => marker.position.x < 0), hasLength(2));
  });

  test(
    'Icebreaker unresolved doors do not manufacture artwork expectations',
    () {
      final positives = (fixture['landmarks'] as List)
          .cast<Map<String, dynamic>>();
      for (final raw in fixture['unresolvedMarkerMatches'] as List) {
        final candidate = raw as Map<String, dynamic>;
        final map = pack.byId[candidate['mapId']]!;
        final marker = map.markers.singleWhere(
          (marker) => marker.id == candidate['markerId'],
        );
        final game = candidate['game'] as List;
        expect(marker.position.x, game[0]);
        expect(marker.position.z, game[1]);
        expect(marker.position.height, game[2]);
        expect(marker.details['key'], candidate['keyId']);
        expect(marker.floorId, isNull);
        expect(candidate['artwork'], isNull);
        expect(
          positives.any(
            (control) => control['markerId'] == candidate['markerId'],
          ),
          isFalse,
          reason: candidate['reason'] as String,
        );
      }
    },
  );

  test('hidden known Interchange console leaves shared drawing browsing detail and hit eligibility', () async {
    final sourceMap = (manifest['maps'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((map) => map['id'] == 'interchange');
    // Use the actual promoted source marker/configuration, but exclude art
    // demands: this regression targets shared eligibility, not vector pixels.
    final isolated = jsonDecode(jsonEncode(sourceMap)) as Map<String, dynamic>;
    for (final floor in isolated['floors'] as List) {
      floor['componentIds'] = <String>[];
      floor['artwork'] = {'components': <Object>[]};
    }
    isolated['layerOrder'] = <String>[];
    const consoleId = 'switches:6b9023f26446d73433823e872e6d69688083beaf:0';
    const unresolvedId = 'switches:b6ebc39ee29cb6659334df309194b696bbfef555:0';
    isolated['markers'] = [
      for (final marker in isolated['markers'] as List)
        if (marker['id'] == consoleId || marker['id'] == unresolvedId) marker,
    ];
    final loader = PreparedMapPackLoader(
      loadBytes: (path) async {
        final json = path.endsWith('active.json')
            ? {
                'schemaVersion': 1,
                'version': 'eligibility',
                'manifest': 'versions/eligibility/manifest.json',
              }
            : {
                'schemaVersion': 1,
                'vectorsCompiled': true,
                'runtimeVectorVersion': '1.2.3',
                'maps': [isolated],
              };
        return ByteData.sublistView(
          Uint8List.fromList(utf8.encode(jsonEncode(json))),
        );
      },
    );
    final controller = MapController(
      loader: loader,
      resources: NativeMapResourceOwner(loader),
    );
    addTearDown(controller.dispose);
    controller.updateViewport(const Size(1200, 1000));
    await controller.initialize(selectedMapId: 'interchange');
    final map = controller.preparedMap!;
    final console = map.markers.singleWhere((marker) => marker.id == consoleId);
    expect(console.floorId, 'Second_Floor');
    expect(console.position.height, 37.347);
    expect(map.floorPolicy.floorForHeight(37.347), isNull);
    expect(controller.applyOfflineHeight(37.347), isFalse);
    expect(
      map.markers.singleWhere((marker) => marker.id == unresolvedId).floorId,
      isNull,
    );

    final initiallyHidden = !controller.floorSelection!.visibleLayerIds
        .contains('Second_Floor');
    if (initiallyHidden) controller.toggleFloor('Second_Floor');
    final shown = controller.visibleMarkers().singleWhere(
      (projection) => projection.marker.id == consoleId,
    );
    expect(shown.marker.details, console.details);
    expect(controller.hitTestMarker(shown.viewportPoint)!.marker.id, consoleId);

    controller.toggleFloor('Second_Floor');
    expect(
      controller.visibleMarkers().map((projection) => projection.marker.id),
      isNot(contains(consoleId)),
    );
    expect(controller.hitTestMarker(shown.viewportPoint), isNull);
    expect(
      controller.visibleMarkers().map((projection) => projection.marker.id),
      contains(unresolvedId),
    );
    // The UI's drawing, keyboard/browser rows and detail selection all consume
    // this projected list; the pointer predicate consumes the identical list.
    controller.toggleFloor('Second_Floor');
    expect(
      controller.visibleMarkers().map((projection) => projection.marker.id),
      contains(consoleId),
    );
  });

  test('Icebreaker physical helipad ownership wins for visibility and hit eligibility', () {
    final map = pack.byId['icebreaker']!;
    final controls = (fixture['observedSourceParity'] as List)
        .cast<Map<String, dynamic>>();
    final helipad = controls.singleWhere(
      (control) => control['id'] == 'icebreaker-octagonal-helipad',
    );
    final marker = map.markers.singleWhere(
      (marker) => marker.id == helipad['markerId'],
    );
    // Physical ownership does not move the upstream off-artwork marker or
    // relabel its frozen height/activation band to match a drawn landing pad.
    expect(marker.floorId, 'Helipad');
    expect(marker.position.height, 22.56);
    expect(marker.heightBand!.min, 21.06);
    expect(marker.heightBand!.max, 24.06);
    expect(
      map.floorPolicy.floorForHeight(marker.position.height)?.id,
      'Gym_Canteen',
    );
    final helipadSelection = map.floorPolicy.reset().select('Helipad');
    final heightSelection = map.floorPolicy.selectionForHeight(
      marker.position.height,
    );
    expect(heightSelection.visibleLayerIds, ['Gym_Canteen']);

    // The shared predicate governs paint and hit eligibility. Supplying the
    // prepared ownership must reverse the height-only result on both floors.
    bool eligible(MapFloorSelection selection, {String? floorId}) =>
        selection.isVisible(
          floorId: floorId,
          height: marker.position.height,
          unknownHeight: UnknownHeightVisibility.hidden,
        );
    expect(eligible(helipadSelection), isFalse);
    expect(eligible(heightSelection), isTrue);
    expect(eligible(helipadSelection, floorId: marker.floorId), isTrue);
    expect(eligible(heightSelection, floorId: marker.floorId), isFalse);
  });

  test('unknown height stays unknown on every actual map, not height zero', () {
    for (final map in pack.maps) {
      expect(map.floorPolicy.floorForHeight(null), isNull);
      final selection = map.floorPolicy.reset();
      expect(
        selection.isVisible(
          height: null,
          unknownHeight: UnknownHeightVisibility.hidden,
        ),
        isFalse,
      );
    }
    expect(
      pack.byId['icebreaker']!.floorPolicy.floorForHeight(0)!.id,
      'Control_Room',
    );
  });

  for (final raw in fixture['unknownObservations'] as List) {
    final observation = raw as Map<String, dynamic>;
    test('filename is not map/floor evidence: ${observation['id']}', () async {
      final loader = _loader();
      final controller = MapController(
        loader: loader,
        resources: NativeMapResourceOwner(loader),
      );
      addTearDown(controller.dispose);
      // Exercise the real identity boundary with an adversarial filename. No
      // viewport is opened and no actual artwork decoding is needed.
      await controller.initialize(
        selectedMapId: observation['filename'] as String,
      );
      expect(controller.preparedMap, isNull);
      expect(controller.floorSelection, isNull);
      expect(controller.scene, isNull);
      expect(controller.unavailable, isTrue);
      expect(controller.visibleMarkers(), isEmpty);
      expect(
        controller.applyOfflineHeight(
          (observation['height'] as num?)?.toDouble(),
        ),
        isFalse,
      );
      expect(observation['mapId'], isNull);
      expect(observation['floorId'], isNull);
    });
  }

  test(
    'known map offline floor replay preserves the last known selection',
    () async {
      final loader = _loader();
      final controller = MapController(
        loader: loader,
        resources: NativeMapResourceOwner(loader),
      );
      addTearDown(controller.dispose);
      await controller.initialize(selectedMapId: 'icebreaker');
      expect(controller.applyOfflineHeight(35.64), isTrue);
      expect(controller.floorSelection!.visibleLayerIds, ['Officers_Deck']);
      expect(controller.applyOfflineHeight(null), isFalse);
      expect(controller.floorSelection!.visibleLayerIds, ['Officers_Deck']);
    },
  );
}

PreparedMapPackLoader _loader() => PreparedMapPackLoader(
  loadBytes: (path) async =>
      ByteData.sublistView(await File(path).readAsBytes()),
);

void _expectSourceMarker(PreparedMarker marker, Map<String, dynamic> control) {
  final game = control['game'] as List;
  expect(marker.name, control['name']);
  expect(marker.source['url'], 'https://json.tarkov.dev/regular/maps');
  expect(marker.source['path'], control['sourcePath']);
  expect(marker.position.x, game[0]);
  expect(marker.position.z, game[1]);
  expect(marker.position.height, game[2]);
  if (control['physicalFloorBasis'] != null) {
    expect(marker.floorId, control['preparedFloorId']);
    final assignment = marker.source['floorAssignment'] as Map<String, dynamic>;
    expect(assignment['floorId'], control['preparedFloorId']);
    expect(assignment['evidenceUrls'], isNotEmpty);
  }
  if (control['keyId'] != null) {
    expect(marker.details['key'], control['keyId']);
  }
}

double _labelScale(PreparedMap map, Map<String, dynamic> control) {
  if (control['artworkUnits'] == 'svg-viewbox') return 1;
  expect(control['artworkUnits'], 'original-256px-tile-mosaic');
  // This is source image-to-display unit conversion, not game calibration.
  return map.id == 'thelab' ? 175 / 256 : 1;
}

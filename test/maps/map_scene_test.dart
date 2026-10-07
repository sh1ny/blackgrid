import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart'
    as compiler;

import 'package:blackgrid/domain/map_coordinates.dart';
import 'package:blackgrid/domain/map_floors.dart';
import 'package:blackgrid/domain/map_geometry.dart';
import 'package:blackgrid/maps/native_map_scene.dart';
import 'package:blackgrid/maps/prepared_map.dart';
import 'package:blackgrid/maps/prepared_map_loader.dart';

import '../../tool/maps/calibration.dart';
import '../../tool/maps/pack.dart';
import '../support/map_preparation_fixtures.dart'
    show preparedMapMetadataFixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'pointer and manifest resolve exactly one immutable asset version',
    () async {
      final paths = <String>[];
      final loader = PreparedMapPackLoader(
        loadBytes: (path) async {
          paths.add(path);
          if (path.endsWith('active.json')) {
            return _json({
              'schemaVersion': 1,
              'version': 'fixture',
              'manifest': 'versions/fixture/manifest.json',
            });
          }
          return _json({
            'schemaVersion': 1,
            'vectorsCompiled': true,
            'runtimeVectorVersion': '1.2.3',
            'maps': [_vectorMap()],
          });
        },
      );
      final pack = await loader.load();
      expect(pack.version, 'fixture');
      expect(
        pack.maps.single.components.first.path,
        'assets/maps/versions/fixture/overlay.vec',
      );
      expect(paths, [
        'assets/maps/active.json',
        'assets/maps/versions/fixture/manifest.json',
      ]);
      expect(identical(pack, await loader.load()), isTrue);
      final invalid = PreparedMapPackLoader(
        loadBytes: (_) async => _json({
          'schemaVersion': 1,
          'version': 'fixture',
          'manifest': 'versions/other/manifest.json',
        }),
      );
      await expectLater(invalid.load(), throwsFormatException);
    },
  );

  test('version-three inventory and artwork output closure load all thirteen maps without decoding', () async {
    final manifest = _completeManifest();
    final loaded = <String>[];
    final loader = _manifestLoader(manifest, loaded: loaded);
    final pack = await loader.load();
    expect(pack.maps.map((map) => map.id), _canonicalMapIds);
    expect(pack.byId.keys, _canonicalMapIds);
    expect(loaded, [
      'assets/maps/active.json',
      'assets/maps/versions/fixture/manifest.json',
    ]);
    expect(identical(await loader.load(), pack), isTrue);
    expect(() => pack.maps.clear(), throwsUnsupportedError);
    expect(() => pack.byId.clear(), throwsUnsupportedError);
  });

  test('version-three rejects missing duplicate or mismatched inventory and unclosed outputs', () async {
    final mutations = <void Function(Map<String, dynamic>)>[
      (manifest) => (manifest['maps'] as List).removeLast(),
      (manifest) => (manifest['supportedMapIds'] as List).removeLast(),
      (manifest) => (manifest['supportedMapIds'] as List)[12] = 'factory',
      (manifest) => (manifest['supportedMapIds'] as List)[12] = 'unprepared',
      (manifest) {
        (manifest['supportedMapIds'] as List)[12] = 'unprepared';
        (manifest['maps'] as List)[12]['id'] = 'unprepared';
      },
      (manifest) =>
          (manifest['maps'] as List)[12] = (manifest['maps'] as List).first,
      (manifest) => manifest.remove('outputs'),
      (manifest) => (manifest['outputs'] as List).removeWhere(
        (entry) => (entry['path'] as String).endsWith('.vec'),
      ),
      (manifest) => (manifest['outputs'] as List).removeWhere(
        (entry) => (entry['path'] as String).startsWith('artwork/labyrinth/'),
      ),
      (manifest) => (manifest['outputs'] as List).removeWhere(
        (entry) =>
            (entry['path'] as String).startsWith('artwork/dependencies/'),
      ),
      (manifest) => (manifest['outputs'] as List).add(
        (manifest['outputs'] as List).first,
      ),
      (manifest) =>
          (manifest['outputs'] as List).add({'path': '../escape.vec'}),
    ];
    for (var index = 0; index < mutations.length; index++) {
      final manifest = _completeManifest();
      mutations[index](manifest);
      await expectLater(
        _manifestLoader(manifest).load(),
        throwsFormatException,
        reason: 'closure mutation $index',
      );
    }
  });

  test('version-two manifests keep the legacy partial-pack contract', () async {
    final pack = await _manifestLoader({
      'schemaVersion': 1,
      'preparationVersion': 2,
      'vectorsCompiled': true,
      'runtimeVectorVersion': '1.2.3',
      'maps': [_vectorMap()],
    }).load();
    expect(pack.maps.single.id, 'interchange');
  });

  test('all-family parser preserves authored frames floors and runtime quest filter identities', () {
    // Structural/parity coverage only. Authored calibration is not an
    // independent numeric placement oracle for these map families.
    for (final entry in supportedMapSources.entries) {
      final raw = preparedMapMetadataFixture(entry.value);
      raw['markers'] = [
        _marker('item', 'questItems', details: {'questId': 'quest'}),
        _marker('objective', 'questObjectives', details: {'questId': 'quest'}),
        _marker('transit', 'transits'),
        _marker('scav', 'extracts', details: {'faction': 'Scav'}),
        _marker('pmc', 'extracts', details: {'faction': 'PMC'}),
        _marker('shared', 'extracts'),
        _marker('spawn', 'spawns', details: {'side': 'scav'}),
        _marker('hazard', 'hazards', details: {'outline': <Object>[]}),
      ];
      final map = PreparedMap.fromJson(raw, assetRoot: 'fixture/');
      final authored = calibrationFor(entry.value);
      final frame = authored['artworkFrame'] as Map;
      expect(map.id, entry.key);
      expect(map.displayFrame.originalArtwork.width, frame['width']);
      expect(map.displayFrame.originalArtwork.height, frame['height']);
      expect(map.displayFrame.sceneExtent.width, frame['width']);
      expect(map.displayFrame.sceneExtent.height, frame['height']);
      expect(map.floorPolicy.floors.map((floor) => floor.id), [
        for (final floor in authored['floors'] as List)
          if (floor['base'] == true) floor['id'],
        for (final floor in authored['floors'] as List)
          if (floor['base'] != true) floor['id'],
      ]);
      expect(map.categories, {
        'QuestItems',
        'QuestObjectives',
        'Transits',
        'ScavExtracts',
        'PmcExtracts',
        'SharedExtracts',
        'ScavSpawns',
        'HazardZones',
      });
      expect(map.markers.take(2).map((marker) => marker.filterKey), [
        'QuestItems',
        'QuestObjectives',
      ]);
      expect(map.markers.first.details['questId'], 'quest');
      expect(() => map.categories.clear(), throwsUnsupportedError);
      expect(() => map.markers.first.details.clear(), throwsUnsupportedError);
      expect(() => map.components.clear(), throwsUnsupportedError);
      expect(() => map.tiles.clear(), throwsUnsupportedError);
      expect(
        map.floorPolicy.supportsAutomaticHeight,
        entry.key == 'thelab' || entry.key == 'icebreaker',
      );
    }
    final explicit = PreparedMarker.fromJson({
      ..._marker('authored-key', 'questItems'),
      'filterKey': 'QuestItems',
    });
    expect(explicit.filterKey, 'QuestItems');
  });

  test('production-shaped spawns and bosses classify by sides and mob', () {
    String key(String category, Map<String, dynamic> details) =>
        PreparedMarker.fromJson(_marker('m', category, details: details))
            .filterKey;
    expect(
      key('spawns', {
        'sides': ['scav'],
        'categories': ['bot'],
      }),
      'ScavSpawns',
    );
    expect(
      key('spawns', {
        'sides': ['pmc'],
        'categories': ['player'],
      }),
      'PmcSpawns',
    );
    expect(
      key('spawns', {
        'sides': ['all'],
        'categories': ['player'],
      }),
      'PmcSpawns',
    );
    expect(
      key('spawns', {
        'sides': ['none'],
      }),
      'PmcSpawns',
    );
    expect(key('spawns', {'sides': <Object>[]}), 'PmcSpawns');
    expect(key('spawns', {'side': 'scav'}), 'ScavSpawns');
    expect(key('spawns', const {}), 'PmcSpawns');
    expect(
      PreparedMarker.fromJson({
        ..._marker(
          'authored',
          'spawns',
          details: {
            'sides': ['scav'],
          },
        ),
        'filterKey': 'PmcSpawns',
      }).filterKey,
      'PmcSpawns',
    );
    expect(
      key('bosses', {'mob': 'sectantPriest', 'spawnChance': 0.1}),
      'CultistSpawns',
    );
    expect(key('bosses', {'mob': 'sectantWarrior'}), 'CultistSpawns');
    expect(
      key('bosses', {'mob': 'bossTagilla', 'spawnChance': 0.35}),
      'BossSpawns',
    );
  });

  for (final source in [
    'shoreline',
    'streets-of-tarkov',
    'ground-zero',
    'terminal',
  ]) {
    test(
      '$source native ordering paints attached First_Floor with base and manual overlays',
      () async {
        final raw = preparedMapMetadataFixture(source);
        // Synthetic pixels, deliberately independent of actual artwork placement.
        // First is last in source DOM order even though owned by the base floor.
        final order = (raw['layerOrder'] as List).cast<String>();
        order.remove('First_Floor');
        order.add('First_Floor');
        final map = PreparedMap.fromJson(raw, assetRoot: 'fixture/');
        final loaded = <String>[];
        final owner = NativeMapResourceOwner(
          PreparedMapPackLoader(
            loadBytes: (path) async {
              loaded.add(path);
              if (path.contains('/dependencies/')) {
                throw StateError(
                  'Alternate rendition must not decode or paint',
                );
              }
              final id = path.split('/').last.replaceAll('.vec', '');
              final fill = id == 'First_Floor' ? '#0000ff' : '#ff0000';
              final x = id == 'First_Floor' ? 4 : 0;
              return _vector(
                '<rect x="$x" y="0" width="16" height="16" fill="$fill"/>',
              );
            },
          ),
        );
        addTearDown(owner.dispose);
        var selected = map.floorPolicy.reset();
        Future<void> assertScene() async {
          final scene = (await owner.loadScene(
            map,
            selected,
            MapViewTransform(),
            const ui.Size(32, 32),
            isCurrent: () => true,
          ))!;
          try {
            final pixels = await _render(scene, 32);
            expect(_rgba(pixels, 32, 2, 2), [255, 0, 0, 255]);
            expect(_rgba(pixels, 32, 8, 8), [0, 0, 255, 255]);
            expect(_rgba(pixels, 32, 24, 24), [0, 0, 0, 0]);
          } finally {
            scene.dispose();
          }
        }

        await assertScene();
        expect(loaded, [
          for (final component in map.components)
            if (component.floorId == map.floorPolicy.base.id) component.path,
        ]);
        for (final overlay in map.floorPolicy.overlays) {
          selected = selected.select(overlay.id);
          await assertScene();
        }
        expect(
          loaded.toSet(),
          map.components.map((component) => component.path).toSet(),
        );
        expect(owner.imageDecodedBytes, 0);
        expect(owner.reservedImageBytes, 0);
        selected = selected.select(map.floorPolicy.base.id);
        await assertScene();
      },
    );
  }

  test('Ground Zero alternate grids are complete original-frame immutable dependencies', () {
    final raw = preparedMapMetadataFixture('ground-zero');
    final map = PreparedMap.fromJson(raw, assetRoot: 'fixture/');
    expect(map.kind, 'vector');
    expect(map.tiles, isEmpty);
    expect(map.tileLayout, isNull);
    expect(map.rasterDependencies.map((dependency) => dependency.id), [
      'Ground_Level',
      'Second_Floor',
      'Third_Floor',
      'Underground_Level',
    ]);
    for (final dependency in map.rasterDependencies) {
      expect(dependency.frame.width, 4096);
      expect(dependency.frame.height, 4096);
      expect(
        dependency.sourceUrl,
        startsWith('https://assets.tarkov.dev/maps/groundzero/'),
      );
      expect(dependency.assetPaths.length, 256);
      expect(dependency.assetPaths.toSet().length, 256);
      expect(
        dependency.assetPaths.first,
        'fixture/artwork/dependencies/groundzero/${dependency.id}/0/0.png',
      );
      expect(
        dependency.assetPaths.last,
        'fixture/artwork/dependencies/groundzero/${dependency.id}/15/15.png',
      );
      expect(() => dependency.assetPaths.clear(), throwsUnsupportedError);
    }
    expect(() => map.rasterDependencies.clear(), throwsUnsupportedError);
    (raw['rasterDependencies'] as List).clear();
    expect(map.rasterDependencies.length, 4);
  });

  test('Ground Zero rejects malformed dependency grids frames paths and floor ownership', () {
    final mutations = <void Function(Map<String, dynamic>)>[
      (dependency) => (dependency['artwork']['tiles'] as List).removeLast(),
      (dependency) => (dependency['artwork']['tiles'] as List)[255] =
          (dependency['artwork']['tiles'] as List).first,
      (dependency) => dependency['artwork']['tiles'][0]['x'] = 16,
      (dependency) => dependency['artwork']['tiles'][0]['y'] = -1,
      (dependency) => dependency['artwork']['tiles'][0]['x'] = 0.5,
      (dependency) => dependency['artwork']['tiles'][0].remove('empty'),
      (dependency) =>
          dependency['artwork']['tiles'][0]['path'] = '../escape.png',
      (dependency) => dependency['displayFrame']['width'] = 2800,
      (dependency) => dependency['displayFrame']['height'] = 2048,
      (dependency) => dependency['displayFrame']['tileStride'] = 175,
      (dependency) => dependency['displayFrame']['tileImageExtent'] = 256.5,
      (dependency) => dependency['displayFrame']['nativeTilePixels'] = 512,
      (dependency) => dependency['id'] = 'First_Floor',
      (dependency) => dependency['sourceTileUrl'] = '',
      (dependency) {
        for (final tile in dependency['artwork']['tiles'] as List) {
          tile['empty'] = true;
        }
      },
    ];
    for (var index = 0; index < mutations.length; index++) {
      final raw = preparedMapMetadataFixture('ground-zero');
      mutations[index]((raw['rasterDependencies'] as List).first);
      expect(
        () => PreparedMap.fromJson(raw, assetRoot: 'fixture/'),
        throwsFormatException,
        reason: 'dependency mutation $index',
      );
    }
    final duplicate = preparedMapMetadataFixture('ground-zero');
    (duplicate['rasterDependencies'] as List).add(
      (duplicate['rasterDependencies'] as List).first,
    );
    expect(
      () => PreparedMap.fromJson(duplicate, assetRoot: 'fixture/'),
      throwsFormatException,
    );
  });

  for (final entry in <String, Set<String>>{
    'customs': {'Fourth_Floor'},
    'reserve': {'Second_Floor', 'Third_Floor', 'Fourth_Floor', 'Fifth_Floor'},
  }.entries) {
    test('${entry.key} abstract SVG draws tile-only floors over a dimmed base', () async {
      // Synthetic artwork exercises loading and composition only; overlay
      // placement is covered against tarkov.dev's CRS in its own test.
      final raw = preparedMapMetadataFixture(entry.key);
      final map = PreparedMap.fromJson(raw, assetRoot: 'fixture/');
      expect(map.kind, 'vector');
      expect(map.tiles.map((tile) => tile.floorId).toSet(), entry.value);
      final loaded = <String>[];
      final owner = NativeMapResourceOwner(
        PreparedMapPackLoader(
          loadBytes: (path) async {
            loaded.add(path);
            return path.endsWith('.png')
                ? ByteData.sublistView(
                    image.encodePng(
                      image.Image(width: 256, height: 256, numChannels: 4),
                    ),
                  )
                : _vector(
                    '<rect x="0" y="0" width="32" height="32" fill="#ff0000"/>',
                  );
          },
        ),
      );
      addTearDown(owner.dispose);
      Future<int> baseAlpha(MapFloorSelection selection) async {
        final scene = (await owner.loadScene(
          map,
          selection,
          MapViewTransform(),
          const ui.Size(32, 32),
          isCurrent: () => true,
        ))!;
        try {
          return _rgba(await _render(scene, 32), 32, 16, 16)[3];
        } finally {
          scene.dispose();
        }
      }

      expect(await baseAlpha(map.floorPolicy.reset()), 255);
      expect(loaded.where((path) => path.endsWith('.png')), isEmpty);
      for (final floor in map.floorPolicy.overlays) {
        loaded.clear();
        final alpha = await baseAlpha(map.floorPolicy.reset().select(floor.id));
        if (entry.value.contains(floor.id)) {
          expect(alpha, inExclusiveRange(0, 128));
          expect(
            map.tiles.where((tile) => tile.floorId == floor.id),
            isNotEmpty,
          );
        } else {
          expect(alpha, 255);
          expect(loaded.where((path) => path.endsWith('.png')), isEmpty);
        }
      }
    });
  }

  test('Labyrinth native raster has one scene and no inferred automatic height bands', () async {
    final raw = preparedMapMetadataFixture('the-labyrinth');
    final map = PreparedMap.fromJson(raw, assetRoot: 'fixture/');
    expect(map.components, isEmpty);
    expect(map.rasterDependencies, isEmpty);
    expect(map.floorPolicy.floors.map((floor) => floor.id), ['Main_Level']);
    expect(map.floorPolicy.overlays, isEmpty);
    expect(map.floorPolicy.base.heightBand, isNull);
    expect(map.floorPolicy.supportsAutomaticHeight, isFalse);
    expect(map.displayFrame.originalArtwork.width, 4096);
    expect(map.displayFrame.originalArtwork.height, 4096);
    expect(map.tileLayout!.displayStride.width, 256);
    expect(map.tileLayout!.nativeTilePixels.width, 256);
    expect((raw['geometry'] as Map)['rotation'], 270);
    expect((raw['geometry'] as Map)['affine'], [2.115, 85.5, 2.115, 128]);
    for (final height in [null, -10000.0, 0.0, 10000.0]) {
      expect(map.floorPolicy.floorForHeight(height), isNull);
      expect(map.floorPolicy.selectionForHeight(height).visibleLayerIds, [
        'Main_Level',
      ]);
    }
    final loaded = <String>[];
    final owner = NativeMapResourceOwner(
      PreparedMapPackLoader(
        loadBytes: (path) async {
          loaded.add(path);
          return _png();
        },
      ),
    );
    addTearDown(owner.dispose);
    final scene = (await owner.loadScene(
      map,
      map.floorPolicy.reset(),
      MapViewTransform(),
      const ui.Size(32, 32),
      isCurrent: () => true,
    ))!;
    addTearDown(scene.dispose);
    expect(loaded, ['fixture/artwork/labyrinth/Main_Level/0/0.png']);
    final pixels = await _render(scene, 32);
    expect(_rgba(pixels, 32, 0, 0), [255, 0, 0, 255]);
    expect(_rgba(pixels, 32, 8, 8), [0, 0, 0, 0]);
    expect(owner.imageDecodedBytes, 256 * 256 * 4);
    expect(owner.pictureApproximateBytes, 0);
  });

  test('native components retain global ordering and exact zero-blur offset shadow', () async {
    final map = PreparedMap.fromJson(_vectorMap(), assetRoot: 'fixture/');
    final assets = {
      'fixture/base.vec': _vector(
        '<rect x="4" y="4" width="4" height="4" fill="#ff0000"/>',
      ),
      'fixture/overlay.vec': _vector(
        '<rect x="16" y="4" width="4" height="4" fill="#0000ff"/>',
      ),
    };
    final owner = NativeMapResourceOwner(
      PreparedMapPackLoader(loadBytes: (path) async => assets[path]!),
    );
    addTearDown(owner.dispose);
    final scene = (await owner.loadScene(
      map,
      map.floorPolicy.reset().select('Second'),
      MapViewTransform(),
      const ui.Size(32, 32),
      isCurrent: () => true,
    ))!;
    addTearDown(scene.dispose);
    final pixels = await _render(scene, 32);
    expect(_rgba(pixels, 32, 6, 6), [255, 0, 0, 255]);
    // Overlay is painted first despite being the second selectable floor.
    // The base's exact dx=12, sigma=0 alpha shadow is painted over it.
    expect(_rgba(pixels, 32, 18, 6), [0, 0, 0, 255]);
    expect(_rgba(pixels, 32, 10, 6), [0, 0, 0, 0]);
    expect(owner.pictureApproximateBytes, greaterThan(0));
    expect(owner.imageDecodedBytes, 0);
    expect(owner.accountedBytes, lessThanOrEqualTo(owner.maxBytes));
  });

  test('raster demand decodes only visible active floors and evicts unleased tiles', () async {
    final map = PreparedMap.fromJson(_rasterMap(), assetRoot: 'fixture/');
    final bytes = _png();
    final loaded = <String>[];
    final owner = NativeMapResourceOwner(
      PreparedMapPackLoader(
        loadBytes: (path) async {
          loaded.add(path);
          return bytes;
        },
      ),
      maxBytes: 256 * 256 * 4,
    );
    addTearDown(owner.dispose);
    final base = map.floorPolicy.reset();
    final first = (await owner.loadScene(
      map,
      base,
      MapViewTransform(),
      const ui.Size(200, 200),
      isCurrent: () => true,
    ))!;
    expect(loaded, ['fixture/base-0.png']);
    expect(owner.imageDecodedBytes, 256 * 256 * 4);
    expect(
      first.matchesDemand(
        base,
        MapViewTransform(translationX: 10),
        const ui.Size(180, 180),
      ),
      isTrue,
    );
    first.dispose();
    final second = (await owner.loadScene(
      map,
      base,
      MapViewTransform(translationX: -256),
      const ui.Size(200, 200),
      isCurrent: () => true,
    ))!;
    expect(loaded, ['fixture/base-0.png', 'fixture/base-1.png']);
    expect(owner.retainedResourceCount, 1);
    expect(owner.accountedBytes, 256 * 256 * 4);
    second.dispose();
    final upper = (await owner.loadScene(
      map,
      base.select('Upper'),
      MapViewTransform(),
      const ui.Size(200, 200),
      isCurrent: () => true,
    ))!;
    expect(loaded.last, 'fixture/upper-0.png');
    expect(owner.retainedResourceCount, 1);
    upper.dispose();
    owner.dispose();
    expect(owner.accountedBytes, 0);
    expect(owner.retainedResourceCount, 0);
    expect(owner.reservedImageBytes, 0);
  });

  test(
    'superseded bytes and disposed owners cannot publish late resources',
    () async {
      final map = PreparedMap.fromJson(_rasterMap(), assetRoot: 'fixture/');
      final gate = Completer<ByteData>();
      final owner = NativeMapResourceOwner(
        PreparedMapPackLoader(loadBytes: (_) => gate.future),
      );
      var current = true;
      final demand = owner.loadScene(
        map,
        map.floorPolicy.reset(),
        MapViewTransform(),
        const ui.Size(200, 200),
        isCurrent: () => current,
      );
      current = false;
      gate.complete(_png());
      expect(await demand, isNull);
      expect(owner.retainedResourceCount, 0);
      expect(owner.accountedBytes, 0);
      owner.dispose();
      expect(
        await owner.loadScene(
          map,
          map.floorPolicy.reset(),
          MapViewTransform(),
          const ui.Size(200, 200),
          isCurrent: () => true,
        ),
        isNull,
      );
    },
  );

  test(
    'invalid raster dimensions fail instead of scaling or filling silently',
    () async {
      final map = PreparedMap.fromJson(_rasterMap(), assetRoot: 'fixture/');
      final owner = NativeMapResourceOwner(
        PreparedMapPackLoader(loadBytes: (_) async => _png(width: 128)),
      );
      addTearDown(owner.dispose);
      await expectLater(
        owner.loadScene(
          map,
          map.floorPolicy.reset(),
          MapViewTransform(),
          const ui.Size(200, 200),
          isCurrent: () => true,
        ),
        throwsFormatException,
      );
      expect(owner.accountedBytes, 0);
      expect(owner.reservedImageBytes, 0);
    },
  );

  test('Labs source landmarks and native revision-one pins share the displayed tile frame', () {
    final map = PreparedMap.fromJson(
      _calibratedRasterMap('the-lab'),
      assetRoot: 'fixture/',
    );
    // Independently labelled features in the original 4096-pixel tile frame.
    // The full displayed frame is 2800 pixels; seam extent is not its stride.
    for (final (name, x, z, nativeX, nativeY, tolerance) in [
      ('Parking Gate', -231.46, -457.77, 420.0, 1420.0, 90.0),
      ('Hangar Gate', -170.49, -218.87, 3640.0, 2240.0, 90.0),
      ('Main Elevator', -282.69, -334.73, 2075.0, 730.0, 45.0),
      ('Medical Block Elevator', -112.3, -344.04, 1950.0, 3025.0, 45.0),
      ('Cargo Elevator', -111.79, -408.55, 1080.0, 3030.0, 55.0),
    ]) {
      final scene = map.gameToScene(GamePoint(x, z));
      final expectedX = nativeX * 175 / 256;
      final expectedY = nativeY * 175 / 256;
      expect(scene.x, closeTo(expectedX, tolerance * 175 / 256), reason: name);
      expect(scene.y, closeTo(expectedY, tolerance * 175 / 256), reason: name);
      final pin = MapPinCoordinates(
        mapId: 'thelab',
        point: ArtworkPoint(nativeX / 4096, nativeY / 4096),
        frame: MapCoordinateFrame.labsNativeNormalized,
      );
      final pinScene = map.displayFrame.artworkToScene(
        map.pinProjector.pinToArtwork(pin),
      );
      expect(pinScene.x, closeTo(expectedX, 1e-9), reason: name);
      expect(pinScene.y, closeTo(expectedY, 1e-9), reason: name);
      final restored = map.geometry.artworkToGame(
        map.displayFrame.sceneToArtwork(scene),
      );
      expect(restored.x, closeTo(x, 1e-9), reason: name);
      expect(restored.z, closeTo(z, 1e-9), reason: name);
    }
    final offMap = map.gameToScene(GamePoint(-500, -600));
    expect(offMap.x, lessThan(0));
    expect(offMap.y, lessThan(0));
    final restored = map.geometry.artworkToGame(
      map.displayFrame.sceneToArtwork(offMap),
    );
    expect(restored.x, closeTo(-500, 1e-9));
    expect(restored.z, closeTo(-600, 1e-9));
  });

  test('evidenced Icebreaker marker ownership wins without changing source heights or bands', () {
    // Minimal source records preserve the real public marker identities and
    // coordinates. The unrelated same-name record must not inherit a floor.
    final snapshot = <String, dynamic>{
      'data': {
        'maps': {
          'icebreaker': {
            'id': 'icebreaker',
            'normalizedName': 'icebreaker',
            'extracts': [
              {
                'id': '9bf65c4c24d0153f1542a90ddabadb37198ab9ff',
                'name': 'Heli',
                'position': {'x': .28, 'y': 22.56, 'z': -66.03},
                'bottom': 21.06,
                'top': 24.06,
                'outline': [
                  {'x': 5.01, 'y': 21.06, 'z': -73.71},
                  {'x': -4.99, 'y': 21.06, 'z': -73.34},
                  {'x': -4.45, 'y': 21.06, 'z': -58.35},
                  {'x': 5.55, 'y': 21.06, 'z': -58.72},
                ],
              },
              {
                'id': 'unrelated',
                'name': 'Heli',
                'position': {'x': 0, 'y': 22.56, 'z': 0},
              },
            ],
            'locks': [
              {
                'id': 'f680d37a9e9c4f7b4673a2cd1bedd4a8ed73e104',
                'key': '69bb3f278af9f360ee010a7a',
                'position': {'x': -5.25, 'y': 35.64, 'z': 28.39},
              },
            ],
            'bosses': <Object>[],
          },
        },
      },
    };
    final raw = _calibratedRasterMap('icebreaker');
    raw['markers'] = [
      for (final marker in prepareMarkers(snapshot, {
        'Heli': 'Helicopter',
      }, raw))
        Map<String, dynamic>.from(marker),
    ];
    final map = PreparedMap.fromJson(raw, assetRoot: 'fixture/');
    final helicopter = map.markers.first;
    expect(helicopter.floorId, 'Helipad');
    expect(helicopter.position.height, 22.56);
    expect(helicopter.heightBand!.min, 21.06);
    expect(helicopter.heightBand!.max, 24.06);
    expect(
      helicopter.outline.map((point) => point.height),
      everyElement(21.06),
    );
    expect(map.floorPolicy.floorForHeight(21.06)!.id, 'Helipad');
    expect(helicopter.details['position'], {'x': .28, 'y': 22.56, 'z': -66.03});
    expect(
      helicopter.source['floorAssignment'],
      containsPair('basis', 'helicopter-extraction-at-physical-helipad-centre'),
    );
    expect(map.floorPolicy.floorForHeight(22.56)!.id, 'Gym_Canteen');
    expect(map.floorPolicy.floorForHeight(22.2)!.id, 'Gym_Canteen');
    expect(map.floorPolicy.floorForHeight(19.57)!.id, 'Helipad');
    expect(map.floorPolicy.floorForHeight(null), isNull);
    expect(map.floorPolicy.floorForHeight(0)!.id, 'Control_Room');
    bool visibleOn(String floorId) => map.floorPolicy
        .reset()
        .select(floorId)
        .isVisible(
          floorId: helicopter.floorId,
          height: helicopter.position.height,
          unknownHeight: UnknownHeightVisibility.hidden,
        );
    expect(visibleOn('Helipad'), isTrue);
    expect(visibleOn('Gym_Canteen'), isFalse);
    expect(map.markers[1].floorId, isNull);
    final serverDoor = map.markers[2];
    expect(serverDoor.floorId, 'Officers_Deck');
    expect(serverDoor.position.height, 35.64);
    expect(
      map.floorPolicy
          .reset()
          .select('Officers_Deck')
          .isVisible(
            floorId: serverDoor.floorId,
            height: serverDoor.position.height,
            unknownHeight: UnknownHeightVisibility.hidden,
          ),
      isTrue,
    );
  });

  test(
    'Labs native full frame and crop remain separate from display stride',
    () {
      final raw = _rasterMap();
      raw['id'] = 'thelab';
      raw['geometry'] = {
        'rotation': 0,
        'affine': [1, 0, 1, 256],
        'bounds': [
          [0, 0],
          [256, 256],
        ],
        'nativeZoom': 4,
        'coordinateRevision': 1,
        'pinFrame': 'labs-native-normalized',
        'projection': 'native-pixels',
      };
      raw['artworkFrame'] = {
        'width': 2800,
        'height': 2800,
        'tileStride': 175,
        'tileImageExtent': 175.5,
        'nativeTilePixels': 256,
      };
      raw['displayCrop'] = {
        'left': 100,
        'top': 50,
        'right': 2800,
        'bottom': 2800,
      };
      final map = PreparedMap.fromJson(raw, assetRoot: 'fixture/');
      final point = map.geometry.artworkToGame(
        map.displayFrame.sceneToArtwork(
          map.displayFrame.artworkToScene(
            map.geometry.gameToArtwork(GamePoint(128, 128)),
          ),
        ),
      );
      expect(point.x, closeTo(128, 1e-9));
      final normalized = map.geometry.gameToArtwork(GamePoint(128, 128));
      expect(normalized.x, closeTo(.5, 1e-9));
      expect(
        map.displayFrame.artworkToScene(normalized).x,
        closeTo(1300, 1e-9),
      );
      expect(map.tileLayout!.sceneTileExtent.width, 175.5);
    },
  );
}

const _canonicalMapIds = [
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

Map<String, dynamic> _marker(
  String id,
  String category, {
  Map<String, dynamic> details = const {},
}) => {
  'id': id,
  'category': category,
  'name': id,
  'position': {'x': 0, 'z': 0, 'height': null},
  'details': details,
  'source': <String, dynamic>{},
};

Map<String, dynamic> _completeManifest() {
  final maps = [
    for (final source in supportedMapSources.values)
      preparedMapMetadataFixture(source),
  ];
  final paths = <String>{};
  for (final raw in maps) {
    final map = PreparedMap.fromJson(raw, assetRoot: '');
    paths.addAll([
      for (final component in map.components) component.path,
      for (final tile in map.tiles) tile.path,
      for (final dependency in map.rasterDependencies) ...dependency.assetPaths,
    ]);
  }
  return {
    'schemaVersion': 1,
    'preparationVersion': 3,
    'vectorsCompiled': true,
    'runtimeVectorVersion': '1.2.3',
    'supportedMapIds': [..._canonicalMapIds],
    'maps': maps,
    'outputs': [
      for (final path in paths) {'path': path},
    ],
  };
}

PreparedMapPackLoader _manifestLoader(
  Map<String, dynamic> manifest, {
  List<String>? loaded,
}) => PreparedMapPackLoader(
  loadBytes: (path) async {
    loaded?.add(path);
    if (path.endsWith('active.json')) {
      return _json({
        'schemaVersion': 1,
        'version': 'fixture',
        'manifest': 'versions/fixture/manifest.json',
      });
    }
    if (path.endsWith('manifest.json')) return _json(manifest);
    throw StateError('Metadata loading must not decode artwork: $path');
  },
);

// These independently authored fixtures exercise the public production loader
// and real Flutter picture/image decoding; they are not production fallbacks.
Map<String, dynamic> _vectorMap() => {
  'id': 'interchange',
  'name': 'Vector fixture',
  'kind': 'vector',
  'geometry': {
    'rotation': 0,
    'affine': [1, 0, 1, 32],
    'bounds': [
      [0, 0],
      [32, 32],
    ],
    'nativeZoom': null,
    'coordinateRevision': 0,
    'pinFrame': 'legacy-normalized',
    'projection': 'bounds-normalized',
  },
  'artworkFrame': {'width': 32, 'height': 32},
  'displayCrop': {'left': 0, 'top': 0, 'right': 32, 'bottom': 32},
  'layerOrder': ['overlay', 'base'],
  'floors': [
    {
      'id': 'Ground',
      'base': true,
      'manual': true,
      'exclusive': false,
      'attachedIds': [],
      'componentIds': ['base'],
      'artwork': {
        'components': [
          {
            'id': 'base',
            'type': 'vector',
            'path': 'base.vec',
            'effects': [
              {
                'type': 'drop-shadow',
                'dx': 12,
                'dy': 0,
                'sigma': 0,
                'color': '#000000',
                'sourceDeclaration': 'drop-shadow(12px 0 #000)',
              },
            ],
          },
        ],
      },
    },
    {
      'id': 'Second',
      'base': false,
      'manual': true,
      'exclusive': false,
      'attachedIds': [],
      'componentIds': ['overlay'],
      'artwork': {
        'components': [
          {
            'id': 'overlay',
            'type': 'vector',
            'path': 'overlay.vec',
            'effects': [],
          },
        ],
      },
    },
  ],
  'markers': [],
  'attribution': {'author': 'Independent fixture'},
};
Map<String, dynamic> _rasterMap() => {
  'id': 'icebreaker',
  'name': 'Raster fixture',
  'kind': 'raster',
  'geometry': {
    'rotation': 0,
    'affine': [1, 0, 1, 256],
    'bounds': [
      [0, 0],
      [512, 256],
    ],
    'nativeZoom': 0,
    'coordinateRevision': 0,
    'pinFrame': 'legacy-normalized',
    'projection': 'native-pixels',
  },
  'artworkFrame': {
    'width': 512,
    'height': 256,
    'tileStride': 256,
    'tileImageExtent': 256,
    'nativeTilePixels': 256,
  },
  'displayCrop': {'left': 0, 'top': 0, 'right': 512, 'bottom': 256},
  'floors': [
    {
      'id': 'Base',
      'base': true,
      'manual': true,
      'exclusive': true,
      'attachedIds': [],
      'artwork': {
        'tiles': [
          {'x': 0, 'y': 0, 'empty': false, 'path': 'base-0.png'},
          {'x': 1, 'y': 0, 'empty': false, 'path': 'base-1.png'},
        ],
      },
    },
    {
      'id': 'Upper',
      'base': false,
      'manual': true,
      'exclusive': true,
      'attachedIds': [],
      'heightBand': [3, 5],
      'artwork': {
        'tiles': [
          {'x': 0, 'y': 0, 'empty': false, 'path': 'upper-0.png'},
        ],
      },
    },
  ],
  'markers': [],
  'attribution': {'author': 'Independent fixture'},
};
Map<String, dynamic> _calibratedRasterMap(String sourceKey) {
  final raw = Map<String, dynamic>.from(calibrationFor(sourceKey));
  final frame = raw['artworkFrame'] as Map;
  raw['displayCrop'] = {
    'left': 0,
    'top': 0,
    'right': frame['width'],
    'bottom': frame['height'],
  };
  raw['floors'] = [
    for (final floor in raw['floors'] as List)
      <String, dynamic>{
        ...floor as Map<String, Object?>,
        'artwork': {'tiles': <Object>[]},
      },
  ];
  raw['markers'] = <Object>[];
  raw['attribution'] = {'author': 'Synthetic calibration-parity fixture'};
  return raw;
}

ByteData _json(Object value) =>
    ByteData.sublistView(Uint8List.fromList(utf8.encode(jsonEncode(value))));
ByteData _vector(String content) => ByteData.sublistView(
  compiler.encodeSvg(
    xml:
        '<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">$content</svg>',
    debugName: 'independent-native-fixture',
    enableClippingOptimizer: false,
    enableMaskingOptimizer: false,
    enableOverdrawOptimizer: false,
  ),
);
ByteData _png({int width = 256, int red = 255}) {
  final pixels = image.Image(width: width, height: 256, numChannels: 4);
  pixels.setPixelRgba(0, 0, red, 0, 0, 255);
  return ByteData.sublistView(image.encodePng(pixels));
}

Future<ByteData> _render(NativeMapScene scene, int extent) async {
  final recorder = ui.PictureRecorder();
  scene.paint(
    ui.Canvas(recorder),
    MapViewTransform(),
    ui.Size(extent.toDouble(), extent.toDouble()),
  );
  final picture = recorder.endRecording();
  try {
    final bitmap = await picture.toImage(extent, extent);
    try {
      return (await bitmap.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    } finally {
      bitmap.dispose();
    }
  } finally {
    picture.dispose();
  }
}

List<int> _rgba(ByteData pixels, int width, int x, int y) {
  final offset = (y * width + x) * 4;
  return [
    for (var channel = 0; channel < 4; channel++)
      pixels.getUint8(offset + channel),
  ];
}

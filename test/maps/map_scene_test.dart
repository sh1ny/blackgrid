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
  raw['attribution'] = {'author': 'Independent placement controls'};
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
ByteData _png({int width = 256}) {
  final pixels = image.Image(width: width, height: 256, numChannels: 4);
  pixels.setPixelRgba(0, 0, 255, 0, 0, 255);
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

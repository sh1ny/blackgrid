import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:blackgrid/application/map_controller.dart';
import 'package:blackgrid/domain/map_coordinates.dart';
import 'package:blackgrid/maps/native_map_scene.dart';
import 'package:blackgrid/maps/prepared_map_loader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart'
    as compiler;

import '../support/prepared_pack_manifest.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MapController controller;
  setUp(() async {
    controller = _controller();
    addTearDown(controller.dispose);
    controller.updateViewport(const Size(320, 320));
    await controller.initialize(selectedMapId: 'interchange');
    await _settled(controller);
  });

  List<String> raidIds() => [
    for (final marker in controller.raidMatchedMarkers) marker.marker.id,
  ];

  group('map-controls: This raid lists the matched extracts', () {
    test(
      'lists only highlighted markers that pass category, floor and map',
      () {
        controller.setRaidHighlights({
          'west',
          'east',
          'gate',
          'upper',
          'absent',
        });
        expect(raidIds(), ['west', 'east', 'gate']);
        expect(
          controller.raidMatchedMarkers.every(
            (marker) => marker.raidHighlighted,
          ),
          isTrue,
        );

        // Category: hiding one filter removes its markers only.
        controller.setCategoryVisibility({'SharedExtracts': false});
        expect(raidIds(), ['west', 'east']);
        controller.setCategoryVisibility({});
        expect(raidIds(), ['west', 'east', 'gate']);

        // Floor: the overlay's marker joins when its floor is shown.
        controller.toggleFloor('Upper');
        expect(raidIds(), contains('upper'));
      },
    );

    test('is independent of pan, zoom and the viewport edge', () {
      controller.setRaidHighlights({'west', 'east'});
      expect(
        controller.visibleMarkers(margin: 0).map((m) => m.marker.id),
        containsAll(['west', 'east']),
      );
      controller.panBy(-150, 0);
      final west = controller.raidMatchedMarkers.firstWhere(
        (marker) => marker.marker.id == 'west',
      );
      expect(west.viewportPoint.x, lessThan(0));
      expect(
        controller.visibleMarkers(margin: 0).map((m) => m.marker.id),
        isNot(contains('west')),
        reason: 'the fixture must put west off view',
      );
      expect(raidIds(), ['west', 'east']);

      controller.zoomAt(ViewportPoint(0, 0), 8);
      expect(raidIds(), ['west', 'east']);
      controller.updateViewport(const Size(40, 40));
      expect(raidIds(), ['west', 'east']);
    });

    test('is empty once the map changes and clears its evidence', () async {
      controller.setRaidHighlights({'west'});
      expect(raidIds(), ['west']);
      await controller.selectPersistedMap('icebreaker');
      expect(raidIds(), isEmpty);
    });
  });

  group('map-controls: Off-view rows bring the marker into view', () {
    test('an off-view marker is selected and centred at the same zoom', () {
      controller.setRaidHighlights({'west'});
      controller.panBy(-150, 0);
      final scale = controller.transform.scale;
      expect(controller.raidMatchedMarkers.single.viewportPoint.x, lessThan(0));

      controller.revealMarker('west');

      expect(controller.selectedMarkerProjection!.marker.id, 'west');
      expect(controller.transform.scale, scale);
      final point = controller.selectedMarkerProjection!.viewportPoint;
      expect(point.x, closeTo(160, 1e-9));
      expect(point.y, closeTo(160, 1e-9));
    });

    test('an in-view marker is selected without moving the view', () {
      controller.setRaidHighlights({'east'});
      final before = controller.transform;
      controller.revealMarker('east');
      expect(controller.selectedMarkerProjection!.marker.id, 'east');
      expect(controller.transform.scale, before.scale);
      expect(controller.transform.translationX, before.translationX);
      expect(controller.transform.translationY, before.translationY);
    });

    test('an id that is no longer eligible is ignored', () {
      controller.setRaidHighlights({'west', 'upper'});
      controller.panBy(-150, 0);
      controller.setSelectedMarker('east');
      final before = controller.transform;

      controller.revealMarker('upper'); // its floor is hidden
      controller.revealMarker('absent'); // not a marker at all
      controller.setCategoryVisibility({'PmcExtracts': false});
      controller.revealMarker('west'); // its category is now hidden

      expect(controller.selectedMarkerProjection, isNull);
      expect(controller.transform.translationX, before.translationX);
      expect(controller.transform.translationY, before.translationY);
    });

    test('selecting elsewhere never moves the view', () {
      controller.panBy(-150, 0);
      final before = controller.transform;
      controller.setSelectedMarker('west');
      expect(controller.selectedMarkerProjection!.marker.id, 'west');
      expect(controller.transform.translationX, before.translationX);
      expect(controller.transform.translationY, before.translationY);
    });
  });
}

MapController _controller() {
  final loader = PreparedMapPackLoader(
    loadBytes: preparedPackBytes(
      preparedPackManifest(maps: [_map('interchange'), _map('icebreaker')]),
      other: (path) async => _picture(),
    ),
  );
  return MapController(
    loader: loader,
    resources: NativeMapResourceOwner(loader),
  );
}

Map<String, dynamic> _marker(
  String id,
  String filterKey,
  double x,
  double z, {
  String? floorId,
  double? height,
}) => {
  'id': id,
  'category': 'extracts',
  'filterKey': filterKey,
  'name': id,
  'floorId': ?floorId,
  'position': {'x': x, 'z': z, 'height': height},
  'details': <String, dynamic>{},
  'outline': const <Object>[],
  'source': {'url': 'fixture'},
};

Map<String, dynamic> _map(String id) => {
  'id': id,
  'name': '$id fixture',
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
  'layerOrder': ['Base', 'Upper'],
  'floors': [
    for (final (floor, base, band) in [
      ('Base', true, null),
      ('Upper', false, [3, 5]),
    ])
      {
        'id': floor,
        'base': base,
        'manual': true,
        'exclusive': false,
        'attachedIds': <String>[],
        'heightBand': ?band,
        'artwork': {
          'components': [
            {
              'id': floor,
              'type': 'vector',
              'path': '$id-$floor.vec',
              'effects': <Object>[],
            },
          ],
        },
      },
  ],
  'markers': [
    _marker('west', 'PmcExtracts', 8, 24),
    _marker('east', 'PmcExtracts', 24, 24),
    _marker('gate', 'SharedExtracts', 16, 8),
    _marker('upper', 'PmcExtracts', 24, 8, floorId: 'Upper', height: 4),
  ],
  'labels': <Object>[],
  'attribution': {'author': 'Independent fixture'},
};

ByteData _picture() => ByteData.sublistView(
  compiler.encodeSvg(
    xml: '<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><rect width="32" height="32" fill="#336699"/></svg>',
    debugName: 'raid-list-fixture',
    enableClippingOptimizer: false,
    enableMaskingOptimizer: false,
    enableOverdrawOptimizer: false,
  ),
);

Future<void> _settled(MapController controller) async {
  if (!controller.loading) return;
  final completer = Completer<void>();
  void listener() {
    if (!controller.loading && !completer.isCompleted) completer.complete();
  }

  controller.addListener(listener);
  try {
    await completer.future.timeout(const Duration(seconds: 5));
  } finally {
    controller.removeListener(listener);
  }
}

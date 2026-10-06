import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart'
    as compiler;

import 'package:blackgrid/application/map_controller.dart';
import 'package:blackgrid/domain/map_coordinates.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:blackgrid/maps/native_map_scene.dart';
import 'package:blackgrid/maps/prepared_map_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('viewport framing: untouched maps refit after resize', () async {
    final controller = _controller();
    addTearDown(controller.dispose);
    controller.updateViewport(const Size(320, 320));
    await controller.initialize(selectedMapId: 'interchange');
    controller.updateViewport(const Size(640, 480));
    await _settled(controller);
    final topLeft = controller.transform.sceneToViewport(ScenePoint(0, 0));
    final bottomRight = controller.transform.sceneToViewport(
      ScenePoint(32, 32),
    );
    expect(topLeft.x, closeTo(104, 1e-9));
    expect(topLeft.y, closeTo(24, 1e-9));
    expect(bottomRight.x, closeTo(536, 1e-9));
    expect(bottomRight.y, closeTo(456, 1e-9));
    final marker = controller.visibleMarkers().single;
    expect(marker.viewportPoint.x, closeTo(212, 1e-9));
    expect(marker.viewportPoint.y, closeTo(132, 1e-9));
    expect(
      controller.hitTestMarker(ViewportPoint(212, 132))!.marker.id,
      'unknown',
    );
    expect(controller.hitTestMarker(ViewportPoint(92, 92)), isNull);
  });

  test(
    'viewport framing: untouched revisited maps fit the current viewport',
    () async {
      final controller = _controller();
      addTearDown(controller.dispose);
      controller.updateViewport(const Size(320, 320));
      await controller.initialize(selectedMapId: 'interchange');
      await controller.selectPersistedMap('icebreaker');
      controller.updateViewport(const Size(640, 480));
      await _settled(controller);
      await controller.selectPersistedMap('interchange');
      final center = controller.transform.sceneToViewport(ScenePoint(16, 16));
      final bottomRight = controller.transform.sceneToViewport(
        ScenePoint(32, 32),
      );
      expect(center.x, closeTo(320, 1e-9));
      expect(center.y, closeTo(240, 1e-9));
      expect(bottomRight.x, closeTo(536, 1e-9));
      expect(bottomRight.y, closeTo(456, 1e-9));
    },
  );

  test(
    'viewport framing: Fit map restores automatic fitting after a gesture',
    () async {
      final controller = _controller();
      addTearDown(controller.dispose);
      controller.updateViewport(const Size(320, 320));
      await controller.initialize(selectedMapId: 'interchange');
      controller.panBy(37, -12);
      controller.zoomAt(ViewportPoint(120, 100), 1.5);
      controller.fit();
      controller.updateViewport(const Size(640, 480));
      await _settled(controller);
      final center = controller.transform.sceneToViewport(ScenePoint(16, 16));
      final bottomRight = controller.transform.sceneToViewport(
        ScenePoint(32, 32),
      );
      expect(center.x, closeTo(320, 1e-9));
      expect(center.y, closeTo(240, 1e-9));
      expect(bottomRight.x, closeTo(536, 1e-9));
      expect(bottomRight.y, closeTo(456, 1e-9));
    },
  );

  for (final gesture in ['pan', 'zoom']) {
    test(
      'viewport framing: deliberate $gesture survives resize and revisit',
      () async {
        final controller = _controller();
        addTearDown(controller.dispose);
        controller.updateViewport(const Size(320, 320));
        await controller.initialize(selectedMapId: 'interchange');
        if (gesture == 'pan') {
          controller.panBy(37, -12);
        } else {
          controller.zoomAt(ViewportPoint(120, 100), 1.5);
        }
        final before = controller.transform;
        controller.updateViewport(const Size(640, 480));
        await _settled(controller);
        expect(controller.transform.scale, before.scale);
        expect(controller.transform.translationX, before.translationX);
        expect(controller.transform.translationY, before.translationY);
        await controller.selectPersistedMap('icebreaker');
        controller.updateViewport(const Size(800, 600));
        await _settled(controller);
        await controller.selectPersistedMap('interchange');
        expect(controller.transform.scale, before.scale);
        expect(controller.transform.translationX, before.translationX);
        expect(controller.transform.translationY, before.translationY);
      },
    );
  }

  test('late A cannot publish after authoritative B selection', () async {
    final entered = Completer<void>();
    final lateA = Completer<ByteData>();
    final controller = _controller(
      artwork: (path) async {
        if (path.endsWith('interchange-base.vec')) {
          if (!entered.isCompleted) entered.complete();
          return lateA.future;
        }
        return _picture();
      },
    );
    addTearDown(controller.dispose);
    controller.updateViewport(const Size(320, 320));
    final initial = controller.initialize(selectedMapId: 'interchange');
    await entered.future;
    await controller.selectPersistedMap('icebreaker');
    expect(controller.selectedMapId, 'icebreaker');
    expect(controller.scene!.map.id, 'icebreaker');
    lateA.complete(_picture());
    await initial;
    expect(controller.scene!.map.id, 'icebreaker');
    expect(controller.resources.retainedResourceCount, 1);
    expect(controller.loading, isFalse);
  });

  test(
    'hidden floor art and marker hits disappear before late decode returns',
    () async {
      final entered = Completer<void>();
      final lateUpper = Completer<ByteData>();
      final controller = _controller(
        artwork: (path) async {
          if (path.endsWith('interchange-upper.vec')) {
            if (!entered.isCompleted) entered.complete();
            return lateUpper.future;
          }
          return _picture();
        },
      );
      addTearDown(controller.dispose);
      controller.updateViewport(const Size(320, 320));
      await controller.initialize(selectedMapId: 'interchange');
      expect(controller.visibleMarkers().map((m) => m.marker.id), ['unknown']);
      controller.toggleFloor('Upper');
      await entered.future;
      final upperPoint = controller
          .visibleMarkers()
          .singleWhere((m) => m.marker.id == 'upper')
          .viewportPoint;
      expect(controller.hitTestMarker(upperPoint)!.marker.id, 'upper');
      controller.toggleFloor('Upper');
      expect(
        controller.visibleMarkers().any((m) => m.marker.id == 'upper'),
        isFalse,
      );
      expect(controller.hitTestMarker(upperPoint), isNull);
      await _settled(controller);
      lateUpper.complete(_picture());
      await Future<void>.delayed(Duration.zero);
      expect(controller.floorSelection!.selectedOverlayIds, isEmpty);
      expect(controller.scene!.selection.selectedOverlayIds, isEmpty);
    },
  );

  test(
    'dispose fences late completion and emits no shutdown notification',
    () async {
      final entered = Completer<void>();
      final gate = Completer<ByteData>();
      final controller = _controller(
        artwork: (_) {
          if (!entered.isCompleted) entered.complete();
          return gate.future;
        },
      );
      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.updateViewport(const Size(320, 320));
      final initial = controller.initialize(selectedMapId: 'interchange');
      await entered.future;
      final beforeDispose = notifications;
      controller.dispose();
      gate.complete(_picture());
      await initial;
      expect(notifications, beforeDispose);
      expect(controller.scene, isNull);
      expect(controller.resources.accountedBytes, 0);
      expect(controller.resources.retainedResourceCount, 0);
    },
  );

  test(
    'failed new map cannot display previous-good art under its identity',
    () async {
      final controller = _controller(
        artwork: (path) async => path.contains('icebreaker')
            ? ByteData.sublistView(Uint8List.fromList([1, 2, 3]))
            : _picture(),
      );
      addTearDown(controller.dispose);
      controller.updateViewport(const Size(320, 320));
      await controller.initialize(selectedMapId: 'interchange');
      final previous = controller.scene!;
      final switching = controller.selectPersistedMap('icebreaker');
      expect(controller.scene, isNull);
      expect(previous.isDisposed, isTrue);
      await switching;
      expect(controller.selectedMapId, 'icebreaker');
      expect(controller.preparedMap!.id, 'icebreaker');
      expect(controller.scene, isNull);
      expect(controller.error, isNotNull);
    },
  );

  test(
    'unbundled selection is honest and per-map transforms survive revisits',
    () async {
      final controller = _controller();
      addTearDown(controller.dispose);
      controller.updateViewport(const Size(320, 320));
      await controller.initialize(selectedMapId: 'interchange');
      controller.panBy(37, -12);
      controller.zoomAt(ViewportPoint(120, 100), 1.5);
      final view = controller.transform;
      await controller.selectPersistedMap('icebreaker');
      await controller.selectPersistedMap('interchange');
      expect(controller.transform.scale, view.scale);
      expect(controller.transform.translationX, view.translationX);
      expect(controller.transform.translationY, view.translationY);
      await controller.selectPersistedMap('woods');
      expect(controller.selectedMapId, 'woods');
      expect(controller.unavailable, isTrue);
      expect(controller.preparedMap, isNull);
      expect(controller.scene, isNull);
      expect(controller.visibleMarkers(), isEmpty);
    },
  );

  test(
    'category/floor query and hit logic share cached viewport projections',
    () async {
      final controller = _controller();
      addTearDown(controller.dispose);
      controller.updateViewport(const Size(320, 320));
      await controller.initialize(selectedMapId: 'interchange');
      final first = controller.visibleMarkers();
      expect(identical(first, controller.visibleMarkers()), isTrue);
      expect(first.single.marker.position.height, isNull);
      expect(
        controller.hitTestMarker(first.single.viewportPoint)!.marker.id,
        'unknown',
      );
      controller.setCategoryVisibility({'Switches': false});
      expect(controller.visibleMarkers(), isEmpty);
      expect(controller.hitTestMarker(first.single.viewportPoint), isNull);
      controller.setCategoryVisibility({});
      final anchor = controller.visibleMarkers().single.viewportPoint;
      controller.zoomAt(anchor, 2);
      final zoomed = controller.visibleMarkers().single.viewportPoint;
      expect(zoomed.x, closeTo(anchor.x, 1e-9));
      expect(zoomed.y, closeTo(anchor.y, 1e-9));
      expect(
        controller
            .hitTestMarker(ViewportPoint(anchor.x + 17, anchor.y))!
            .marker
            .id,
        'unknown',
      );
      expect(
        controller.hitTestMarker(ViewportPoint(anchor.x + 19, anchor.y)),
        isNull,
      );
      expect(controller.applyOfflineHeight(4), isFalse);
      expect(controller.floorSelection!.selectedOverlayIds, isEmpty);
      await controller.selectPersistedMap('icebreaker');
      expect(controller.applyOfflineHeight(null), isFalse);
      expect(controller.applyOfflineHeight(3), isTrue);
      expect(controller.floorSelection!.selectedOverlayIds, {'Upper'});
      expect(controller.applyOfflineHeight(5), isTrue);
      expect(controller.floorSelection!.selectedOverlayIds, isEmpty);
    },
  );

  test(
    'finite pins with overflowing projections are skipped unchanged',
    () async {
      final controller = _controller();
      addTearDown(controller.dispose);
      controller.updateViewport(const Size(320, 320));
      await controller.initialize(selectedMapId: 'interchange');
      // 1e308 overflows the legacy inverse; 1e306 reaches viewport scaling.
      for (final magnitude in [1e308, 1e306]) {
        for (final coordinate in [magnitude, -magnitude]) {
          for (final xAxis in [true, false]) {
            final pin = CustomPin(
              id: 'overflow',
              mapId: 'interchange',
              x: xAxis ? coordinate : .5,
              y: xAxis ? .5 : coordinate,
              frame: 'legacy-normalized',
              frameRevision: 0,
              label: 'Still editable',
              updatedAt: DateTime.utc(2026),
            );
            pin.validate();
            expect(controller.projectPin(pin), isNull);
            expect(pin.x, xAxis ? coordinate : .5);
            expect(pin.y, xAxis ? .5 : coordinate);
            expect(pin.frame, 'legacy-normalized');
            expect(pin.frameRevision, 0);
          }
        }
      }
    },
  );

  test(
    'legacy off-map pins round trip without frame conversion or clamping',
    () async {
      final controller = _controller();
      addTearDown(controller.dispose);
      controller.updateViewport(const Size(320, 320));
      await controller.initialize(selectedMapId: 'interchange');
      final pin = CustomPin(
        id: 'off-map',
        mapId: 'interchange',
        x: -.2,
        y: 1.5,
        frame: 'legacy-normalized',
        frameRevision: 0,
        label: 'Off map',
        updatedAt: DateTime.utc(2026),
      );
      final projected = controller.projectPin(pin)!;
      expect(projected.x, closeTo(-30.4, 1e-9));
      expect(projected.y, closeTo(-112, 1e-9));
      final stored = controller.pinAt(projected)!;
      expect(stored.point.x, closeTo(-.2, 1e-9));
      expect(stored.point.y, closeTo(1.5, 1e-9));
      expect(stored.frame, MapCoordinateFrame.legacyNormalized);
      controller.panBy(10, 20);
      final moved = controller.projectPin(pin)!;
      expect(moved.x, closeTo(projected.x + 10, 1e-9));
      expect(moved.y, closeTo(projected.y + 20, 1e-9));
      expect(pin.x, -.2);
      expect(pin.y, 1.5);
      expect(pin.frameRevision, 0);
    },
  );
}

MapController _controller({Future<ByteData> Function(String)? artwork}) {
  final loader = PreparedMapPackLoader(
    loadBytes: (path) async {
      if (path.endsWith('active.json')) {
        return _json({
          'schemaVersion': 1,
          'version': 'fixture',
          'manifest': 'versions/fixture/manifest.json',
        });
      }
      if (path.endsWith('manifest.json')) {
        return _json({
          'schemaVersion': 1,
          'vectorsCompiled': true,
          'runtimeVectorVersion': '1.2.3',
          'maps': [_map('interchange'), _map('icebreaker', exclusive: true)],
        });
      }
      return artwork == null ? _picture() : artwork(path);
    },
  );
  return MapController(
    loader: loader,
    resources: NativeMapResourceOwner(loader),
  );
}

Map<String, dynamic> _map(String id, {bool exclusive = false}) => {
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
    {
      'id': 'Base',
      'base': true,
      'manual': true,
      'exclusive': exclusive,
      'attachedIds': [],
      'artwork': {
        'components': [
          {
            'id': 'Base',
            'type': 'vector',
            'path': '$id-base.vec',
            'effects': [],
          },
        ],
      },
    },
    {
      'id': 'Upper',
      'base': false,
      'manual': true,
      'exclusive': exclusive,
      'attachedIds': [],
      'heightBand': [3, 5],
      'artwork': {
        'components': [
          {
            'id': 'Upper',
            'type': 'vector',
            'path': '$id-upper.vec',
            'effects': [],
          },
        ],
      },
    },
  ],
  'markers': [
    {
      'id': 'unknown',
      'category': 'switches',
      'name': 'Unknown height',
      'position': {'x': 8, 'z': 24, 'height': null},
      'details': {},
      'source': {'url': 'fixture'},
    },
    {
      'id': 'upper',
      'category': 'switches',
      'name': 'Explicit upper',
      'floorId': 'Upper',
      'position': {'x': 24, 'z': 8, 'height': 0},
      'details': {},
      'source': {'url': 'fixture'},
    },
  ],
  'attribution': {'author': 'Independent fixture'},
};
ByteData _json(Object value) =>
    ByteData.sublistView(Uint8List.fromList(utf8.encode(jsonEncode(value))));
ByteData _picture() => ByteData.sublistView(
  compiler.encodeSvg(
    xml: '<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><rect width="32" height="32" fill="#336699"/></svg>',
    debugName: 'independent-controller-fixture',
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

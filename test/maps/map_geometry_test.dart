import 'package:blackgrid/domain/map_coordinates.dart';
import 'package:blackgrid/domain/map_geometry.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:test/test.dart';

void expectPoint(double x, double y, double expectedX, double expectedY) {
  expect(x, closeTo(expectedX, 1e-9));
  expect(y, closeTo(expectedY, 1e-9));
}

void main() {
  final bounds = GameBounds(minX: -2, maxX: 6, minZ: -4, maxZ: 8);

  group('affine game projection', () {
    test('rotation precedes anisotropic scaling in the full native frame', () {
      final geometry = MapGeometry.affine(
        bounds: bounds,
        a: 2,
        b: 10,
        c: 3,
        d: 20,
        rotationDegrees: 90,
        scale: 4,
        nativeArtwork: MapExtent(100, 200),
      );
      // (x,z)=(2,3) rotates to (-3,2), then pixels are (16,56).
      final artwork = geometry.gameToArtwork(GamePoint(2, 3, height: 0));
      expectPoint(artwork.x, artwork.y, .16, .28);
      final restored = geometry.artworkToGame(artwork, height: 0);
      expectPoint(restored.x, restored.z, 2, 3);
      expect(restored.height, 0);
      for (final point in [
        GamePoint(-2, -4),
        GamePoint(6, -4),
        GamePoint(-2, 8),
        GamePoint(6, 8),
        GamePoint(1, 2),
        GamePoint(-20, 30),
      ]) {
        final back = geometry.artworkToGame(geometry.gameToArtwork(point));
        expectPoint(back.x, back.z, point.x, point.z);
        expect(back.height, isNull);
      }
    });

    test(
      'without native dimensions all four rotated corners define extrema',
      () {
        final geometry = MapGeometry.affine(
          bounds: GameBounds(minX: 0, maxX: 10, minZ: 0, maxZ: 20),
          a: 2,
          b: 17,
          c: 3,
          d: -4,
          rotationDegrees: 45,
          scale: 8,
        );
        // rotX spans [-20/sqrt(2),10/sqrt(2)], rotZ [0,30/sqrt(2)].
        final expectations = [
          (0.0, 0.0, 2 / 3, 1.0),
          (10.0, 0.0, 1.0, 2 / 3),
          (0.0, 20.0, 0.0, 1 / 3),
          (10.0, 20.0, 1 / 3, 0.0),
          (5.0, 10.0, .5, .5),
          (-10.0, 40.0, -1.0, 0.0),
        ];
        for (final (x, z, u, v) in expectations) {
          final art = geometry.gameToArtwork(GamePoint(x, z));
          expectPoint(art.x, art.y, u, v);
          final back = geometry.artworkToGame(art);
          expectPoint(back.x, back.z, x, z);
        }
      },
    );

    test(
      'bounds-only orientation is legacy orientation, not another rotation',
      () {
        final cases = [
          (LegacyMapOrientation.degrees0, .25, .5),
          (LegacyMapOrientation.degrees90, .5, .75),
          (LegacyMapOrientation.degrees180, .75, .5),
          (LegacyMapOrientation.degrees270, .5, .25),
        ];
        for (final (orientation, u, v) in cases) {
          final geometry = MapGeometry.boundsOnly(
            bounds: GameBounds(minX: 0, maxX: 8, minZ: 0, maxZ: 4),
            orientation: orientation,
          );
          final art = geometry.gameToArtwork(GamePoint(2, 2));
          expectPoint(art.x, art.y, u, v);
          for (final point in [
            GamePoint(0, 0),
            GamePoint(8, 0),
            GamePoint(0, 4),
            GamePoint(8, 4),
            GamePoint(2, 3),
            GamePoint(-2, 6),
          ]) {
            final back = geometry.artworkToGame(geometry.gameToArtwork(point));
            expectPoint(back.x, back.z, point.x, point.z);
          }
        }
      },
    );
  });

  test('crop translates once and tile stride is independent of native pixels and seam', () {
    final display = MapDisplayFrame(
      originalArtwork: MapExtent(2048, 1024),
      crop: ArtworkCrop(left: 256, top: 128, width: 1536, height: 768),
      sceneUnitsPerArtworkX: .5,
      sceneUnitsPerArtworkY: .25,
    );
    final point = ArtworkPoint(.25, .5);
    final pixels = display.artworkToPixels(point);
    expectPoint(pixels.x, pixels.y, 512, 512);
    final normalized = display.pixelsToArtwork(pixels);
    expectPoint(normalized.x, normalized.y, .25, .5);
    final scene = display.artworkToScene(point);
    expectPoint(scene.x, scene.y, 128, 96);
    expectPoint(
      display.sceneExtent.width,
      display.sceneExtent.height,
      768,
      192,
    );
    final art = display.sceneToArtwork(scene);
    expectPoint(art.x, art.y, .25, .5);
    final off = display.artworkToScene(ArtworkPoint(-.2, 1.5));
    expectPoint(off.x, off.y, -332.8, 352);
    final back = display.sceneToArtwork(off);
    expectPoint(back.x, back.y, -.2, 1.5);
    final tiles = MapTileLayout(
      nativeTilePixels: MapExtent(1024, 1024),
      displayStride: MapExtent(512, 256),
      seamExtent: 1,
    );
    final native = tiles.nativeOrigin(2, 3);
    final tile = tiles.sceneOrigin(2, 3);
    expectPoint(native.x, native.y, 2048, 3072);
    expectPoint(tile.x, tile.y, 1024, 768);
    expectPoint(
      tiles.sceneTileExtent.width,
      tiles.sceneTileExtent.height,
      513,
      257,
    );
  });

  test('view pan inverse anchored zoom and fit use scene coordinates', () {
    final view = MapViewTransform(scale: 2, translationX: 10, translationY: -5);
    final projected = view.sceneToViewport(ScenePoint(3, 7));
    expectPoint(projected.x, projected.y, 16, 9);
    final scene = view.viewportToScene(ViewportPoint(16, 9));
    expectPoint(scene.x, scene.y, 3, 7);
    final zoom = view.zoomAt(ViewportPoint(16, 9), 3);
    expect(zoom.scale, 6);
    expectPoint(zoom.translationX, zoom.translationY, -2, -33);
    final anchored = zoom.sceneToViewport(ScenePoint(3, 7));
    expectPoint(anchored.x, anchored.y, 16, 9);
    final pan = zoom.panBy(8, -4);
    expectPoint(pan.translationX, pan.translationY, 6, -37);
    final fit = MapViewTransform.fit(
      scene: MapExtent(100, 50),
      viewport: MapExtent(300, 200),
      padding: 10,
    );
    expect(fit.scale, closeTo(2.8, 1e-12));
    expectPoint(fit.translationX, fit.translationY, 10, 30);
    final off = fit.viewportToScene(fit.sceneToViewport(ScenePoint(-20, 90)));
    expectPoint(off.x, off.y, -20, 90);
  });

  test('pin adapter preserves immutable frames and does not repeat Labs import conversion', () {
    final native = MapGeometry.affine(
      bounds: bounds,
      a: 1,
      b: 0,
      c: 1,
      d: 100,
      nativeArtwork: MapExtent(100, 100),
    );
    final legacy = MapGeometry.boundsOnly(bounds: bounds);
    for (final (mapId, frame, revision, x, y) in [
      ('streetsoftarkov', 'legacy-normalized', 0, -.2, 1.5),
      ('thelab', 'labs-native-normalized', 1, -.2, 1.5),
      // Independent expected existing import rev0(-2,3) -> rev1.
      ('thelab', 'labs-native-normalized', 1, -319.675 / 175, 385.75 / 175),
    ]) {
      final pin = CustomPin(
        id: 'fixture',
        mapId: mapId,
        x: x,
        y: y,
        frame: frame,
        frameRevision: revision,
        label: 'Fixture',
        updatedAt: DateTime.utc(2026),
      );
      final before = pin.toJson();
      final coordinates = MapPinCoordinates.fromPin(pin);
      final projector = MapPinProjector(
        mapId: mapId,
        artworkGeometry: native,
        legacyGeometry: legacy,
      );
      final art = projector.pinToArtwork(coordinates);
      if (mapId == 'thelab') {
        expectPoint(art.x, art.y, x, y);
      } else {
        // legacy -> game (-3.6,14) -> native art (-.036,.86).
        expectPoint(art.x, art.y, -.036, .86);
      }
      final display = MapDisplayFrame(
        originalArtwork: MapExtent(100, 100),
        crop: ArtworkCrop(left: 10, top: 20, width: 70, height: 60),
      );
      final view = MapViewTransform.fit(
        scene: display.sceneExtent,
        viewport: MapExtent(400, 300),
      ).zoomAt(ViewportPoint(120, 90), 2).panBy(-13, 27);
      final viewed = view.sceneToViewport(display.artworkToScene(art));
      final restoredArtwork = display.sceneToArtwork(
        view.viewportToScene(viewed),
      );
      final restored = projector.artworkToPin(restoredArtwork);
      expectPoint(restored.point.x, restored.point.y, x, y);
      expect(restored.frame.wireName, frame);
      expect(restored.frame.revision, revision);
      expect(pin.toJson(), before);
    }
    final labsRev0 = CustomPin(
      id: 'old',
      mapId: 'thelab',
      x: 0,
      y: 0,
      frame: 'legacy-normalized',
      frameRevision: 0,
      label: '',
      updatedAt: DateTime.utc(2026),
    );
    expect(() => MapPinCoordinates.fromPin(labsRev0), throwsFormatException);
    final noLegacy = MapPinProjector(
      mapId: 'streetsoftarkov',
      artworkGeometry: native,
    );
    expect(
      () => noLegacy.pinToArtwork(
        MapPinCoordinates(
          mapId: 'streetsoftarkov',
          point: ArtworkPoint(0, 0),
          frame: MapCoordinateFrame.legacyNormalized,
        ),
      ),
      throwsArgumentError,
    );
  });

  test(
    'finite and nonsingular contracts reject invalid input, not off-map input',
    () {
      for (final value in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(() => GamePoint(value, 0), throwsArgumentError);
        expect(() => GamePoint(0, 0, height: value), throwsArgumentError);
        expect(() => ArtworkPoint(0, value), throwsArgumentError);
        expect(() => ArtworkPixelPoint(value, 0), throwsArgumentError);
        expect(() => ScenePoint(value, 0), throwsArgumentError);
        expect(() => ViewportPoint(value, 0), throwsArgumentError);
        expect(() => MapExtent(value, 2), throwsArgumentError);
        expect(() => MapViewTransform(scale: value), throwsArgumentError);
        expect(
          () => MapGeometry.affine(bounds: bounds, a: 1, b: value, c: 1, d: 0),
          throwsArgumentError,
        );
        expect(
          () => MapGeometry.affine(
            bounds: bounds,
            a: 1,
            b: 0,
            c: 1,
            d: 0,
            rotationDegrees: value,
          ),
          throwsArgumentError,
        );
      }
      expect(
        () => GameBounds(minX: 0, maxX: 0, minZ: 0, maxZ: 1),
        throwsArgumentError,
      );
      expect(
        () => MapGeometry.affine(bounds: bounds, a: 0, b: 0, c: 1, d: 0),
        throwsArgumentError,
      );
      expect(
        () => MapGeometry.affine(bounds: bounds, a: 1, b: 0, c: 0, d: 0),
        throwsArgumentError,
      );
      expect(
        () => MapGeometry.affine(
          bounds: bounds,
          a: 1e-300,
          b: 0,
          c: 1e-300,
          d: 0,
          nativeArtwork: MapExtent(100, 200),
        ),
        throwsArgumentError,
      );
      expect(() => MapViewTransform(scale: 0), throwsArgumentError);
      expect(() => MapViewTransform(scale: -1), throwsArgumentError);
      expect(
        () => MapViewTransform().zoomAt(ViewportPoint(0, 0), 0),
        throwsArgumentError,
      );
      expect(
        () => MapViewTransform.fit(
          scene: MapExtent(1, 1),
          viewport: MapExtent(1, 1),
          padding: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => MapDisplayFrame(
          originalArtwork: MapExtent(10, 10),
          crop: ArtworkCrop(left: 5, top: 0, width: 10, height: 10),
        ),
        throwsArgumentError,
      );
      expect(
        () => MapTileLayout(
          nativeTilePixels: MapExtent(1, 1),
          displayStride: MapExtent(1, 1),
          seamExtent: -1,
        ),
        throwsArgumentError,
      );
      expect(GamePoint(0, 0).height, isNull);
      expect(GamePoint(0, 0, height: 0).height, 0);
    },
  );
}

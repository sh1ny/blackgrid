import 'dart:math' as math;

import 'map_coordinates.dart';

enum LegacyMapOrientation { degrees0, degrees90, degrees180, degrees270 }

// The six coefficients map game X/Z directly into normalized original artwork.
// Inverses are computed once, not by composing rotations at interaction time.
class MapGeometry {
  MapGeometry._(this._xx, this._xz, this._tx, this._yx, this._yz, this._ty) {
    for (final value in [_xx, _xz, _tx, _yx, _yz, _ty]) {
      requireFinite(value, 'projection coefficient');
    }
    final determinant = _xx * _yz - _xz * _yx;
    if (!determinant.isFinite || determinant == 0) {
      throw ArgumentError('Projection must be finite and nonsingular.');
    }
    _inverseXX = _yz / determinant;
    _inverseXZ = -_xz / determinant;
    _inverseYX = -_yx / determinant;
    _inverseYZ = _xx / determinant;
    for (final value in [_inverseXX, _inverseXZ, _inverseYX, _inverseYZ]) {
      requireFinite(value, 'inverse coefficient');
    }
  }

  factory MapGeometry.affine({
    required GameBounds bounds,
    required double a,
    required double b,
    required double c,
    required double d,
    double rotationDegrees = 0,
    double scale = 1,
    MapExtent? nativeArtwork,
  }) {
    for (final value in [a, b, c, d, rotationDegrees, scale]) {
      requireFinite(value, 'affine parameter');
    }
    if (a == 0 || c == 0 || scale <= 0) {
      throw ArgumentError(
        'Affine axes must be nonsingular and scale positive.',
      );
    }
    final radians = (rotationDegrees % 360) * math.pi / 180;
    final cos = math.cos(radians);
    final sin = math.sin(radians);
    // rotX = x*cos-z*sin; rotZ = x*sin+z*cos.
    final xx = scale * a * cos;
    final xz = -scale * a * sin;
    final tx = scale * b;
    final yx = -scale * c * sin;
    final yz = -scale * c * cos;
    final ty = scale * d;
    var left = 0.0;
    var top = 0.0;
    double width;
    double height;
    if (nativeArtwork != null) {
      width = nativeArtwork.width;
      height = nativeArtwork.height;
    } else {
      var minPx = double.infinity;
      var maxPx = double.negativeInfinity;
      var minPy = double.infinity;
      var maxPy = double.negativeInfinity;
      for (final x in [bounds.minX, bounds.maxX]) {
        for (final z in [bounds.minZ, bounds.maxZ]) {
          final px = xx * x + xz * z + tx;
          final py = yx * x + yz * z + ty;
          requireFinite(px, 'projected bound x');
          requireFinite(py, 'projected bound y');
          minPx = math.min(minPx, px);
          maxPx = math.max(maxPx, px);
          minPy = math.min(minPy, py);
          maxPy = math.max(maxPy, py);
        }
      }
      left = minPx;
      top = minPy;
      width = maxPx - minPx;
      height = maxPy - minPy;
      requirePositiveFinite(width, 'projected width');
      requirePositiveFinite(height, 'projected height');
    }
    return MapGeometry._(
      xx / width,
      xz / width,
      (tx - left) / width,
      yx / height,
      yz / height,
      (ty - top) / height,
    );
  }

  // Historical bounds-only orientation is intentionally NOT affine rotation.
  factory MapGeometry.boundsOnly({
    required GameBounds bounds,
    LegacyMapOrientation orientation = LegacyMapOrientation.degrees0,
  }) {
    final xScale = 1 / (bounds.maxX - bounds.minX);
    final zScale = 1 / (bounds.maxZ - bounds.minZ);
    final xOffset = -bounds.minX * xScale;
    final zOffset = -bounds.minZ * zScale;
    return switch (orientation) {
      LegacyMapOrientation.degrees0 => MapGeometry._(
        xScale,
        0,
        xOffset,
        0,
        zScale,
        zOffset,
      ),
      LegacyMapOrientation.degrees90 => MapGeometry._(
        0,
        -zScale,
        1 - zOffset,
        -xScale,
        0,
        1 - xOffset,
      ),
      LegacyMapOrientation.degrees180 => MapGeometry._(
        -xScale,
        0,
        1 - xOffset,
        0,
        zScale,
        zOffset,
      ),
      LegacyMapOrientation.degrees270 => MapGeometry._(
        0,
        -zScale,
        1 - zOffset,
        xScale,
        0,
        xOffset,
      ),
    };
  }

  final double _xx;
  final double _xz;
  final double _tx;
  final double _yx;
  final double _yz;
  final double _ty;
  late final double _inverseXX;
  late final double _inverseXZ;
  late final double _inverseYX;
  late final double _inverseYZ;

  ArtworkPoint gameToArtwork(GamePoint point) => ArtworkPoint(
    _xx * point.x + _xz * point.z + _tx,
    _yx * point.x + _yz * point.z + _ty,
  );

  GamePoint artworkToGame(ArtworkPoint point, {double? height}) {
    final x = point.x - _tx;
    final y = point.y - _ty;
    return GamePoint(
      _inverseXX * x + _inverseXZ * y,
      _inverseYX * x + _inverseYZ * y,
      height: height,
    );
  }
}

class ArtworkCrop {
  ArtworkCrop({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  }) {
    requireFinite(left, 'left');
    requireFinite(top, 'top');
    requirePositiveFinite(width, 'width');
    requirePositiveFinite(height, 'height');
    if (left < 0 || top < 0) {
      throw ArgumentError('Crop origin must be nonnegative.');
    }
  }
  final double left;
  final double top;
  final double width;
  final double height;
}

class MapDisplayFrame {
  MapDisplayFrame({
    required this.originalArtwork,
    ArtworkCrop? crop,
    this.sceneUnitsPerArtworkX = 1,
    this.sceneUnitsPerArtworkY = 1,
  }) : crop =
           crop ??
           ArtworkCrop(
             left: 0,
             top: 0,
             width: originalArtwork.width,
             height: originalArtwork.height,
           ) {
    requirePositiveFinite(sceneUnitsPerArtworkX, 'sceneUnitsPerArtworkX');
    requirePositiveFinite(sceneUnitsPerArtworkY, 'sceneUnitsPerArtworkY');
    if (this.crop.left + this.crop.width > originalArtwork.width ||
        this.crop.top + this.crop.height > originalArtwork.height) {
      throw ArgumentError('Display crop must lie inside the original artwork.');
    }
    sceneExtent = MapExtent(
      this.crop.width * sceneUnitsPerArtworkX,
      this.crop.height * sceneUnitsPerArtworkY,
    );
  }
  final MapExtent originalArtwork;
  final ArtworkCrop crop;
  final double sceneUnitsPerArtworkX;
  final double sceneUnitsPerArtworkY;
  late final MapExtent sceneExtent;

  ArtworkPixelPoint artworkToPixels(ArtworkPoint point) => ArtworkPixelPoint(
    point.x * originalArtwork.width,
    point.y * originalArtwork.height,
  );

  ArtworkPoint pixelsToArtwork(ArtworkPixelPoint point) => ArtworkPoint(
    point.x / originalArtwork.width,
    point.y / originalArtwork.height,
  );

  ScenePoint artworkToScene(ArtworkPoint point) => ScenePoint(
    (point.x * originalArtwork.width - crop.left) * sceneUnitsPerArtworkX,
    (point.y * originalArtwork.height - crop.top) * sceneUnitsPerArtworkY,
  );

  ArtworkPoint sceneToArtwork(ScenePoint point) => ArtworkPoint(
    (point.x / sceneUnitsPerArtworkX + crop.left) / originalArtwork.width,
    (point.y / sceneUnitsPerArtworkY + crop.top) / originalArtwork.height,
  );
}

class MapTileLayout {
  MapTileLayout({
    required this.nativeTilePixels,
    required this.displayStride,
    this.seamExtent = 0,
  }) {
    requireFinite(seamExtent, 'seamExtent');
    if (seamExtent < 0) throw ArgumentError('Seam extent must be nonnegative.');
    sceneTileExtent = MapExtent(
      displayStride.width + seamExtent,
      displayStride.height + seamExtent,
    );
  }
  final MapExtent nativeTilePixels;
  final MapExtent displayStride;
  final double seamExtent;
  late final MapExtent sceneTileExtent;

  ArtworkPixelPoint nativeOrigin(int column, int row) => ArtworkPixelPoint(
    column * nativeTilePixels.width,
    row * nativeTilePixels.height,
  );
  ScenePoint sceneOrigin(int column, int row) =>
      ScenePoint(column * displayStride.width, row * displayStride.height);
}

class MapViewTransform {
  MapViewTransform({
    this.scale = 1,
    this.translationX = 0,
    this.translationY = 0,
  }) {
    requireFinite(scale, 'scale');
    requireFinite(translationX, 'translationX');
    requireFinite(translationY, 'translationY');
    if (scale <= 0 || !(1 / scale).isFinite) {
      throw ArgumentError('View scale must have a finite positive inverse.');
    }
    _inverseScale = 1 / scale;
  }
  final double scale;
  final double translationX;
  final double translationY;
  late final double _inverseScale;

  factory MapViewTransform.fit({
    required MapExtent scene,
    required MapExtent viewport,
    double padding = 0,
  }) {
    requireFinite(padding, 'padding');
    if (padding < 0 ||
        viewport.width <= 2 * padding ||
        viewport.height <= 2 * padding) {
      throw ArgumentError('Fit padding must leave a positive viewport.');
    }
    final scale = math.min(
      (viewport.width - 2 * padding) / scene.width,
      (viewport.height - 2 * padding) / scene.height,
    );
    return MapViewTransform(
      scale: scale,
      translationX: (viewport.width - scene.width * scale) / 2,
      translationY: (viewport.height - scene.height * scale) / 2,
    );
  }

  ViewportPoint sceneToViewport(ScenePoint point) => ViewportPoint(
    point.x * scale + translationX,
    point.y * scale + translationY,
  );
  ScenePoint viewportToScene(ViewportPoint point) => ScenePoint(
    (point.x - translationX) * _inverseScale,
    (point.y - translationY) * _inverseScale,
  );
  MapViewTransform panBy(double dx, double dy) {
    requireFinite(dx, 'dx');
    requireFinite(dy, 'dy');
    return MapViewTransform(
      scale: scale,
      translationX: translationX + dx,
      translationY: translationY + dy,
    );
  }

  MapViewTransform zoomAt(ViewportPoint cursor, double factor) {
    requireFinite(factor, 'factor');
    if (factor <= 0) throw ArgumentError('Zoom factor must be positive.');
    return MapViewTransform(
      scale: scale * factor,
      translationX: cursor.x + (translationX - cursor.x) * factor,
      translationY: cursor.y + (translationY - cursor.y) * factor,
    );
  }
}

// Legacy coordinates are interpreted through their own geometry, never simply
// relabelled as a new artwork frame. Labs rev1 is already full-native normalized.
class MapPinProjector {
  MapPinProjector({
    required this.mapId,
    required this.artworkGeometry,
    this.legacyGeometry,
  });
  final String mapId;
  final MapGeometry artworkGeometry;
  final MapGeometry? legacyGeometry;

  ArtworkPoint pinToArtwork(MapPinCoordinates pin) {
    if (pin.mapId != mapId) throw ArgumentError('Pin belongs to another map.');
    if (pin.frame == MapCoordinateFrame.labsNativeNormalized) return pin.point;
    final legacy = legacyGeometry;
    if (legacy == null) {
      throw ArgumentError('Legacy frame geometry is required.');
    }
    return artworkGeometry.gameToArtwork(legacy.artworkToGame(pin.point));
  }

  MapPinCoordinates artworkToPin(ArtworkPoint point) {
    if (mapId == 'thelab') {
      return MapPinCoordinates(
        mapId: mapId,
        point: point,
        frame: MapCoordinateFrame.labsNativeNormalized,
      );
    }
    final legacy = legacyGeometry;
    if (legacy == null) {
      throw ArgumentError('Legacy frame geometry is required.');
    }
    return MapPinCoordinates(
      mapId: mapId,
      point: legacy.gameToArtwork(artworkGeometry.artworkToGame(point)),
      frame: MapCoordinateFrame.legacyNormalized,
    );
  }
}

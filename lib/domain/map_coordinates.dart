import 'settings.dart';

void requireFinite(double value, String name) {
  if (!value.isFinite) {
    throw ArgumentError.value(value, name, 'Must be finite.');
  }
}

void requirePositiveFinite(double value, String name) {
  requireFinite(value, name);
  if (value <= 0) throw ArgumentError.value(value, name, 'Must be positive.');
}

class GamePoint {
  GamePoint(this.x, this.z, {this.height}) {
    requireFinite(x, 'x');
    requireFinite(z, 'z');
    if (height != null) requireFinite(height!, 'height');
  }
  final double x;
  final double z;
  final double? height;
}

// Artwork normalization always refers to the original uncropped artwork.
class ArtworkPoint {
  ArtworkPoint(this.x, this.y) {
    requireFinite(x, 'x');
    requireFinite(y, 'y');
  }
  final double x;
  final double y;
}

class ArtworkPixelPoint {
  ArtworkPixelPoint(this.x, this.y) {
    requireFinite(x, 'x');
    requireFinite(y, 'y');
  }
  final double x;
  final double y;
}

class ScenePoint {
  ScenePoint(this.x, this.y) {
    requireFinite(x, 'x');
    requireFinite(y, 'y');
  }
  final double x;
  final double y;
}

class ViewportPoint {
  ViewportPoint(this.x, this.y) {
    requireFinite(x, 'x');
    requireFinite(y, 'y');
  }
  final double x;
  final double y;
}

class MapExtent {
  MapExtent(this.width, this.height) {
    requirePositiveFinite(width, 'width');
    requirePositiveFinite(height, 'height');
  }
  final double width;
  final double height;
}

class GameBounds {
  GameBounds({
    required this.minX,
    required this.maxX,
    required this.minZ,
    required this.maxZ,
  }) {
    requireFinite(minX, 'minX');
    requireFinite(maxX, 'maxX');
    requireFinite(minZ, 'minZ');
    requireFinite(maxZ, 'maxZ');
    if (maxX <= minX ||
        maxZ <= minZ ||
        !(maxX - minX).isFinite ||
        !(maxZ - minZ).isFinite) {
      throw ArgumentError('Bounds must have finite positive spans.');
    }
  }
  final double minX;
  final double maxX;
  final double minZ;
  final double maxZ;
}

enum MapCoordinateFrame {
  legacyNormalized('legacy-normalized', 0),
  labsNativeNormalized('labs-native-normalized', 1);

  const MapCoordinateFrame(this.wireName, this.revision);
  final String wireName;
  final int revision;
}

// Immutable interpretation only. Labs revision-0 conversion remains import-owned.
class MapPinCoordinates {
  MapPinCoordinates({
    required this.mapId,
    required this.point,
    required this.frame,
  }) {
    if (!supportedMaps.contains(mapId) ||
        (mapId == 'thelab') !=
            (frame == MapCoordinateFrame.labsNativeNormalized)) {
      throw ArgumentError('Unsupported map and persisted coordinate frame.');
    }
  }

  factory MapPinCoordinates.fromPin(CustomPin pin) {
    pin.validate();
    return MapPinCoordinates(
      mapId: pin.mapId,
      point: ArtworkPoint(pin.x, pin.y),
      frame: pin.mapId == 'thelab'
          ? MapCoordinateFrame.labsNativeNormalized
          : MapCoordinateFrame.legacyNormalized,
    );
  }
  final String mapId;
  final ArtworkPoint point;
  final MapCoordinateFrame frame;
}

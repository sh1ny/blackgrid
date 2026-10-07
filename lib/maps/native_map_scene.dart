import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart' show BuildContext;
import 'package:vector_graphics/vector_graphics.dart' as vg;

import '../domain/map_coordinates.dart';
import '../domain/map_floors.dart';
import '../domain/map_geometry.dart';
import 'prepared_map.dart';
import 'prepared_map_loader.dart';

/// Owns a bounded, least-recently-used cache of individual native resources.
///
/// Raster accounting uses decoded width × height × four bytes. Picture
/// accounting uses Flutter's [ui.Picture.approximateBytesUsed], not compressed
/// asset length or an invented native-memory multiplier. Both are resource
/// accounting, not OS/GPU retained-memory measurements. Raster decode reserves
/// its validated 256 × 256 allocation before starting the codec. Picture size
/// is available only after decode; an over-budget picture is immediately
/// disposed and never enters the cache. Floor combinations are never cached.
class NativeMapResourceOwner {
  NativeMapResourceOwner(this.loader, {this.maxBytes = 192 * 1024 * 1024}) {
    if (maxBytes <= 0 || maxBytes > 192 * 1024 * 1024) {
      throw ArgumentError.value(
        maxBytes,
        'maxBytes',
        'Must be within the 192 MiB resource budget.',
      );
    }
  }
  final PreparedMapPackLoader loader;
  final int maxBytes;
  final LinkedHashMap<String, _NativeResource> _cache = LinkedHashMap();
  int _imageDecodedBytes = 0;
  int _pictureApproximateBytes = 0;
  int _reservedImageBytes = 0;
  bool _disposed = false;

  /// The accounted decoded raster allocation, excluding GPU copies.
  int get imageDecodedBytes => _imageDecodedBytes;

  /// The approximate native picture allocation reported by Flutter.
  int get pictureApproximateBytes => _pictureApproximateBytes;

  /// The validated image allocation reserved by outstanding raster decodes.
  int get reservedImageBytes => _reservedImageBytes;
  int get retainedResourceCount => _cache.length;
  int get accountedBytes => _imageDecodedBytes + _pictureApproximateBytes;

  /// Acquires only active vector components or visible, active-floor tiles.
  ///
  /// [isCurrent] fences both byte loading and native decoding. A superseded
  /// demand returns `null`; its newly decoded resources are disposed rather
  /// than published. The returned scene owns resource leases until disposal.
  Future<NativeMapScene?> loadScene(
    PreparedMap map,
    MapFloorSelection selection,
    MapViewTransform transform,
    ui.Size viewportSize, {
    required bool Function() isCurrent,
  }) async {
    if (!identical(selection.policy, map.floorPolicy)) {
      throw ArgumentError('Floor selection belongs to another prepared map.');
    }
    if (!_current(isCurrent)) return null;
    final resources = <_NativeResource>[];
    final pictures = <_ScenePicture>[];
    final images = <_SceneTile>[];
    final visibleTiles = _visibleTiles(map, selection, transform, viewportSize);
    var transferred = false;
    try {
      for (final component in map.components) {
        if (!selection.isLayerVisible(component.floorId)) continue;
        final resource = await _acquirePicture(component.path, isCurrent);
        if (resource == null) return null;
        resources.add(resource);
        pictures.add(_ScenePicture(component, resource.picture!));
      }
      for (final tile in visibleTiles) {
        final resource = await _acquireImage(tile.path, isCurrent);
        if (resource == null) return null;
        resources.add(resource);
        images.add(_SceneTile(tile, resource.image!));
      }
      if (!_current(isCurrent)) return null;
      final scene = NativeMapScene._(
        this,
        map,
        selection,
        pictures,
        images,
        resources,
        {for (final tile in visibleTiles) tile.path},
      );
      transferred = true;
      return scene;
    } finally {
      if (!transferred) {
        for (final resource in resources) {
          _release(resource);
        }
      }
    }
  }

  bool _current(bool Function() isCurrent) => !_disposed && isCurrent();

  _NativeResource? _cached(String path) {
    final resource = _cache.remove(path);
    if (resource == null) return null;
    _cache[path] = resource;
    resource.leases++;
    return resource;
  }

  Future<_NativeResource?> _acquirePicture(
    String path,
    bool Function() isCurrent,
  ) async {
    if (!_current(isCurrent)) return null;
    final cached = _cached(path);
    if (cached != null) return cached;
    final bytes = await loader.loadAsset(path);
    if (!_current(isCurrent)) return null;
    final picture = await vg.vg.loadPicture(
      _PreparedVectorBytes(path, bytes),
      null,
      clipViewbox: false,
      onError: (error, stack) =>
          Error.throwWithStackTrace(error, stack ?? StackTrace.current),
    );
    if (!_current(isCurrent)) {
      picture.picture.dispose();
      return null;
    }
    return _publish(
      path,
      _NativeResource.picture(
        picture.picture,
        picture.picture.approximateBytesUsed,
      ),
    );
  }

  Future<_NativeResource?> _acquireImage(
    String path,
    bool Function() isCurrent,
  ) async {
    if (!_current(isCurrent)) return null;
    final cached = _cached(path);
    if (cached != null) return cached;
    final bytes = await loader.loadAsset(path);
    if (!_current(isCurrent)) return null;
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    var reserved = 0;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      if (!_current(isCurrent)) return null;
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (!_current(isCurrent)) return null;
      if (descriptor.width != 256 || descriptor.height != 256) {
        throw const FormatException(
          'Prepared raster tiles must be native 256 × 256 pixels.',
        );
      }
      reserved = descriptor.width * descriptor.height * 4;
      _makeRoom(reserved);
      _reservedImageBytes += reserved;
      codec = await descriptor.instantiateCodec();
      if (!_current(isCurrent)) return null;
      final frame = await codec.getNextFrame();
      if (!_current(isCurrent)) {
        frame.image.dispose();
        return null;
      }
      _reservedImageBytes -= reserved;
      reserved = 0;
      return _publish(
        path,
        _NativeResource.image(
          frame.image,
          frame.image.width * frame.image.height * 4,
        ),
      );
    } finally {
      _reservedImageBytes -= reserved;
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  _NativeResource _publish(String path, _NativeResource resource) {
    final existing = _cached(path);
    if (existing != null) {
      resource.dispose();
      return existing;
    }
    try {
      _makeRoom(resource.bytes);
    } catch (_) {
      resource.dispose();
      rethrow;
    }
    resource.leases = 1;
    _cache[path] = resource;
    if (resource.image != null) {
      _imageDecodedBytes += resource.bytes;
    } else {
      _pictureApproximateBytes += resource.bytes;
    }
    return resource;
  }

  void _makeRoom(int bytes) {
    while (accountedBytes + _reservedImageBytes + bytes > maxBytes) {
      String? victim;
      for (final entry in _cache.entries) {
        if (entry.value.leases == 0) {
          victim = entry.key;
          break;
        }
      }
      if (victim == null) {
        throw StateError(
          'Active map demand exceeds the native resource budget.',
        );
      }
      final resource = _cache.remove(victim)!;
      if (resource.image != null) {
        _imageDecodedBytes -= resource.bytes;
      } else {
        _pictureApproximateBytes -= resource.bytes;
      }
      resource.dispose();
    }
  }

  void _release(_NativeResource resource) {
    if (resource.leases > 0) resource.leases--;
  }

  /// Releases all retained pictures/images and invalidates pending publication.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final resource in _cache.values) {
      resource.dispose();
    }
    _cache.clear();
    _imageDecodedBytes = 0;
    _pictureApproximateBytes = 0;
  }
}

/// A disposable resource lease for one map and one floor/viewport demand.
///
/// Pictures remain vector instructions. Native canvas shadow layers reproduce
/// component alpha effects in source units, independently of pan/zoom. Painting
/// performs no parsing, compilation or image decoding. A scene is not cached
/// by its floor combination; only its individual resources are reusable.
class NativeMapScene {
  NativeMapScene._(
    this._owner,
    this.map,
    this.selection,
    this._pictures,
    this._tiles,
    this._resources,
    this._tilePaths,
  ) : _dimBase =
          map.kind == 'vector' &&
          map.tiles.any(
            (tile) =>
                tile.floorId != map.floorPolicy.base.id &&
                selection.isLayerVisible(tile.floorId),
          );
  final NativeMapResourceOwner _owner;
  final PreparedMap map;
  final MapFloorSelection selection;
  final List<_ScenePicture> _pictures;

  /// Like tarkov.dev, a tile floor shown over SVG artwork dims the base level.
  final bool _dimBase;
  final List<_SceneTile> _tiles;
  final List<_NativeResource> _resources;
  final Set<String> _tilePaths;
  ui.Size _paintViewportSize = ui.Size.zero;
  ui.Rect _paintViewportRect = ui.Rect.zero;
  bool _disposed = false;
  bool get isDisposed => _disposed;

  /// Whether this lease already contains exactly the requested visible tiles.
  bool matchesDemand(
    MapFloorSelection floors,
    MapViewTransform transform,
    ui.Size viewportSize,
  ) {
    if (_disposed ||
        _owner._disposed ||
        !identical(floors.policy, map.floorPolicy) ||
        !_sameFloors(selection, floors)) {
      return false;
    }
    final tiles = _visibleTiles(map, floors, transform, viewportSize);
    return tiles.length == _tilePaths.length &&
        tiles.every((tile) => _tilePaths.contains(tile.path));
  }

  /// Paints active artwork under the caller's shared scene-to-viewport matrix.
  void paint(
    ui.Canvas canvas,
    MapViewTransform transform,
    ui.Size viewportSize,
  ) {
    if (_disposed || _owner._disposed) return;
    if (_paintViewportSize != viewportSize) {
      _paintViewportSize = viewportSize;
      _paintViewportRect = ui.Offset.zero & viewportSize;
    }
    canvas.save();
    canvas.clipRect(_paintViewportRect);
    canvas.translate(transform.translationX, transform.translationY);
    canvas.scale(transform.scale);
    final crop = map.displayFrame.crop;
    canvas.translate(-crop.left, -crop.top);
    for (final item in _pictures) {
      final dimmed = _dimBase && item.floorId == map.floorPolicy.base.id;
      if (dimmed) canvas.saveLayer(null, _dimPaint);
      for (final effect in item.effects) {
        canvas.save();
        canvas.translate(effect.dx, effect.dy);
        canvas.saveLayer(null, effect.paint);
        canvas.drawPicture(item.picture);
        canvas.restore();
        canvas.restore();
      }
      canvas.drawPicture(item.picture);
      if (dimmed) canvas.restore();
    }
    for (final item in _tiles) {
      canvas.drawImageRect(
        item.image,
        item.source,
        item.destination,
        _tilePaint,
      );
    }
    canvas.restore();
  }

  /// Releases this demand's leases without disposing resources used elsewhere.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final resource in _resources) {
      _owner._release(resource);
    }
  }

  static final ui.Paint _dimPaint = ui.Paint()
    ..color = const ui.Color.fromARGB(51, 0, 0, 0);
  static final ui.Paint _tilePaint = ui.Paint()
    ..filterQuality = ui.FilterQuality.low;
}

bool _sameFloors(MapFloorSelection a, MapFloorSelection b) =>
    a.selectedOverlayIds.length == b.selectedOverlayIds.length &&
    a.selectedOverlayIds.containsAll(b.selectedOverlayIds);

List<PreparedRasterTile> _visibleTiles(
  PreparedMap map,
  MapFloorSelection selection,
  MapViewTransform transform,
  ui.Size size,
) {
  if (map.tiles.isEmpty || size.width <= 0 || size.height <= 0) {
    return const [];
  }
  final topLeft = transform.viewportToScene(ViewportPoint(0, 0));
  final bottomRight = transform.viewportToScene(
    ViewportPoint(size.width, size.height),
  );
  final crop = map.displayFrame.crop;
  final left = topLeft.x + crop.left;
  final top = topLeft.y + crop.top;
  final right = bottomRight.x + crop.left;
  final bottom = bottomRight.y + crop.top;
  return [
    for (final tile in map.tiles)
      if (selection.isLayerVisible(tile.floorId) &&
          tile.left < right &&
          tile.left + tile.width > left &&
          tile.top < bottom &&
          tile.top + tile.height > top)
        tile,
  ];
}

class _NativeResource {
  _NativeResource.picture(this.picture, this.bytes) : image = null;
  _NativeResource.image(this.image, this.bytes) : picture = null;
  final ui.Picture? picture;
  final ui.Image? image;
  final int bytes;
  int leases = 0;
  bool _disposed = false;
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    picture?.dispose();
    image?.dispose();
  }
}

class _ScenePicture {
  _ScenePicture(PreparedVectorComponent component, this.picture)
    : floorId = component.floorId,
      effects = [for (final effect in component.effects) _SceneShadow(effect)];
  final ui.Picture picture;
  final String floorId;
  final List<_SceneShadow> effects;
}

class _SceneShadow {
  _SceneShadow(PreparedDropShadow shadow)
    : dx = shadow.dx,
      dy = shadow.dy,
      paint = (ui.Paint()
        ..colorFilter = ui.ColorFilter.mode(
          ui.Color(shadow.argb),
          ui.BlendMode.srcIn,
        )) {
    if (shadow.sigma > 0) {
      paint.imageFilter = ui.ImageFilter.blur(
        sigmaX: shadow.sigma,
        sigmaY: shadow.sigma,
      );
    }
  }
  final double dx;
  final double dy;
  final ui.Paint paint;
}

class _SceneTile {
  _SceneTile(PreparedRasterTile tile, this.image)
    : floorId = tile.floorId,
      source = ui.Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      ),
      destination = ui.Rect.fromLTWH(
        tile.left,
        tile.top,
        tile.width,
        tile.height,
      );
  final ui.Image image;
  final String floorId;
  final ui.Rect source;
  final ui.Rect destination;
}

class _PreparedVectorBytes extends vg.BytesLoader {
  const _PreparedVectorBytes(this.path, this.bytes);
  final String path;
  final ByteData bytes;
  @override
  Future<ByteData> loadBytes(BuildContext? context) async => bytes;
  @override
  String toString() => 'PreparedVectorBytes($path)';
}

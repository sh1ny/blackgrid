import 'dart:math' as math;

import '../domain/map_coordinates.dart';
import '../domain/map_floors.dart';
import '../domain/map_geometry.dart';

/// An immutable inventory resolved from one active pack version.
class PreparedMapPack {
  PreparedMapPack({
    required this.version,
    required this.assetRoot,
    required Iterable<PreparedMap> maps,
  }) : maps = List.unmodifiable(maps) {
    byId = Map.unmodifiable({for (final map in this.maps) map.id: map});
    if (byId.length != this.maps.length) {
      throw const FormatException('Duplicate prepared map identity.');
    }
  }
  final String version;
  final String assetRoot;
  final List<PreparedMap> maps;
  late final Map<String, PreparedMap> byId;
}

/// Manifest-owned geometry, floor policy, artwork and independent data markers.
class PreparedMap {
  PreparedMap._({
    required this.id,
    required this.name,
    required this.kind,
    required this.geometry,
    required this.displayFrame,
    required this.pinProjector,
    required this.floorPolicy,
    required this.components,
    required this.tiles,
    required this.markers,
    required this.attribution,
    required this.rasterDependencies,
    this.tileLayout,
  }) {
    categories = Set.unmodifiable(markers.map((marker) => marker.filterKey));
  }

  factory PreparedMap.fromJson(
    Map<String, dynamic> json, {
    required String assetRoot,
  }) {
    final id = _string(json, 'id');
    final kind = _string(json, 'kind');
    if (kind != 'vector' && kind != 'raster') {
      throw FormatException('Unsupported prepared artwork kind $kind.');
    }
    final rawGeometry = _object(json['geometry'], 'geometry');
    final frame = _object(json['artworkFrame'], 'artworkFrame');
    final extent = MapExtent(_number(frame, 'width'), _number(frame, 'height'));
    final crop = _object(json['displayCrop'], 'displayCrop');
    final displayFrame = MapDisplayFrame(
      originalArtwork: extent,
      crop: ArtworkCrop(
        left: _number(crop, 'left'),
        top: _number(crop, 'top'),
        width: _number(crop, 'right') - _number(crop, 'left'),
        height: _number(crop, 'bottom') - _number(crop, 'top'),
      ),
    );
    final boundsValues = _list(rawGeometry['bounds'], 'bounds');
    if (boundsValues.length != 2) {
      throw const FormatException('Expected two game bounds.');
    }
    final first = _numbers(boundsValues[0], 2, 'bounds');
    final second = _numbers(boundsValues[1], 2, 'bounds');
    final bounds = GameBounds(
      minX: math.min(first[0], second[0]),
      maxX: math.max(first[0], second[0]),
      minZ: math.min(first[1], second[1]),
      maxZ: math.max(first[1], second[1]),
    );
    final rotation = _number(rawGeometry, 'rotation');
    final affine = _numbers(rawGeometry['affine'], 4, 'affine');
    final projection = _string(rawGeometry, 'projection');
    final nativeZoom = rawGeometry['nativeZoom'];
    if (nativeZoom != null &&
        (nativeZoom is! int || nativeZoom < 0 || nativeZoom > 30)) {
      throw const FormatException('Invalid native zoom.');
    }
    if (projection != 'native-pixels' && projection != 'bounds-normalized') {
      throw FormatException('Unsupported projection $projection.');
    }
    if (projection == 'native-pixels' && nativeZoom == null) {
      throw const FormatException('Native projection requires zoom.');
    }
    final geometry = MapGeometry.affine(
      bounds: bounds,
      a: affine[0],
      b: affine[1],
      c: affine[2],
      d: affine[3],
      rotationDegrees: rotation,
      scale: nativeZoom == null ? 1 : math.pow(2, nativeZoom as int).toDouble(),
      // Native-pixels affine coefficients must use original tile pixels.
      // Display stride and seam overlap affect painting only; converting a
      // display-unit source calibration belongs in the prepared manifest.
      nativeArtwork: projection == 'native-pixels'
          ? MapExtent(
              extent.width *
                  _number(frame, 'nativeTilePixels') /
                  _number(frame, 'tileStride'),
              extent.height *
                  _number(frame, 'nativeTilePixels') /
                  _number(frame, 'tileStride'),
            )
          : null,
    );
    final orientation = switch (rotation % 360) {
      0 => LegacyMapOrientation.degrees0,
      90 => LegacyMapOrientation.degrees90,
      180 => LegacyMapOrientation.degrees180,
      270 => LegacyMapOrientation.degrees270,
      _ => throw const FormatException(
        'Legacy pin orientation must be a quarter turn.',
      ),
    };
    final pinFrame = _string(rawGeometry, 'pinFrame');
    final revision = rawGeometry['coordinateRevision'];
    if (!((id == 'thelab' &&
            pinFrame == 'labs-native-normalized' &&
            revision == 1) ||
        (id != 'thelab' && pinFrame == 'legacy-normalized' && revision == 0))) {
      throw const FormatException('Unsupported persisted pin frame/revision.');
    }
    // Persisted legacy-normalized revision-0 pins are interpreted in their
    // original source bounds, not a newly selected artwork rendition's bounds.
    // The preparation manifest explicitly freezes that basis when it differs.
    var legacyBounds = bounds;
    if (rawGeometry['legacyPinBounds'] != null) {
      final values = _list(rawGeometry['legacyPinBounds'], 'legacy pin bounds');
      if (values.length != 2) {
        throw const FormatException('Legacy pin bounds require two corners.');
      }
      final first = _numbers(values[0], 2, 'legacy pin bounds');
      final second = _numbers(values[1], 2, 'legacy pin bounds');
      legacyBounds = GameBounds(
        minX: math.min(first[0], second[0]),
        maxX: math.max(first[0], second[0]),
        minZ: math.min(first[1], second[1]),
        maxZ: math.max(first[1], second[1]),
      );
    }
    final projector = MapPinProjector(
      mapId: id,
      artworkGeometry: geometry,
      legacyGeometry: MapGeometry.boundsOnly(
        bounds: legacyBounds,
        orientation: orientation,
      ),
    );
    final rawFloors = _list(
      json['floors'],
      'floors',
    ).map((floor) => _object(floor, 'floor')).toList();
    final bases = rawFloors.where((floor) => floor['base'] == true).toList();
    if (bases.length != 1) {
      throw const FormatException('Prepared map requires exactly one base.');
    }
    MapFloor floor(Map<String, dynamic> raw) {
      if (raw['manual'] != true) {
        throw const FormatException('Unsupported nonmanual floor.');
      }
      final floorId = _string(raw, 'id');
      final band = raw['heightBand'] == null
          ? null
          : _numbers(raw['heightBand'], 2, 'heightBand');
      return MapFloor(
        id: floorId,
        label: raw['label'] == null
            ? floorId.replaceAll('_', ' ')
            : _string(raw, 'label'),
        attachedLayerIds: _list(
          raw['attachedIds'],
          'attachedIds',
        ).map((id) => _nonemptyString(id, 'attachedId')),
        heightBand: band == null ? null : HeightBand(band[0], band[1]),
      );
    }

    final exclusive = bases.single['exclusive'] == true;
    if (rawFloors.any((floor) => (floor['exclusive'] == true) != exclusive)) {
      throw const FormatException('Inconsistent floor exclusivity.');
    }
    final policy = MapFloorPolicy(
      mapId: id,
      base: floor(bases.single),
      overlays: rawFloors.where((f) => f['base'] != true).map(floor),
      exclusive: exclusive,
    );
    final componentsById = <String, PreparedVectorComponent>{};
    final tiles = <PreparedRasterTile>[];
    MapTileLayout? layout;
    if (kind == 'raster') layout = _tileLayout(frame);
    // A vector map may draw tile-only floors over its SVG. Each overlay tile
    // is placed through game coordinates: overlay pixels -> game -> SVG units.
    final overlay = kind == 'vector' && json['rasterOverlayFrame'] != null
        ? _RasterOverlay(
            _object(json['rasterOverlayFrame'], 'rasterOverlayFrame'),
            bounds: bounds,
            affine: affine,
            rotation: rotation,
            target: geometry,
            targetExtent: extent,
          )
        : null;
    void addTiles(
      String floorId,
      Map<String, dynamic> art,
      (double, double, double, double) Function(int x, int y) rect,
    ) {
      final positions = <String>{};
      for (final raw in _list(art['tiles'], 'tiles')) {
        final tile = _object(raw, 'tile');
        final x = tile['x'];
        final y = tile['y'];
        if (x is! int ||
            y is! int ||
            x < 0 ||
            y < 0 ||
            !positions.add('$x:$y')) {
          throw const FormatException('Invalid or duplicate tile position.');
        }
        if (tile['empty'] == true) continue;
        if (tile['empty'] != false) {
          throw const FormatException('Missing tile emptiness identity.');
        }
        final (left, top, width, height) = rect(x, y);
        tiles.add(
          PreparedRasterTile(
            floorId: floorId,
            path: preparedAssetPath(assetRoot, _string(tile, 'path')),
            column: x,
            row: y,
            left: left,
            top: top,
            width: width,
            height: height,
          ),
        );
      }
    }

    for (final rawFloor in rawFloors) {
      final floorId = _string(rawFloor, 'id');
      final art = _object(rawFloor['artwork'], 'artwork');
      if (kind == 'vector' && rawFloor['sourceTileUrl'] != null) {
        if (overlay == null) {
          throw const FormatException('Tile floor requires an overlay frame.');
        }
        addTiles(floorId, art, overlay.tileRect);
      } else if (kind == 'vector') {
        final expectedIds = rawFloor['componentIds'] == null
            ? {
                floorId,
                ..._list(rawFloor['attachedIds'], 'attachedIds').cast<String>(),
              }
            : _list(
                rawFloor['componentIds'],
                'componentIds',
              ).map((id) => _nonemptyString(id, 'componentId')).toSet();
        for (final raw in _list(art['components'], 'components')) {
          final rawComponent = _object(raw, 'component');
          final component = PreparedVectorComponent.fromJson(
            rawComponent,
            assetRoot: assetRoot,
            floorId: floorId,
          );
          if (!expectedIds.remove(component.id) ||
              componentsById.containsKey(component.id)) {
            throw const FormatException(
              'Duplicate or unattached vector component.',
            );
          }
          componentsById[component.id] = component;
        }
        if (expectedIds.isNotEmpty) {
          throw const FormatException('Missing required floor component.');
        }
      } else {
        addTiles(
          floorId,
          art,
          (x, y) => (
            x * layout!.displayStride.width,
            y * layout.displayStride.height,
            layout.sceneTileExtent.width,
            layout.sceneTileExtent.height,
          ),
        );
      }
    }
    final ordered = <PreparedVectorComponent>[];
    if (kind == 'vector') {
      final seen = <String>{};
      for (final rawId in _list(json['layerOrder'], 'layerOrder')) {
        final layerId = _nonemptyString(rawId, 'layerOrder');
        final component = componentsById[layerId];
        if (component == null || !seen.add(layerId)) {
          throw const FormatException('Invalid global vector layer order.');
        }
        ordered.add(component);
      }
      if (seen.length != componentsById.length) {
        throw const FormatException('Incomplete global vector layer order.');
      }
    }
    final markers = _list(
      json['markers'],
      'markers',
    ).map((raw) => PreparedMarker.fromJson(_object(raw, 'marker'))).toList();
    final identities = <String>{};
    for (final marker in markers) {
      if (!identities.add(marker.id)) {
        throw const FormatException('Duplicate data marker identity.');
      }
      if (marker.floorId != null) {
        policy.reset().isLayerVisible(marker.floorId!);
      }
    }
    final rasterDependencies =
        (json['rasterDependencies'] == null
                ? const []
                : _list(json['rasterDependencies'], 'rasterDependencies'))
            .map(
              (raw) => PreparedRasterDependency.fromJson(
                _object(raw, 'raster dependency'),
                assetRoot: assetRoot,
              ),
            )
            .toList();
    final dependencyIds = <String>{};
    for (final dependency in rasterDependencies) {
      if (!dependencyIds.add(dependency.id) ||
          !rawFloors.any((floor) => floor['id'] == dependency.id)) {
        throw const FormatException(
          'Duplicate or unattached raster dependency.',
        );
      }
    }
    return PreparedMap._(
      id: id,
      name: _string(json, 'name'),
      kind: kind,
      geometry: geometry,
      displayFrame: displayFrame,
      pinProjector: projector,
      floorPolicy: policy,
      components: List.unmodifiable(ordered),
      tiles: List.unmodifiable(tiles),
      markers: List.unmodifiable(markers),
      tileLayout: layout,
      rasterDependencies: List.unmodifiable(rasterDependencies),
      attribution: _immutableObject(
        _object(json['attribution'], 'attribution'),
      ),
    );
  }

  final String id;
  final String name;
  final String kind;
  final MapGeometry geometry;
  final MapDisplayFrame displayFrame;
  final MapPinProjector pinProjector;
  final MapFloorPolicy floorPolicy;
  final List<PreparedVectorComponent> components;
  final List<PreparedRasterTile> tiles;
  final MapTileLayout? tileLayout;
  final List<PreparedMarker> markers;
  final Map<String, dynamic> attribution;

  /// Frozen alternate source renditions, not duplicate scene layers.
  ///
  /// These belong to the same immutable pack and are closure-validated during
  /// preparation. The native scene renders only the selected representation.
  final List<PreparedRasterDependency> rasterDependencies;
  late final Set<String> categories;

  ScenePoint gameToScene(GamePoint point) =>
      displayFrame.artworkToScene(geometry.gameToArtwork(point));
}

MapTileLayout _tileLayout(Map<String, dynamic> frame) {
  final native = _number(frame, 'nativeTilePixels');
  final stride = _number(frame, 'tileStride');
  return MapTileLayout(
    nativeTilePixels: MapExtent(native, native),
    displayStride: MapExtent(stride, stride),
    seamExtent: _number(frame, 'tileImageExtent') - stride,
  );
}

/// Places a published tile grid, in its own native frame, over SVG artwork.
class _RasterOverlay {
  _RasterOverlay(
    Map<String, dynamic> frame, {
    required GameBounds bounds,
    required List<double> affine,
    required double rotation,
    required this.target,
    required this.targetExtent,
  }) : layout = _tileLayout(frame) {
    final zoom = frame['nativeZoom'];
    if (zoom is! int || zoom < 0 || zoom > 30) {
      throw const FormatException('Invalid overlay native zoom.');
    }
    final width = _number(frame, 'width');
    final height = _number(frame, 'height');
    final stride = layout.displayStride.width;
    native = MapExtent(
      width * layout.nativeTilePixels.width / stride,
      height * layout.nativeTilePixels.height / stride,
    );
    _unitsX = native.width / width;
    _unitsY = native.height / height;
    source = MapGeometry.affine(
      bounds: bounds,
      a: affine[0],
      b: affine[1],
      c: affine[2],
      d: affine[3],
      rotationDegrees: rotation,
      scale: math.pow(2, zoom).toDouble(),
      nativeArtwork: native,
    );
  }
  final MapTileLayout layout;
  final MapGeometry target;
  final MapExtent targetExtent;
  late final MapExtent native;
  late final MapGeometry source;
  late final double _unitsX;
  late final double _unitsY;

  /// The tile's destination rectangle in uncropped SVG artwork units.
  (double, double, double, double) tileRect(int x, int y) {
    final origin = layout.sceneOrigin(x, y);
    final extent = layout.sceneTileExtent;
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final (dx, dy) in [(0.0, 0.0), (extent.width, extent.height)]) {
      final game = source.artworkToGame(
        ArtworkPoint(
          (origin.x + dx) * _unitsX / native.width,
          (origin.y + dy) * _unitsY / native.height,
        ),
      );
      final point = target.gameToArtwork(game);
      final px = point.x * targetExtent.width;
      final py = point.y * targetExtent.height;
      minX = math.min(minX, px);
      maxX = math.max(maxX, px);
      minY = math.min(minY, py);
      maxY = math.max(maxY, py);
    }
    final width = maxX - minX;
    final height = maxY - minY;
    if (!minX.isFinite ||
        !minY.isFinite ||
        !width.isFinite ||
        !height.isFinite) {
      throw const FormatException('Overlay tile rectangle overflows.');
    }
    return (minX, minY, width, height);
  }
}

/// One dependency-closed compiled picture in global source stacking order.
class PreparedVectorComponent {
  PreparedVectorComponent({
    required this.id,
    required this.floorId,
    required this.path,
    required Iterable<PreparedDropShadow> effects,
  }) : effects = List.unmodifiable(effects);
  factory PreparedVectorComponent.fromJson(
    Map<String, dynamic> json, {
    required String assetRoot,
    required String floorId,
  }) {
    if (json['type'] != 'vector') {
      throw const FormatException('Unsupported vector component.');
    }
    return PreparedVectorComponent(
      id: _string(json, 'id'),
      floorId: floorId,
      path: preparedAssetPath(assetRoot, _string(json, 'path')),
      effects: _list(
        json['effects'],
        'effects',
      ).map((raw) => PreparedDropShadow.fromJson(_object(raw, 'effect'))),
    );
  }
  final String id;
  final String path;
  final String floorId;
  final List<PreparedDropShadow> effects;
}

/// A source-unit alpha shadow transferred without flattening the vector scene.
class PreparedDropShadow {
  PreparedDropShadow({
    required this.dx,
    required this.dy,
    required this.sigma,
    required this.argb,
    required this.sourceDeclaration,
  });
  factory PreparedDropShadow.fromJson(Map<String, dynamic> json) {
    if (json['type'] != 'drop-shadow') {
      throw const FormatException('Unsupported native component effect.');
    }
    final color = _string(json, 'color');
    if (!RegExp(r'^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$').hasMatch(color)) {
      throw const FormatException('Unsupported shadow color.');
    }
    final rgb = int.parse(color.substring(1, 7), radix: 16);
    final alpha = color.length == 9
        ? int.parse(color.substring(7), radix: 16)
        : 255;
    final sigma = _number(json, 'sigma');
    if (sigma < 0) throw const FormatException('Negative shadow sigma.');
    return PreparedDropShadow(
      dx: _number(json, 'dx'),
      dy: _number(json, 'dy'),
      sigma: sigma,
      argb: alpha << 24 | rgb,
      sourceDeclaration: _string(json, 'sourceDeclaration'),
    );
  }
  final double dx;
  final double dy;
  final double sigma;
  final int argb;
  final String sourceDeclaration;
}

/// A nonempty raster tile in uncropped scene-pixel units.
class PreparedRasterTile {
  const PreparedRasterTile({
    required this.floorId,
    required this.path,
    required this.column,
    required this.row,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
  final String floorId;
  final String path;
  final int column;
  final int row;
  final double left;
  final double top;
  final double width;
  final double height;
}

/// One metadata-declared alternative raster rendition in its original frame.
class PreparedRasterDependency {
  PreparedRasterDependency._({
    required this.id,
    required this.sourceUrl,
    required this.frame,
    required this.assetPaths,
  });

  factory PreparedRasterDependency.fromJson(
    Map<String, dynamic> json, {
    required String assetRoot,
  }) {
    final frame = _object(json['displayFrame'], 'dependency displayFrame');
    final extent = MapExtent(_number(frame, 'width'), _number(frame, 'height'));
    final native = _number(frame, 'nativeTilePixels');
    final stride = _number(frame, 'tileStride');
    final imageExtent = _number(frame, 'tileImageExtent');
    if (native != 256 ||
        stride != 256 ||
        imageExtent != 256 ||
        extent.width != 4096 ||
        extent.height != 4096) {
      throw const FormatException(
        'Unsupported original dependency tile frame.',
      );
    }
    final tiles = _list(
      _object(json['artwork'], 'dependency artwork')['tiles'],
      'dependency tiles',
    );
    if (tiles.length != 256) {
      throw const FormatException('Incomplete dependency tile grid.');
    }
    final coordinates = <String>{};
    final paths = <String>[];
    for (final raw in tiles) {
      final tile = _object(raw, 'dependency tile');
      final x = tile['x'], y = tile['y'];
      if (x is! int ||
          y is! int ||
          x < 0 ||
          x > 15 ||
          y < 0 ||
          y > 15 ||
          !coordinates.add('$x/$y') ||
          tile['empty'] is! bool) {
        throw const FormatException('Invalid dependency tile identity.');
      }
      if (tile['empty'] == false) {
        paths.add(preparedAssetPath(assetRoot, _string(tile, 'path')));
      }
    }
    if (paths.isEmpty) {
      throw const FormatException('Required raster dependency has no artwork.');
    }
    return PreparedRasterDependency._(
      id: _string(json, 'id'),
      sourceUrl: _string(json, 'sourceTileUrl'),
      frame: extent,
      assetPaths: List.unmodifiable(paths),
    );
  }

  final String id;
  final String sourceUrl;
  final MapExtent frame;
  final List<String> assetPaths;
}

/// An independently acquired data marker, distinct from a persisted user pin.
class PreparedMarker {
  PreparedMarker({
    required this.id,
    required this.category,
    required this.filterKey,
    required this.name,
    required this.position,
    required this.details,
    required this.source,
    required this.outline,
    this.floorId,
    this.heightBand,
  });
  factory PreparedMarker.fromJson(Map<String, dynamic> json) {
    final category = _string(json, 'category');
    final details = _immutableObject(_object(json['details'], 'details'));
    final rawBand = json['heightBand'] == null
        ? null
        : _numbers(json['heightBand'], 2, 'marker heightBand');
    return PreparedMarker(
      id: _string(json, 'id'),
      category: category,
      filterKey: json['filterKey'] is String
          ? _string(json, 'filterKey')
          : _markerFilterKey(category, details),
      name: _string(json, 'name'),
      position: _gamePoint(_object(json['position'], 'position')),
      floorId: json['floorId'] == null ? null : _string(json, 'floorId'),
      details: details,
      source: _immutableObject(_object(json['source'], 'source')),
      outline: List.unmodifiable(
        (json['outline'] == null ? const [] : _list(json['outline'], 'outline'))
            .map((raw) => _gamePoint(_object(raw, 'outline point'))),
      ),
      heightBand: rawBand == null ? null : HeightBand(rawBand[0], rawBand[1]),
    );
  }
  final String id;
  final String category;
  final String filterKey;
  final String name;
  final GamePoint position;
  final String? floorId;
  final Map<String, dynamic> details;
  final Map<String, dynamic> source;
  final List<GamePoint> outline;
  final HeightBand? heightBand;
}

String _markerFilterKey(String category, Map<String, dynamic> details) {
  return switch (category) {
    'questItems' => 'QuestItems',
    'questObjectives' => 'QuestObjectives',
    'transits' => 'Transits',
    'hazards' => details['outline'] is List ? 'HazardZones' : 'Hazards',
    'switches' => 'Switches',
    'bosses' =>
      _cultistMobs.contains(details['mob']) ? 'CultistSpawns' : 'BossSpawns',
    'btrStops' => 'BtrStops',
    'spawns' => _isScavSpawn(details) ? 'ScavSpawns' : 'PmcSpawns',
    'extracts' => switch (details['faction']) {
      'Scav' || 'scav' => 'ScavExtracts',
      'PMC' || 'pmc' => 'PmcExtracts',
      _ => 'SharedExtracts',
    },
    _ => category,
  };
}

/// Source mob identities that tarkov.dev lists under bosses but are cultists.
const _cultistMobs = {'sectantPriest', 'sectantWarrior'};

/// Production data lists `sides`; the singular `side` is the legacy shape.
bool _isScavSpawn(Map<String, dynamic> details) {
  final sides = details['sides'];
  if (sides is List && sides.isNotEmpty) {
    return sides.every((side) => side == 'scav');
  }
  return details['side'] == 'scav';
}

/// Resolves a safe pack-relative path without allowing a version escape.
String preparedAssetPath(String root, String relative) {
  if (relative.isEmpty ||
      relative.startsWith('/') ||
      relative.contains('\\') ||
      relative.contains(':') ||
      relative
          .split('/')
          .any((part) => part.isEmpty || part == '.' || part == '..')) {
    throw const FormatException('Unsafe prepared asset path.');
  }
  return '$root$relative';
}

Map<String, dynamic> _object(Object? value, String name) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('Expected $name object.');
  }
  return value;
}

List<dynamic> _list(Object? value, String name) {
  if (value is! List) throw FormatException('Expected $name array.');
  return value;
}

String _nonemptyString(Object? value, String name) {
  if (value is! String || value.isEmpty) {
    throw FormatException('Expected nonempty $name.');
  }
  return value;
}

String _string(Map<String, dynamic> json, String key) =>
    _nonemptyString(json[key], key);
double _number(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num || !value.isFinite) {
    throw FormatException('Expected finite $key.');
  }
  return value.toDouble();
}

List<double> _numbers(Object? value, int count, String name) {
  final list = _list(value, name);
  if (list.length != count || list.any((v) => v is! num || !v.isFinite)) {
    throw FormatException('Invalid $name.');
  }
  return list.cast<num>().map((v) => v.toDouble()).toList();
}

GamePoint _gamePoint(Map<String, dynamic> json) => GamePoint(
  _number(json, 'x'),
  _number(json, 'z'),
  height: json['height'] == null ? null : _number(json, 'height'),
);
Map<String, dynamic> _immutableObject(Map<String, dynamic> value) =>
    Map.unmodifiable(
      value.map((key, item) => MapEntry(key, _immutableValue(item))),
    );
Object? _immutableValue(Object? value) {
  if (value is Map<String, dynamic>) return _immutableObject(value);
  if (value is List) return List.unmodifiable(value.map(_immutableValue));
  return value;
}

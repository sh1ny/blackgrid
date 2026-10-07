import 'dart:math' as math;

import 'package:blackgrid/domain/map_coordinates.dart';
import 'package:blackgrid/maps/prepared_map.dart';
import 'package:test/test.dart';

// Reserve's published metadata: one affine/rotation shared by the SVG
// (svgBounds frame) and the z4 tile grid, as tarkov.dev's Leaflet CRS uses.
const _affine = [0.395, 122.0, 0.395, 137.65];
const _svgBounds = [
  [289, -274],
  [-303, 272],
];
const _frame = [827.28742, 761.16437];

Map<String, dynamic> _floor(String id, {bool base = false, String? tiles}) => {
  'id': id,
  'base': base,
  'manual': true,
  'exclusive': false,
  'attachedIds': <String>[],
  'sourceTileUrl': ?tiles,
  'artwork': tiles == null
      ? {
          'components': [
            {
              'id': id,
              'path': 'artwork/reserve/$id.vec',
              'type': 'vector',
              'effects': <Object>[],
            },
          ],
        }
      : {
          'tiles': [
            {
              'x': 7,
              'y': 9,
              'empty': false,
              'path': 'artwork/reserve/$id/7/9.png',
            },
            {'x': 0, 'y': 0, 'empty': true},
          ],
        },
};

/// Leaflet CRS.Simple with tarkov.dev's transformation, at zoom 4.
(double, double) _tilePixel(GamePoint point) {
  const radians = math.pi; // coordinateRotation 180
  final x = point.x * math.cos(radians) - point.z * math.sin(radians);
  final z = point.x * math.sin(radians) + point.z * math.cos(radians);
  const scale = 16.0;
  return (
    scale * (_affine[0] * x + _affine[1]),
    scale * (-_affine[2] * z + _affine[3]),
  );
}

void main() {
  test(
    'overlay tiles are placed in SVG units through shared game coordinates',
    () {
      // A game point inside the SVG frame, located in the published z4 grid
      // with tarkov.dev's own Leaflet CRS math as an independent oracle.
      final probe = GamePoint(150, -40);
      final (px, py) = _tilePixel(probe);
      final column = (px / 256).floor(), row = (py / 256).floor();
      final fx = px / 256 - column, fy = py / 256 - row;
      final map = PreparedMap.fromJson(
        _mapJsonWithTile(column, row),
        assetRoot: 'assets/',
      );
      expect(map.kind, 'vector');
      final tile = map.tiles.single;
      expect(tile.floorId, 'Second_Floor');

      final svg = map.displayFrame.artworkToPixels(
        map.geometry.gameToArtwork(probe),
      );
      expect(svg.x, closeTo(tile.left + fx * tile.width, 1e-6));
      expect(svg.y, closeTo(tile.top + fy * tile.height, 1e-6));
    },
  );

  test(
    'finite overlay inputs cannot publish an overflowing tile rectangle',
    () {
      final json = _mapJsonWithTile(0, 0);
      (json['artworkFrame'] as Map)['width'] = 1e200;
      (json['artworkFrame'] as Map)['height'] = 1.0;
      (json['displayCrop'] as Map)['right'] = 1e200;
      (json['displayCrop'] as Map)['bottom'] = 1.0;
      json['rasterOverlayFrame'] = {
        'nativeZoom': 0,
        'width': 256.0,
        'height': 1e-100,
        'tileStride': 256.0,
        'tileImageExtent': 256.0,
        'nativeTilePixels': 1e200,
      };
      expect(
        () => PreparedMap.fromJson(json, assetRoot: 'assets/'),
        throwsFormatException,
      );
    },
  );

  test('a tile floor without an overlay frame is rejected', () {
    final json = _mapJsonWithTile(1, 1)..remove('rasterOverlayFrame');
    expect(
      () => PreparedMap.fromJson(json, assetRoot: 'assets/'),
      throwsFormatException,
    );
  });
}

Map<String, dynamic> _mapJsonWithTile(int x, int y) {
  final json = _mapJson();
  final floor = (json['floors'] as List)[1] as Map<String, dynamic>;
  floor['artwork'] = {
    'tiles': [
      {'x': x, 'y': y, 'empty': false, 'path': 'artwork/reserve/t/$x/$y.png'},
    ],
  };
  return json;
}

Map<String, dynamic> _mapJson() => {
  'id': 'reserve',
  'name': 'Reserve',
  'kind': 'vector',
  'geometry': {
    'rotation': 180,
    'affine': _affine,
    'bounds': _svgBounds,
    'nativeZoom': null,
    'coordinateRevision': 0,
    'pinFrame': 'legacy-normalized',
    'projection': 'bounds-normalized',
  },
  'artworkFrame': {
    'width': _frame[0],
    'height': _frame[1],
    'viewBox': [0.0, 0.0, ..._frame],
  },
  'rasterOverlayFrame': {
    'nativeZoom': 4,
    'width': 4096,
    'height': 4096,
    'tileStride': 256,
    'tileImageExtent': 256,
    'nativeTilePixels': 256,
  },
  'displayCrop': {'left': 0, 'top': 0, 'right': _frame[0], 'bottom': _frame[1]},
  'layerOrder': ['Ground_Level'],
  'floors': [
    _floor('Ground_Level', base: true),
    _floor(
      'Second_Floor',
      tiles: 'https://example.invalid/2nd/{z}/{x}/{y}.png',
    ),
  ],
  'markers': <Object>[],
  'attribution': <String, Object>{},
};

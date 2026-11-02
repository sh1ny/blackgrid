import 'dart:convert';
import 'dart:typed_data';

import 'package:blackgrid/maps/prepared_map.dart';
import 'package:blackgrid/maps/prepared_map_loader.dart';

import '../../tool/maps/calibration.dart' show supportedMapSources;

/// Builds a complete preparation-version-3 manifest for loader tests.
///
/// [maps] are the maps a test cares about. Every other supported map id is
/// padded with [minimalPreparedMap], so the supported-map closure holds. The
/// `outputs` list is derived from the artwork paths of all maps, and the
/// manifest records [preparedVectorCodecFormat]. The result is a fresh mutable
/// map, so a test can overwrite or remove any key to build a bad manifest.
Map<String, dynamic> preparedPackManifest({
  List<Map<String, dynamic>> maps = const [],
}) {
  // A JSON round trip gives the loader the same typed maps a decoded asset has.
  final given = {for (final map in maps) map['id'] as String};
  final all = [
    for (final map in maps) jsonDecode(jsonEncode(map)) as Map<String, dynamic>,
    for (final id in supportedMapSources.keys)
      if (!given.contains(id)) minimalPreparedMap(id),
  ];
  final paths = <String>{};
  for (final raw in all) {
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
    'vectorCodecFormat': preparedVectorCodecFormat,
    'supportedMapIds': [...supportedMapSources.keys],
    'maps': all,
    'outputs': [
      for (final path in paths) {'path': path},
    ],
  };
}

/// One vector map with a single floor and a single component.
///
/// The Labs map keeps its own pin frame, which the parser requires.
Map<String, dynamic> minimalPreparedMap(String id) => {
  'id': id,
  'name': '$id padding',
  'kind': 'vector',
  'geometry': {
    'rotation': 0,
    'affine': [1, 0, 1, 32],
    'bounds': [
      [0, 0],
      [32, 32],
    ],
    'nativeZoom': null,
    'coordinateRevision': id == 'thelab' ? 1 : 0,
    'pinFrame': id == 'thelab' ? 'labs-native-normalized' : 'legacy-normalized',
    'projection': 'bounds-normalized',
  },
  'artworkFrame': {'width': 32, 'height': 32},
  'displayCrop': {'left': 0, 'top': 0, 'right': 32, 'bottom': 32},
  'layerOrder': ['Ground'],
  'floors': [
    {
      'id': 'Ground',
      'base': true,
      'manual': true,
      'exclusive': false,
      'attachedIds': [],
      'componentIds': ['Ground'],
      'artwork': {
        'components': [
          {
            'id': 'Ground',
            'type': 'vector',
            'path': 'padding/$id.vec',
            'effects': [],
          },
        ],
      },
    },
  ],
  'markers': [],
  'attribution': {'author': 'Padding fixture'},
};

/// Encodes [value] as the UTF-8 JSON bytes an asset bundle would return.
ByteData preparedJsonBytes(Object value) =>
    ByteData.sublistView(Uint8List.fromList(utf8.encode(jsonEncode(value))));

/// A byte source serving [manifest] as the active pack `fixture`.
///
/// Every requested path is appended to [requested]. [other] serves any path
/// that is neither the pointer nor the manifest, and defaults to failing so a
/// metadata-only load cannot touch artwork.
Future<ByteData> Function(String) preparedPackBytes(
  Object manifest, {
  List<String>? requested,
  Future<ByteData> Function(String path)? other,
}) => (path) async {
  requested?.add(path);
  if (path.endsWith('active.json')) {
    return preparedJsonBytes({
      'schemaVersion': 1,
      'version': 'fixture',
      'manifest': 'versions/fixture/manifest.json',
    });
  }
  if (path.endsWith('manifest.json')) return preparedJsonBytes(manifest);
  if (other != null) return other(path);
  throw StateError('Metadata loading must not decode artwork: $path');
};

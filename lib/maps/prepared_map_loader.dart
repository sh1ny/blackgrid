import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/settings.dart' show supportedMaps;
import 'prepared_map.dart';

/// Loads one coherent immutable version from a local active pointer.
///
/// The optional byte callback receives complete asset paths, including
/// [assetPrefix]. It can read a prepared directory for offline qualification;
/// no runtime acquisition or platform-specific file dependency is required.
class PreparedMapPackLoader {
  PreparedMapPackLoader({
    AssetBundle? bundle,
    String assetPrefix = 'assets/maps/',
    Future<ByteData> Function(String path)? loadBytes,
  }) : assetPrefix = assetPrefix.endsWith('/') ? assetPrefix : '$assetPrefix/',
       _loadBytes = loadBytes ?? (bundle ?? rootBundle).load;

  final String assetPrefix;
  final Future<ByteData> Function(String path) _loadBytes;
  Future<PreparedMapPack>? _pack;

  /// Loads and caches metadata without decoding native artwork.
  Future<PreparedMapPack> load() => _pack ??= _readPack();

  /// Loads a complete local asset path from the injected byte source.
  Future<ByteData> loadAsset(String path) => _loadBytes(path);

  Future<Map<String, dynamic>> _json(String path) async {
    final bytes = await _loadBytes(path);
    final decoded = jsonDecode(
      utf8.decode(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      ),
    );
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid prepared JSON object.');
    }
    return decoded;
  }

  Future<PreparedMapPack> _readPack() async {
    final pointer = await _json('${assetPrefix}active.json');
    if (pointer['schemaVersion'] != 1) {
      throw const FormatException(
        'Unsupported prepared active pointer version.',
      );
    }
    final version = pointer['version'];
    if (version is! String || !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(version)) {
      throw const FormatException('Invalid immutable pack identity.');
    }
    final manifestPath = 'versions/$version/manifest.json';
    if (pointer['manifest'] != manifestPath) {
      throw const FormatException(
        'Active pointer crosses an immutable version.',
      );
    }
    final manifest = await _json(preparedAssetPath(assetPrefix, manifestPath));
    if (manifest['schemaVersion'] != 1 || manifest['maps'] is! List) {
      throw const FormatException('Unsupported prepared manifest version.');
    }
    if (manifest['vectorsCompiled'] != true ||
        manifest['runtimeVectorVersion'] != '1.2.3') {
      throw const FormatException(
        'Pack is not qualified for vector_graphics 1.2.3.',
      );
    }
    final root = '${assetPrefix}versions/$version/';
    final maps = <PreparedMap>[];
    for (final value in manifest['maps'] as List) {
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Invalid prepared map.');
      }
      maps.add(PreparedMap.fromJson(value, assetRoot: root));
    }
    if (maps.isEmpty) throw const FormatException('Prepared pack has no maps.');
    if (manifest['preparationVersion'] == 3) {
      final supported = manifest['supportedMapIds'];
      if (supported is! List ||
          supported.length != supportedMaps.length ||
          supported.any((id) => id is! String || id.isEmpty) ||
          supported.toSet().length != supported.length ||
          !supported.toSet().containsAll(supportedMaps) ||
          maps.length != supported.length ||
          maps.map((map) => map.id).toSet().length != maps.length ||
          !supported.toSet().containsAll(maps.map((map) => map.id))) {
        throw const FormatException(
          'Incomplete prepared supported-map closure.',
        );
      }
      final outputEntries = manifest['outputs'];
      if (outputEntries is! List) {
        throw const FormatException('Missing prepared output closure.');
      }
      final outputs = <String>{};
      for (final value in outputEntries) {
        if (value is! Map<String, dynamic> || value['path'] is! String) {
          throw const FormatException('Invalid prepared output identity.');
        }
        final path = preparedAssetPath(root, value['path'] as String);
        if (!outputs.add(path)) {
          throw const FormatException('Duplicate prepared output identity.');
        }
      }
      for (final map in maps) {
        for (final path in [
          for (final component in map.components) component.path,
          for (final tile in map.tiles) tile.path,
          for (final dependency in map.rasterDependencies)
            ...dependency.assetPaths,
        ]) {
          if (!outputs.contains(path)) {
            throw const FormatException(
              'Prepared scene escapes output closure.',
            );
          }
        }
      }
    }
    return PreparedMapPack(version: version, assetRoot: root, maps: maps);
  }
}

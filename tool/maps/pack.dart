import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as image;
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart'
    as vector;

import 'calibration.dart';
import 'svg.dart';

String canonicalJson(Object? value) {
  Object? sorted(Object? v) {
    if (v is Map) {
      final keys = v.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: sorted(v[key])};
    }
    if (v is List) return v.map(sorted).toList();
    return v;
  }

  return '${const JsonEncoder.withIndent('  ').convert(sorted(value))}\n';
}

File packFile(Directory root, String relative) {
  if (relative.isEmpty ||
      relative.contains('\\') ||
      relative.startsWith('/') ||
      relative.contains(':') ||
      relative.split('/').any((s) => s.isEmpty || s == '.' || s == '..')) {
    throw FormatException('Nonportable pack path $relative');
  }
  return File('${root.path}/$relative');
}

Future<void> _write(Directory root, String path, List<int> bytes) async {
  final file = packFile(root, path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
}

Future<Map<String, dynamic>> _readJson(Directory root, String path) async =>
    jsonDecode(await packFile(root, path).readAsString())
        as Map<String, dynamic>;
String _hash(List<int> bytes) => sha256.convert(bytes).toString();

// Independently frozen compiler-input -> payload identities for the reviewed
// Interchange source, compiler 1.3.0 and the optimizer flags below. These are
// not candidate-provided hashes: validation authenticates the actual picture,
// including when another valid .vec is copied onto its canonical path.
const _pinnedVectorHashes = {
  '11e25b360e519002c247d009752f19181eea1ae369bb3c51c26494b5230b2734':
      '8683e42dd3893d64c5ba2c7d459c96e63f47a98f7ebcfa331357ca873666d9ad',
  '5fa97bd9a4acaa93644ce305f395b041d5eb8ec20f0db008c58f488273366504':
      '4354bd9bf3096727f9485530d4de843aac626e507483cd592baeff08ff532ba7',
  '77f8ec1fff31fd6e24e4232123e117181fe138560635e3dc307cc8ca3b4a2c84':
      'e4bdc19947fee99a8a3ce0addeb96d983710f9c2e13665f9d1bb3e27211bdc70',
  'ca28586c7a81d4034bb5ce9467bf8f5d4e8154bb7c7974ec6ebe60b3a1810062':
      '00690f1c553fe2fa7511cf22a7c091e1aafcab4e4b2d520c3d37ea048b237823',
  'd6857bf90b5c810f13023aa5751d26e58ae6c6eaafdb1a113f5e9deaff697a9f':
      '37bb90587c5375e2273da694ceab1522f6e5936ac7ec8bf8fc6c27f796c3528f',
  '1e49c92621de169bc95842598edd6e226f69000c074194f94f948a113d9dabb1':
      'f9a5822f84df9b0ad07a7084eae5a22a2bf72acb7409ae6af86af5aef6ac4ff9',
  'dbf9222ec02ef907312495d42346e048ec55f0a932ff14f967e26f89b6052cfb':
      '7f663c61c40224b106c1de6806c776f9b5d06b6b396f7a8b7b78158385fa978d',
  'e5dcbbfb8490b63db5e378a2f76205bde6592c0713ad500352bcc18833f4a38e':
      '4263274e06d69d964f223997c175d18cd79858b12c338cfbc638ec20309a6c89',
};
final _compiledVectorHashes = Map<String, String>.of(_pinnedVectorHashes);

Uint8List _encodeVector(String xml, String debugName) => vector.encodeSvg(
  xml: xml,
  debugName: debugName,
  warningsAsErrors: true,
  enableMaskingOptimizer: false,
  enableClippingOptimizer: false,
  enableOverdrawOptimizer: false,
);

String _expectedVectorHash(String xml, String debugName) {
  final sourceHash = _hash(utf8.encode(xml));
  // Unpinned independently authored sources (including test fixtures) need one
  // real compilation, never a hash supplied by the candidate. Cache only small
  // identities, not SVG strings or compiled buffers. The production source
  // takes the frozen fast path and is never recompiled during validation.
  return _compiledVectorHashes.putIfAbsent(
    sourceHash,
    () => _hash(_encodeVector(xml, debugName)),
  );
}

String _emptyTileWitnessPath(String sourceHash) =>
    'evidence/tile-alpha/$sourceHash.png';

class FrozenInputs {
  FrozenInputs._(this.root, this.index);
  final Directory root;
  final Map<String, dynamic> index;
  static Future<FrozenInputs> open(Directory root) async {
    final index = await _readJson(root, 'sources.json');
    if (index['schemaVersion'] != 1 || index['sources'] is! List) {
      throw const FormatException('Unsupported frozen inputs');
    }
    final paths = <String>{};
    for (final source in index['sources'] as List) {
      final path = source['path'] as String;
      if (!paths.add(path)) {
        throw FormatException('Duplicate frozen path $path');
      }
      final bytes = await packFile(root, path).readAsBytes();
      if (_hash(bytes) != source['sha256']) {
        throw FormatException('Frozen input hash mismatch: $path');
      }
      if (Uri.tryParse(source['url'] as String)?.scheme != 'https' &&
          source['url'] != 'blackgrid:calibration-v1') {
        throw FormatException('Invalid frozen source URL: $path');
      }
    }
    return FrozenInputs._(root, index);
  }

  Future<Uint8List> bytes(String path) async {
    if (!(index['sources'] as List).any((s) => s['path'] == path)) {
      throw FormatException('Unfrozen dependency: $path');
    }
    return packFile(root, path).readAsBytes();
  }

  Future<String> text(String path) async => utf8.decode(await bytes(path));
}

class PngInspection {
  const PngInspection(this.empty, this.left, this.top, this.right, this.bottom);
  final bool empty;
  final int left, top, right, bottom;
}

PngInspection inspectPng(Uint8List bytes, {int expectedSize = 256}) {
  image.Image? decoded;
  try {
    decoded = image.decodePng(bytes);
  } catch (error) {
    throw FormatException('PNG decoding failed: $error');
  }
  if (decoded == null ||
      decoded.width != expectedSize ||
      decoded.height != expectedSize ||
      decoded.numFrames != 1) {
    throw FormatException(
      'PNG dimensions/frame mismatch; expected ${expectedSize}x$expectedSize',
    );
  }
  var left = expectedSize, top = expectedSize, right = 0, bottom = 0;
  for (final pixel in decoded) {
    if (pixel.a > 0) {
      left = math.min(left, pixel.x);
      top = math.min(top, pixel.y);
      right = math.max(right, pixel.x + 1);
      bottom = math.max(bottom, pixel.y + 1);
    }
  }
  return PngInspection(right == 0, left, top, right, bottom);
}

Future<void> acquireInputs(Directory root) async {
  if (await root.exists()) {
    throw const FormatException('Acquisition requires a fresh raw directory');
  }
  await root.create(recursive: true);
  final client = http.Client();
  final sources = <Map<String, Object?>>[];
  Future<Uint8List> fetch(String path, String url) async {
    final response = await client.get(
      Uri.parse(url),
      headers: {
        'User-Agent': 'Blackgrid/1 independent offline map preparation',
        'Accept': '*/*',
      },
    );
    if (response.statusCode != 200) {
      throw HttpException(
        'Required source returned HTTP ${response.statusCode}',
        uri: Uri.parse(url),
      );
    }
    final bytes = response.bodyBytes;
    final expectedHash = primarySourceHashes[path];
    if (expectedHash != null && _hash(bytes) != expectedHash) {
      throw FormatException(
        'Upstream changed locked source $path; review a new source generation before acquisition',
      );
    }
    if (path.endsWith('.png')) inspectPng(bytes);
    await _write(root, path, bytes);
    sources.add({'path': path, 'url': url, 'sha256': _hash(bytes)});
    return bytes;
  }

  try {
    final metadata = jsonDecode(
      utf8.decode(await fetch('metadata/maps.json', metadataUrl)),
    ) as List;
    await fetch('markers/maps.json', markerUrl);
    await fetch('markers/maps_en.json', '${markerUrl}_en');
    await fetch(vectorSourcePath, vectorSourceUrl);
    sources.last.addAll({
      'repositoryUrl': '$vectorSourceRoot/Interchange.svg',
      'repositoryRevision': vectorSourceRevision,
      'gitBlobSha1': vectorSourceBlob,
    });
    await fetch('terms/svg-maps-README.md', '$vectorSourceRoot/README.md');
    await fetch('terms/svg-maps-LICENSE.md', '$vectorSourceRoot/LICENSE.md');
    await fetch(
      'terms/tarkov-dev-README.md',
      'https://raw.githubusercontent.com/the-hideout/tarkov-dev/main/README.md',
    );
    await fetch(
      'terms/tarkov-dev-software-LICENSE.txt',
      'https://raw.githubusercontent.com/the-hideout/tarkov-dev/main/LICENSE',
    );
    await fetch('terms/tarkovbot-creator.html', 'https://tarkovbot.eu/');
    final calibration = [
      for (final key in ['interchange', 'the-lab', 'icebreaker'])
        calibrationFor(key),
    ];
    final calibrationBytes = utf8.encode(
      canonicalJson({'schemaVersion': 1, 'maps': calibration}),
    );
    await _write(root, 'calibration.json', calibrationBytes);
    sources.add({
      'path': 'calibration.json',
      'url': 'blackgrid:calibration-v1',
      'sha256': _hash(calibrationBytes),
    });
    final jobs = <({String path, String url})>[];
    for (final local in calibration) {
      final upstream = interactiveMetadata(
        metadata,
        local['sourceKey'] as String,
      );
      final floors = reconcileFloors(local, upstream);
      for (final floor in floors) {
        if (floor['sourceTileUrl'] == null) continue;
        for (var x = 0; x < 16; x++) {
          for (var y = 0; y < 16; y++) {
            jobs.add((
              path: rawTilePath(
                local['id'] as String,
                floor['id'] as String,
                x,
                y,
              ),
              url: tileUrl(floor['sourceTileUrl'] as String, x, y),
            ));
          }
        }
      }
    }
    // Decode every response, including transparent tiles. No missing tiles are
    // guessed to be empty; a 404 or malformed response aborts the freeze.
    for (var start = 0; start < jobs.length; start += 8) {
      await Future.wait(
        jobs.skip(start).take(8).map((job) => fetch(job.path, job.url)),
      );
    }
    sources.sort(
      (a, b) => (a['path'] as String).compareTo(b['path'] as String),
    );
    await _write(
      root,
      'sources.json',
      utf8.encode(
        canonicalJson({
          'schemaVersion': 1,
          'vectorSourceRevision': vectorSourceRevision,
          'metadataRepositoryRevision': metadataRepositoryRevision,
          'metadataBlob': metadataBlob,
          'sources': sources,
        }),
      ),
    );
  } finally {
    client.close();
  }
}

Future<Map<String, dynamic>> rebuildCandidate(
  Directory raw,
  Directory candidate, {
  bool compileVectors = true,
}) async {
  if (await candidate.exists() && !(await candidate.list().isEmpty)) {
    throw const FormatException('Rebuild requires an empty fresh candidate');
  }
  final frozen = await FrozenInputs.open(raw);
  final calibration =
      jsonDecode(await frozen.text('calibration.json')) as Map<String, dynamic>;
  final metadata = jsonDecode(await frozen.text('metadata/maps.json')) as List;
  final markerSnapshot = jsonDecode(
    await frozen.text('markers/maps.json'),
  ) as Map<String, dynamic>;
  final translations =
      (jsonDecode(await frozen.text('markers/maps_en.json'))
              as Map<String, dynamic>)['data']
          as Map<String, dynamic>;
  final maps = <Map<String, Object?>>[];
  final emptyTileWitnesses = <String>{};
  await candidate.create(recursive: true);
  for (final untyped in calibration['maps'] as List) {
    final local = Map<String, Object?>.from(untyped as Map);
    final sourceKey = local['sourceKey'] as String;
    _validateCalibration(local);
    final upstream = interactiveMetadata(metadata, sourceKey);
    final floors = reconcileFloors(local, upstream);
    final mapId = local['id'] as String;
    var crop = <num>[
      double.infinity,
      double.infinity,
      double.negativeInfinity,
      double.negativeInfinity,
    ];
    if (local['kind'] == 'vector') {
      final source = await frozen.text(vectorSourcePath);
      if (canonicalJson(svgFrame(source)) !=
          canonicalJson(local['artworkFrame'])) {
        throw const FormatException(
          'Vector source frame differs from locked calibration',
        );
      }
      final allFloors = _vectorSelectionIds(floors);
      final componentIds = {
        for (final floor in floors) ..._floorComponents(floor),
      };
      final sourceOrder = svgLayerOrder(source, componentIds);
      // Attached base content can interleave with selectable overlays.
      // Preserve the global DOM order, not just the order inside each floor.
      local['layerOrder'] = sourceOrder;
      for (final floor in floors) {
        final components = <Map<String, Object?>>[];
        final ids = _floorComponents(floor).toSet();
        for (final id in sourceOrder.where(ids.contains)) {
          final normalized = normalizeSvgFloor(source, {id}, allFloors);
          final transferable = compilerSvg(normalized, id);
          final path = 'artwork/$mapId/$id.svg';
          await _write(candidate, path, utf8.encode(normalized));
          final compilerPath = 'artwork/$mapId/$id.compiler.svg';
          await _write(candidate, compilerPath, utf8.encode(transferable.xml));
          final vectorPath = 'artwork/$mapId/$id.vec';
          if (compileVectors) {
            await _compile(candidate, compilerPath, vectorPath);
          }
          components.add({
            'id': id,
            'sourceSvg': path,
            'compilerSvg': compilerPath,
            'path': vectorPath,
            'type': 'vector',
            'effects': transferable.effects,
          });
        }
        if (components.length != ids.length) {
          throw FormatException(
            'Missing ordered floor components for ${floor['id']}',
          );
        }
        floor['artwork'] = {'components': components};
      }
      final frame = local['artworkFrame'] as Map;
      crop = [0, 0, frame['width'] as num, frame['height'] as num];
    } else {
      final frame = local['artworkFrame'] as Map;
      final stride = frame['tileStride'] as num;
      final extent = frame['tileImageExtent'] as num;
      for (final floor in floors) {
        final inventory = <Map<String, Object?>>[];
        for (var x = 0; x < 16; x++) {
          for (var y = 0; y < 16; y++) {
            final path = rawTilePath(mapId, floor['id'] as String, x, y);
            final bytes = await frozen.bytes(path);
            final decoded = inspectPng(bytes);
            final sourceHash = _hash(bytes);
            if (decoded.empty && emptyTileWitnesses.add(sourceHash)) {
              // Deduplicate by frozen source identity, not byte length or a
              // manifest assertion. Promotion can decode this original PNG
              // without the external raw cache even for omitted empty tiles.
              await _write(candidate, _emptyTileWitnessPath(sourceHash), bytes);
            }
            final tile = <String, Object?>{
              'x': x,
              'y': y,
              'empty': decoded.empty,
              'sourcePath': path,
              'sourceSha256': sourceHash,
            };
            if (!decoded.empty) {
              final output = 'artwork/$mapId/${floor['id']}/$x/$y.png';
              await _write(candidate, output, bytes);
              tile['path'] = output;
              tile['alphaBounds'] = [
                decoded.left,
                decoded.top,
                decoded.right,
                decoded.bottom,
              ];
              crop = [
                math.min(crop[0], x * stride + decoded.left / 256 * extent),
                math.min(crop[1], y * stride + decoded.top / 256 * extent),
                math.max(crop[2], x * stride + decoded.right / 256 * extent),
                math.max(crop[3], y * stride + decoded.bottom / 256 * extent),
              ];
            }
            inventory.add(tile);
          }
        }
        if (inventory.every((t) => t['empty'] == true)) {
          throw FormatException(
            'Required floor ${floor['id']} has no decoded artwork',
          );
        }
        floor['artwork'] = {'tiles': inventory};
      }
      // A union crop is display-only. Pins continue using original frame units.
      crop = [crop[0].floor(), crop[1].floor(), crop[2].ceil(), crop[3].ceil()];
    }
    local['displayCrop'] = {
      'left': crop[0],
      'top': crop[1],
      'right': crop[2],
      'bottom': crop[3],
    };
    local['floors'] = floors;
    local['markers'] = prepareMarkers(markerSnapshot, translations, local);
    local['attribution'] = {
      'author': upstream['author'],
      'authorLink': upstream['authorLink'],
      'sourceKey': sourceKey,
      'termsStatus': sourceKey == 'interchange'
          ? 'CC-BY-NC-SA-4.0-with-published-README-restrictions'
          : 'published-credit-evidence-no-owner-clearance-asserted',
      if (local['kind'] == 'vector')
        'artworkSource': {
          ...Map<String, Object?>.from(
            (frozen.index['sources'] as List).singleWhere(
              (s) => s['path'] == vectorSourcePath,
            ) as Map,
          ),
          'termsPaths': [
            'terms/svg-maps-README.md',
            'terms/svg-maps-LICENSE.md',
          ],
        },
    };
    maps.add(local);
  }
  for (final entry in frozen.index['sources'] as List) {
    final path = entry['path'] as String;
    // Bundle terms, metadata and source vector, but not the raster source cache.
    if (!path.startsWith('tiles/')) {
      await _write(candidate, 'evidence/$path', await frozen.bytes(path));
    }
  }
  await _write(
    candidate,
    'evidence/sources.json',
    utf8.encode(canonicalJson(frozen.index)),
  );
  await _write(candidate, 'NOTICE.txt', utf8.encode(artworkNotices));
  final manifest = <String, dynamic>{
    'schemaVersion': 1,
    'preparationVersion': 2,
    'sourceGeneration': _hash(utf8.encode(canonicalJson(frozen.index))),
    'sourceLock': {
      'vectorSourceRevision': vectorSourceRevision,
      'vectorSourceUrl': vectorSourceUrl,
      'vectorSourceBlob': vectorSourceBlob,
      'metadataRepositoryRevision': metadataRepositoryRevision,
      'metadataBlob': metadataBlob,
      'primaryHashes': primarySourceHashes,
    },
    'dependencies': {
      'xml': '6.6.1',
      'image': '4.8.0',
      'vector_graphics_compiler': '1.3.0',
      'vector_graphics_runtimeTarget': '1.2.3',
    },
    'compilerVersion': '1.3.0',
    'runtimeVectorVersion': '1.2.3',
    'vectorsCompiled': compileVectors,
    'maps': maps,
    'outputs': await _outputHashes(candidate),
  };
  await _write(
    candidate,
    'manifest.json',
    utf8.encode(canonicalJson(manifest)),
  );
  await validateCandidate(candidate, requireCompiled: compileVectors);
  return manifest;
}

List<String> _floorComponents(Map<String, Object?> floor) => [
  ...(floor['componentIds'] as List? ?? [floor['id']]).cast<String>(),
  ...(floor['attachedIds'] as List).cast<String>(),
];

Set<String> _vectorSelectionIds(List<Map<String, Object?>> floors) => {
  for (final floor in floors) floor['id'] as String,
  for (final floor in floors) ..._floorComponents(floor),
};

// New builds require the currently authored calibration. Reading an already
// published generation instead validates against its hash-locked evidence.
void _validateCalibration(Map<String, Object?> local) {
  final expected = calibrationFor(local['sourceKey'] as String);
  if (canonicalJson(local) != canonicalJson(expected)) {
    throw FormatException(
      'Calibration revision mismatch for ${local['sourceKey']}; changes require a new preparation revision',
    );
  }
}

Future<void> _compile(Directory root, String input, String output) async {
  final xml = await packFile(root, input).readAsString();
  final bytes = _encodeVector(xml, input);
  _compiledVectorHashes.putIfAbsent(
    _hash(utf8.encode(xml)),
    () => _hash(bytes),
  );
  await _write(root, output, bytes);
}

/// Optional separate adapter: raw inputs and normalized scenes do not change.
/// Manifest publication is last, so interrupted compilation remains unpromotable.
Future<void> compileCandidate(Directory candidate) async {
  final manifest = await validateCandidate(candidate, requireCompiled: false);
  if (manifest['vectorsCompiled'] == true) {
    throw const FormatException('Candidate is already compiled');
  }
  for (final map in manifest['maps'] as List) {
    if (map['kind'] != 'vector') continue;
    for (final floor in map['floors'] as List) {
      for (final component in floor['artwork']['components'] as List) {
        await _compile(
          candidate,
          component['compilerSvg'] as String,
          component['path'] as String,
        );
      }
    }
  }
  manifest['vectorsCompiled'] = true;
  manifest['outputs'] = await _outputHashes(candidate);
  await _write(
    candidate,
    'manifest.json',
    utf8.encode(canonicalJson(manifest)),
  );
  await validateCandidate(candidate);
}

Future<List<Map<String, Object?>>> _outputHashes(Directory root) async {
  final rootPath = root.path
      .replaceAll('\\', '/')
      .replaceFirst(RegExp(r'/+$'), '');
  final files = <File>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is Link) {
      throw const FormatException('Symlinks are not portable pack assets');
    }
    if (entity is File &&
        entity.path.replaceAll('\\', '/').split('/').last != 'manifest.json') {
      files.add(entity);
    }
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final file in files)
      {
        'path': file.path.replaceAll('\\', '/').substring(rootPath.length + 1),
        'sha256': _hash(await file.readAsBytes()),
      },
  ];
}

Future<Map<String, dynamic>> validateCandidate(
  Directory candidate, {
  bool requireCompiled = true,
}) async {
  final manifest = await _readJson(candidate, 'manifest.json');
  if (manifest['schemaVersion'] != 1 ||
      manifest['maps'] is! List ||
      manifest['outputs'] is! List) {
    throw const FormatException('Invalid candidate manifest');
  }
  if (requireCompiled && manifest['vectorsCompiled'] != true) {
    throw const FormatException(
      'Uncompiled vector candidate cannot be promoted',
    );
  }
  final outputs = <String, String>{};
  for (final entry in manifest['outputs'] as List) {
    final path = entry['path'] as String;
    if (outputs.containsKey(path)) {
      throw FormatException('Duplicate output $path');
    }
    final bytes = await packFile(candidate, path).readAsBytes();
    if (_hash(bytes) != entry['sha256']) {
      throw FormatException('Candidate output hash mismatch: $path');
    }
    outputs[path] = entry['sha256'] as String;
  }
  final actual = await _outputHashes(candidate);
  if (canonicalJson(actual) != canonicalJson(manifest['outputs'])) {
    throw const FormatException(
      'Candidate contains untracked or missing output bytes',
    );
  }
  void required(String path) {
    if (!outputs.containsKey(path)) {
      throw FormatException('Candidate closure missing $path');
    }
  }

  required('NOTICE.txt');
  required('evidence/sources.json');
  required('evidence/calibration.json');
  required('evidence/metadata/maps.json');
  required('evidence/markers/maps.json');
  required('evidence/markers/maps_en.json');
  required('evidence/terms/svg-maps-README.md');
  required('evidence/terms/svg-maps-LICENSE.md');
  final maps = (manifest['maps'] as List).cast<Map<String, dynamic>>();
  if (maps.length != 3 ||
      maps.map((m) => m['id']).toSet().length != 3 ||
      maps.map((m) => m['id']).toSet().difference({
        'interchange',
        'thelab',
        'icebreaker',
      }).isNotEmpty) {
    throw const FormatException('Candidate requires exactly all three maps');
  }
  final sourceIndex = await _readJson(candidate, 'evidence/sources.json');
  if (manifest['sourceGeneration'] !=
      _hash(utf8.encode(canonicalJson(sourceIndex)))) {
    throw const FormatException('Frozen source generation changed');
  }
  final frozenHashes = <String, String>{};
  for (final source in sourceIndex['sources'] as List) {
    final path = source['path'] as String;
    if (frozenHashes.containsKey(path)) {
      throw const FormatException('Duplicate frozen source');
    }
    frozenHashes[path] = source['sha256'] as String;
    if (!path.startsWith('tiles/')) {
      required('evidence/$path');
      if (outputs['evidence/$path'] != source['sha256']) {
        throw FormatException(
          'Bundled evidence differs from frozen source: $path',
        );
      }
    }
  }
  if (frozenHashes['calibration.json'] !=
      outputs['evidence/calibration.json']) {
    throw const FormatException(
      'Calibration is not hash-locked frozen evidence',
    );
  }
  final calibration = await _readJson(candidate, 'evidence/calibration.json');
  if (calibration['schemaVersion'] != 1 || calibration['maps'] is! List) {
    throw const FormatException('Unsupported frozen calibration');
  }
  final calibratedMaps = (calibration['maps'] as List)
      .cast<Map<String, dynamic>>();
  final calibrationsBySource = <String, Map<String, dynamic>>{
    for (final map in calibratedMaps) map['sourceKey'] as String: map,
  };
  if (calibratedMaps.length != maps.length ||
      calibrationsBySource.length != maps.length) {
    throw const FormatException('Frozen calibration lost or duplicated maps');
  }
  final sourceMetadata = jsonDecode(
    await packFile(candidate, 'evidence/metadata/maps.json').readAsString(),
  ) as List;
  final sourceMarkers = await _readJson(
    candidate,
    'evidence/markers/maps.json',
  );
  final decodedTiles = <String, PngInspection>{};
  final translations =
      (await _readJson(candidate, 'evidence/markers/maps_en.json'))['data']
          as Map<String, dynamic>;
  for (final map in maps) {
    final expected = calibrationsBySource[map['sourceKey']];
    if (expected == null ||
        map['id'] != expected['id'] ||
        map['kind'] != expected['kind'] ||
        canonicalJson(map['geometry']) != canonicalJson(expected['geometry']) ||
        canonicalJson(map['artworkFrame']) !=
            canonicalJson(expected['artworkFrame'])) {
      throw const FormatException(
        'Candidate frame identity/calibration changed',
      );
    }
    if (canonicalJson(map['markers']) !=
        canonicalJson(prepareMarkers(sourceMarkers, translations, expected))) {
      throw const FormatException(
        'Markers differ from independently frozen source',
      );
    }
    final floors = (map['floors'] as List).cast<Map<String, dynamic>>();
    final expectedFloors = reconcileFloors(
      expected,
      interactiveMetadata(sourceMetadata, map['sourceKey'] as String),
    );
    if (floors.length != expectedFloors.length) {
      throw const FormatException('Candidate lost floor families');
    }
    if (map['kind'] == 'vector') {
      const sourcePath = 'evidence/$vectorSourcePath';
      required(sourcePath);
      final source = await packFile(candidate, sourcePath).readAsString();
      if (canonicalJson(map['artworkFrame']) !=
              canonicalJson(expected['artworkFrame']) ||
          canonicalJson(svgFrame(source)) !=
              canonicalJson(expected['artworkFrame'])) {
        throw const FormatException(
          'Vector artwork frame differs from frozen source/calibration',
        );
      }
      final layerIds = {
        for (final floor in expectedFloors) ..._floorComponents(floor),
      };
      final sourceOrder = svgLayerOrder(source, layerIds);
      if (canonicalJson(map['layerOrder']) != canonicalJson(sourceOrder)) {
        throw const FormatException(
          'Vector global stacking differs from frozen source',
        );
      }
    }
    for (var i = 0; i < floors.length; i++) {
      final floor = floors[i];
      final metadata = Map<String, dynamic>.from(floor)..remove('artwork');
      if (canonicalJson(metadata) != canonicalJson(expectedFloors[i])) {
        throw const FormatException('Candidate changed local floor metadata');
      }
      final art = floor['artwork'] as Map<String, dynamic>;
      if (map['kind'] == 'vector') {
        final components = (art['components'] as List)
            .cast<Map<String, dynamic>>();
        final ids = _floorComponents(expectedFloors[i]);
        if (canonicalJson(components.map((c) => c['id']).toList()) !=
            canonicalJson(ids)) {
          throw const FormatException(
            'Vector component attachment/order mismatch',
          );
        }
        for (final component in components) {
          final componentRoot = 'artwork/${map['id']}/${component['id']}';
          if (component['sourceSvg'] != '$componentRoot.svg' ||
              component['compilerSvg'] != '$componentRoot.compiler.svg' ||
              component['path'] != '$componentRoot.vec' ||
              component['type'] != 'vector') {
            throw const FormatException(
              'Vector component paths differ from canonical identity',
            );
          }
          required(component['sourceSvg'] as String);
          required(component['compilerSvg'] as String);
          final normalized = await packFile(
            candidate,
            component['sourceSvg'] as String,
          ).readAsString();
          final source = await packFile(
            candidate,
            'evidence/$vectorSourcePath',
          ).readAsString();
          if (normalized !=
              normalizeSvgFloor(source, {
                component['id'] as String,
              }, _vectorSelectionIds(expectedFloors))) {
            throw const FormatException(
              'Vector component differs from dependency-closed frozen source',
            );
          }
          final transferred = compilerSvg(
            normalized,
            component['id'] as String,
          );
          if (canonicalJson(component['effects']) !=
                  canonicalJson(transferred.effects) ||
              await packFile(
                    candidate,
                    component['compilerSvg'] as String,
                  ).readAsString() !=
                  transferred.xml) {
            throw const FormatException(
              'Vector native effect/source closure mismatch',
            );
          }
          if (requireCompiled || manifest['vectorsCompiled'] == true) {
            final path = component['path'] as String;
            required(path);
            if (manifest['compilerVersion'] != '1.3.0' ||
                outputs[path] !=
                    _expectedVectorHash(
                      transferred.xml,
                      component['compilerSvg'] as String,
                    )) {
              throw const FormatException(
                'Vector payload differs from pinned source compilation',
              );
            }
          }
        }
      } else {
        final inventory = art['tiles'] as List;
        if (inventory.length != 256) {
          throw const FormatException('Raster floor requires full z4 grid');
        }
        final coordinates = <String>{};
        var visible = false;
        for (final tile in inventory) {
          final x = tile['x'] as int, y = tile['y'] as int;
          if (x < 0 || x > 15 || y < 0 || y > 15 || !coordinates.add('$x/$y')) {
            throw const FormatException('Invalid raster tile closure');
          }
          final rawPath = rawTilePath(
            map['id'] as String,
            floor['id'] as String,
            x,
            y,
          );
          final sourceHash = frozenHashes[rawPath];
          if (sourceHash == null ||
              tile['sourcePath'] != rawPath ||
              tile['sourceSha256'] != sourceHash) {
            throw const FormatException(
              'Raster tile differs from frozen source inventory',
            );
          }
          if (tile['empty'] is! bool) {
            throw const FormatException('Invalid alpha-empty tile record');
          }
          final empty = tile['empty'] as bool;
          if (empty && (tile['path'] != null || tile['alphaBounds'] != null)) {
            throw const FormatException('Invalid alpha-empty tile record');
          }
          final path = empty
              ? _emptyTileWitnessPath(sourceHash)
              : tile['path'] as String;
          required(path);
          if (outputs[path] != sourceHash) {
            throw const FormatException(
              'Raster witness differs from frozen source identity',
            );
          }
          var decoded = decodedTiles[sourceHash];
          if (decoded == null) {
            decoded = inspectPng(await packFile(candidate, path).readAsBytes());
            decodedTiles[sourceHash] = decoded;
          }
          if (decoded.empty != empty ||
              (!empty &&
                  canonicalJson(tile['alphaBounds']) !=
                      canonicalJson([
                        decoded.left,
                        decoded.top,
                        decoded.right,
                        decoded.bottom,
                      ]))) {
            throw const FormatException(
              'Raster decoded/source closure mismatch',
            );
          }
          if (!empty) visible = true;
        }
        if (!visible) {
          throw const FormatException('Raster floor has no artwork');
        }
      }
    }
    final markers = map['markers'] as List;
    if (markers.isEmpty) {
      throw FormatException('Missing source markers for ${map['id']}');
    }
    final ids = <String>{};
    for (final marker in markers) {
      if (!ids.add(marker['id'] as String)) {
        throw const FormatException('Duplicate marker identity');
      }
      final position = marker['position'] as Map;
      for (final key in ['x', 'z']) {
        if (position[key] is! num || !(position[key] as num).isFinite) {
          throw const FormatException('Invalid source marker position');
        }
      }
      if (position['height'] != null &&
          (position['height'] is! num ||
              !(position['height'] as num).isFinite)) {
        throw const FormatException('Invalid source marker height');
      }
    }
    final frame = map['artworkFrame'] as Map;
    final crop = map['displayCrop'] as Map;
    if (!(frame['width'] as num).isFinite ||
        !(frame['height'] as num).isFinite ||
        (frame['width'] as num) <= 0 ||
        (frame['height'] as num) <= 0 ||
        !(crop['left'] as num).isFinite ||
        !(crop['top'] as num).isFinite ||
        !(crop['right'] as num).isFinite ||
        !(crop['bottom'] as num).isFinite ||
        crop['left'] < 0 ||
        crop['top'] < 0 ||
        crop['right'] <= crop['left'] ||
        crop['bottom'] <= crop['top'] ||
        crop['right'] > frame['width'] ||
        crop['bottom'] > frame['height']) {
      throw const FormatException('Invalid artwork frame/crop');
    }
  }
  return manifest;
}

List<Map<String, Object?>> prepareMarkers(
  Map<String, dynamic> snapshot,
  Map<String, dynamic> translations,
  Map<String, Object?> calibration,
) {
  final sourceKey = calibration['sourceKey'] as String;
  final data = snapshot['data'] as Map<String, dynamic>;
  final source = (data['maps'] as Map<String, dynamic>).values
      .cast<Map<String, dynamic>>()
      .singleWhere((m) => m['normalizedName'] == sourceKey);
  final floorAssignments =
      calibration['markerFloorAssignments'] as Map<String, Object?>? ??
      const <String, Object?>{};
  final result = <Map<String, Object?>>[];
  final identityCounts = <String, int>{};
  void add(
    String category,
    Map<String, dynamic> entry,
    String sourcePath, {
    String? label,
  }) {
    final p = entry['position'];
    if (p is! Map || p['x'] is! num || p['z'] is! num) {
      throw FormatException(
        'Missing real marker coordinates $sourceKey/$sourcePath',
      );
    }
    final name =
        label ??
        entry['name'] ??
        entry['zoneName'] ??
        entry['hazardType'] ??
        category;
    final identity =
        '$category:${entry['id'] ?? _hash(utf8.encode('$sourceKey/${canonicalJson(entry)}')).substring(0, 20)}';
    final occurrence = identityCounts.update(
      identity,
      (count) => count + 1,
      ifAbsent: () => 0,
    );
    final markerId = '$identity:$occurrence';
    final floorAssignment = floorAssignments[markerId] as Map<String, Object?>?;
    final reviewedVolume = floorAssignment?['sourceVolume'];
    if (reviewedVolume != null &&
        canonicalJson(reviewedVolume) !=
            canonicalJson({
              'position': p,
              'heightBand': [entry['bottom'], entry['top']],
              'outline': entry['outline'],
            })) {
      throw FormatException(
        'Reviewed marker ownership volume changed: $sourceKey/$markerId',
      );
    }
    result.add({
      'id': markerId,
      'category': category,
      'name': translations[name] ?? name,
      'position': {'x': p['x'], 'z': p['z'], 'height': p['y']},
      if (floorAssignment != null) 'floorId': floorAssignment['floorId'],
      'source': {
        'url': markerUrl,
        'mapId': source['id'],
        'path': sourcePath,
        'floorAssignment': ?floorAssignment,
      },
      'details': entry,
      if (entry['outline'] is List)
        'outline': [
          for (final point in entry['outline'] as List)
            {'x': point['x'], 'z': point['z'], 'height': point['y']},
        ],
      if (entry['bottom'] is num && entry['top'] is num)
        'heightBand': [entry['bottom'], entry['top']],
    });
  }

  for (final category in [
    'extracts',
    'transits',
    'spawns',
    'locks',
    'hazards',
    'lootContainers',
    'lootLoose',
    'switches',
    'stationaryWeapons',
    'btrStops',
  ]) {
    final entries = source[category] as List? ?? [];
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i] as Map<String, dynamic>;
      String? label;
      if (category == 'lootContainers') {
        label =
            (data['lootContainers'] as Map)[entry['lootContainer']]?['name']
                as String?;
      }
      if (category == 'stationaryWeapons') {
        label =
            (data['stationaryWeapons']
                    as Map)[entry['stationaryWeapon']]?['name']
                as String?;
      }
      add(
        category,
        category == 'btrStops'
            ? {
                ...entry,
                'position': {'x': entry['x'], 'y': entry['y'], 'z': entry['z']},
              }
            : entry,
        '$category/$i',
        label: label,
      );
    }
  }
  for (var b = 0; b < (source['bosses'] as List).length; b++) {
    final boss = source['bosses'][b];
    final label = (data['mobs'] as Map)[boss['mob']]['name'] as String;
    for (var l = 0; l < (boss['spawnLocations'] as List).length; l++) {
      final location = boss['spawnLocations'][l];
      for (var p = 0; p < (location['positions'] as List).length; p++) {
        add(
          'bosses',
          {
            'position': location['positions'][p],
            'mob': boss['mob'],
            'spawnChance': boss['spawnChance'],
            'location': location['name'],
          },
          'bosses/$b/spawnLocations/$l/positions/$p',
          label: label,
        );
      }
    }
  }
  return result;
}

/// Produces complete non-recursive Flutter asset declarations for one version.
Future<List<String>> preparedAssetDirectories(Directory packs) async {
  final pointer = await _readJson(packs, 'active.json');
  final version = pointer['version'];
  if (pointer['schemaVersion'] != 1 ||
      version is! String ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(version) ||
      pointer['manifest'] != 'versions/$version/manifest.json') {
    throw const FormatException('Invalid prepared active pointer');
  }
  final prefix = 'versions/$version/';
  final manifest = await validateCandidate(Directory('${packs.path}/$prefix'));
  final directories = <String>{'', prefix};
  for (final output in manifest['outputs'] as List) {
    final path = output['path'] as String;
    final separator = path.lastIndexOf('/');
    if (separator >= 0) {
      directories.add('$prefix${path.substring(0, separator + 1)}');
    }
  }
  return directories.toList()..sort();
}

/// Copies and validates the entire immutable version before atomic publication.
/// Interrupted copying or pointer replacement cannot expose mixed map assets.
Future<String> promoteCandidate(Directory candidate, Directory packs) async {
  await validateCandidate(candidate);
  final manifestBytes = await packFile(
    candidate,
    'manifest.json',
  ).readAsBytes();
  final version = _hash(manifestBytes);
  final destination = Directory('${packs.path}/versions/$version');
  if (!await destination.exists()) {
    final staging = Directory('${packs.path}/versions/.$version.staging');
    if (await staging.exists()) {
      throw const FormatException(
        'Interrupted staging directory requires explicit inspection/removal',
      );
    }
    await staging.create(recursive: true);
    await for (final entity in candidate.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is Link) {
        throw const FormatException('Pack promotion forbids symlinks');
      }
      if (entity is File) {
        final relative = entity.path
            .substring(candidate.path.length + 1)
            .replaceAll('\\', '/');
        await _write(staging, relative, await entity.readAsBytes());
      }
    }
    await validateCandidate(staging);
    await staging.rename(destination.path);
  } else {
    await validateCandidate(destination);
  }
  // Same-directory rename replaces the old single-file pointer. Readers resolve
  // the immutable version once, never mix a pointer with mutable per-map files.
  final pointer = File('${packs.path}/active.json');
  final next = File('${packs.path}/active.next.json');
  if (await next.exists()) {
    throw const FormatException(
      'Interrupted active pointer requires explicit inspection/removal',
    );
  }
  await next.writeAsString(
    canonicalJson({
      'schemaVersion': 1,
      'version': version,
      'manifest': 'versions/$version/manifest.json',
    }),
    flush: true,
  );
  await next.rename(pointer.path);
  return version;
}

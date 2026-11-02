import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as image;
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart'
    as vector;
import 'package:yaml/yaml.dart';

import 'calibration.dart';
import 'quest_markers.dart';
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

/// Cache of compiler-input hash to payload hash for this process.
///
/// Only [_expectedVectorHash] fills it, with the real encoder, so an injected
/// [VectorEncoder] can never supply an expected hash to validation.
final _compiledVectorHashes = <String, String>{};

/// Compiles SVG [xml] into a vector payload, named [debugName] in diagnostics.
typedef VectorEncoder = Uint8List Function(String xml, String debugName);

/// The packages whose resolved versions a pack records as its `toolchain`.
const toolchainPackages = [
  'xml',
  'image',
  'vector_graphics_compiler',
  'vector_graphics',
  'vector_graphics_codec',
];

/// Returns the resolved version of each [toolchainPackages] entry in a
/// `pubspec.lock` text.
///
/// Throws a [FormatException] naming the first package the lock does not
/// resolve.
Map<String, String> toolchainFromLock(String lockYaml) {
  final packages = switch (loadYaml(lockYaml)) {
    YamlMap(:final nodes) => nodes['packages']?.value,
    _ => null,
  };
  return {
    for (final name in toolchainPackages)
      name: switch (packages) {
        YamlMap(:final nodes) => switch (nodes[name]?.value) {
          YamlMap(:final nodes) when nodes['version']?.value is String =>
            nodes['version']!.value as String,
          _ => throw FormatException('pubspec.lock does not resolve $name'),
        },
        _ => throw FormatException('pubspec.lock does not resolve $name'),
      },
  };
}

const _vectorMagic = [0x62, 0x2d, 0x88, 0x00];

/// Returns the codec format number in the header of a compiled vector payload.
///
/// The header is the magic bytes `62 2d 88 00` followed by one format byte.
/// Throws a [FormatException] naming [path] when [bytes] is shorter than five
/// bytes or does not start with the magic number.
int vectorPayloadFormat(Uint8List bytes, String path) {
  if (bytes.length < 5) {
    throw FormatException('Vector payload $path is too short for a header');
  }
  for (var i = 0; i < _vectorMagic.length; i++) {
    if (bytes[i] != _vectorMagic[i]) {
      throw FormatException('Vector payload $path lacks the vector magic');
    }
  }
  return bytes[4];
}

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
  // Every source needs one real compilation per process, never a hash supplied
  // by the candidate. Cache only small identities, not SVG strings or buffers.
  return _compiledVectorHashes.putIfAbsent(
    sourceHash,
    () => _hash(_encodeVector(xml, debugName)),
  );
}

String _emptyTileWitnessPath(String sourceHash) =>
    'evidence/tile-alpha/$sourceHash.png';

class FrozenInputs {
  FrozenInputs._(this.root, this.index, this._paths);
  final Directory root;
  final Map<String, dynamic> index;
  final Set<String> _paths;
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
    return FrozenInputs._(root, index, paths);
  }

  Future<Uint8List> bytes(String path) async {
    if (!_paths.contains(path)) {
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
    for (final resource in const {
      'quests/tasks.json': 'https://json.tarkov.dev/regular/tasks',
      'quests/tasks_en.json': 'https://json.tarkov.dev/regular/tasks_en',
      'quests/traders.json': 'https://json.tarkov.dev/regular/traders',
      'quests/traders_en.json': 'https://json.tarkov.dev/regular/traders_en',
    }.entries) {
      await fetch(resource.key, resource.value);
    }
    await fetch('markers/maps_en.json', '${markerUrl}_en');
    await fetch(vectorSourcePath, vectorSourceUrl);
    sources.last.addAll({
      'repositoryUrl': '$vectorSourceRoot/Interchange.svg',
      'repositoryRevision': vectorSourceRevision,
      'gitBlobSha1': vectorSourceBlob,
    });
    for (final entry in additionalVectorSources.entries) {
      final filename = entry.value['file']!;
      final path = '${entry.key}/$filename';
      // Pin immutable publisher bytes rather than relying on mutable CDN
      // caching. The selected served rendition was independently observed.
      await fetch(path, '$vectorSourceRoot/$filename');
      sources.last.addAll({
        'servedUrl': 'https://assets.tarkov.dev/maps/svg/$filename',
        'repositoryRevision': vectorSourceRevision,
        'termsPaths': ['terms/svg-maps-README.md', 'terms/svg-maps-LICENSE.md'],
        'privateUse': 'user-directed-private-implementation',
        'publicRedistribution': 'not-owner-cleared',
      });
    }
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
      for (final key in supportedMapSources.values) calibrationFor(key),
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
      final resources = [
        for (final floor in floors)
          if (floor['sourceTileUrl'] != null) floor,
        for (final dependency in (local['rasterDependencies'] as List? ?? []))
          {
            ...Map<String, Object?>.from(dependency as Map),
            'id': 'dependency-${dependency['id']}',
          },
      ];
      for (final floor in resources) {
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

/// Rebuilds a candidate pack offline from the frozen raw generation [raw].
///
/// The manifest records [toolchain] as the versions that built it. With
/// [compileVectors], every vector is compiled twice through [encode] and the
/// manifest records the payload format as `vectorCodecFormat`; without it the
/// candidate has no `.vec` files and no format record.
Future<Map<String, dynamic>> rebuildCandidate(
  Directory raw,
  Directory candidate, {
  required Map<String, String> toolchain,
  bool compileVectors = true,
  VectorEncoder encode = _encodeVector,
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
  final questSources = <String, Map<String, dynamic>>{
    for (final path in const [
      'quests/tasks.json',
      'quests/tasks_en.json',
      'quests/traders.json',
      'quests/traders_en.json',
    ])
      path: jsonDecode(await frozen.text(path)) as Map<String, dynamic>,
  };
  _requireMapInventory(
    (calibration['maps'] as List).cast<Map>(),
    supportedMapSources.keys.toSet(),
  );
  final maps = <Map<String, Object?>>[];
  final emptyTileWitnesses = <String>{};
  final decodedTiles = <String, PngInspection>{};
  final vectorPaths = <String>[];
  await candidate.create(recursive: true);
  for (final untyped in calibration['maps'] as List) {
    final local = Map<String, Object?>.from(untyped as Map);
    final sourceKey = local['sourceKey'] as String;
    _validateCalibration(local);
    final upstream = interactiveMetadata(metadata, sourceKey);
    _validateMetadataCalibration(local, upstream);
    final floors = reconcileFloors(local, upstream);
    final mapId = local['id'] as String;
    var crop = <num>[
      double.infinity,
      double.infinity,
      double.negativeInfinity,
      double.negativeInfinity,
    ];
    if (local['kind'] == 'vector') {
      final source = await frozen.text(
        local['sourceSvgPath'] as String? ?? vectorSourcePath,
      );
      if (canonicalJson(svgFrame(source)) !=
          canonicalJson(local['artworkFrame'])) {
        throw const FormatException(
          'Vector source frame differs from locked calibration',
        );
      }
      final svgFloors = _svgFloors(floors);
      validateSvgFloorInventory(source, svgFloors);
      final allFloors = _vectorSelectionIds(svgFloors);
      final componentIds = {
        for (final floor in svgFloors) ..._floorComponents(floor),
      };
      final sourceOrder = svgLayerOrder(source, componentIds);
      // Attached base content can interleave with selectable overlays.
      // Preserve the global DOM order, not just the order inside each floor.
      local['layerOrder'] = sourceOrder;
      for (final floor in floors) {
        if (_isRasterOverlay(floor)) {
          // A tile-only floor drawn over the SVG, as tarkov.dev's Abstract
          // view does. Its tiles keep their own frame; the runtime places
          // them through the shared game-coordinate transform.
          floor['artwork'] = {
            'tiles': await _prepareFloorTiles(
              frozen,
              candidate,
              mapId,
              floor['id'] as String,
              emptyTileWitnesses,
              decodedTiles,
              (x, y, decoded) {},
            ),
          };
          continue;
        }
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
            await compileVector(
              candidate,
              compilerPath,
              vectorPath,
              encode: encode,
            );
            vectorPaths.add(vectorPath);
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
        floor['artwork'] = {
          'tiles': await _prepareFloorTiles(
            frozen,
            candidate,
            mapId,
            floor['id'] as String,
            emptyTileWitnesses,
            decodedTiles,
            (x, y, decoded) {
              crop = [
                math.min(crop[0], x * stride + decoded.left / 256 * extent),
                math.min(crop[1], y * stride + decoded.top / 256 * extent),
                math.max(crop[2], x * stride + decoded.right / 256 * extent),
                math.max(crop[3], y * stride + decoded.bottom / 256 * extent),
              ];
            },
          ),
        };
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
    final dependencies = <Map<String, Object?>>[];
    for (final rawDependency in (local['rasterDependencies'] as List? ?? [])) {
      final dependency = Map<String, Object?>.from(rawDependency as Map);
      dependency['artwork'] = await _prepareDependencyGrid(
        frozen,
        candidate,
        mapId,
        dependency['id'] as String,
        emptyTileWitnesses,
        decodedTiles,
      );
      dependencies.add(dependency);
    }
    if (local.containsKey('rasterDependencies')) {
      local['rasterDependencies'] = dependencies;
    }
    local['floors'] = floors;
    local['markers'] = [
      ...prepareMarkers(markerSnapshot, translations, local),
      ..._prepareFrozenQuests(questSources, markerSnapshot, local),
    ];
    local['attribution'] = {
      'author': upstream['author'],
      'authorLink': upstream['authorLink'],
      'sourceKey': sourceKey,
      'termsStatus': local['kind'] == 'vector'
          ? 'CC-BY-NC-SA-4.0-with-published-README-restrictions'
          : 'published-credit-evidence-no-owner-clearance-asserted',
      if (local['kind'] == 'vector' && floors.any(_isRasterOverlay))
        'rasterOverlayTermsStatus':
            'published-credit-evidence-no-owner-clearance-asserted',
      if (local['kind'] == 'vector')
        'artworkSource': {
          ...Map<String, Object?>.from(
            (frozen.index['sources'] as List).singleWhere(
              (s) =>
                  s['path'] ==
                  (local['sourceSvgPath'] as String? ?? vectorSourcePath),
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
    'preparationVersion': 3,
    'supportedMapIds': supportedMapSources.keys.toList(),
    'sourceGeneration': _hash(utf8.encode(canonicalJson(frozen.index))),
    'sourceLock': {
      'vectorSourceRevision': vectorSourceRevision,
      'vectorSourceUrl': vectorSourceUrl,
      'vectorSourceBlob': vectorSourceBlob,
      'metadataRepositoryRevision': metadataRepositoryRevision,
      'metadataBlob': metadataBlob,
      'primaryHashes': primarySourceHashes,
    },
    'toolchain': toolchain,
    if (compileVectors)
      'vectorCodecFormat': await _compiledVectorFormat(candidate, vectorPaths),
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

void _requireMapInventory(List<Map> maps, Set<String> expected) {
  final ids = maps.map((map) => map['id']).toSet();
  if (maps.length != expected.length ||
      ids.length != expected.length ||
      !ids.containsAll(expected)) {
    throw FormatException(
      'Candidate requires exact supported map inventory; '
      'missing ${expected.difference(ids)}, unexpected ${ids.difference(expected)}',
    );
  }
}

List<Map<String, Object?>> _prepareFrozenQuests(
  Map<String, Map<String, dynamic>> sources,
  Map<String, dynamic> markerSnapshot,
  Map<String, Object?> local,
) {
  final maps = (markerSnapshot['data'] as Map)['maps'] as Map;
  final source = maps.values.cast<Map>().singleWhere(
    (map) => map['normalizedName'] == local['sourceKey'],
  );
  final taskData = sources['quests/tasks.json']!['data'] as Map;
  return prepareQuestMarkers(
    mapId: source['id'] as String,
    tasks: Map<String, dynamic>.from(taskData['tasks'] as Map),
    questItems: Map<String, dynamic>.from(taskData['questItems'] as Map),
    translations: Map<String, dynamic>.from(
      sources['quests/tasks_en.json']!['data'] as Map,
    ),
    questItemTranslations: Map<String, dynamic>.from(
      sources['quests/tasks_en.json']!['data'] as Map,
    ),
    traders: Map<String, dynamic>.from(
      sources['quests/traders.json']!['data'] as Map,
    ),
    traderTranslations: Map<String, dynamic>.from(
      sources['quests/traders_en.json']!['data'] as Map,
    ),
  );
}

Future<List<Map<String, Object?>>> _prepareFloorTiles(
  FrozenInputs frozen,
  Directory candidate,
  String mapId,
  String floorId,
  Set<String> emptyTileWitnesses,
  Map<String, PngInspection> decodedTiles,
  void Function(int x, int y, PngInspection decoded) onVisible,
) async {
  final inventory = <Map<String, Object?>>[];
  for (var x = 0; x < 16; x++) {
    for (var y = 0; y < 16; y++) {
      final path = rawTilePath(mapId, floorId, x, y);
      final bytes = await frozen.bytes(path);
      final sourceHash = _hash(bytes);
      final decoded = decodedTiles.putIfAbsent(
        sourceHash,
        () => inspectPng(bytes),
      );
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
        final output = 'artwork/$mapId/$floorId/$x/$y.png';
        await _write(candidate, output, bytes);
        tile['path'] = output;
        tile['alphaBounds'] = [
          decoded.left,
          decoded.top,
          decoded.right,
          decoded.bottom,
        ];
        onVisible(x, y, decoded);
      }
      inventory.add(tile);
    }
  }
  if (inventory.every((t) => t['empty'] == true)) {
    throw FormatException('Required floor $floorId has no decoded artwork');
  }
  return inventory;
}

/// A vector map's floor that exists only as published tiles.
bool _isRasterOverlay(Map floor) => floor['sourceTileUrl'] != null;

List<Map<String, Object?>> _svgFloors(List<Map<String, Object?>> floors) => [
  for (final floor in floors)
    if (!_isRasterOverlay(floor)) floor,
];

Future<Map<String, Object?>> _prepareDependencyGrid(
  FrozenInputs frozen,
  Directory candidate,
  String mapId,
  String dependencyId,
  Set<String> emptyWitnesses,
  Map<String, PngInspection> decodedTiles,
) async {
  final inventory = <Map<String, Object?>>[];
  for (var x = 0; x < 16; x++) {
    for (var y = 0; y < 16; y++) {
      final path = rawTilePath(mapId, 'dependency-$dependencyId', x, y);
      final bytes = await frozen.bytes(path);
      final hash = _hash(bytes);
      final decoded = decodedTiles.putIfAbsent(hash, () => inspectPng(bytes));
      if (decoded.empty && emptyWitnesses.add(hash)) {
        await _write(candidate, _emptyTileWitnessPath(hash), bytes);
      }
      final tile = <String, Object?>{
        'x': x,
        'y': y,
        'empty': decoded.empty,
        'sourcePath': path,
        'sourceSha256': hash,
      };
      if (!decoded.empty) {
        final output = 'artwork/dependencies/$mapId/$dependencyId/$x/$y.png';
        await _write(candidate, output, bytes);
        tile['path'] = output;
        tile['alphaBounds'] = [
          decoded.left,
          decoded.top,
          decoded.right,
          decoded.bottom,
        ];
      }
      inventory.add(tile);
    }
  }
  if (inventory.every((tile) => tile['empty'] == true)) {
    throw FormatException(
      'Required raster dependency $mapId/$dependencyId has no artwork',
    );
  }
  return {'tiles': inventory};
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

void _validateMetadataCalibration(
  Map<String, Object?> local,
  Map<String, dynamic> upstream,
) {
  final geometry = local['geometry'] as Map;
  final evidence = local['calibrationEvidence'] as Map?;
  String numbers(Object? value) {
    if (value is List) return '[${value.map(numbers).join(',')}]';
    if (value is! num || !value.isFinite) {
      throw const FormatException('Missing finite source calibration numbers');
    }
    return value.toDouble().toString();
  }

  final bounds = local['kind'] == 'vector'
      ? upstream['svgBounds'] ?? upstream['bounds']
      : upstream['bounds'];
  if (geometry['legacyPinBounds'] != null &&
      numbers(geometry['legacyPinBounds']) !=
          numbers(upstream['svgBounds'] ?? upstream['bounds'])) {
    throw FormatException(
      'Frozen original legacy pin basis changed for ${local['id']}',
    );
  }
  if (upstream['coordinateRotation'] != geometry['rotation'] ||
      numbers(upstream['transform']) !=
          numbers(evidence?['sourceAffine'] ?? geometry['affine']) ||
      numbers(bounds) != numbers(geometry['bounds'])) {
    throw FormatException(
      'Frozen metadata calibration changed for ${local['id']}',
    );
  }
}

/// Compiles the SVG at [input] under [root] into the payload at [output].
///
/// The input is encoded twice through [encode]. Throws a [FormatException]
/// naming [output], without writing it, when the two payloads differ in any
/// byte.
Future<void> compileVector(
  Directory root,
  String input,
  String output, {
  VectorEncoder encode = _encodeVector,
}) async {
  final xml = await packFile(root, input).readAsString();
  final bytes = encode(xml, input);
  final again = encode(xml, input);
  if (bytes.length != again.length ||
      Iterable<int>.generate(bytes.length).any((i) => bytes[i] != again[i])) {
    throw FormatException(
      'Vector compiler output is not deterministic: $output',
    );
  }
  await _write(root, output, bytes);
}

/// Reads the header of every payload in [paths] and returns their shared
/// format, or throws a [FormatException] when they disagree or none exist.
Future<int> _compiledVectorFormat(Directory root, List<String> paths) async {
  final formats = <int>{
    for (final path in paths)
      vectorPayloadFormat(await packFile(root, path).readAsBytes(), path),
  };
  return switch (formats.toList()) {
    [final format] => format,
    [] => throw const FormatException('No compiled vector payloads'),
    _ => throw FormatException('Vector payload formats differ: $formats'),
  };
}

/// Optional separate adapter: raw inputs and normalized scenes do not change.
///
/// Replaces the manifest's `toolchain` with [toolchain], the versions that
/// compile the vectors, and records `vectorCodecFormat`. Manifest publication
/// is last, so interrupted compilation remains unpromotable.
Future<void> compileCandidate(
  Directory candidate, {
  required Map<String, String> toolchain,
  VectorEncoder encode = _encodeVector,
}) async {
  final manifest = await validateCandidate(candidate, requireCompiled: false);
  if (manifest['vectorsCompiled'] == true) {
    throw const FormatException('Candidate is already compiled');
  }
  final vectorPaths = <String>[];
  for (final map in manifest['maps'] as List) {
    if (map['kind'] != 'vector') continue;
    for (final floor in map['floors'] as List) {
      if (_isRasterOverlay(floor as Map)) continue;
      for (final component in floor['artwork']['components'] as List) {
        final path = component['path'] as String;
        await compileVector(
          candidate,
          component['compilerSvg'] as String,
          path,
          encode: encode,
        );
        vectorPaths.add(path);
      }
    }
  }
  manifest['toolchain'] = toolchain;
  manifest['vectorCodecFormat'] = await _compiledVectorFormat(
    candidate,
    vectorPaths,
  );
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
    packFile(candidate, path);
    outputs[path] = entry['sha256'] as String;
  }
  // Enumerate independently of the manifest and hash each actual output once.
  // This inventory belongs to this validation only, not another pack boundary.
  final actual = await _outputHashes(candidate);
  final actualHashes = {
    for (final entry in actual)
      entry['path'] as String: entry['sha256'] as String,
  };
  for (final entry in outputs.entries) {
    final actualHash = actualHashes[entry.key];
    if (actualHash == null) {
      // Preserve a filesystem error for a missing listed file without reading
      // or hashing it again. Existing excluded files still fail output closure.
      await packFile(candidate, entry.key).length();
      throw const FormatException(
        'Candidate contains untracked or missing output bytes',
      );
    }
    if (actualHash != entry.value) {
      throw FormatException('Candidate output hash mismatch: ${entry.key}');
    }
  }
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
  final version = manifest['preparationVersion'];
  if (version != 3) {
    throw FormatException('Unsupported preparation version $version');
  }
  _requireMapInventory(maps, supportedMapSources.keys.toSet());
  if (maps.any((map) => map['sourceKey'] != supportedMapSources[map['id']])) {
    throw const FormatException('Candidate source identity contract changed');
  }
  if (canonicalJson(manifest['supportedMapIds']) !=
      canonicalJson(supportedMapSources.keys.toList())) {
    throw const FormatException(
      'Candidate supported identity contract changed',
    );
  }
  for (final path in const [
    'quests/tasks.json',
    'quests/tasks_en.json',
    'quests/traders.json',
    'quests/traders_en.json',
  ]) {
    required('evidence/$path');
  }
  final compiled = requireCompiled || manifest['vectorsCompiled'] == true;
  final recordedFormat = manifest['vectorCodecFormat'];
  if (compiled && recordedFormat is! int) {
    throw const FormatException('Pack vector format is not recorded');
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
  final questSources = <String, Map<String, dynamic>>{
    for (final path in const [
      'quests/tasks.json',
      'quests/tasks_en.json',
      'quests/traders.json',
      'quests/traders_en.json',
    ])
      path: await _readJson(candidate, 'evidence/$path'),
  };
  for (final map in maps) {
    final expected = calibrationsBySource[map['sourceKey']];
    if (expected == null ||
        map['id'] != expected['id'] ||
        map['kind'] != expected['kind'] ||
        map['sourceSvgPath'] != expected['sourceSvgPath'] ||
        canonicalJson(map['geometry']) != canonicalJson(expected['geometry']) ||
        canonicalJson(map['artworkFrame']) !=
            canonicalJson(expected['artworkFrame'])) {
      throw const FormatException(
        'Candidate frame identity/calibration changed',
      );
    }
    if (canonicalJson(map['markers']) !=
        canonicalJson([
          ...prepareMarkers(sourceMarkers, translations, expected),
          ..._prepareFrozenQuests(questSources, sourceMarkers, expected),
        ])) {
      throw const FormatException(
        'Markers differ from independently frozen source',
      );
    }
    final floors = (map['floors'] as List).cast<Map<String, dynamic>>();
    final upstream = interactiveMetadata(
      sourceMetadata,
      map['sourceKey'] as String,
    );
    _validateMetadataCalibration(expected, upstream);
    final expectedFloors = reconcileFloors(expected, upstream);
    if (floors.length != expectedFloors.length) {
      throw const FormatException('Candidate lost floor families');
    }
    if (map['kind'] == 'vector') {
      final sourcePath =
          'evidence/${expected['sourceSvgPath'] as String? ?? vectorSourcePath}';
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
      validateSvgFloorInventory(source, _svgFloors(expectedFloors));
      final layerIds = {
        for (final floor in _svgFloors(expectedFloors))
          ..._floorComponents(floor),
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
      if (map['kind'] == 'vector' && !_isRasterOverlay(expectedFloors[i])) {
        final components = (art['components'] as List)
            .cast<Map<String, dynamic>>();
        final ids = (map['layerOrder'] as List)
            .where(_floorComponents(expectedFloors[i]).contains)
            .toList();
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
            'evidence/${expected['sourceSvgPath'] as String? ?? vectorSourcePath}',
          ).readAsString();
          if (normalized !=
              normalizeSvgFloor(source, {
                component['id'] as String,
              }, _vectorSelectionIds(_svgFloors(expectedFloors)))) {
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
          if (compiled) {
            final path = component['path'] as String;
            required(path);
            final payloadFormat = vectorPayloadFormat(
              await packFile(candidate, path).readAsBytes(),
              path,
            );
            if (payloadFormat != recordedFormat) {
              throw FormatException(
                'Vector payload $path has format $payloadFormat but the '
                'pack records format $recordedFormat',
              );
            }
            if (outputs[path] !=
                _expectedVectorHash(
                  transferred.xml,
                  component['compilerSvg'] as String,
                )) {
              throw FormatException(
                'Vector payload differs from its source compilation: $path',
              );
            }
          }
        }
      } else {
        await _validateRasterGrid(
          candidate,
          map['id'] as String,
          floor['id'] as String,
          art,
          frozenHashes,
          outputs,
          decodedTiles,
          required,
          outputRoot: 'artwork/${map['id']}/${floor['id']}',
        );
      }
    }
    final expectedDependencies = (expected['rasterDependencies'] as List? ?? [])
        .cast<Map>();
    final dependencies = (map['rasterDependencies'] as List? ?? []).cast<Map>();
    if (dependencies.length != expectedDependencies.length) {
      throw const FormatException('Candidate lost raster dependencies');
    }
    for (var i = 0; i < dependencies.length; i++) {
      final dependency = dependencies[i];
      final metadata = Map<String, dynamic>.from(dependency)..remove('artwork');
      if (canonicalJson(metadata) != canonicalJson(expectedDependencies[i])) {
        throw const FormatException('Raster dependency metadata changed');
      }
      await _validateRasterGrid(
        candidate,
        map['id'] as String,
        'dependency-${dependency['id']}',
        Map<String, dynamic>.from(dependency['artwork'] as Map),
        frozenHashes,
        outputs,
        decodedTiles,
        required,
        outputRoot: 'artwork/dependencies/${map['id']}/${dependency['id']}',
      );
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

Future<void> _validateRasterGrid(
  Directory candidate,
  String mapId,
  String sourceFloorId,
  Map<String, dynamic> art,
  Map<String, String> frozenHashes,
  Map<String, String> outputs,
  Map<String, PngInspection> decodedTiles,
  void Function(String) required, {
  required String outputRoot,
}) async {
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
    final rawPath = rawTilePath(mapId, sourceFloorId, x, y);
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
    if (!empty && tile['path'] != '$outputRoot/$x/$y.png') {
      throw const FormatException(
        'Raster path differs from canonical identity',
      );
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
    var inspection = decodedTiles[sourceHash];
    if (inspection == null) {
      inspection = inspectPng(await packFile(candidate, path).readAsBytes());
      decodedTiles[sourceHash] = inspection;
    }
    if (inspection.empty != empty ||
        (!empty &&
            canonicalJson(tile['alphaBounds']) !=
                canonicalJson([
                  inspection.left,
                  inspection.top,
                  inspection.right,
                  inspection.bottom,
                ]))) {
      throw const FormatException('Raster decoded/source closure mismatch');
    }
    if (!empty) visible = true;
  }
  if (!visible) throw const FormatException('Raster floor has no artwork');
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
        // Transits carry only a translation key such as FAC_TRANSIT_12_DESC;
        // its "Transit to Woods" label is what saved exfil panels show.
        entry['description'] ??
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

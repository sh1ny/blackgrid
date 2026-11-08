import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:blackgrid/application/output_path_guard.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as image;
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart'
    as vector;
import 'package:yaml/yaml.dart';

import 'calibration.dart';
import 'place_labels.dart';

import 'package:blackgrid/maps/live_map_normalizer.dart'
    show
        canonicalJson,
        normalizeLiveMapData,
        LiveMapSourceBodies,
        LiveMapBinding;

import 'svg.dart';

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
    _decodeRequiredJsonObject(await packFile(root, path).readAsString(), path);
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

/// Compiles SVG [xml] with the pack's compiler flags, named [debugName] in
/// diagnostics.
///
/// This is the encoder every pack build and validation uses, exposed so tests
/// can recompile committed payloads without writing into a generation.
Uint8List encodeMapVector(String xml, String debugName) =>
    _encodeVector(xml, debugName);

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

/// A hash-locked view of the raw inputs a pack is built from.
///
/// [open] reads a raw generation folder. [fromGeneration] reads a committed
/// pack generation, which carries its own inputs.
class FrozenInputs {
  FrozenInputs._(this.index, this._files, this._unverified, this._missing);

  /// The parsed `sources.json` index.
  final Map<String, dynamic> index;
  final Map<String, File> _files;

  /// Expected hash of each carried file that is hashed when read, not on open.
  final Map<String, String> _unverified;

  /// Listed sources no file carries, with the message to throw reading each.
  final Map<String, String> _missing;

  /// Opens the raw generation at [root] and hashes every listed source.
  static Future<FrozenInputs> open(Directory root) async {
    final index = await _readJson(root, 'sources.json');
    final files = <String, File>{};
    for (final source in _sourceList(index)) {
      final path = source['path'] as String;
      if (files.containsKey(path)) {
        throw FormatException('Duplicate frozen path $path');
      }
      final file = packFile(root, path);
      if (_hash(await file.readAsBytes()) != source['sha256']) {
        throw FormatException('Frozen input hash mismatch: $path');
      }
      _requireSourceUrl(source, path);
      files[path] = file;
    }
    return FrozenInputs._(index, files, const {}, const {});
  }

  /// Opens a committed [generation] as a raw-input view.
  ///
  /// The index is `evidence/sources.json`. A source outside `tiles/` resolves
  /// to `evidence/<path>` and is hashed against the index here. A tile source
  /// resolves to any output of the generation whose recorded hash equals the
  /// source hash (artwork or an `evidence/tile-alpha` witness), hashed when
  /// read. A source nothing carries makes [bytes] throw, naming its path.
  static Future<FrozenInputs> fromGeneration(Directory generation) async {
    final index = await _readJson(generation, 'evidence/sources.json');
    final manifest = await _readJson(generation, 'manifest.json');
    final carriers = <String, String>{};
    for (final output in manifest['outputs'] as List) {
      carriers.putIfAbsent(
        output['sha256'] as String,
        () => output['path'] as String,
      );
    }
    final id = generation.path
        .replaceAll('\\', '/')
        .split('/')
        .where((part) => part.isNotEmpty)
        .last;
    final files = <String, File>{};
    final unverified = <String, String>{};
    final missing = <String, String>{};
    final seen = <String>{};
    for (final source in _sourceList(index)) {
      final path = source['path'] as String;
      if (!seen.add(path)) throw FormatException('Duplicate frozen path $path');
      _requireSourceUrl(source, path);
      final hash = source['sha256'] as String;
      if (!path.startsWith('tiles/')) {
        final file = packFile(generation, 'evidence/$path');
        if (_hash(await file.readAsBytes()) != hash) {
          throw FormatException('Frozen input hash mismatch: $path');
        }
        files[path] = file;
      } else if (carriers[hash] case final carrier?) {
        files[path] = packFile(generation, carrier);
        unverified[path] = hash;
      } else {
        missing[path] =
            'Frozen input $path is not carried by generation $id; rebuild '
            'from a raw generation with prepare.dart rebuild --raw';
      }
    }
    return FrozenInputs._(index, files, unverified, missing);
  }

  static List<Map<String, dynamic>> _sourceList(Map<String, dynamic> index) {
    if (index['schemaVersion'] != 1 || index['sources'] is! List) {
      throw const FormatException('Unsupported frozen inputs');
    }
    return (index['sources'] as List).cast<Map<String, dynamic>>();
  }

  static void _requireSourceUrl(Map<String, dynamic> source, String path) {
    if (Uri.tryParse(source['url'] as String)?.scheme != 'https' &&
        source['url'] != 'blackgrid:calibration-v1') {
      throw FormatException('Invalid frozen source URL: $path');
    }
  }

  /// Returns the bytes of the frozen source [path].
  ///
  /// Throws a [FormatException] when [path] is not a listed source or no file
  /// carries it.
  Future<Uint8List> bytes(String path) async {
    if (_missing[path] case final message?) throw FormatException(message);
    final file = _files[path];
    if (file == null) throw FormatException('Unfrozen dependency: $path');
    final bytes = await file.readAsBytes();
    if (_unverified[path] case final expected? when _hash(bytes) != expected) {
      throw FormatException('Frozen input hash mismatch: $path');
    }
    return bytes;
  }

  Future<String> text(String path) async => utf8.decode(await bytes(path));

  /// Creates a view that replaces only the six approved metadata sources.
  ///
  /// Reads each replacement from [replacements] to bind its exact bytes into a
  /// derived source index. Replacement files are checked against those hashes
  /// every time they are read through [bytes]. Existing carried and missing
  /// source behavior is retained for all other paths, and this instance's
  /// index and backing files are not changed.
  Future<FrozenInputs> withMetadata(Directory replacements) async {
    final sources = _sourceList(index);
    final files = Map<String, File>.of(_files);
    final unverified = Map<String, String>.of(_unverified);
    final sourceIndex = <String, Map<String, dynamic>>{};
    for (final source in sources) {
      final path = source['path'] as String;
      if (sourceIndex.containsKey(path)) {
        throw FormatException('Duplicate frozen path $path');
      }
      sourceIndex[path] = source;
    }

    final updatedSources = <Map<String, dynamic>>[];
    for (final source in sources) {
      final path = source['path'] as String;
      if (!_metadataReplacementPaths.contains(path)) {
        updatedSources.add(Map<String, dynamic>.of(source));
        continue;
      }
      final file = packFile(replacements, path);
      late final List<int> bytes;
      try {
        bytes = await file.readAsBytes();
      } on FileSystemException catch (error) {
        throw FormatException(
          'Metadata replacement source is unavailable: $path ($error)',
        );
      }
      final hash = _hash(bytes);
      files[path] = file;
      unverified[path] = hash;
      updatedSources.add({...source, 'sha256': hash});
    }
    for (final path in _metadataReplacementPaths) {
      if (!sourceIndex.containsKey(path)) {
        throw FormatException('Baseline is missing metadata source $path');
      }
    }

    final derivedIndex = <String, dynamic>{...index, 'sources': updatedSources};
    return FrozenInputs._(derivedIndex, files, unverified, _missing);
  }
}

/// Supplies one builder invocation with its reviewed or generation-owned
/// calibration, source lock, and exact notice bytes.
class MapBuildContext {
  MapBuildContext._({
    required Map<String, dynamic> calibration,
    required Map<String, dynamic> sourceLock,
    required List<int> noticeBytes,
  }) : calibration = _freezeMap(calibration),
       sourceLock = _freezeMap(sourceLock),
       noticeBytes = List<int>.unmodifiable(noticeBytes);

  static Map<String, dynamic> _freezeMap(Map<String, dynamic> value) =>
      Map<String, dynamic>.unmodifiable({
        for (final entry in value.entries) entry.key: _freezeJson(entry.value),
      });

  static Object? _freezeJson(Object? value) => switch (value) {
    Map map => Map<String, dynamic>.unmodifiable({
      for (final entry in map.entries)
        entry.key as String: _freezeJson(entry.value),
    }),
    List list => List<Object?>.unmodifiable([
      for (final item in list) _freezeJson(item),
    ]),
    _ => value,
  };

  /// The calibration snapshot used to validate and build each map.
  final Map<String, dynamic> calibration;

  /// The source lock recorded in the output manifest.
  final Map<String, dynamic> sourceLock;

  /// The exact bytes written to `NOTICE.txt`.
  final List<int> noticeBytes;

  /// Creates a context from explicitly reviewed configuration snapshots.
  ///
  /// This is intended for tooling and deterministic tests. Runtime acquisition
  /// must use [reviewedConfiguration] or the verified active generation.
  factory MapBuildContext.reviewed({
    required Map<String, dynamic> calibration,
    required Map<String, dynamic> sourceLock,
    required List<int> noticeBytes,
  }) => MapBuildContext._(
    calibration: calibration,
    sourceLock: sourceLock,
    noticeBytes: noticeBytes,
  );

  /// Creates the reviewed configuration context for a fresh raw generation.
  ///
  /// Fresh admission uses current authored calibration and source identities;
  /// it does not infer approval from acquired bytes.
  factory MapBuildContext.reviewedConfiguration() => MapBuildContext._(
    calibration: {
      'schemaVersion': 1,
      'maps': [
        for (final key in supportedMapSources.values) calibrationFor(key),
      ],
    },
    sourceLock: {
      'vectorSourceRevision': vectorSourceRevision,
      'vectorSourceUrl': vectorSourceUrl,
      'vectorSourceBlob': vectorSourceBlob,
      'metadataRepositoryRevision': metadataRepositoryRevision,
      'metadataBlob': metadataBlob,
      'primaryHashes': primarySourceHashes,
      'primaryUrls': primarySourceUrls,
      'primaryRepositoryRevisions': primarySourceRepositoryRevisions,
      'primaryGitBlobs': primarySourceGitBlobs,
      'primaryProvenance': primarySourceProvenance,
    },
    noticeBytes: utf8.encode(artworkNotices),
  );

  /// Reads the frozen build context from a verified active generation.
  ///
  /// [generation] must come from [verifyCommittedGeneration].
  static Future<MapBuildContext> fromGeneration(
    CommittedGeneration generation,
  ) async {
    final sourceLock = generation.manifest['sourceLock'];
    if (sourceLock is! Map<String, dynamic>) {
      throw const FormatException('Verified generation has no source lock');
    }
    return MapBuildContext._(
      calibration: await _readJson(
        generation.directory,
        'evidence/calibration.json',
      ),
      sourceLock: sourceLock,
      noticeBytes: await packFile(
        generation.directory,
        'NOTICE.txt',
      ).readAsBytes(),
    );
  }
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

/// Verifies a fetched source against its reviewed identity and byte lock.
///
/// The source record must name [path], [expectedUrl], and the approved hash.
void validateLockedSourceRecord({
  required String path,
  required Map<String, dynamic> source,
  required List<int> bytes,
  required String expectedUrl,
  required String expectedSha256,
  String? expectedRepositoryRevision,
  String? expectedGitBlobSha1,
}) {
  final observedHash = _hash(bytes);
  final observedUrl = source['url'];
  final observedRecordHash = source['sha256'];
  final mismatches = <String>[];
  if (source['path'] != path) {
    mismatches.add('identity ${source['path']}');
  }
  if (observedUrl != expectedUrl) {
    mismatches.add('URL $observedUrl');
  }
  if (observedRecordHash != expectedSha256 || observedHash != expectedSha256) {
    mismatches.add(
      'recorded SHA-256 $observedRecordHash, acquired SHA-256 $observedHash',
    );
  }
  if (expectedRepositoryRevision != null &&
      source['repositoryRevision'] != expectedRepositoryRevision) {
    mismatches.add('repository revision ${source['repositoryRevision']}');
  }
  if (expectedGitBlobSha1 != null &&
      source['gitBlobSha1'] != expectedGitBlobSha1) {
    mismatches.add('Git blob ${source['gitBlobSha1']}');
  }
  if (mismatches.isNotEmpty) {
    throw FormatException(
      'Locked source $path differs from reviewed identity: '
      '${mismatches.join('; ')}; approved SHA-256 $expectedSha256, '
      'observed SHA-256 $observedHash',
    );
  }
}

/// Diagnoses new unsupported identities and rejects invalid supported metadata.
///
/// [currentMetadata] is fresh upstream map metadata and [baselineMetadata] is
/// the verified baseline's frozen metadata. [supportedSourceKeys] is the
/// complete authored source-key inventory.
List<String> validateFreshMapIdentities(
  List<dynamic> currentMetadata,
  List<dynamic> baselineMetadata, {
  required List<String> supportedSourceKeys,
}) {
  Map<String, int> counts(
    List<dynamic> metadata,
    String label, {
    bool checkSupportedShapes = false,
  }) {
    final result = <String, int>{};
    for (final (index, value) in metadata.indexed) {
      if (value is! Map<String, dynamic>) {
        throw FormatException(
          '$label record $index is malformed: expected a map identity record',
        );
      }
      final identity = value['normalizedName'];
      if (identity is! String || identity.isEmpty) {
        throw FormatException(
          '$label record $index has malformed normalizedName: $identity',
        );
      }
      if (checkSupportedShapes && supportedSourceKeys.contains(identity)) {
        final maps = value['maps'];
        if (maps is! List) {
          throw FormatException(
            'Supported map identity $identity has malformed maps metadata',
          );
        }
        var interactiveCount = 0;
        for (final map in maps) {
          if (map is! Map<String, dynamic>) {
            throw FormatException(
              'Supported map identity $identity has a malformed map projection',
            );
          }
          if (map['key'] == identity && map['projection'] == 'interactive') {
            interactiveCount++;
          }
        }
        if (interactiveCount != 1) {
          throw FormatException(
            'Supported map identity $identity must have exactly one '
            'interactive projection; found $interactiveCount',
          );
        }
      }
      result.update(identity, (count) => count + 1, ifAbsent: () => 1);
    }
    return result;
  }

  final current = counts(
    currentMetadata,
    'Fresh map metadata',
    checkSupportedShapes: true,
  );
  final baseline = counts(baselineMetadata, 'Baseline map metadata');
  for (final sourceKey in supportedSourceKeys) {
    final count = current[sourceKey] ?? 0;
    if (count != 1) {
      throw FormatException(
        'Supported map identity $sourceKey must appear exactly once; found $count',
      );
    }
  }
  return [
    for (final identity in current.keys)
      if (!supportedSourceKeys.contains(identity) &&
          !baseline.containsKey(identity))
        'New upstream identity "$identity" is unsupported; add it through '
            'authored tool and runtime integration before it can be selected.',
  ];
}

/// Verifies that a raster tile was fetched from its reviewed expanded URL.
///
/// Tile bytes are hash-locked after acquisition; this check does not claim a
/// pre-reviewed byte hash.
/// Selects frozen baseline calibration or explicitly reviewed current calibration.
///
/// Without [reviewedCalibrationUpdate], reports the first named discrepancy
/// instead of silently replacing the baseline.
Map<String, dynamic> selectArtworkRefreshCalibration({
  required Map<String, dynamic> baseline,
  required Map<String, dynamic> reviewed,
  bool reviewedCalibrationUpdate = false,
}) {
  if (reviewedCalibrationUpdate) return reviewed;

  Object? firstDifference(Object? before, Object? after, String path) {
    if (before is Map && after is Map) {
      final keys = {...before.keys, ...after.keys}.toList()
        ..sort((a, b) => '$a'.compareTo('$b'));
      for (final key in keys) {
        final childPath = '$path.$key';
        if (!before.containsKey(key) || !after.containsKey(key)) {
          return childPath;
        }
        final difference = firstDifference(before[key], after[key], childPath);
        if (difference != null) return difference;
      }
      return null;
    }
    if (before is List && after is List) {
      if (before.length != after.length) return '$path.length';
      for (var index = 0; index < before.length; index++) {
        final difference = firstDifference(
          before[index],
          after[index],
          '$path[$index]',
        );
        if (difference != null) return difference;
      }
      return null;
    }
    return before == after ? null : path;
  }

  final beforeMaps = baseline['maps'];
  final afterMaps = reviewed['maps'];
  if (beforeMaps is! List || afterMaps is! List) {
    throw const FormatException(
      'Reviewed calibration has malformed map inventory',
    );
  }
  final common = {
    for (final key in baseline.keys)
      if (key != 'maps') key: baseline[key],
  };
  final reviewedCommon = {
    for (final key in reviewed.keys)
      if (key != 'maps') key: reviewed[key],
  };
  final commonDifference = firstDifference(
    common,
    reviewedCommon,
    'calibration',
  );
  if (commonDifference != null) {
    throw FormatException(
      'Reviewed calibration differs from baseline at $commonDifference; '
      'use --reviewed-calibration-update after authored review.',
    );
  }
  if (beforeMaps.length != afterMaps.length) {
    throw const FormatException(
      'Reviewed calibration map inventory differs from baseline',
    );
  }
  for (var index = 0; index < beforeMaps.length; index++) {
    final before = beforeMaps[index];
    final after = afterMaps[index];
    if (before is! Map<String, dynamic> || after is! Map<String, dynamic>) {
      throw FormatException('Malformed calibration map at index $index');
    }
    final sourceKey = before['sourceKey'];
    if (sourceKey is! String || after['sourceKey'] != sourceKey) {
      throw FormatException(
        'Reviewed calibration map identity differs from baseline at index '
        '$index: $sourceKey vs ${after['sourceKey']}',
      );
    }
    final difference = firstDifference(before, after, 'calibration.$sourceKey');
    if (difference != null) {
      throw FormatException(
        'Reviewed calibration differs from baseline at $difference; '
        'use --reviewed-calibration-update after authored review.',
      );
    }
  }
  return baseline;
}

void validateRasterTileSourceUrl({
  required String path,
  required String observedUrl,
  required String expectedUrl,
}) {
  if (observedUrl != expectedUrl ||
      Uri.tryParse(observedUrl)?.scheme != 'https' ||
      Uri.tryParse(expectedUrl)?.scheme != 'https') {
    throw FormatException(
      'Raster source URL mismatch for $path: expected $expectedUrl, '
      'observed $observedUrl',
    );
  }
}

Map<String, String> _requiredSourceLockMap(
  Map<String, dynamic> sourceLock,
  String key,
) {
  final raw = sourceLock[key];
  if (raw is! Map) {
    throw FormatException('Reviewed source lock has no $key configuration');
  }
  final result = <String, String>{};
  for (final entry in raw.entries) {
    if (entry.key is! String || entry.value is! String) {
      throw FormatException('Reviewed source lock has malformed $key data');
    }
    result[entry.key as String] = entry.value as String;
  }
  return result;
}

Map<String, Object?> _lockedSourceRecord(
  String path,
  Uri uri,
  List<int> bytes,
  Map<String, dynamic> sourceLock,
) {
  final urls = _requiredSourceLockMap(sourceLock, 'primaryUrls');
  final hashes = _requiredSourceLockMap(sourceLock, 'primaryHashes');
  final revisions = _requiredSourceLockMap(
    sourceLock,
    'primaryRepositoryRevisions',
  );
  final blobs = _requiredSourceLockMap(sourceLock, 'primaryGitBlobs');
  final provenance = _requiredSourceLockMap(sourceLock, 'primaryProvenance');
  final expectedUrl = urls[path];
  final expectedHash = hashes[path];
  final expectedProvenance = provenance[path];
  if (expectedUrl == null ||
      expectedHash == null ||
      expectedProvenance == null ||
      expectedProvenance.isEmpty) {
    throw FormatException('Required reviewed source lock is incomplete: $path');
  }
  final record = <String, dynamic>{
    'path': path,
    'url': uri.toString(),
    'sha256': _hash(bytes),
    'provenance': expectedProvenance,
    'repositoryRevision': ?revisions[path],
    'gitBlobSha1': ?blobs[path],
  };
  validateLockedSourceRecord(
    path: path,
    source: record,
    bytes: bytes,
    expectedUrl: expectedUrl,
    expectedSha256: expectedHash,
    expectedRepositoryRevision: revisions[path],
    expectedGitBlobSha1: blobs[path],
  );
  return record;
}

Future<void> acquireInputs(Directory root) async {
  if (await root.exists()) {
    throw const FormatException('Acquisition requires a fresh raw directory');
  }
  await root.create(recursive: true);
  final client = http.Client();
  final sourceLock = MapBuildContext.reviewedConfiguration().sourceLock;
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
    if (path.endsWith('.png')) inspectPng(bytes);
    final source = primarySourceUrls.containsKey(path)
        ? _lockedSourceRecord(path, Uri.parse(url), bytes, sourceLock)
        : <String, Object?>{'path': path, 'url': url, 'sha256': _hash(bytes)};
    await _write(root, path, bytes);
    sources.add(source);
    return bytes;
  }

  try {
    final metadata = jsonDecode(
      utf8.decode(
        await fetch(
          'metadata/maps.json',
          primarySourceUrls['metadata/maps.json']!,
        ),
      ),
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
    await fetch(vectorSourcePath, primarySourceUrls[vectorSourcePath]!);
    sources.last.addAll({
      'termsPaths': ['terms/svg-maps-README.md', 'terms/svg-maps-LICENSE.md'],
      'privateUse': 'user-directed-private-implementation',
      'publicRedistribution': 'not-owner-cleared',
    });
    for (final entry in additionalVectorSources.entries) {
      final filename = entry.value['file']!;
      final path = '${entry.key}/$filename';
      // Pin immutable publisher bytes rather than relying on mutable CDN
      // caching. The selected served rendition was independently observed.
      await fetch(path, primarySourceUrls[path]!);
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
      primarySourceUrls['terms/tarkov-dev-README.md']!,
    );
    await fetch(
      'terms/tarkov-dev-software-LICENSE.txt',
      primarySourceUrls['terms/tarkov-dev-software-LICENSE.txt']!,
    );
    await fetch(
      'terms/tarkovbot-creator.html',
      primarySourceUrls['terms/tarkovbot-creator.html']!,
    );
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

Map<String, dynamic> _decodeRequiredJsonObject(String text, String path) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException catch (error) {
    throw FormatException('Invalid JSON $path: ${error.message}');
  }
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('Expected a JSON object in $path');
  }
  return decoded;
}

Future<Map<String, dynamic>> _readFrozenSourceObject(
  FrozenInputs frozen,
  String path,
) async {
  final String text;
  try {
    text = await frozen.text(path);
  } on FormatException catch (error) {
    throw FormatException(
      'Invalid required source bytes $path: ${error.message}',
    );
  }
  return _decodeRequiredJsonObject(text, path);
}

/// Rebuilds a candidate pack offline from the [frozen] inputs and [context].
///
/// Raw generations use reviewed configuration context; existing workflows use
/// the verified active generation's frozen calibration, source lock, and
/// exact notice bytes.
/// The manifest records [toolchain] as the versions that built it. With
/// [compileVectors], every vector is compiled twice through [encode] and the
/// manifest records the payload format as `vectorCodecFormat`; without it the
/// candidate has no `.vec` files and no format record.
Future<Map<String, dynamic>> rebuildCandidate(
  FrozenInputs frozen,
  Directory candidate, {
  required MapBuildContext context,
  required Map<String, String> toolchain,
  bool compileVectors = true,
  VectorEncoder encode = _encodeVector,
}) async {
  if (await candidate.exists() && !(await candidate.list().isEmpty)) {
    throw const FormatException('Rebuild requires an empty fresh candidate');
  }
  final frozenCalibration =
      jsonDecode(await frozen.text('calibration.json')) as Map<String, dynamic>;
  if (canonicalJson(context.calibration) != canonicalJson(frozenCalibration)) {
    throw const FormatException(
      'Builder context calibration differs from frozen inputs',
    );
  }
  final calibration = context.calibration;
  final metadata = jsonDecode(await frozen.text('metadata/maps.json')) as List;
  final markerSnapshot = await _readFrozenSourceObject(
    frozen,
    'markers/maps.json',
  );
  final markerTranslations = await _readFrozenSourceObject(
    frozen,
    'markers/maps_en.json',
  );
  final questSources = <String, Map<String, dynamic>>{};
  for (final path in const [
    'quests/tasks.json',
    'quests/tasks_en.json',
    'quests/traders.json',
    'quests/traders_en.json',
  ]) {
    questSources[path] = await _readFrozenSourceObject(frozen, path);
  }
  _requireMapInventory(
    (calibration['maps'] as List).cast<Map>(),
    supportedMapSources.keys.toSet(),
  );
  final normalizedMarkers = normalizeLiveMapData(
    sources: LiveMapSourceBodies(
      maps: markerSnapshot,
      mapTranslations: markerTranslations,
      tasks: questSources['quests/tasks.json']!,
      taskTranslations: questSources['quests/tasks_en.json']!,
      traders: questSources['quests/traders.json']!,
      traderTranslations: questSources['quests/traders_en.json']!,
    ),
    mode: 'regular',
    bindings: [
      for (final raw in calibration['maps'] as List)
        LiveMapBinding(
          sourceKey: (raw as Map)['sourceKey'] as String,
          mapId: (raw)['id'] as String,
          calibration: Map<String, Object?>.from(raw),
        ),
    ],
  );
  final maps = <Map<String, Object?>>[];
  final emptyTileWitnesses = <String>{};
  final decodedTiles = <String, PngInspection>{};
  final vectorPaths = <String>[];
  await candidate.create(recursive: true);
  for (final untyped in calibration['maps'] as List) {
    final local = Map<String, Object?>.from(untyped as Map);
    final sourceKey = local['sourceKey'] as String;
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
    local['markers'] = normalizedMarkers[mapId]!;
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
  // The reviewed band table must still match the frozen metadata before any
  // label gets a floor from it.
  checkBandTable(metadata, maps);
  for (final map in maps) {
    final mapId = map['id'] as String;
    map['labels'] = manifestLabels(
      interactiveMetadata(metadata, map['sourceKey'] as String),
      mapId: mapId,
      baseFloorId: _baseFloorId(mapId, map['floors']),
    );
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
  await _write(candidate, 'NOTICE.txt', context.noticeBytes);
  final manifest = <String, dynamic>{
    'schemaVersion': 1,
    'preparationVersion': preparedPackVersion,
    'supportedMapIds': supportedMapSources.keys.toList(),
    'sourceGeneration': _hash(utf8.encode(canonicalJson(frozen.index))),
    'sourceLock': context.sourceLock,
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

/// The only preparation version the builder writes and the validator accepts.
///
/// Version 4 adds the required per-map `labels` list.
const preparedPackVersion = 4;

String _baseFloorId(String mapId, Object? floors) {
  final bases = [
    for (final floor in (floors as List).cast<Map>())
      if (floor['base'] == true) floor['id'] as String,
  ];
  if (bases.length != 1) {
    throw FormatException('$mapId: expected exactly one base floor');
  }
  return bases.single;
}

/// Requires every map's `labels` to equal the labels derived again from
/// [sourceMetadata], the candidate's own `evidence/metadata/maps.json`.
///
/// This is the label step of [validateCandidate]. [maps] are the manifest's map
/// entries with `id`, `sourceKey`, `floors` and `labels`. Derivation uses the
/// builder's functions and band table, so a candidate cannot carry labels its
/// own evidence does not give.
///
/// Throws a [FormatException] naming the map when `labels` is missing, is not a
/// list, or differs from the derived list.
void validateCandidateLabels(
  List<dynamic> sourceMetadata,
  List<Map<String, dynamic>> maps,
) {
  for (final map in maps) {
    final mapId = map['id'] as String;
    if (map['labels'] is! List) {
      throw FormatException('$mapId: labels is missing or not a list');
    }
    final derived = manifestLabels(
      interactiveMetadata(sourceMetadata, map['sourceKey'] as String),
      mapId: mapId,
      baseFloorId: _baseFloorId(mapId, map['floors']),
    );
    if (canonicalJson(map['labels']) != canonicalJson(derived)) {
      throw FormatException(
        '$mapId: labels differ from those derived from the frozen '
        'metadata (evidence/metadata/maps.json)',
      );
    }
  }
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

/// Requires the files under [root] to be exactly the manifest-listed [listed]
/// outputs with exactly their recorded hashes, and returns path to hash.
///
/// Throws a [FormatException] naming the first duplicate, changed, extra or
/// unlisted path, or the filesystem error for a missing listed file.
Future<Map<String, String>> _verifyOutputClosure(
  Directory root,
  Object? listed,
) async {
  final outputs = <String, String>{};
  for (final entry in listed as List) {
    final path = entry['path'] as String;
    if (outputs.containsKey(path)) {
      throw FormatException('Duplicate output $path');
    }
    packFile(root, path);
    outputs[path] = entry['sha256'] as String;
  }
  // Enumerate independently of the manifest and hash each actual output once.
  // This inventory belongs to this verification only, not another pack boundary.
  final actual = await _outputHashes(root);
  final actualHashes = {
    for (final entry in actual)
      entry['path'] as String: entry['sha256'] as String,
  };
  for (final entry in outputs.entries) {
    final actualHash = actualHashes[entry.key];
    if (actualHash == null) {
      // Preserve a filesystem error for a missing listed file without reading
      // or hashing it again. Existing excluded files still fail output closure.
      await packFile(root, entry.key).length();
      throw FormatException(
        'Candidate contains untracked or missing output bytes: ${entry.key}',
      );
    }
    if (actualHash != entry.value) {
      throw FormatException('Candidate output hash mismatch: ${entry.key}');
    }
  }
  for (final path in actualHashes.keys) {
    if (!outputs.containsKey(path)) {
      throw FormatException(
        'Candidate contains untracked or missing output bytes: $path',
      );
    }
  }
  if (canonicalJson(actual) != canonicalJson(listed)) {
    throw const FormatException(
      'Candidate contains untracked or missing output bytes',
    );
  }
  return outputs;
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
  // Cheap structural gates first: the version and the labels key of every map.
  final version = manifest['preparationVersion'];
  if (version != preparedPackVersion) {
    throw FormatException('Unsupported preparation version $version');
  }
  for (final map in manifest['maps'] as List) {
    if (map is! Map || map['labels'] is! List) {
      throw FormatException(
        '${map is Map ? map['id'] : map}: labels is missing or not a list',
      );
    }
  }
  if (requireCompiled && manifest['vectorsCompiled'] != true) {
    throw const FormatException(
      'Uncompiled vector candidate cannot be promoted',
    );
  }
  final outputs = await _verifyOutputClosure(candidate, manifest['outputs']);
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
  required('evidence/terms/tarkov-dev-software-LICENSE.txt');
  final maps = (manifest['maps'] as List).cast<Map<String, dynamic>>();
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
  validateCandidateLabels(sourceMetadata, maps);
  final sourceMarkers = await _readJson(
    candidate,
    'evidence/markers/maps.json',
  );
  final decodedTiles = <String, PngInspection>{};
  final markerTranslations = await _readJson(
    candidate,
    'evidence/markers/maps_en.json',
  );
  final questSources = <String, Map<String, dynamic>>{
    for (final path in const [
      'quests/tasks.json',
      'quests/tasks_en.json',
      'quests/traders.json',
      'quests/traders_en.json',
    ])
      path: await _readJson(candidate, 'evidence/$path'),
  };
  final normalizedMarkers = normalizeLiveMapData(
    sources: LiveMapSourceBodies(
      maps: sourceMarkers,
      mapTranslations: markerTranslations,
      tasks: questSources['quests/tasks.json']!,
      taskTranslations: questSources['quests/tasks_en.json']!,
      traders: questSources['quests/traders.json']!,
      traderTranslations: questSources['quests/traders_en.json']!,
    ),
    mode: 'regular',
    bindings: [
      for (final raw in calibratedMaps)
        LiveMapBinding(
          sourceKey: raw['sourceKey'] as String,
          mapId: raw['id'] as String,
          calibration: Map<String, Object?>.from(raw),
        ),
    ],
  );
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
        canonicalJson(normalizedMarkers[map['id']]!)) {
      throw FormatException(
        'Markers differ from independently frozen source: '
        'markers/maps.json: ${map['sourceKey']}',
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

/// Returns the generation id that `active.json` under [packs] names.
///
/// Throws a [FormatException] when the pointer is not well-formed.
Future<String> _activeVersion(Directory packs) async {
  final pointer = await _readJson(packs, 'active.json');
  final version = pointer['version'];
  if (pointer['schemaVersion'] != 1 ||
      version is! String ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(version) ||
      pointer['manifest'] != 'versions/$version/manifest.json') {
    throw const FormatException('Invalid prepared active pointer');
  }
  return version;
}

/// Produces complete non-recursive Flutter asset declarations for one version.
Future<List<String>> preparedAssetDirectories(Directory packs) async {
  final version = await _activeVersion(packs);
  final prefix = 'versions/$version/';
  final manifest = await validateCandidate(Directory('${packs.path}/$prefix'));
  return assetDirectoriesOf(version, manifest);
}

/// Returns the sorted asset directories, relative to the pack root, that
/// generation [version] with [manifest] needs declared in `pubspec.yaml`.
///
/// Pure: it reads only the manifest's `outputs` and does not validate.
List<String> assetDirectoriesOf(String version, Map<String, dynamic> manifest) {
  final prefix = 'versions/$version/';
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

/// The active generation of a packs folder after [verifyCommittedGeneration].
class CommittedGeneration {
  /// Creates a verified generation record.
  const CommittedGeneration(this.id, this.directory, this.manifest);

  /// The generation id, which is the SHA-256 of its `manifest.json`.
  final String id;

  /// The generation folder, `versions/<id>` under the packs folder.
  final Directory directory;

  /// The parsed `manifest.json`.
  final Map<String, dynamic> manifest;
}

/// Verifies that the active generation under [packs] is exactly what its
/// manifest describes.
///
/// It needs none of the newer manifest fields, so it also accepts older
/// generations. Throws a [FormatException] when the pointer is malformed, the
/// manifest bytes do not hash to the generation id (naming the id), or the
/// generation's files differ from `outputs` (naming the first path).
Future<CommittedGeneration> verifyCommittedGeneration(Directory packs) async {
  final id = await _activeVersion(packs);
  final directory = Directory('${packs.path}/versions/$id');
  final bytes = await packFile(directory, 'manifest.json').readAsBytes();
  if (_hash(bytes) != id) {
    throw FormatException('Manifest of generation $id does not hash to its id');
  }
  final manifest = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  if (manifest['outputs'] is! List) {
    throw FormatException('Generation $id manifest lists no outputs');
  }
  await _verifyOutputClosure(directory, manifest['outputs']);
  return CommittedGeneration(id, directory, manifest);
}

/// Throws a [FormatException] when an earlier promotion under [packs] left
/// `active.next.json` or any `versions/.<id>.staging` folder behind.
Future<void> requireNoInterruptedPromotion(Directory packs) async {
  final root = packs.path
      .replaceAll('\\', '/')
      .replaceFirst(RegExp(r'/+$'), '');
  FormatException left(String path) => FormatException(
    'Interrupted map pack promotion left $path; inspect and remove it, '
    'then rerun.',
  );
  if (await File('$root/active.next.json').exists()) {
    throw left('$root/active.next.json');
  }
  final versions = Directory('$root/versions');
  if (!await versions.exists()) return;
  final names = [
    await for (final entity in versions.list(followLinks: false))
      entity.path.replaceAll('\\', '/').split('/').last,
  ]..sort();
  for (final name in names) {
    if (name.startsWith('.') && name.endsWith('.staging')) {
      throw left('$root/versions/$name');
    }
  }
}

/// What differs between a committed manifest and its rebuild, by owner.
class PackChangeReport {
  /// Creates a report.
  const PackChangeReport({
    required this.lines,
    required this.paths,
    required this.valueKeys,
  });

  /// One summary line per group that changed, in manifest map order.
  final List<String> lines;

  /// Every output path that was added, removed or changed, sorted.
  final List<String> paths;

  /// The manifest values that differ outside `outputs`, as readable names.
  final List<String> valueKeys;

  /// Whether anything other than the provenance `toolchain` differs.
  bool get changed => lines.isNotEmpty;
}

class _Tally {
  int files = 0;
  bool values = false;
}

/// Compares two manifests and groups every difference by owner.
///
/// Files are grouped by `(map id, floor id)`, `(map id, dependency id)` or
/// `other` (evidence, notices and shared empty-tile witnesses). Manifest value
/// differences mark their floor, their map (`<map id>`) or the `pack` group.
/// The `toolchain` record is provenance and is never reported.
PackChangeReport packChangeReport(
  Map<String, dynamic> committed,
  Map<String, dynamic> rebuilt,
) {
  Map<String, String> hashes(Map<String, dynamic> manifest) => {
    for (final output in manifest['outputs'] as List)
      output['path'] as String: output['sha256'] as String,
  };
  final before = hashes(committed), after = hashes(rebuilt);
  final changedPaths = [
    for (final path in {...before.keys, ...after.keys})
      if (before[path] != after[path]) path,
  ]..sort();

  List<Map<String, dynamic>> listOf(Object? value) =>
      (value as List? ?? const []).cast<Map<String, dynamic>>();
  String same(Object? value) => canonicalJson(value);

  final mapIds = <String>[];
  final sides = <String, List<Map<String, dynamic>?>>{};
  for (final (index, manifest) in [committed, rebuilt].indexed) {
    for (final map in listOf(manifest['maps'])) {
      final id = map['id'] as String;
      if (!mapIds.contains(id)) mapIds.add(id);
      (sides[id] ??= [null, null])[index] = map;
    }
  }

  // Insertion order is the report order: per map, the map, then its floors and
  // dependencies; then `pack` and `other`.
  final tallies = <String, _Tally>{};
  final owners = <String, String>{};
  final valueKeys = <String>[];
  _Tally tally(String label) => tallies.putIfAbsent(label, _Tally.new);

  Object? artworkValues(Map<String, dynamic> entry) {
    final artwork = (entry['artwork'] ?? const {}) as Map<String, dynamic>;
    return {
      for (final key in entry.keys)
        if (key != 'artwork') key: entry[key],
      'tiles': [
        for (final tile in listOf(artwork['tiles']))
          [tile['x'], tile['y'], tile['empty'], tile['alphaBounds']],
      ],
      'components': [
        for (final component in listOf(artwork['components']))
          [component['id'], component['effects']],
      ],
    };
  }

  void own(String label, Map<String, dynamic> entry) {
    final artwork = (entry['artwork'] ?? const {}) as Map<String, dynamic>;
    for (final component in listOf(artwork['components'])) {
      for (final key in const ['sourceSvg', 'compilerSvg', 'path']) {
        if (component[key] case final String path) owners[path] = label;
      }
    }
    for (final tile in listOf(artwork['tiles'])) {
      if (tile['path'] case final String path) owners[path] = label;
    }
  }

  Map<String, dynamic>? mapValues(Map<String, dynamic>? map) => map == null
      ? null
      : {
          for (final key in map.keys)
            if (key != 'floors' && key != 'rasterDependencies') key: map[key],
        };

  for (final id in mapIds) {
    final pair = sides[id]!;
    tally(id);
    final left = mapValues(pair[0]), right = mapValues(pair[1]);
    if (left == null || right == null) {
      tallies[id]!.values = true;
      valueKeys.add(id);
    } else {
      for (final key in {...left.keys, ...right.keys}) {
        if (same(left[key]) != same(right[key])) {
          tallies[id]!.values = true;
          valueKeys.add('$id $key');
        }
      }
    }
    for (final (prefix, key) in const [
      ('', 'floors'),
      ('dependency ', 'rasterDependencies'),
    ]) {
      final bySide = [
        for (final map in pair)
          {for (final entry in listOf(map?[key])) entry['id'] as String: entry},
      ];
      final entryIds = <String>{for (final side in bySide) ...side.keys};
      for (final entryId in entryIds) {
        final label = '$id $prefix$entryId';
        final a = bySide[0][entryId], b = bySide[1][entryId];
        for (final entry in [a, b]) {
          if (entry != null) own(label, entry);
        }
        tally(label);
        if (a == null ||
            b == null ||
            same(artworkValues(a)) != same(artworkValues(b))) {
          tallies[label]!.values = true;
          valueKeys.add('$label values');
        }
      }
    }
  }

  for (final path in changedPaths) {
    // Insert `other` last, after every map group.
    final label = owners[path];
    if (label != null) tally(label).files++;
  }
  const notPackKeys = {'toolchain', 'outputs', 'maps'};
  final packKeys = {...committed.keys, ...rebuilt.keys}..removeAll(notPackKeys);
  for (final key in packKeys.toList()..sort()) {
    if (same(committed[key]) != same(rebuilt[key])) {
      tally('pack').values = true;
      valueKeys.add(key);
    }
  }
  final unowned = changedPaths.where((path) => !owners.containsKey(path));
  if (unowned.isNotEmpty) tally('other').files = unowned.length;

  Map<String, dynamic> withoutToolchain(Map<String, dynamic> manifest) => {
    for (final key in manifest.keys)
      if (key != 'toolchain') key: manifest[key],
  };
  if (!tallies.values.any((t) => t.files > 0 || t.values) &&
      same(withoutToolchain(committed)) != same(withoutToolchain(rebuilt))) {
    tally('pack').values = true;
    valueKeys.add('unattributed manifest values');
  }

  final lines = <String>[];
  for (final MapEntry(key: label, value: t) in tallies.entries) {
    if (t.files == 0 && !t.values) continue;
    if (label == 'pack' || mapIds.contains(label)) {
      lines.add('$label: manifest values changed');
    } else {
      lines.add(
        '$label: ${t.files} changed file(s)'
        '${t.values ? ', manifest values changed' : ''}',
      );
    }
  }
  return PackChangeReport(
    lines: lines,
    paths: changedPaths,
    valueKeys: valueKeys,
  );
}

/// The line `check` prints when the rebuild of generation [id] matched.
String packReproducedLine(String id, Map<String, String> toolchain) {
  final versions = [
    for (final name in toolchainPackages) '$name ${toolchain[name]}',
  ];
  return 'Map pack $id reproduced byte-identically with ${versions.join(', ')}.';
}

/// Thrown by [checkActive] when the committed pack does not reproduce.
///
/// [toString] is the full multi-line report so the command prints it as is.
class MapPackCheckFailure implements Exception {
  /// Creates a failure with the full report [message].
  const MapPackCheckFailure(this.message);

  /// The summary, the differing paths and keys, and the closing instruction.
  final String message;

  @override
  String toString() => message;
}

const _maxReportedPaths = 100;

/// The report lines, then the changed paths and manifest values, as printed
/// by both `check` and `refresh`.
List<String> _reportDetails(PackChangeReport report) => [
  ...report.lines,
  if (report.paths.isNotEmpty) ...[
    'Changed files:',
    for (final path in report.paths.take(_maxReportedPaths)) '  $path',
    if (report.paths.length > _maxReportedPaths)
      '  ... and ${report.paths.length - _maxReportedPaths} more',
  ],
  if (report.valueKeys.isNotEmpty) ...[
    'Changed manifest values:',
    for (final key in report.valueKeys) '  $key',
  ],
];

const _metadataReplacementPaths = {
  'markers/maps.json',
  'markers/maps_en.json',
  'quests/tasks.json',
  'quests/tasks_en.json',
  'quests/traders.json',
  'quests/traders_en.json',
};

bool _sameMapExcept(
  Map<dynamic, dynamic> before,
  Map<dynamic, dynamic> after,
  Set<String> excluded,
) {
  final beforeKeys = before.keys
      .where((key) => !excluded.contains(key))
      .toSet();
  final afterKeys = after.keys.where((key) => !excluded.contains(key)).toSet();
  if (beforeKeys.length != afterKeys.length ||
      !beforeKeys.containsAll(afterKeys) ||
      !afterKeys.containsAll(beforeKeys)) {
    return false;
  }
  for (final key in beforeKeys) {
    if (canonicalJson(before[key]) != canonicalJson(after[key])) return false;
  }
  return true;
}

/// Rejects replacement source indexes outside the approved metadata closure.
///
/// The candidate must retain every baseline path and non-replacement record.
/// Only the six regular-mode REST hashes may be replaced.
void validateMetadataSourceIndex(
  Map<String, dynamic> baseline,
  Map<String, dynamic> candidate,
) {
  List<Map<String, dynamic>> sources(Map<String, dynamic> index) {
    if (index['schemaVersion'] != 1 || index['sources'] is! List) {
      throw const FormatException('Unsupported metadata source index');
    }
    return (index['sources'] as List).cast<Map<String, dynamic>>();
  }

  final baselineSources = sources(baseline);
  final candidateSources = sources(candidate);
  Map<String, Map<String, dynamic>> byPath(List<Map<String, dynamic>> records) {
    final result = <String, Map<String, dynamic>>{};
    for (final record in records) {
      final path = record['path'];
      if (path is! String || result.containsKey(path)) {
        throw FormatException(
          'Duplicate or invalid metadata source path: $path',
        );
      }
      result[path] = record;
    }
    return result;
  }

  final before = byPath(baselineSources), after = byPath(candidateSources);
  final baselinePaths = before.keys.toSet(),
      candidatePaths = after.keys.toSet();
  if (!_metadataReplacementPaths.every(before.containsKey)) {
    throw const FormatException(
      'Baseline is missing one or more approved metadata sources',
    );
  }
  if (baselinePaths.length != candidatePaths.length ||
      !baselinePaths.containsAll(candidatePaths) ||
      !candidatePaths.containsAll(baselinePaths)) {
    final changed =
        {...baselinePaths, ...candidatePaths}
            .where(
              (path) =>
                  baselinePaths.contains(path) != candidatePaths.contains(path),
            )
            .toList()
          ..sort();
    throw FormatException(
      'Metadata source path inventory changed: ${changed.join(', ')}',
    );
  }
  if (!baselineSources.indexed.every(
    (entry) => entry.$2['path'] == candidateSources[entry.$1]['path'],
  )) {
    throw const FormatException('Metadata source record order changed');
  }

  for (final path in before.keys) {
    final oldRecord = before[path]!;
    final newRecord = after[path]!;
    if (_metadataReplacementPaths.contains(path)) {
      if (!_sameMapExcept(oldRecord, newRecord, const {'sha256'})) {
        throw FormatException('Metadata source record changed: $path');
      }
      if (newRecord['sha256'] is! String) {
        throw FormatException('Metadata source hash is invalid: $path');
      }
    } else if (canonicalJson(oldRecord) != canonicalJson(newRecord)) {
      throw FormatException('Non-metadata source record changed: $path');
    }
  }
  if (!_sameMapExcept(baseline, candidate, const {'sources'})) {
    throw const FormatException('Metadata source index fields changed');
  }
}

/// Rejects artifact changes outside the refreshed metadata evidence.
///
/// Map records may change, but non-marker map data and all non-metadata output
/// hashes and manifest settings must stay fixed. Every map key except
/// `markers` is compared, so a changed, added or removed `labels` entry fails
/// naming the map.
void validateMetadataPreservation(
  Map<String, dynamic> baseline,
  Map<String, dynamic> candidate,
) {
  List<Map<String, dynamic>> maps(Map<String, dynamic> manifest) {
    final raw = manifest['maps'];
    if (raw is! List) {
      throw const FormatException('Metadata refresh manifest has no maps');
    }
    return raw.cast<Map<String, dynamic>>();
  }

  Map<String, Map<String, dynamic>> byMap(List<Map<String, dynamic>> records) {
    final result = <String, Map<String, dynamic>>{};
    for (final map in records) {
      final id = map['id'];
      if (id is! String || result.containsKey(id)) {
        throw FormatException('Metadata refresh has invalid map identity: $id');
      }
      result[id] = map;
    }
    return result;
  }

  final beforeMaps = byMap(maps(baseline));
  final afterMaps = byMap(maps(candidate));
  if (beforeMaps.length != afterMaps.length ||
      !beforeMaps.keys.toSet().containsAll(afterMaps.keys) ||
      !afterMaps.keys.toSet().containsAll(beforeMaps.keys)) {
    throw const FormatException('Metadata refresh changed the map inventory');
  }

  for (final id in beforeMaps.keys) {
    final before = beforeMaps[id]!;
    final after = afterMaps[id]!;
    if (!_sameMapExcept(before, after, const {'markers'})) {
      throw FormatException('Metadata refresh changed preserved map data: $id');
    }
  }

  Map<String, String> outputHashes(Map<String, dynamic> manifest) {
    final raw = manifest['outputs'];
    if (raw is! List) {
      throw const FormatException('Metadata refresh manifest has no outputs');
    }
    final result = <String, String>{};
    for (final rawOutput in raw) {
      if (rawOutput is! Map<String, dynamic>) {
        throw const FormatException('Metadata refresh output is malformed');
      }
      final path = rawOutput['path'];
      final hash = rawOutput['sha256'];
      if (path is! String || hash is! String || result.containsKey(path)) {
        throw FormatException('Metadata refresh output is invalid: $path');
      }
      result[path] = hash;
    }
    return result;
  }

  final beforeOutputs = outputHashes(baseline);
  final afterOutputs = outputHashes(candidate);
  if (beforeOutputs.length != afterOutputs.length ||
      !beforeOutputs.keys.toSet().containsAll(afterOutputs.keys) ||
      !afterOutputs.keys.toSet().containsAll(beforeOutputs.keys)) {
    throw const FormatException(
      'Metadata refresh changed the output inventory',
    );
  }
  final mutableEvidence = {
    'evidence/sources.json',
    for (final path in _metadataReplacementPaths) 'evidence/$path',
  };
  for (final entry in beforeOutputs.entries) {
    if (!mutableEvidence.contains(entry.key) &&
        afterOutputs[entry.key] != entry.value) {
      throw FormatException(
        'Metadata refresh changed preserved output hash: ${entry.key}',
      );
    }
  }

  if (!_sameMapExcept(baseline, candidate, const {
    'sourceGeneration',
    'outputs',
    'maps',
    'toolchain',
  })) {
    throw const FormatException('Metadata refresh changed manifest settings');
  }
}

/// Rebuilds the active generation of [packs] into [candidate] from the
/// generation's own carried inputs, and returns the verified committed
/// generation with the rebuilt manifest.
///
/// Verifies the committed generation first, so a comparison of manifests
/// compares bytes. The rebuild validates the candidate it writes.
Future<(CommittedGeneration, Map<String, dynamic>)> _rebuildActive(
  Directory packs,
  Directory candidate, {
  required Map<String, String> toolchain,
  VectorEncoder encode = _encodeVector,
}) async {
  final committed = await verifyCommittedGeneration(packs);
  final rebuilt = await rebuildCandidate(
    await FrozenInputs.fromGeneration(committed.directory),
    candidate,
    context: await MapBuildContext.fromGeneration(committed),
    toolchain: toolchain,
    encode: encode,
  );
  return (committed, rebuilt);
}

/// Rebuilds the active generation under [packs] with the installed
/// [toolchain] and returns the line to print when it reproduces byte for byte.
///
/// Writes nothing under [packs]. The rebuild lives in a folder created under
/// [tempParent] (default: the system temp folder) and is always deleted; a
/// failed deletion is reported on stderr and never replaces the result.
/// Throws a [MapPackCheckFailure] with the per-map summary, the differing
/// paths and manifest values, and the instruction to rebuild when it does not.
Future<String> checkActive(
  Directory packs, {
  required Map<String, String> toolchain,
  Directory? tempParent,
}) async {
  await requireNoInterruptedPromotion(packs);
  final work = await (tempParent ?? Directory.systemTemp).createTemp(
    'blackgrid-map-check-',
  );
  try {
    final (committed, rebuilt) = await _rebuildActive(
      packs,
      Directory('${work.path}/candidate'),
      toolchain: toolchain,
    );
    final report = packChangeReport(committed.manifest, rebuilt);
    if (!report.changed) return packReproducedLine(committed.id, toolchain);
    throw MapPackCheckFailure(
      [
        ..._reportDetails(report),
        'Map pack is not reproducible with the installed toolchain. '
            'Run: mise run maps:rebuild',
      ].join('\n'),
    );
  } finally {
    try {
      await work.delete(recursive: true);
    } on FileSystemException catch (error) {
      stderr.writeln('Could not delete ${work.path}: $error');
    }
  }
}

/// The line that opens the generated map asset block in `pubspec.yaml`.
const mapPackAssetsBegin =
    '    # BEGIN generated map pack assets (mise run maps:rebuild)';

/// The line that closes the generated map asset block in `pubspec.yaml`.
const mapPackAssetsEnd = '    # END generated map pack assets';

/// Replaces exactly the lines between the asset block markers in [pubspec]
/// with [lines], and returns the new text.
///
/// The text needs exactly one [mapPackAssetsBegin] line followed by exactly
/// one [mapPackAssetsEnd] line; otherwise this throws a [FormatException]
/// naming the missing, duplicated or misordered marker. Everything outside the
/// block is returned byte for byte. Inserted lines use the line ending of the
/// begin marker line (LF or CRLF).
String replaceMapPackAssetBlock(String pubspec, List<String> lines) {
  final parts = pubspec.split('\n');
  List<int> find(String marker) => [
    for (final (index, part) in parts.indexed)
      if (part.trim() == marker.trim()) index,
  ];
  const beginName = 'BEGIN generated map pack assets';
  const endName = 'END generated map pack assets';
  final begins = find(mapPackAssetsBegin), ends = find(mapPackAssetsEnd);
  for (final (found, name) in [(begins, beginName), (ends, endName)]) {
    if (found.isEmpty) {
      throw FormatException('pubspec.yaml is missing the $name marker');
    }
  }
  for (final (found, name) in [(begins, beginName), (ends, endName)]) {
    if (found.length > 1) {
      throw FormatException('pubspec.yaml has the $name marker more than once');
    }
  }
  final [begin] = begins;
  final [end] = ends;
  if (end < begin) {
    throw const FormatException(
      'pubspec.yaml has the $endName marker before the $beginName marker',
    );
  }
  final cr = parts[begin].endsWith('\r') ? '\r' : '';
  return [
    ...parts.sublist(0, begin + 1),
    for (final line in lines) '$line$cr',
    ...parts.sublist(end),
  ].join('\n');
}

/// The asset declaration lines for [directories] under the pack [root].
///
/// Each line is indented four spaces, as inside the `flutter: assets:` list.
List<String> mapPackAssetLines(String root, List<String> directories) => [
  for (final directory in directories) '    - $root/$directory',
];

/// Normalizes [root] and requires it to be a repo-relative pack folder.
///
/// Throws a [FormatException] for absolute paths, drive letters and `.`, `..`
/// or empty segments, because the asset declarations are relative to the
/// repository.
String requireRepoRelativePackRoot(String root) {
  final normalized = root.replaceAll('\\', '/');
  if (normalized.startsWith('/') ||
      normalized.contains(':') ||
      normalized
          .split('/')
          .any((part) => part.isEmpty || part == '.' || part == '..')) {
    throw const FormatException(
      'Asset declarations require a repo-relative pack root',
    );
  }
  return normalized;
}

/// Deletes every generation folder under `versions/` of [packs] except
/// [activeId], and returns the deleted ids sorted.
///
/// Only folders whose name is 64 lowercase hex digits are generations.
/// Staging folders, files and anything else are never touched.
Future<List<String>> pruneSupersededGenerations(
  Directory packs,
  String activeId,
) async {
  final versions = Directory('${packs.path}/versions');
  if (!await versions.exists()) return const [];
  final generation = RegExp(r'^[0-9a-f]{64}$');
  final doomed = <String>[];
  await for (final entity in versions.list(followLinks: false)) {
    if (entity is! Directory) continue;
    final name = entity.path.replaceAll('\\', '/').split('/').last;
    if (generation.hasMatch(name) && name != activeId) doomed.add(name);
  }
  doomed.sort();
  for (final name in doomed) {
    await Directory('${versions.path}/$name').delete(recursive: true);
  }
  return doomed;
}

/// Describes a successful map-pack publication.
class MapPackRefresh {
  /// Creates a result.
  const MapPackRefresh({
    required this.id,
    required this.changed,
    required this.pruned,
  });

  /// The new active generation id.
  final String id;

  /// Whether anything but the toolchain record differed (the owner check).
  final bool changed;

  /// The superseded generation ids that were deleted.
  final List<String> pruned;
}

/// Describes a failed publication and its actual recovery state.
///
/// [message] names the candidate folder when it remains available.
class MapPackRefreshFailure implements Exception {
  /// Creates a failure with [message].
  const MapPackRefreshFailure(this.message);

  /// The original error followed by the kept candidate folder.
  final String message;

  @override
  String toString() => message;
}

/// Supplies the narrow filesystem operations used by shared pack publication.
abstract interface class MapPackPublicationOperations {
  /// Writes the staged asset declaration file.
  Future<void> stagePubspec(File temporary, String contents);

  /// Promotes the validated candidate and switches the active pointer.
  Future<String> promote(Directory candidate, Directory packs);

  /// Replaces the pubspec file with its staged replacement.
  Future<void> renamePubspec(File temporary, File destination);

  /// Removes superseded generations and returns their ids.
  Future<List<String>> prune(Directory packs, String activeId);

  /// Removes an owned candidate after successful publication.
  Future<void> cleanup(Directory candidate);
}

/// Publishes one already-staged candidate through the pack transaction.
///
/// The candidate is verified against [reviewedContext] and the current active
/// baseline before any active files are changed. The staged directory remains
/// operator-owned and is retained after successful publication.
Future<MapPackRefresh> publishStagedCandidate(
  Directory candidate,
  Directory packs,
  File pubspec, {
  required String assetRoot,
  required MapBuildContext reviewedContext,
  MapPackPublicationOperations? operations,
  void Function(String line)? log,
}) async {
  final root = requireRepoRelativePackRoot(assetRoot);
  await requireNoInterruptedPromotion(packs);
  replaceMapPackAssetBlock(await pubspec.readAsString(), const []);

  final baseline = await verifyCommittedGeneration(packs);
  final manifest = await validateCandidate(candidate);
  await _validateArtworkCandidateAdmission(
    candidate,
    manifest,
    reviewedContext,
  );
  final report = packChangeReport(baseline.manifest, manifest);
  final void Function(String) say = log ?? stdout.writeln;
  _reportDetails(report).forEach(say);
  say(
    report.changed
        ? 'A non-toolchain change requires the existing before-merge owner '
              'check; command success is not human-review proof.'
        : 'No changes outside the toolchain record: no owner check is needed.',
  );

  return runMapPackPublicationTransaction(
    candidate: candidate,
    packs: packs,
    pubspec: pubspec,
    assetRoot: root,
    operations: operations ?? _FileSystemMapPackPublicationOperations(),
    expectedBaselineId: baseline.id,
    changed: report.changed,
    deleteCandidateOnSuccess: false,
  );
}

/// Runs the report-independent transaction for an already-validated candidate.
///
/// It stages the pubspec replacement, rechecks the baseline immediately before
/// promotion, invokes the validated candidate promotion, replaces the pubspec,
/// prunes superseded versions, and optionally removes a caller-owned candidate.
/// A failure reports the actual pointer/pubspec state and keeps the candidate
/// when it still exists.
Future<MapPackRefresh> runMapPackPublicationTransaction({
  required Directory candidate,
  required Directory packs,
  required File pubspec,
  required String assetRoot,
  required MapPackPublicationOperations operations,
  String? expectedBaselineId,
  bool changed = false,
  bool deleteCandidateOnSuccess = true,
}) async {
  final root = requireRepoRelativePackRoot(assetRoot);
  await requireNoInterruptedPromotion(packs);
  final originalPubspec = await pubspec.readAsString();
  replaceMapPackAssetBlock(originalPubspec, const []);
  final baseline = await verifyCommittedGeneration(packs);
  if (expectedBaselineId != null && baseline.id != expectedBaselineId) {
    throw FormatException(
      'Active baseline changed before publication: expected '
      '$expectedBaselineId, observed ${baseline.id}',
    );
  }

  final manifestBytes = await packFile(
    candidate,
    'manifest.json',
  ).readAsBytes();
  final id = _hash(manifestBytes);
  final manifest = jsonDecode(utf8.decode(manifestBytes));
  if (manifest is! Map<String, dynamic>) {
    throw const FormatException('Candidate manifest must be an object');
  }
  final updated = replaceMapPackAssetBlock(
    originalPubspec,
    mapPackAssetLines(root, assetDirectoriesOf(id, manifest)),
  );
  final temporary = File('${pubspec.path}.tmp');
  var pruningStarted = false;
  var cleanupStarted = false;

  try {
    await operations.stagePubspec(temporary, updated);

    await requireNoInterruptedPromotion(packs);
    final current = await verifyCommittedGeneration(packs);
    if (current.id != baseline.id) {
      throw FormatException(
        'Active baseline changed during publication: expected ${baseline.id}, '
        'observed ${current.id}',
      );
    }

    final promotedId = await operations.promote(candidate, packs);
    if (promotedId != id || await _activeVersion(packs) != id) {
      throw FormatException(
        'Promotion did not publish the exact candidate generation $id',
      );
    }

    await operations.renamePubspec(temporary, pubspec);
    if (await pubspec.readAsString() != updated) {
      throw const FileSystemException(
        'Pubspec replacement did not install the staged declaration block',
      );
    }

    pruningStarted = true;
    final pruned = await operations.prune(packs, id);
    if (deleteCandidateOnSuccess) {
      cleanupStarted = true;
      await operations.cleanup(candidate);
    }
    return MapPackRefresh(id: id, changed: changed, pruned: pruned);
  } catch (error) {
    if (await temporary.exists()) {
      try {
        await temporary.delete();
      } on FileSystemException catch (cleanupError) {
        stderr.writeln('Could not delete ${temporary.path}: $cleanupError');
      }
    }

    final activeId = await _publicationActiveId(packs);
    final pubspecInstalled =
        await pubspec.exists() && await pubspec.readAsString() == updated;
    final remaining = await _remainingGenerationIds(packs, id);
    final targetDetails =
        'Publication targets: packs ${packs.path}; pubspec ${pubspec.path}.';
    final recovery = _publicationRecoveryAction(packs, pubspec, root);
    final phase = switch ((activeId == id, pubspecInstalled)) {
      (false, _) when activeId == baseline.id =>
        'The active pointer remains unchanged at ${baseline.id}; the pubspec '
            'does not name $id.',
      (false, _) =>
        'The active pointer no longer names baseline ${baseline.id}; it now '
            'names ${activeId ?? 'an unreadable value'}. The pubspec '
            '${pubspecInstalled ? 'names' : 'does not name'} $id.',
      (true, false) =>
        'active.json already names $id but pubspec.yaml does not. $recovery',
      (true, true) when pruningStarted && remaining.isNotEmpty =>
        'active.json and pubspec.yaml already name $id; pruning was '
            'interrupted. Remaining generations: ${remaining.join(', ')}. '
            '$recovery',
      (true, true) when pruningStarted =>
        'active.json and pubspec.yaml already name $id; pruning took effect '
            'before the operation reported failure. $recovery',
      (true, _) when id == baseline.id && originalPubspec == updated =>
        'The active generation and pubspec already matched $id; no pointer or '
            'pubspec change is observable.',
      (true, true) =>
        'active.json and pubspec.yaml already name $id; inspect the '
            'publication state before retrying.',
    };
    final phaseWithTargets = '$phase $targetDetails';
    final candidateExists = await candidate.exists();
    final cleanup = switch ((cleanupStarted, candidateExists)) {
      (true, true) => 'Candidate cleanup did not remove ${candidate.path}.',
      (true, false) =>
        'Candidate cleanup took effect before the operation failed.',
      (false, true) => 'Candidate kept at ${candidate.path}.',
      (false, false) => 'Candidate ${candidate.path} is no longer present.',
    };
    throw MapPackRefreshFailure('$error\n$phaseWithTargets\n$cleanup');
  }
}

String _publicationRecoveryAction(
  Directory packs,
  File pubspec,
  String assetRoot,
) {
  final packPath = packs.path.replaceAll('\\', '/');
  if (packPath != assetRoot) {
    return 'Inspect or repair only these named targets before retrying; '
        'the repository-root maps:rebuild alias does not apply.';
  }
  if (assetRoot == 'assets/maps' && pubspec.path == 'pubspec.yaml') {
    return 'Recover with `mise run maps:rebuild`.';
  }
  return 'Recover with `dart run tool/maps/prepare.dart refresh --packs '
      '"$assetRoot" --pubspec "${pubspec.path}"`.';
}

Future<String?> _publicationActiveId(Directory packs) async {
  try {
    return await _activeVersion(packs);
  } on Object {
    return null;
  }
}

Future<List<String>> _remainingGenerationIds(
  Directory packs,
  String activeId,
) async {
  final versions = Directory('${packs.path}/versions');
  if (!await versions.exists()) return const [];
  final generation = RegExp(r'^[0-9a-f]{64}$');
  final remaining = <String>[];
  await for (final entity in versions.list(followLinks: false)) {
    if (entity is! Directory) continue;
    final name = entity.path.replaceAll('\\', '/').split('/').last;
    if (generation.hasMatch(name) && name != activeId) remaining.add(name);
  }
  remaining.sort();
  return remaining;
}

class _FileSystemMapPackPublicationOperations
    implements MapPackPublicationOperations {
  @override
  Future<void> stagePubspec(File temporary, String contents) async {
    await temporary.writeAsString(contents, flush: true);
  }

  @override
  Future<String> promote(Directory candidate, Directory packs) =>
      promoteCandidate(candidate, packs);

  @override
  Future<void> renamePubspec(File temporary, File destination) async {
    await temporary.rename(destination.path);
  }

  @override
  Future<List<String>> prune(Directory packs, String activeId) =>
      pruneSupersededGenerations(packs, activeId);

  @override
  Future<void> cleanup(Directory candidate) async {
    await candidate.delete(recursive: true);
  }
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

Set<String> _requiredArtworkSourcePaths() => {
  'metadata/maps.json',
  ..._artworkRefreshTermPaths,
  for (final entry in additionalVectorSources.entries)
    '${entry.key}/${entry.value['file']}',
  vectorSourcePath,
};

Future<void> _validateArtworkCandidateAdmission(
  Directory candidate,
  Map<String, dynamic> manifest,
  MapBuildContext reviewedContext,
) async {
  final reviewedLock = reviewedContext.sourceLock;
  _validateArtworkSourceConfiguration(reviewedLock);
  final candidateLock = manifest['sourceLock'];
  if (candidateLock is! Map<String, dynamic>) {
    throw const FormatException(
      'Artwork candidate has no reviewed source lock',
    );
  }
  final currentCalibration = reviewedContext.calibration;
  final candidateCalibration = await _readJson(
    candidate,
    'evidence/calibration.json',
  );
  if (canonicalJson(candidateCalibration) !=
      canonicalJson(currentCalibration)) {
    throw const FormatException(
      'Artwork candidate calibration differs from current reviewed calibration',
    );
  }
  if (!_sameBytes(
    await packFile(candidate, 'NOTICE.txt').readAsBytes(),
    reviewedContext.noticeBytes,
  )) {
    throw const FormatException(
      'Artwork candidate NOTICE.txt differs from current reviewed notice bytes',
    );
  }

  const lockedFields = [
    'primaryUrls',
    'primaryHashes',
    'primaryRepositoryRevisions',
    'primaryGitBlobs',
    'primaryProvenance',
  ];
  final requiredPaths = _requiredArtworkSourcePaths();
  final currentValues = <String, Map<String, String>>{
    for (final field in lockedFields)
      field: _requiredSourceLockMap(reviewedLock, field),
  };
  final candidateValues = <String, Map<String, String>>{
    for (final field in lockedFields)
      field: _requiredSourceLockMap(candidateLock, field),
  };
  final rawIndex = await _readJson(candidate, 'evidence/sources.json');
  final rawSources = rawIndex['sources'];
  if (rawSources is! List) {
    throw const FormatException('Artwork candidate has no frozen source list');
  }
  final sourcesByPath = <String, Map<String, dynamic>>{};
  for (final raw in rawSources) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException(
        'Artwork candidate source record is malformed',
      );
    }
    final path = raw['path'];
    if (path is! String || sourcesByPath.containsKey(path)) {
      throw FormatException('Duplicate or invalid artwork source path: $path');
    }
    sourcesByPath[path] = raw;
  }

  for (final path in requiredPaths) {
    for (final field in lockedFields) {
      final expected = currentValues[field]![path];
      final requiredLock = switch (field) {
        'primaryUrls' || 'primaryHashes' || 'primaryProvenance' => true,
        _ => false,
      };
      if ((requiredLock && expected == null) ||
          candidateValues[field]![path] != expected) {
        throw FormatException(
          'Artwork candidate current reviewed $field admission differs for $path',
        );
      }
    }
    final expectedUrl = currentValues['primaryUrls']![path]!;
    final expectedHash = currentValues['primaryHashes']![path]!;
    final source = sourcesByPath[path];
    if (source == null) {
      throw FormatException(
        'Artwork candidate frozen source record is missing: $path',
      );
    }
    final bytes = await packFile(candidate, 'evidence/$path').readAsBytes();
    validateLockedSourceRecord(
      path: path,
      source: source,
      bytes: bytes,
      expectedUrl: expectedUrl,
      expectedSha256: expectedHash,
      expectedRepositoryRevision:
          currentValues['primaryRepositoryRevisions']![path],
      expectedGitBlobSha1: currentValues['primaryGitBlobs']![path],
    );
    if (source['provenance'] != currentValues['primaryProvenance']![path]) {
      throw FormatException(
        'Artwork candidate reviewed provenance differs for $path',
      );
    }
    if (source['repositoryRevision'] !=
            currentValues['primaryRepositoryRevisions']![path] ||
        source['gitBlobSha1'] != currentValues['primaryGitBlobs']![path]) {
      throw FormatException(
        'Artwork candidate pinned repository evidence differs for $path',
      );
    }
  }

  final metadata = jsonDecode(
    await packFile(candidate, 'evidence/metadata/maps.json').readAsString(),
  ) as List;
  for (final rawLocal
      in (currentCalibration['maps'] as List).cast<Map<String, dynamic>>()) {
    final local = Map<String, Object?>.from(rawLocal);
    final upstream = interactiveMetadata(
      metadata,
      local['sourceKey'] as String,
    );
    final resources = <Map<String, Object?>>[
      for (final floor in reconcileFloors(local, upstream))
        if (floor['sourceTileUrl'] != null) floor,
    ];
    for (final rawDependency
        in (local['rasterDependencies'] as List? ?? const <Object?>[])) {
      if (rawDependency is! Map) {
        throw FormatException(
          'Artwork candidate raster dependency is malformed: ${local['id']}',
        );
      }
      resources.add({
        ...Map<String, Object?>.from(rawDependency),
        'id': 'dependency-${rawDependency['id']}',
      });
    }
    for (final resource in resources) {
      final mapId = local['id'] as String;
      final floorId = resource['id'] as String;
      final url = resource['sourceTileUrl'] as String;
      for (var x = 0; x < 16; x++) {
        for (var y = 0; y < 16; y++) {
          final path = rawTilePath(mapId, floorId, x, y);
          final source = sourcesByPath[path];
          if (source == null) {
            throw FormatException(
              'Artwork candidate frozen raster source is missing: $path',
            );
          }
          final observedUrl = source['url'];
          if (observedUrl is! String) {
            throw FormatException(
              'Artwork candidate raster source URL is invalid: $path',
            );
          }
          validateRasterTileSourceUrl(
            path: path,
            observedUrl: observedUrl,
            expectedUrl: tileUrl(url, x, y),
          );
        }
      }
    }
  }
}

String _refreshStamp(DateTime moment) {
  final utc = moment.toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}${two(utc.month)}'
      '${two(utc.day)}T${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
}

/// Rebuilds the active generation under [packs] with [toolchain], promotes
/// it, rewrites the asset block in [pubspec] and prunes superseded
/// generations.
///
/// In order: the leftover-promotion precheck and the marker check; verification
/// of the committed generation; the rebuild and validation into
/// `refresh-<UTC>` under [candidateParent] (default `.dart_tool/maps`); the
/// existing change report through [log] (default stdout); then the shared
/// publication transaction, which stages the replacement asset block, promotes
/// the validated candidate, replaces [pubspec], prunes superseded generations
/// and removes this refresh-owned candidate.
///
/// The publication transaction rechecks the committed baseline immediately
/// before promotion and reports the actual pointer, pubspec, pruning and
/// candidate-cleanup state after an interruption. When [metadataInputs] is
/// omitted, the committed generation's inputs are rebuilt as usual. When
/// supplied, only its six replacement metadata sources may differ from the
/// verified baseline. [encode] replaces the vector encoder of the rebuild only;
/// validation always uses the real one.
Future<MapPackRefresh> refreshActive(
  Directory packs,
  File pubspec, {
  required Map<String, String> toolchain,
  required String assetRoot,
  Directory? candidateParent,
  DateTime? now,
  VectorEncoder? encode,
  FrozenInputs? metadataInputs,
  void Function(String line)? log,
}) async {
  final void Function(String) say = log ?? stdout.writeln;
  final root = requireRepoRelativePackRoot(assetRoot);
  await requireNoInterruptedPromotion(packs);
  replaceMapPackAssetBlock(await pubspec.readAsString(), const []);
  final candidate = Directory(
    '${(candidateParent ?? Directory('.dart_tool/maps')).path}'
    '/refresh-${_refreshStamp(now ?? DateTime.now())}',
  );
  try {
    late CommittedGeneration committed;
    late Map<String, dynamic> rebuilt;
    if (metadataInputs == null) {
      (committed, rebuilt) = await _rebuildActive(
        packs,
        candidate,
        toolchain: toolchain,
        encode: encode ?? _encodeVector,
      );
    } else {
      committed = await verifyCommittedGeneration(packs);
      final baselineInputs = await FrozenInputs.fromGeneration(
        committed.directory,
      );
      validateMetadataSourceIndex(baselineInputs.index, metadataInputs.index);
      await candidate.create(recursive: true);
      rebuilt = await rebuildCandidate(
        metadataInputs,
        candidate,
        context: await MapBuildContext.fromGeneration(committed),
        toolchain: toolchain,
        encode: encode ?? _encodeVector,
      );
      validateMetadataPreservation(committed.manifest, rebuilt);
    }
    final report = packChangeReport(committed.manifest, rebuilt);
    _reportDetails(report).forEach(say);
    say(
      report.changed
          ? metadataInputs == null
                ? 'Artwork changed: the owner must check the maps listed above '
                      'in the app before merge.'
                : 'Metadata changed: the owner must check the maps listed '
                      'above in the app before merge.'
          : 'Only the toolchain record changed: no owner check is needed.',
    );
    return await runMapPackPublicationTransaction(
      candidate: candidate,
      packs: packs,
      pubspec: pubspec,
      assetRoot: root,
      operations: _FileSystemMapPackPublicationOperations(),
      expectedBaselineId: committed.id,
      changed: report.changed,
      deleteCandidateOnSuccess: true,
    );
  } on MapPackRefreshFailure {
    rethrow;
  } catch (error) {
    if (await candidate.exists()) {
      throw MapPackRefreshFailure(
        '$error\nCandidate kept at ${candidate.path}',
      );
    }
    rethrow;
  }
}

const _artworkRefreshTermPaths = {
  'terms/svg-maps-README.md',
  'terms/svg-maps-LICENSE.md',
  'terms/tarkov-dev-README.md',
  'terms/tarkov-dev-software-LICENSE.txt',
  'terms/tarkovbot-creator.html',
};

void _validateArtworkSourceConfiguration(Map<String, dynamic> sourceLock) {
  final urls = _requiredSourceLockMap(sourceLock, 'primaryUrls');
  final hashes = _requiredSourceLockMap(sourceLock, 'primaryHashes');
  final revisions = _requiredSourceLockMap(
    sourceLock,
    'primaryRepositoryRevisions',
  );
  final blobs = _requiredSourceLockMap(sourceLock, 'primaryGitBlobs');
  final provenance = _requiredSourceLockMap(sourceLock, 'primaryProvenance');
  final requiredPaths = _requiredArtworkSourcePaths();
  for (final path in requiredPaths) {
    final expectedUrl = primarySourceUrls[path];
    final expectedHash = hashes[path];
    final expectedProvenance = provenance[path];
    if (expectedUrl == null ||
        urls[path] != expectedUrl ||
        expectedHash == null ||
        expectedHash.isEmpty ||
        expectedProvenance == null ||
        expectedProvenance.isEmpty) {
      throw FormatException(
        'Required reviewed source lock is incomplete: $path',
      );
    }
    final expectedRevision = primarySourceRepositoryRevisions[path];
    if (revisions[path] != expectedRevision) {
      throw FormatException(
        'Reviewed repository revision is missing or changed for $path',
      );
    }
    final expectedBlob = primarySourceGitBlobs[path];
    if (blobs[path] != expectedBlob) {
      throw FormatException(
        'Reviewed Git blob is missing or changed for $path',
      );
    }
  }
}

/// Acquires sources admitted by reviewed configuration and builds a candidate
/// without publishing.
///
/// The active generation supplies the six retained regular-mode snapshots.
/// Raster URLs come from reviewed calibration; acquired raster hashes freeze
/// candidate integrity but do not approve prior bytes. Without
/// [reviewedCalibrationUpdate], a calibration mismatch fails before fetches.
/// When true, the reviewed configuration is selected and must pass the same
/// candidate validation. [stage] must be a new directory. Temporary acquired
/// inputs are removed on exit; a built candidate is retained after a later
/// failure for diagnosis. Retrying requires another fresh stage directory.
Future<
  ({
    Directory candidate,
    Map<String, dynamic> manifest,
    PackChangeReport report,
    List<String> diagnostics,
  })
>
stageArtworkRefresh(
  Directory packs,
  File pubspec, {
  required Directory stage,
  required Map<String, String> toolchain,
  required Future<Uint8List> Function(Uri uri) fetch,
  required MapBuildContext reviewedContext,
  bool reviewedCalibrationUpdate = false,
}) async {
  final stagePath = stage.uri.toFilePath();
  final separator = Platform.pathSeparator.codeUnitAt(0);
  var end = stagePath.length;
  while (end > 0 && stagePath.codeUnitAt(end - 1) == separator) {
    end--;
  }
  if (end == 0) {
    throw const FormatException('Artwork staging requires a directory name');
  }
  final raw = Directory('${stagePath.substring(0, end)}.raw');
  for (final output in [stage, raw]) {
    final unsafe = unsafeOutputReason(
      output.path,
      protectedDirectories: [packs.path],
      protectedFiles: [pubspec.path],
    );
    if (unsafe != null) {
      throw FormatException('Unsafe artwork staging path: $unsafe');
    }
    if (await FileSystemEntity.type(output.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw FormatException(
        'Artwork staging requires a fresh directory: ${output.path}',
      );
    }
  }
  replaceMapPackAssetBlock(await pubspec.readAsString(), const []);
  await requireNoInterruptedPromotion(packs);
  final active = await verifyCommittedGeneration(packs);
  final baselineContext = await MapBuildContext.fromGeneration(active);
  _validateArtworkSourceConfiguration(reviewedContext.sourceLock);
  final calibration = selectArtworkRefreshCalibration(
    baseline: baselineContext.calibration,
    reviewed: reviewedContext.calibration,
    reviewedCalibrationUpdate: reviewedCalibrationUpdate,
  );
  final context = MapBuildContext.reviewed(
    calibration: calibration,
    sourceLock: reviewedContext.sourceLock,
    noticeBytes: reviewedContext.noticeBytes,
  );
  final baselineInputs = await FrozenInputs.fromGeneration(active.directory);
  final baselineMetadata =
      jsonDecode(await baselineInputs.text('metadata/maps.json')) as List;
  final diagnostics = <String>[];
  final sourceRecords = <String, Map<String, Object?>>{};
  try {
    await raw.create(recursive: true);

    Future<void> addSource(
      String path,
      Map<String, Object?> record,
      List<int> bytes,
    ) async {
      if (sourceRecords.containsKey(path)) {
        throw FormatException('Duplicate artwork source path: $path');
      }
      await _write(raw, path, bytes);
      sourceRecords[path] = record;
    }

    Future<Uint8List> request(String path, Uri uri) async {
      final Uint8List bytes;
      try {
        bytes = await fetch(uri);
      } catch (error) {
        throw FormatException(
          'Could not acquire required artwork source $path from $uri: $error',
        );
      }
      return bytes;
    }

    Future<Uint8List> acquirePrimary(String path) async {
      final urls = _requiredSourceLockMap(context.sourceLock, 'primaryUrls');
      final url = urls[path];
      if (url == null || url != primarySourceUrls[path]) {
        throw FormatException(
          'Required reviewed source URL is missing or changed: $path',
        );
      }
      final uri = Uri.parse(url);
      final bytes = await request(path, uri);
      final record = _lockedSourceRecord(path, uri, bytes, context.sourceLock);
      await addSource(path, Map<String, Object?>.from(record), bytes);
      return bytes;
    }

    final metadataBytes = await acquirePrimary('metadata/maps.json');
    final metadata = jsonDecode(utf8.decode(metadataBytes)) as List;
    diagnostics.addAll(
      validateFreshMapIdentities(
        metadata,
        baselineMetadata,
        supportedSourceKeys: supportedMapSources.values.toList(),
      ),
    );

    final requiredSourcePaths = <String>{
      ..._artworkRefreshTermPaths,
      for (final entry in (calibration['maps'] as List).cast<Map>())
        if (entry['kind'] == 'vector')
          entry['sourceSvgPath'] as String? ?? vectorSourcePath,
    };
    for (final path in requiredSourcePaths.toList()..sort()) {
      await acquirePrimary(path);
    }

    final baselineSourceRecords = <String, Map<String, dynamic>>{};
    for (final source in FrozenInputs._sourceList(baselineInputs.index)) {
      final path = source['path'] as String;
      if (baselineSourceRecords.containsKey(path)) {
        throw FormatException('Duplicate baseline source path: $path');
      }
      baselineSourceRecords[path] = source;
    }
    for (final path in _metadataReplacementPaths) {
      final record = baselineSourceRecords[path];
      if (record == null) {
        throw FormatException('Verified generation is missing source $path');
      }
      final bytes = await baselineInputs.bytes(path);
      await addSource(path, Map<String, Object?>.from(record), bytes);
    }

    final calibrationBytes = reviewedCalibrationUpdate
        ? utf8.encode(canonicalJson(context.calibration))
        : await baselineInputs.bytes('calibration.json');
    await addSource('calibration.json', {
      'path': 'calibration.json',
      'url': 'blackgrid:calibration-v1',
      'sha256': _hash(calibrationBytes),
    }, calibrationBytes);

    final jobs = <({String path, String url})>[];
    for (final rawLocal in (calibration['maps'] as List).cast<Map>()) {
      final local = Map<String, Object?>.from(rawLocal);
      final upstream = interactiveMetadata(
        metadata,
        local['sourceKey'] as String,
      );
      _validateMetadataCalibration(local, upstream);
      final floors = reconcileFloors(local, upstream);
      final resources = <Map<String, Object?>>[
        for (final floor in floors)
          if (floor['sourceTileUrl'] != null) floor,
        for (final rawDependency
            in (local['rasterDependencies'] as List? ?? []))
          {
            ...Map<String, Object?>.from(rawDependency as Map),
            'id': 'dependency-${rawDependency['id']}',
          },
      ];
      for (final resource in resources) {
        final sourceTileUrl = resource['sourceTileUrl'];
        if (sourceTileUrl is! String || sourceTileUrl.isEmpty) {
          throw FormatException(
            'Reviewed raster resource has no source URL: '
            '${local['id']}/${resource['id']}',
          );
        }
        final mapId = local['id'] as String;
        final floorId = resource['id'] as String;
        for (var x = 0; x < 16; x++) {
          for (var y = 0; y < 16; y++) {
            final path = rawTilePath(mapId, floorId, x, y);
            final url = tileUrl(sourceTileUrl, x, y);
            validateRasterTileSourceUrl(
              path: path,
              observedUrl: url,
              expectedUrl: tileUrl(sourceTileUrl, x, y),
            );
            jobs.add((path: path, url: url));
          }
        }
      }
    }

    final inspectedTileHashes = <String>{};
    for (var start = 0; start < jobs.length; start += 8) {
      await Future.wait(
        jobs.skip(start).take(8).map((job) async {
          final uri = Uri.parse(job.url);
          final bytes = await request(job.path, uri);
          final hash = _hash(bytes);
          if (!inspectedTileHashes.contains(hash)) {
            inspectPng(bytes);
            inspectedTileHashes.add(hash);
          }
          await addSource(job.path, {
            'path': job.path,
            'url': job.url,
            'sha256': hash,
          }, bytes);
        }),
      );
    }

    final sources = sourceRecords.values.toList()
      ..sort((a, b) => (a['path'] as String).compareTo(b['path'] as String));
    final sourceIndex = <String, Object?>{
      'schemaVersion': 1,
      'vectorSourceRevision': vectorSourceRevision,
      'metadataRepositoryRevision': metadataRepositoryRevision,
      'metadataBlob': metadataBlob,
      'sources': sources,
    };
    await _write(raw, 'sources.json', utf8.encode(canonicalJson(sourceIndex)));
    final frozen = await FrozenInputs.open(raw);
    final manifest = await rebuildCandidate(
      frozen,
      stage,
      context: context,
      toolchain: toolchain,
    );
    return (
      candidate: stage,
      manifest: manifest,
      report: packChangeReport(active.manifest, manifest),
      diagnostics: List<String>.unmodifiable(diagnostics),
    );
  } finally {
    if (await raw.exists()) await raw.delete(recursive: true);
  }
}

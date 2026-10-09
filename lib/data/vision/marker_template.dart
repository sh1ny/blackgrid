import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'vision_job.dart';
import 'vision_runtime.dart';

/// Name under which the marker template is passed to the vision service.
const String markerTemplateName = 'inspectionMarker';

/// Bundle-relative path of the marker's raw grayscale pixels.
const String markerGrayPath = 'data/vision/marker/inspection_marker.gray';

/// Bundle-relative path of the marker's metadata.
const String markerMetadataPath = 'data/vision/marker/inspection_marker.json';

/// Side of the stored marker template in pixels.
const int markerTemplateSide = 28;

/// Outcome of [loadMarkerTemplate].
sealed class MarkerTemplateResult {
  const MarkerTemplateResult();
}

/// The template was bound by the manifest and passed every check.
final class MarkerTemplateLoaded extends MarkerTemplateResult {
  const MarkerTemplateLoaded(this.template);

  final VisionTemplate template;
}

/// The runtime binding failed: a file is missing ([VisionMissingFile]) or its
/// bytes differ from the manifest ([VisionHashMismatch]).
final class MarkerTemplateUnavailable extends MarkerTemplateResult {
  const MarkerTemplateUnavailable(this.failure);

  final VisionFailure failure;
}

/// The files match the manifest but do not describe a usable 28x28
/// grayscale template (`invalidTemplate`).
final class MarkerTemplateInvalid extends MarkerTemplateResult {
  const MarkerTemplateInvalid(this.path, this.reason);

  /// The offending file.
  final String path;
  final String reason;

  String get message => 'Marker template $path is invalid: $reason';
}

/// Loads the inspection marker from [runtimeDirectory] without the UI or the
/// database.
///
/// Reads `data/vision/runtime.manifest.json`, requires both marker files to be
/// listed there with matching SHA-256, and checks the metadata and pixel bytes
/// describe a 28x28 1-channel image with non-zero variance. Never throws for a
/// bad bundle.
MarkerTemplateResult loadMarkerTemplate(String runtimeDirectory) {
  var root = runtimeDirectory.replaceAll('\\', '/');
  while (root.length > 1 && root.endsWith('/')) {
    root = root.substring(0, root.length - 1);
  }
  String resolve(String relative) => '$root/$relative';

  final bound = _readManifestHashes(resolve(visionManifestPath));
  if (bound == null) {
    return MarkerTemplateUnavailable(
      VisionMissingFile(resolve(visionManifestPath)),
    );
  }
  final contents = <String, Uint8List>{};
  for (final relative in [markerGrayPath, markerMetadataPath]) {
    final expected = bound[relative];
    if (expected == null) {
      return MarkerTemplateUnavailable(VisionMissingFile(resolve(relative)));
    }
    final Uint8List bytes;
    try {
      bytes = File(resolve(relative)).readAsBytesSync();
    } on FileSystemException {
      return MarkerTemplateUnavailable(VisionMissingFile(resolve(relative)));
    }
    final actual = sha256.convert(bytes).toString();
    if (actual != expected) {
      return MarkerTemplateUnavailable(
        VisionHashMismatch(resolve(relative), expected, actual),
      );
    }
    contents[relative] = bytes;
  }

  final grayFile = resolve(markerGrayPath);
  final metaFile = resolve(markerMetadataPath);
  final Object? meta;
  try {
    meta = jsonDecode(utf8.decode(contents[markerMetadataPath]!));
  } on FormatException catch (error) {
    return MarkerTemplateInvalid(metaFile, 'metadata is not JSON: $error');
  }
  if (meta is! Map<String, dynamic>) {
    return MarkerTemplateInvalid(metaFile, 'metadata is not an object');
  }
  final width = meta['width'];
  final height = meta['height'];
  final stride = meta['stride'];
  if (width is! int || height is! int || stride is! int) {
    return MarkerTemplateInvalid(metaFile, 'width, height or stride missing');
  }
  final pixels = contents[markerGrayPath]!;
  if (width * height != pixels.length || stride != width) {
    return MarkerTemplateInvalid(
      grayFile,
      'metadata declares ${width}x$height (stride $stride) but the file has '
      '${pixels.length} bytes',
    );
  }
  if (width != markerTemplateSide || height != markerTemplateSide) {
    return MarkerTemplateInvalid(
      grayFile,
      'expected ${markerTemplateSide}x$markerTemplateSide, got '
      '${width}x$height',
    );
  }
  if (pixels.every((byte) => byte == pixels.first)) {
    return MarkerTemplateInvalid(
      grayFile,
      'zero variance: every pixel is ${pixels.first}',
    );
  }
  return MarkerTemplateLoaded(
    VisionTemplate(
      markerTemplateName,
      VisionImage(
        pixels,
        width: width,
        height: height,
        stride: stride,
        channels: 1,
      ),
    ),
  );
}

/// Path to lowercase SHA-256 for every manifest entry, or null when the
/// manifest is absent or malformed.
Map<String, String>? _readManifestHashes(String path) {
  try {
    final decoded = jsonDecode(File(path).readAsStringSync());
    if (decoded is! Map<String, dynamic>) return null;
    final files = decoded['files'];
    if (files is! List) return null;
    final hashes = <String, String>{};
    for (final file in files) {
      if (file is! Map<String, dynamic>) return null;
      final entryPath = file['path'];
      final digest = file['sha256'];
      if (entryPath is! String || digest is! String) return null;
      hashes[entryPath] = digest.toLowerCase();
    }
    return hashes;
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  }
}

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

/// Name under which the FIR check template is passed to the vision service.
const String firTemplateName = 'inspectionFir';

/// Bundle-relative path of the FIR check's raw grayscale pixels.
const String firGrayPath = 'data/vision/fir/inspection_fir.gray';

/// Bundle-relative path of the FIR check's metadata.
const String firMetadataPath = 'data/vision/fir/inspection_fir.json';

/// Outcome of [loadInspectionTemplates].
sealed class InspectionTemplatesResult {
  const InspectionTemplatesResult();
}

/// Every inspection template was bound by the manifest and validated.
final class InspectionTemplatesLoaded extends InspectionTemplatesResult {
  const InspectionTemplatesLoaded(this.templates);

  /// The complete set of templates to pass to the vision worker.
  final List<VisionTemplate> templates;
}

/// A required file is missing or its bytes differ from the manifest.
final class InspectionTemplatesUnavailable extends InspectionTemplatesResult {
  const InspectionTemplatesUnavailable(this.failure);

  final VisionFailure failure;
}

/// Bound files do not describe a usable grayscale template.
final class InspectionTemplatesInvalid extends InspectionTemplatesResult {
  const InspectionTemplatesInvalid(this.path, this.reason);

  /// The offending file.
  final String path;
  final String reason;

  String get message => 'Inspection template $path is invalid: $reason';
}

/// Loads and validates both inspection templates from [runtimeDirectory].
///
/// Each file must be listed in the runtime manifest with a matching hash.
/// Invalid metadata, dimensions, or constant pixels prevent activation.
InspectionTemplatesResult loadInspectionTemplates(String runtimeDirectory) {
  var root = runtimeDirectory.replaceAll('\\', '/');
  while (root.length > 1 && root.endsWith('/')) {
    root = root.substring(0, root.length - 1);
  }
  String resolve(String relative) => '$root/$relative';

  final bound = _readManifestHashes(resolve(visionManifestPath));
  if (bound == null) {
    return InspectionTemplatesUnavailable(
      VisionMissingFile(resolve(visionManifestPath)),
    );
  }
  final contents = <String, Uint8List>{};
  for (final relative in [
    markerGrayPath,
    markerMetadataPath,
    firGrayPath,
    firMetadataPath,
  ]) {
    final expected = bound[relative];
    if (expected == null) {
      return InspectionTemplatesUnavailable(
        VisionMissingFile(resolve(relative)),
      );
    }
    final Uint8List bytes;
    try {
      bytes = File(resolve(relative)).readAsBytesSync();
    } on FileSystemException {
      return InspectionTemplatesUnavailable(
        VisionMissingFile(resolve(relative)),
      );
    }
    final actual = sha256.convert(bytes).toString();
    if (actual != expected) {
      return InspectionTemplatesUnavailable(
        VisionHashMismatch(resolve(relative), expected, actual),
      );
    }
    contents[relative] = bytes;
  }

  final templates = <VisionTemplate>[];
  for (final (name, grayPath, metaPath) in [
    (markerTemplateName, markerGrayPath, markerMetadataPath),
    (firTemplateName, firGrayPath, firMetadataPath),
  ]) {
    final Object? meta;
    try {
      meta = jsonDecode(utf8.decode(contents[metaPath]!));
    } on FormatException catch (error) {
      return InspectionTemplatesInvalid(
        resolve(metaPath),
        'metadata is not JSON: $error',
      );
    }
    if (meta is! Map<String, dynamic>) {
      return InspectionTemplatesInvalid(
        resolve(metaPath),
        'metadata is not an object',
      );
    }
    final width = meta['width'];
    final height = meta['height'];
    final stride = meta['stride'];
    if (meta['format'] != 1 ||
        width is! int ||
        height is! int ||
        stride is! int) {
      return InspectionTemplatesInvalid(
        resolve(metaPath),
        'invalid format, width, height or stride',
      );
    }
    final pixels = contents[grayPath]!;
    if (width * height != pixels.length || stride != width) {
      return InspectionTemplatesInvalid(
        resolve(grayPath),
        'metadata declares ${width}x$height (stride $stride) but the file has ${pixels.length} bytes',
      );
    }
    if (width != markerTemplateSide || height != markerTemplateSide) {
      return InspectionTemplatesInvalid(
        resolve(grayPath),
        'expected 28x28, got ${width}x$height',
      );
    }
    if (pixels.every((byte) => byte == pixels.first)) {
      return InspectionTemplatesInvalid(
        resolve(grayPath),
        'zero variance: every pixel is ${pixels.first}',
      );
    }
    if (name == firTemplateName && !_validFirProvenance(meta)) {
      return InspectionTemplatesInvalid(
        resolve(metaPath),
        'invalid FIR recipe or source geometry',
      );
    }
    templates.add(
      VisionTemplate(
        name,
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
  return InspectionTemplatesLoaded(templates);
}

bool _validFirProvenance(Map<String, dynamic> meta) {
  final sha = meta['sourceSha256'];
  final sourceWidth = meta['sourceWidth'];
  final sourceHeight = meta['sourceHeight'];
  final client = meta['client'];
  final crop = meta['crop'];
  if (sha is! String ||
      !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha) ||
      sourceWidth is! int ||
      sourceHeight is! int ||
      sourceWidth <= 0 ||
      sourceHeight <= 0 ||
      client is! Map ||
      crop is! Map ||
      client['width'] != sourceWidth ||
      client['height'] != sourceHeight ||
      meta['recipe'] != 'inspection-fir-v1' ||
      meta['grayscale'] != 'opencv-bgr2gray-fixed-point') {
    return false;
  }
  final x = crop['x'];
  final y = crop['y'];
  return x is int &&
      y is int &&
      x >= 0 &&
      y >= 0 &&
      crop['width'] == 28 &&
      crop['height'] == 28 &&
      x <= sourceWidth - 28 &&
      y <= sourceHeight - 28;
}

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

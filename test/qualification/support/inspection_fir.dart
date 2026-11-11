import 'dart:convert';
import 'dart:typed_data';

import 'package:blackgrid/data/vision/vision_runtime.dart';
import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image;

/// The frozen private-image matrix and its repository-relative input root.
final class FirManifest {
  /// Creates a parsed manifest.
  const FirManifest(this.privateInputRoot, this.frames);

  /// The explicitly declared private input directory.
  final String privateInputRoot;

  /// The twelve individually identified cases.
  final List<FirFixtureFrame> frames;
}

/// The identity and physical geometry of one supplied image.
final class FirFixtureFrame {
  /// Creates an annotated case.
  const FirFixtureFrame({
    required this.file,
    required this.expectedFir,
    required this.expectedHash,
    required this.clientWidth,
    required this.clientHeight,
    required this.imageWidth,
    required this.imageHeight,
    required this.imageOriginX,
    required this.imageOriginY,
    required this.capturedLeft,
    required this.capturedTop,
    required this.capturedWidth,
    required this.capturedHeight,
    required this.markerX,
    required this.markerY,
  });

  /// The private input basename.
  final String file;

  /// The frozen owner label, `yes` or `no`.
  final String expectedFir;

  /// The expected SHA-256, or null when unavailable.
  final String? expectedHash;

  /// Physical client width.
  final int clientWidth;

  /// Physical client height.
  final int clientHeight;

  /// Encoded image width.
  final int imageWidth;

  /// Encoded image height.
  final int imageHeight;

  /// Image x coordinate of the captured client rectangle.
  final int imageOriginX;

  /// Image y coordinate of the captured client rectangle.
  final int imageOriginY;

  /// Client-space left edge of the captured rectangle.
  final int capturedLeft;

  /// Client-space top edge of the captured rectangle.
  final int capturedTop;

  /// Captured rectangle width.
  final int capturedWidth;

  /// Captured rectangle height.
  final int capturedHeight;

  /// Annotated marker x coordinate in client pixels.
  final int markerX;

  /// Annotated marker y coordinate in client pixels.
  final int markerY;
}

Never _invalid(String message) => throw FormatException(message);

T _field<T>(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! T) _invalid('Invalid or missing $key');
  return value;
}

/// Parses the frozen matrix, rejecting ambiguous identities and geometry.
FirManifest parseFirManifest(String source) {
  final root = jsonDecode(source);
  if (root is! Map<String, Object?> || root['version'] != 1) {
    _invalid('Invalid FIR manifest version');
  }
  final inputRoot = _field<String>(root, 'privateInputRoot');
  if (inputRoot != '.qualification/found-in-raid') {
    _invalid('Unexpected FIR private input root');
  }
  final entries = _field<List<Object?>>(root, 'frames');
  if (entries.length != 12) _invalid('FIR matrix requires twelve frames');
  final seen = <String>{};
  final frames = <FirFixtureFrame>[];
  for (final raw in entries) {
    if (raw is! Map<String, Object?>) _invalid('Invalid FIR frame');
    final file = _field<String>(raw, 'file');
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]*\.jpg$').hasMatch(file) ||
        !seen.add(file.toLowerCase())) {
      _invalid('Invalid or duplicate FIR source: $file');
    }
    final label = _field<String>(raw, 'fir');
    if (label != 'yes' && label != 'no') _invalid('Invalid FIR label: $file');
    final hash = raw['sha256'];
    if (hash != null &&
        (hash is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash))) {
      _invalid('Invalid FIR source hash: $file');
    }
    final origin = _field<Map<String, Object?>>(raw, 'imageClientOrigin');
    final captured = _field<Map<String, Object?>>(raw, 'capturedClientRect');
    final frame = FirFixtureFrame(
      file: file,
      expectedFir: label,
      expectedHash: hash as String?,
      clientWidth: _field<int>(raw, 'clientWidth'),
      clientHeight: _field<int>(raw, 'clientHeight'),
      imageWidth: _field<int>(raw, 'imageWidth'),
      imageHeight: _field<int>(raw, 'imageHeight'),
      imageOriginX: _field<int>(origin, 'x'),
      imageOriginY: _field<int>(origin, 'y'),
      capturedLeft: _field<int>(captured, 'left'),
      capturedTop: _field<int>(captured, 'top'),
      capturedWidth: _field<int>(captured, 'width'),
      capturedHeight: _field<int>(captured, 'height'),
      markerX: _field<int>(raw, 'markerX'),
      markerY: _field<int>(raw, 'markerY'),
    );
    if (frame.clientWidth <= 0 ||
        frame.clientHeight <= 0 ||
        frame.imageWidth <= 0 ||
        frame.imageHeight <= 0 ||
        frame.capturedWidth <= 0 ||
        frame.capturedHeight <= 0 ||
        frame.imageOriginX < 0 ||
        frame.imageOriginY < 0 ||
        frame.capturedLeft < 0 ||
        frame.capturedTop < 0 ||
        frame.imageOriginX + frame.capturedWidth > frame.imageWidth ||
        frame.imageOriginY + frame.capturedHeight > frame.imageHeight ||
        frame.capturedLeft + frame.capturedWidth > frame.clientWidth ||
        frame.capturedTop + frame.capturedHeight > frame.clientHeight ||
        frame.markerX < frame.capturedLeft ||
        frame.markerY < frame.capturedTop ||
        frame.markerX >= frame.capturedLeft + frame.capturedWidth ||
        frame.markerY >= frame.capturedTop + frame.capturedHeight) {
      _invalid('Inconsistent FIR geometry: $file');
    }
    frames.add(frame);
  }
  if (frames.where((frame) => frame.expectedFir == 'yes').length != 6) {
    _invalid('FIR matrix requires six positive and six negative labels');
  }
  return FirManifest(inputRoot, List.unmodifiable(frames));
}

/// Whether a source is verifiable and agrees with its frozen identity.
enum FirSourceStatus { verified, missingSource, missingHash, hashMismatch }

/// The identity check for one supplied source.
final class FirSourceIdentity {
  /// Creates an identity result.
  const FirSourceIdentity(this.status, this.actualHash);

  /// The verification status.
  final FirSourceStatus status;

  /// The observed SHA-256 when source bytes were available.
  final String? actualHash;
}

/// Checks supplied bytes against the expected source hash.
FirSourceIdentity verifyFirSource(FirFixtureFrame frame, Uint8List? source) {
  final actual = source == null ? null : sha256.convert(source).toString();
  if (frame.expectedHash == null) {
    return FirSourceIdentity(FirSourceStatus.missingHash, actual);
  }
  if (actual == null) {
    return const FirSourceIdentity(FirSourceStatus.missingSource, null);
  }
  return FirSourceIdentity(
    actual == frame.expectedHash
        ? FirSourceStatus.verified
        : FirSourceStatus.hashMismatch,
    actual,
  );
}

/// One matrix input and the result of checking its source identity.
final class FirInputCheck {
  /// Creates an input check.
  const FirInputCheck(this.frame, this.identity);

  /// The frozen frame annotation.
  final FirFixtureFrame frame;

  /// The identity check for this frame.
  final FirSourceIdentity identity;
}

/// Checks all inputs one at a time without retaining source bytes.
List<FirInputCheck> checkFirInputs(
  FirManifest manifest,
  Uint8List? Function(FirFixtureFrame frame) readSource,
) => [
  for (final frame in manifest.frames)
    FirInputCheck(frame, verifyFirSource(frame, readSource(frame))),
];

/// Whether every frozen case has a source with the expected hash.
bool firInputsComplete(List<FirInputCheck> inputs) =>
    inputs.length == 12 &&
    inputs.every((input) => input.identity.status == FirSourceStatus.verified);

/// Captured pixels with their independent client geometry.
final class FirCapturedImage {
  /// Creates a normalized image and its client-space origin.
  const FirCapturedImage(
    this.image,
    this.clientWidth,
    this.clientHeight,
    this.left,
    this.top,
  );

  /// The tightly packed BGRX image of the captured rectangle.
  final VisionImage image;

  /// Physical client width.
  final int clientWidth;

  /// Physical client height.
  final int clientHeight;

  /// Client-space left edge.
  final int left;

  /// Client-space top edge.
  final int top;
}

/// Removes annotated image borders without scaling or padding the captured area.
FirCapturedImage normalizeFirImage(FirFixtureFrame frame, image.Image decoded) {
  if (decoded.width != frame.imageWidth ||
      decoded.height != frame.imageHeight) {
    _invalid('Decoded dimensions disagree with ${frame.file}');
  }
  final width = frame.capturedWidth;
  final height = frame.capturedHeight;
  final bytes = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final pixel = decoded.getPixel(
        frame.imageOriginX + x,
        frame.imageOriginY + y,
      );
      final offset = (y * width + x) * 4;
      bytes[offset] = pixel.b.toInt();
      bytes[offset + 1] = pixel.g.toInt();
      bytes[offset + 2] = pixel.r.toInt();
      bytes[offset + 3] = 255;
    }
  }
  return FirCapturedImage(
    VisionImage(
      bytes,
      width: width,
      height: height,
      stride: width * 4,
      channels: 4,
    ),
    frame.clientWidth,
    frame.clientHeight,
    frame.capturedLeft,
    frame.capturedTop,
  );
}

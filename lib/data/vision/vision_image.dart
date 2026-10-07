import 'dart:typed_data';

import 'vision_failure.dart';

export 'vision_failure.dart' show VisionInvalidImage;

/// Largest accepted image side in pixels (mirrors `BGV_MAX_SIDE`).
const int visionMaxSide = 8192;

/// Largest accepted pixel count (mirrors `BGV_MAX_PIXELS`).
const int visionMaxPixels = 24 * 1024 * 1024;

/// A caller-owned 8-bit image. The descriptor is validated in Dart before any
/// native call so malformed buffers never reach native code.
final class VisionImage {
  const VisionImage(
    this.bytes, {
    required this.width,
    required this.height,
    required this.stride,
    required this.channels,
  });

  final Uint8List bytes;
  final int width;
  final int height;

  /// Bytes between the starts of consecutive rows.
  final int stride;

  /// Interleaved 8-bit channels: 1, 3 or 4.
  final int channels;

  /// Null when the descriptor and buffer satisfy the native contract.
  VisionInvalidImage? validate() {
    if (width < 1 || width > visionMaxSide) {
      return VisionInvalidImage('width $width is outside 1..$visionMaxSide');
    }
    if (height < 1 || height > visionMaxSide) {
      return VisionInvalidImage('height $height is outside 1..$visionMaxSide');
    }
    if (width * height > visionMaxPixels) {
      return VisionInvalidImage(
        '${width}x$height exceeds $visionMaxPixels pixels',
      );
    }
    if (channels != 1 && channels != 3 && channels != 4) {
      return VisionInvalidImage('channels $channels is not 1, 3 or 4');
    }
    if (stride < width * channels) {
      return VisionInvalidImage(
        'stride $stride is shorter than width*channels ${width * channels}',
      );
    }
    if (bytes.length < stride * height) {
      return VisionInvalidImage(
        'buffer of ${bytes.length} bytes is shorter than stride*height '
        '${stride * height}',
      );
    }
    return null;
  }

  /// Validates [template] and that it fits inside [image].
  static VisionInvalidImage? validateTemplate(
    VisionImage image,
    VisionImage template,
  ) {
    final templateFailure = template.validate();
    if (templateFailure != null) {
      return VisionInvalidImage('template: ${templateFailure.reason}');
    }
    if (template.width > image.width || template.height > image.height) {
      return VisionInvalidImage(
        'template ${template.width}x${template.height} is larger than image '
        '${image.width}x${image.height}',
      );
    }
    return null;
  }
}

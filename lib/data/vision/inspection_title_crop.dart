/// Bounds the blank right margin of a thresholded inspection title before
/// OCR, so raw-line OCR has no wide white strip in which to invent a suffix.
library;

import 'dart:typed_data';

import 'vision_image.dart';

/// White pixels kept after the exclusive right edge of the rightmost
/// foreground pixel.
const int titleRightMargin = 8;

/// The outcome of [boundTitleMargin]: a title with foreground to read, or a
/// blank one with nothing to read.
sealed class BoundedTitle {
  const BoundedTitle();
}

/// A title image holding at least one foreground pixel.
final class TitleWithForeground extends BoundedTitle {
  /// Wraps the bounded [image].
  const TitleWithForeground(this.image);

  /// The image to OCR: the source itself when no column was dropped, else a
  /// tightly packed copy of its leftmost columns.
  final VisionImage image;
}

/// A title image whose logical pixels are all white.
final class BlankTitle extends BoundedTitle {
  /// The single blank outcome.
  const BlankTitle();
}

/// Bounds [binary], a one-channel inverted threshold of a title crop, to end
/// [titleRightMargin] pixels after its rightmost foreground pixel.
///
/// Black pixels (value 0) are foreground. The rightmost foreground column is
/// found across every logical row; row padding past `width` is ignored. The
/// width is capped at the source width, and the left edge, height and every
/// pixel left of the new edge are kept.
///
/// Returns [BlankTitle] when no logical pixel is black. Returns [binary]
/// itself when the bound does not narrow it; otherwise a new tightly packed
/// copy, leaving [binary] unchanged.
///
/// Throws an [ArgumentError] when [binary] is not a valid one-channel image.
BoundedTitle boundTitleMargin(VisionImage binary) {
  final invalid = binary.validate();
  if (invalid != null) {
    throw ArgumentError.value(binary, 'binary', invalid.reason);
  }
  if (binary.channels != 1) {
    throw ArgumentError.value(
      binary,
      'binary',
      'channels ${binary.channels} is not 1',
    );
  }

  final VisionImage(:bytes, :width, :height, :stride) = binary;
  var last = -1;
  for (var y = 0; y < height && last < width - 1; y++) {
    final start = y * stride;
    for (var x = width - 1; x > last; x--) {
      if (bytes[start + x] == 0) {
        last = x;
        break;
      }
    }
  }
  if (last < 0) return const BlankTitle();

  final bounded = last + 1 + titleRightMargin;
  if (bounded >= width) return TitleWithForeground(binary);

  final copy = Uint8List(bounded * height);
  for (var y = 0; y < height; y++) {
    copy.setRange(y * bounded, (y + 1) * bounded, bytes, y * stride);
  }
  return TitleWithForeground(
    VisionImage(
      copy,
      width: bounded,
      height: height,
      stride: bounded,
      channels: 1,
    ),
  );
}

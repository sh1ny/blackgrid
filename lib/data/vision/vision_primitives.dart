import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'vision_image.dart';

/// `bgv_resize` interpolation modes.
const int visionInterCubic = 0;
const int visionInterArea = 1;

/// A negative native status, or an engine failure, surfaced from a binding.
final class VisionNativeError implements Exception {
  const VisionNativeError(this.status, [this.detail = '']);

  final int status;
  final String detail;

  @override
  String toString() => detail.isEmpty
      ? 'native status $status'
      : 'native status $status: $detail';
}

/// Best template match: normalised score and top-left location.
final class TemplateMatch {
  const TemplateMatch(this.score, this.x, this.y);

  final double score;
  final int x;
  final int y;
}

/// The `bgv_*` primitives over validated images. Implementations throw
/// [VisionNativeError] for a negative native status.
abstract interface class VisionPrimitives {
  /// Tight 1-channel w x h output.
  Uint8List toGray(VisionImage src, {required bool rgbOrder});

  /// Tight output with the source channel count.
  Uint8List resize(VisionImage src, int dw, int dh, int interp);

  /// 1-channel `dst = src > thresh ? 0 : maxval`.
  Uint8List thresholdBinaryInv(VisionImage src, int thresh, int maxval);

  TemplateMatch matchTemplateBest(VisionImage image, VisionImage template);

  /// Null when no pixel in the row is in range.
  int? findInRangeRow(
    VisionImage src,
    int row,
    int startX,
    List<int> lo,
    List<int> hi,
  );
}

typedef _Gray = int Function(
  Pointer<Uint8>,
  int,
  int,
  int,
  int,
  int,
  Pointer<Uint8>,
  int,
);
typedef _Resize = int Function(
  Pointer<Uint8>,
  int,
  int,
  int,
  int,
  Pointer<Uint8>,
  int,
  int,
  int,
  int,
);
typedef _Threshold = int Function(
  Pointer<Uint8>,
  int,
  int,
  int,
  int,
  int,
  Pointer<Uint8>,
  int,
);
typedef _Match = int Function(
  Pointer<Uint8>,
  int,
  int,
  int,
  Pointer<Uint8>,
  int,
  int,
  int,
  Pointer<Double>,
  Pointer<Int32>,
  Pointer<Int32>,
);
typedef _FindRow = int Function(
  Pointer<Uint8>,
  int,
  int,
  int,
  int,
  int,
  int,
  Pointer<Uint8>,
  Pointer<Uint8>,
  Pointer<Int32>,
);

/// `bgv_*` backed by the loaded vision library with Dart-owned buffers.
final class FfiVisionPrimitives implements VisionPrimitives {
  FfiVisionPrimitives(DynamicLibrary library)
    : _toGray = library
          .lookupFunction<
            Int32 Function(
              Pointer<Uint8>,
              Int32,
              Int32,
              Int32,
              Int32,
              Int32,
              Pointer<Uint8>,
              Int32,
            ),
            _Gray
          >('bgv_to_gray'),
      _resize = library
          .lookupFunction<
            Int32 Function(
              Pointer<Uint8>,
              Int32,
              Int32,
              Int32,
              Int32,
              Pointer<Uint8>,
              Int32,
              Int32,
              Int32,
              Int32,
            ),
            _Resize
          >('bgv_resize'),
      _threshold = library
          .lookupFunction<
            Int32 Function(
              Pointer<Uint8>,
              Int32,
              Int32,
              Int32,
              Int32,
              Int32,
              Pointer<Uint8>,
              Int32,
            ),
            _Threshold
          >('bgv_threshold_binary_inv'),
      _match = library
          .lookupFunction<
            Int32 Function(
              Pointer<Uint8>,
              Int32,
              Int32,
              Int32,
              Pointer<Uint8>,
              Int32,
              Int32,
              Int32,
              Pointer<Double>,
              Pointer<Int32>,
              Pointer<Int32>,
            ),
            _Match
          >('bgv_match_template_best'),
      _findRow = library
          .lookupFunction<
            Int32 Function(
              Pointer<Uint8>,
              Int32,
              Int32,
              Int32,
              Int32,
              Int32,
              Int32,
              Pointer<Uint8>,
              Pointer<Uint8>,
              Pointer<Int32>,
            ),
            _FindRow
          >('bgv_find_in_range_row');

  final _Gray _toGray;
  final _Resize _resize;
  final _Threshold _threshold;
  final _Match _match;
  final _FindRow _findRow;

  static Pointer<Uint8> _copyIn(VisionImage image) {
    final size = image.stride * image.height;
    final buffer = calloc<Uint8>(size);
    buffer
        .asTypedList(size)
        .setAll(0, Uint8List.sublistView(image.bytes, 0, size));
    return buffer;
  }

  static void _check(int status) {
    if (status < 0) throw VisionNativeError(status);
  }

  Uint8List _withOutput(
    VisionImage src,
    int outBytes,
    int Function(Pointer<Uint8> input, Pointer<Uint8> output) call,
  ) {
    final input = _copyIn(src);
    final output = calloc<Uint8>(outBytes);
    try {
      _check(call(input, output));
      return Uint8List.fromList(output.asTypedList(outBytes));
    } finally {
      calloc.free(input);
      calloc.free(output);
    }
  }

  @override
  Uint8List toGray(VisionImage src, {required bool rgbOrder}) => _withOutput(
    src,
    src.width * src.height,
    (input, output) => _toGray(
      input,
      src.width,
      src.height,
      src.stride,
      src.channels,
      rgbOrder ? 1 : 0,
      output,
      src.width,
    ),
  );

  @override
  Uint8List resize(VisionImage src, int dw, int dh, int interp) {
    final dstStride = dw * src.channels;
    return _withOutput(
      src,
      dstStride * dh,
      (input, output) => _resize(
        input,
        src.width,
        src.height,
        src.stride,
        src.channels,
        output,
        dw,
        dh,
        dstStride,
        interp,
      ),
    );
  }

  @override
  Uint8List thresholdBinaryInv(VisionImage src, int thresh, int maxval) =>
      _withOutput(
        src,
        src.width * src.height,
        (input, output) => _threshold(
          input,
          src.width,
          src.height,
          src.stride,
          thresh,
          maxval,
          output,
          src.width,
        ),
      );

  @override
  TemplateMatch matchTemplateBest(VisionImage image, VisionImage template) {
    final img = _copyIn(image);
    final tpl = _copyIn(template);
    final score = calloc<Double>();
    final x = calloc<Int32>();
    final y = calloc<Int32>();
    try {
      _check(
        _match(
          img,
          image.width,
          image.height,
          image.stride,
          tpl,
          template.width,
          template.height,
          template.stride,
          score,
          x,
          y,
        ),
      );
      return TemplateMatch(score.value, x.value, y.value);
    } finally {
      calloc.free(img);
      calloc.free(tpl);
      calloc.free(score);
      calloc.free(x);
      calloc.free(y);
    }
  }

  @override
  int? findInRangeRow(
    VisionImage src,
    int row,
    int startX,
    List<int> lo,
    List<int> hi,
  ) {
    final input = _copyIn(src);
    final low = calloc<Uint8>(3);
    final high = calloc<Uint8>(3);
    final out = calloc<Int32>();
    try {
      low.asTypedList(3).setAll(0, lo);
      high.asTypedList(3).setAll(0, hi);
      final status = _findRow(
        input,
        src.width,
        src.height,
        src.stride,
        src.channels,
        row,
        startX,
        low,
        high,
        out,
      );
      _check(status);
      return status == 1 ? null : out.value;
    } finally {
      calloc.free(input);
      calloc.free(low);
      calloc.free(high);
      calloc.free(out);
    }
  }
}

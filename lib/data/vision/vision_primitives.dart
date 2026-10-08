import 'dart:ffi';
import 'dart:typed_data';

import 'vision_image.dart';
import 'vision_scratch.dart';

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

/// `bgv_to_gray` as Dart sees it.
typedef VisionGrayFn = int Function(
  Pointer<Uint8>,
  int,
  int,
  int,
  int,
  int,
  Pointer<Uint8>,
  int,
);

/// `bgv_resize` as Dart sees it.
typedef VisionResizeFn = int Function(
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

/// `bgv_threshold_binary_inv` as Dart sees it.
typedef VisionThresholdFn = int Function(
  Pointer<Uint8>,
  int,
  int,
  int,
  int,
  int,
  Pointer<Uint8>,
  int,
);

/// `bgv_match_template_best` as Dart sees it.
typedef VisionMatchFn = int Function(
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

/// `bgv_find_in_range_row` as Dart sees it.
typedef VisionFindRowFn = int Function(
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
///
/// Inputs and outputs are staged through the runtime's [VisionScratch], so
/// repeated calls of the same size allocate nothing new.
final class FfiVisionPrimitives implements VisionPrimitives {
  FfiVisionPrimitives(DynamicLibrary library, VisionScratch scratch)
    : this.fromFunctions(
        scratch: scratch,
        toGray: library
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
              VisionGrayFn
            >('bgv_to_gray'),
        resize: library
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
              VisionResizeFn
            >('bgv_resize'),
        threshold: library
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
              VisionThresholdFn
            >('bgv_threshold_binary_inv'),
        match: library
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
              VisionMatchFn
            >('bgv_match_template_best'),
        findRow: library
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
              VisionFindRowFn
            >('bgv_find_in_range_row'),
      );

  /// Builds the primitives over already-resolved functions. Production goes
  /// through the library constructor; tests pass Dart stand-ins.
  FfiVisionPrimitives.fromFunctions({
    required this._scratch,
    required this._toGray,
    required this._resize,
    required this._threshold,
    required this._match,
    required this._findRow,
  });

  final VisionScratch _scratch;
  final VisionGrayFn _toGray;
  final VisionResizeFn _resize;
  final VisionThresholdFn _threshold;
  final VisionMatchFn _match;
  final VisionFindRowFn _findRow;

  static void _check(int status) {
    if (status < 0) throw VisionNativeError(status);
  }

  Uint8List _withOutput(
    VisionImage src,
    int outBytes,
    int Function(Pointer<Uint8> input, Pointer<Uint8> output) call,
  ) {
    final input = _scratch.input.stage(src);
    final output = _scratch.output.ensure(outBytes);
    _check(call(input, output));
    return Uint8List.fromList(output.asTypedList(outBytes));
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
    final img = _scratch.input.stage(image);
    final tpl = _scratch.template.stage(template);
    final aux = _scratch.aux;
    final score = aux.cast<Double>();
    final x = (aux + 8).cast<Int32>();
    final y = (aux + 12).cast<Int32>();
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
  }

  @override
  int? findInRangeRow(
    VisionImage src,
    int row,
    int startX,
    List<int> lo,
    List<int> hi,
  ) {
    final input = _scratch.input.stage(src);
    final aux = _scratch.aux;
    final out = (aux + 16).cast<Int32>();
    final low = aux + 20;
    final high = aux + 24;
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
  }
}

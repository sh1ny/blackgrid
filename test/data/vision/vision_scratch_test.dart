import 'dart:ffi';
import 'dart:typed_data';

import 'package:blackgrid/data/vision/tesseract_binding.dart';
import 'package:blackgrid/data/vision/vision_image.dart';
import 'package:blackgrid/data/vision/vision_native.dart' show OcrText;
import 'package:blackgrid/data/vision/vision_primitives.dart';
import 'package:blackgrid/data/vision/vision_scratch.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

/// Delegates to [calloc] and counts every allocate and free.
final class CountingAllocator implements Allocator {
  int allocations = 0;
  int frees = 0;
  int liveBytes = 0;

  /// When set, the next allocation throws instead of allocating.
  Object? failNext;

  final Map<int, int> _sizes = {};

  int get liveBlocks => _sizes.length;

  @override
  Pointer<T> allocate<T extends NativeType>(int byteCount, {int? alignment}) {
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      throw failure;
    }
    final pointer = calloc.allocate<T>(byteCount, alignment: alignment);
    allocations++;
    liveBytes += byteCount;
    _sizes[pointer.address] = byteCount;
    return pointer;
  }

  @override
  void free(Pointer pointer) {
    frees++;
    liveBytes -= _sizes.remove(pointer.address)!;
    calloc.free(pointer);
  }
}

VisionImage image(int width, int height, int channels, {int pad = 0}) {
  final stride = width * channels + pad;
  return VisionImage(
    Uint8List.fromList([
      for (var i = 0; i < stride * height; i++) (i * 7 + 3) & 0xff,
    ]),
    width: width,
    height: height,
    stride: stride,
    channels: channels,
  );
}

Uint8List _bytes(Pointer<Uint8> p, int n) => p.asTypedList(n);

// Pure-Dart references: the per-call result each stand-in must reproduce.
Uint8List refGray(VisionImage s) => Uint8List.fromList([
  for (var y = 0; y < s.height; y++)
    for (var x = 0; x < s.width; x++) s.bytes[y * s.stride + x * s.channels],
]);

Uint8List refResize(VisionImage s, int dw, int dh) {
  final n = s.stride * s.height;
  return Uint8List.fromList([
    for (var i = 0; i < dw * s.channels * dh; i++) (s.bytes[i % n] + i) & 0xff,
  ]);
}

Uint8List refThreshold(VisionImage s, int thresh, int maxval) =>
    Uint8List.fromList([for (final v in refGray(s)) v > thresh ? 0 : maxval]);

/// Dart stand-ins that read only `stride * height` input bytes and write only
/// the output bytes they report, like the real library.
FfiVisionPrimitives primitivesOver(VisionScratch scratch) =>
    FfiVisionPrimitives.fromFunctions(
      scratch: scratch,
      toGray: (inp, w, h, stride, ch, rgb, out, dstStride) {
        final src = _bytes(inp, stride * h);
        final dst = _bytes(out, w * h);
        for (var y = 0; y < h; y++) {
          for (var x = 0; x < w; x++) {
            dst[y * dstStride + x] = src[y * stride + x * ch];
          }
        }
        return 0;
      },
      resize: (inp, w, h, stride, ch, out, dw, dh, dstStride, interp) {
        final src = _bytes(inp, stride * h);
        final dst = _bytes(out, dstStride * dh);
        for (var i = 0; i < dst.length; i++) {
          dst[i] = (src[i % src.length] + i) & 0xff;
        }
        return 0;
      },
      threshold: (inp, w, h, stride, thresh, maxval, out, dstStride) {
        final src = _bytes(inp, stride * h);
        final dst = _bytes(out, w * h);
        for (var y = 0; y < h; y++) {
          for (var x = 0; x < w; x++) {
            dst[y * dstStride + x] = src[y * stride + x] > thresh ? 0 : maxval;
          }
        }
        return 0;
      },
      match: (img, w, h, stride, tpl, tw, th, tstride, score, x, y) {
        score.value = _bytes(img, stride * h)[0] / 255;
        x.value = _bytes(tpl, tstride * th)[0];
        y.value = tw + th;
        return 0;
      },
      findRow: (inp, w, h, stride, ch, row, startX, lo, hi, out) {
        final low = _bytes(lo, 3);
        final high = _bytes(hi, 3);
        final src = _bytes(inp, stride * h);
        if (low[0] > high[0]) return 1;
        out.value = src[row * stride + startX * ch] + low[1] + high[2];
        return 0;
      },
    );

void main() {
  group('VisionScratch', () {
    test('a buffer that fits is reused without a new allocation', () {
      final allocator = CountingAllocator();
      final scratch = VisionScratch(allocator: allocator);
      final first = scratch.input.ensure(64);
      final again = scratch.input.ensure(64);
      scratch.input.ensure(10);
      expect(again.address, first.address);
      expect(allocator.allocations, 1);
      scratch.dispose();
    });

    test('a larger request grows by freeing the old block first', () {
      final allocator = CountingAllocator();
      final scratch = VisionScratch(allocator: allocator);
      scratch.input.ensure(64);
      scratch.input.ensure(128);
      expect(allocator.allocations, 2);
      expect(allocator.frees, 1);
      expect(allocator.liveBytes, 128);
      expect(scratch.input.capacity, 128);
      scratch.dispose();
    });

    test('trim shrinks only buffers above the retention cap', () {
      final allocator = CountingAllocator();
      final scratch = VisionScratch(allocator: allocator);
      final small = scratch.template.ensure(1024);
      scratch.input.ensure(visionScratchRetainBytes + 1);
      scratch.output.ensure(visionScratchRetainBytes);
      final before = allocator.allocations;

      scratch.trim();

      expect(scratch.input.capacity, visionScratchRetainBytes);
      expect(scratch.output.capacity, visionScratchRetainBytes);
      expect(scratch.template.capacity, 1024);
      expect(scratch.template.ensure(1024).address, small.address);
      expect(allocator.allocations, before + 1);
      expect(allocator.liveBytes, 1024 + 2 * visionScratchRetainBytes);
      scratch.dispose();
    });

    test('dispose frees every block and is idempotent', () {
      final allocator = CountingAllocator();
      final scratch = VisionScratch(allocator: allocator);
      scratch.input.ensure(10);
      scratch.template.ensure(20);
      scratch.output.ensure(30);
      expect(scratch.aux, isNot(nullptr));

      scratch.dispose();
      scratch.dispose();

      expect(allocator.liveBlocks, 0);
      expect(allocator.liveBytes, 0);
      expect(scratch.capacity, 0);
    });

    test('an allocation failure propagates and leaves the buffer usable', () {
      final allocator = CountingAllocator();
      final scratch = VisionScratch(allocator: allocator);
      scratch.input.ensure(16);
      allocator.failNext = StateError('out of memory');

      expect(() => scratch.input.ensure(32), throwsStateError);
      expect(scratch.input.capacity, 0);
      expect(allocator.liveBlocks, 0);

      scratch.input.ensure(32);
      expect(scratch.input.capacity, 32);
      scratch.dispose();
      expect(allocator.liveBlocks, 0);
    });
  });

  group('FfiVisionPrimitives over the scratch pool', () {
    late CountingAllocator allocator;
    late VisionScratch scratch;
    late FfiVisionPrimitives primitives;

    setUp(() {
      allocator = CountingAllocator();
      scratch = VisionScratch(allocator: allocator);
      primitives = primitivesOver(scratch);
    });
    tearDown(() => scratch.dispose());

    /// Runs [call] repeatedly and expects only the first to allocate.
    void expectReused(void Function() call) {
      call();
      expect(allocator.allocations, greaterThan(0), reason: 'uses the pool');
      final warm = allocator.allocations;
      call();
      call();
      expect(allocator.allocations, warm);
      expect(allocator.frees, 0);
    }

    test('toGray reuses buffers and matches the per-call output', () {
      final src = image(8, 8, 3, pad: 2);
      expectReused(() => primitives.toGray(src, rgbOrder: true));
      expect(primitives.toGray(src, rgbOrder: true), refGray(src));
    });

    test('resize reuses buffers and matches the per-call output', () {
      final src = image(8, 8, 4);
      expectReused(() => primitives.resize(src, 4, 4, visionInterArea));
      expect(
        primitives.resize(src, 4, 4, visionInterArea),
        refResize(src, 4, 4),
      );
    });

    test('thresholdBinaryInv reuses buffers and matches', () {
      final src = image(8, 8, 1, pad: 3);
      expectReused(() => primitives.thresholdBinaryInv(src, 100, 255));
      expect(
        primitives.thresholdBinaryInv(src, 100, 255),
        refThreshold(src, 100, 255),
      );
    });

    test('matchTemplateBest reuses buffers and matches', () {
      final img = image(8, 8, 1);
      final tpl = image(3, 2, 1);
      expectReused(() => primitives.matchTemplateBest(img, tpl));
      final match = primitives.matchTemplateBest(img, tpl);
      expect(match.score, img.bytes[0] / 255);
      expect(match.x, tpl.bytes[0]);
      expect(match.y, 5);
    });

    test('findInRangeRow reuses buffers and matches', () {
      final src = image(8, 8, 3);
      final lo = [0, 5, 0];
      final hi = [9, 9, 7];
      expectReused(() => primitives.findInRangeRow(src, 2, 1, lo, hi));
      expect(
        primitives.findInRangeRow(src, 2, 1, lo, hi),
        src.bytes[2 * src.stride + 3] + 5 + 7,
      );
      expect(
        primitives.findInRangeRow(src, 2, 1, [9, 0, 0], [0, 0, 0]),
        isNull,
      );
    });

    test('a smaller call after a larger one is not polluted by stale data', () {
      final big = image(16, 16, 3);
      final small = image(4, 4, 3, pad: 1);
      primitives.toGray(big, rgbOrder: false);
      primitives.resize(big, 16, 16, visionInterCubic);
      final warm = allocator.allocations;

      expect(primitives.toGray(small, rgbOrder: false), refGray(small));
      expect(
        primitives.resize(small, 2, 2, visionInterCubic),
        refResize(small, 2, 2),
      );
      expect(allocator.allocations, warm);
    });

    test('a native failure still leaves the pool intact', () {
      final failing = FfiVisionPrimitives.fromFunctions(
        scratch: scratch,
        toGray: (a, b, c, d, e, f, g, h) => -4,
        resize: (a, b, c, d, e, f, g, h, i, j) => -4,
        threshold: (a, b, c, d, e, f, g, h) => -4,
        match: (a, b, c, d, e, f, g, h, i, j, k) => -4,
        findRow: (a, b, c, d, e, f, g, h, i, j) => -4,
      );
      final src = image(4, 4, 1);

      expect(
        () => failing.toGray(src, rgbOrder: false),
        throwsA(isA<VisionNativeError>().having((e) => e.status, 'status', -4)),
      );
      final warm = allocator.allocations;
      expect(primitives.toGray(src, rgbOrder: false), refGray(src));
      expect(allocator.allocations, warm);
    });
  });

  group('recogniseStaged over the scratch pool', () {
    late CountingAllocator allocator;
    late VisionScratch scratch;

    setUp(() {
      allocator = CountingAllocator();
      scratch = VisionScratch(allocator: allocator);
    });
    tearDown(() => scratch.dispose());

    OcrText recognise(VisionImage src, {List<int>? staged}) {
      var clears = 0;
      final text = recogniseStaged(
        scratch: scratch,
        image: src,
        setImage: (buffer) =>
            staged?.addAll(_bytes(buffer, src.stride * src.height)),
        getText: () => 'ok'.toNativeUtf8(allocator: calloc),
        deleteText: calloc.free,
        clear: () => clears++,
      );
      expect(clears, 1);
      return text;
    }

    test('repeated calls of the same size allocate no new buffer', () {
      final src = image(8, 4, 1, pad: 2);
      recognise(src);
      expect(allocator.allocations, greaterThan(0), reason: 'uses the pool');
      final warm = allocator.allocations;

      recognise(src);
      recognise(src);

      expect(allocator.allocations, warm);
      expect(allocator.frees, 0);
    });

    test('the engine sees exactly the staged image bytes', () {
      final src = image(8, 4, 1, pad: 2);
      recognise(image(16, 16, 1));
      final staged = <int>[];

      final text = recognise(src, staged: staged);

      expect(text.text, 'ok');
      expect(staged, src.bytes.sublist(0, src.stride * src.height));
    });

    test('a failing engine still clears the image and keeps the pool', () {
      var clears = 0;
      final src = image(4, 4, 1);
      expect(
        () => recogniseStaged(
          scratch: scratch,
          image: src,
          setImage: (_) {},
          getText: () => nullptr,
          deleteText: (_) {},
          clear: () => clears++,
        ),
        throwsA(isA<VisionNativeError>().having((e) => e.status, 'status', -5)),
      );
      expect(clears, 1);
      expect(allocator.liveBlocks, 1);
    });
  });
}

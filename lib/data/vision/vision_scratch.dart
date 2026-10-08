import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'vision_image.dart';

/// Retained capacity per scratch buffer after [VisionScratch.trim] (D6).
const int visionScratchRetainBytes = 16 * 1024 * 1024;

/// Bytes of the `aux` buffer: score, x, y, out, low and high scalars.
const int _auxBytes = 32;

/// One reusable native buffer. It grows to the largest request and keeps no
/// data between requests, so a resize frees the old block first and never
/// holds two large blocks at once.
final class ScratchBuffer {
  ScratchBuffer._(this._allocator);

  final Allocator _allocator;
  Pointer<Uint8> _pointer = nullptr;
  int _capacity = 0;

  /// Bytes currently allocated (0 when nothing is held).
  int get capacity => _capacity;

  /// A pointer to at least [size] bytes. Content is unspecified. Throws if
  /// the allocator fails, leaving the buffer empty.
  Pointer<Uint8> ensure(int size) {
    if (size <= _capacity) return _pointer;
    _release();
    _pointer = _allocator.allocate<Uint8>(size);
    _capacity = size;
    return _pointer;
  }

  /// Copies the first `stride * height` bytes of [image] in and returns the
  /// buffer.
  Pointer<Uint8> stage(VisionImage image) {
    final size = image.stride * image.height;
    final buffer = ensure(size);
    buffer
        .asTypedList(size)
        .setAll(0, Uint8List.sublistView(image.bytes, 0, size));
    return buffer;
  }

  /// Shrinks a buffer larger than [retain] bytes to exactly [retain] bytes.
  void _trim(int retain) {
    if (_capacity <= retain) return;
    _release();
    _pointer = _allocator.allocate<Uint8>(retain);
    _capacity = retain;
  }

  void _release() {
    if (_pointer != nullptr) _allocator.free(_pointer);
    _pointer = nullptr;
    _capacity = 0;
  }
}

/// Native scratch buffers reused across vision calls instead of a
/// `calloc`/`free` pair per call. One pool belongs to one native stack and is
/// freed with it; it is not thread-safe.
final class VisionScratch {
  /// [allocator] is injectable so tests can count allocations.
  VisionScratch({Allocator allocator = calloc})
    : input = ScratchBuffer._(allocator),
      template = ScratchBuffer._(allocator),
      output = ScratchBuffer._(allocator),
      _aux = ScratchBuffer._(allocator);

  /// Staged source image (primitives and OCR).
  final ScratchBuffer input;

  /// Staged template image for template matching.
  final ScratchBuffer template;

  /// Primitive output pixels.
  final ScratchBuffer output;
  final ScratchBuffer _aux;

  /// Small fixed scalars, carved from one block: a double score and four
  /// ints, plus two 3-byte colour bounds.
  Pointer<Uint8> get aux => _aux.ensure(_auxBytes);

  /// Total bytes currently allocated across every buffer.
  int get capacity =>
      input.capacity + template.capacity + output.capacity + _aux.capacity;

  /// Shrinks every buffer above [retain] bytes back to [retain]. Called
  /// after a request ends so one full-client frame does not stay pinned.
  void trim({int retain = visionScratchRetainBytes}) {
    input._trim(retain);
    template._trim(retain);
    output._trim(retain);
    _aux._trim(retain);
  }

  /// Frees every buffer. Idempotent.
  void dispose() {
    input._release();
    template._release();
    output._release();
    _aux._release();
  }
}

/// A native stack that owns a [VisionScratch] and can trim it between
/// requests. Implemented by the FFI stack; fakes need not implement it.
abstract interface class VisionScratchOwner {
  /// Trims the owned scratch pool to its retention cap.
  void trimScratch();
}

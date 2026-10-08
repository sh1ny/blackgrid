import 'dart:ffi';
import 'dart:typed_data';

import 'capture_failure.dart';
import 'capture_snapshot.dart';

/// Pixel layout of a native frame. Only 32-bit BGRX exists (fourth byte
/// undefined).
enum CapturePixelFormat { bgrx }

enum CaptureRowOrder { topDown }

/// Immutable, sendable provenance of one frame (spec: Frames have an
/// immutable pixel layout / carry their provenance).
final class CaptureFrameMetadata {
  const CaptureFrameMetadata({
    required this.width,
    required this.height,
    required this.stride,
    required this.desktopLeft,
    required this.desktopTop,
    required this.requested,
    required this.captured,
    required this.clipped,
    required this.dpi,
    required this.hwnd,
    required this.pid,
    required this.tid,
    required this.exeName,
    required this.qpcBefore,
    required this.qpcAfter,
    required this.capturedAtUtc,
    required this.requestId,
  });

  final int width;
  final int height;

  /// Bytes per row, at least `width * 4`.
  final int stride;
  final int desktopLeft;
  final int desktopTop;

  /// Requested and captured rectangles in client pixels.
  final CaptureRect requested;
  final CaptureRect captured;
  final bool clipped;
  final int dpi;
  final int hwnd;
  final int pid;
  final int tid;
  final String exeName;
  final int qpcBefore;
  final int qpcAfter;
  final DateTime capturedAtUtc;
  final int requestId;

  CapturePixelFormat get pixelFormat => CapturePixelFormat.bgrx;
  CaptureRowOrder get rowOrder => CaptureRowOrder.topDown;

  /// Signed desktop origin of the first pixel.
  ({int x, int y}) get desktopOrigin => (x: desktopLeft, y: desktopTop);
}

/// A live native frame's memory.
final class FrameView {
  const FrameView(this.pixels, this.width, this.height, this.stride);

  final Pointer<Uint8> pixels;
  final int width;
  final int height;
  final int stride;
}

/// The frame store behind [CaptureFrame]: the native generation-checked slot
/// registry in production, a fake in tests. All ids are process-wide, so any
/// isolate may release a frame by id.
abstract interface class FrameRegistry {
  /// The live frame, or null when [frameId] is stale, released or unknown.
  FrameView? view(int frameId);

  /// Generation-checked; stale or repeated ids are no-ops.
  void release(int frameId);

  int get liveCount;

  /// Arranges for [frameId] to be released if [owner] is garbage collected.
  void attach(Finalizable owner, int frameId);

  /// Cancels the arrangement made by [attach] for [owner].
  void detach(Finalizable owner);
}

/// Sendable ownership token for one frame: the id plus its metadata. Exactly
/// one `CaptureFrame` may be adopted from it.
final class CaptureFrameTicket {
  const CaptureFrameTicket(this.frameId, this.metadata);

  final int frameId;
  final CaptureFrameMetadata metadata;
}

/// One captured frame with a single owner. Release it, or hand it to another
/// isolate with [handOff]. A finalizer releases it if the owner drops it.
///
/// Pixels are only lent, through [withPixels]: a bare view would not keep the
/// frame reachable, so its finalizer could free the slot under the reader.
final class CaptureFrame implements Finalizable {
  /// Takes ownership of a frame the registry just produced.
  CaptureFrame(this.frameId, this.metadata, this._registry) {
    _registry.attach(this, frameId);
  }

  /// Takes ownership of a frame handed off by another isolate.
  factory CaptureFrame.adopt(
    CaptureFrameTicket ticket,
    FrameRegistry registry,
  ) => CaptureFrame(ticket.frameId, ticket.metadata, registry);

  final int frameId;
  final CaptureFrameMetadata metadata;
  final FrameRegistry _registry;
  bool _released = false;
  int _lends = 0;

  bool get isReleased => _released;

  /// Lends a view over the native pixels (`stride * height` bytes) to [use],
  /// which must be synchronous and must not keep the view. The frame stays
  /// reachable and cannot be released or handed off until [use] returns.
  /// Throws [FrameReleasedError] without touching native memory once released
  /// or handed off.
  R withPixels<R>(R Function(Uint8List pixels) use) {
    if (_released) throw FrameReleasedError(frameId);
    final view = _registry.view(frameId);
    if (view == null) throw FrameReleasedError(frameId);
    _lends++;
    try {
      final result = use(view.pixels.asTypedList(view.stride * view.height));
      if (result is Future) {
        throw ArgumentError.value(use, 'use', 'must be synchronous');
      }
      return result;
    } finally {
      // Touching this after use returns keeps the frame reachable until then.
      _lends--;
    }
  }

  /// Releases the frame. Repeated release is a no-op. Throws [StateError]
  /// inside [withPixels].
  void release() {
    if (_released) return;
    _refuseWhileLent();
    _released = true;
    _registry.detach(this);
    _registry.release(frameId);
  }

  /// Moves ownership out: detaches the finalizer, marks this object released
  /// and returns the sendable ticket. Throws [StateError] inside [withPixels].
  CaptureFrameTicket handOff() {
    if (_released) throw FrameReleasedError(frameId);
    _refuseWhileLent();
    _released = true;
    _registry.detach(this);
    return CaptureFrameTicket(frameId, metadata);
  }

  void _refuseWhileLent() {
    if (_lends > 0) {
      throw StateError('frame $frameId is in use by withPixels');
    }
  }
}

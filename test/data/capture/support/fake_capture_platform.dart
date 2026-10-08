import 'dart:ffi';

import 'package:blackgrid/data/capture/capture_failure.dart';
import 'package:blackgrid/data/capture/capture_frame.dart';
import 'package:blackgrid/data/capture/capture_native.dart';
import 'package:blackgrid/data/capture/capture_snapshot.dart';
import 'package:ffi/ffi.dart';

const _maxFrames = 8;
const _header = 3;
const _perFrame = 6;

/// A frame registry whose state lives in native memory, so two isolates can
/// share it by address exactly like the real process-wide slot registry.
final class FakeFrameRegistry implements FrameRegistry {
  FakeFrameRegistry._(this._mem);

  factory FakeFrameRegistry.create() =>
      FakeFrameRegistry._(calloc<Int64>(_header + _maxFrames * _perFrame));

  /// Another isolate's view of the same registry.
  factory FakeFrameRegistry.fromAddress(int address) =>
      FakeFrameRegistry._(Pointer<Int64>.fromAddress(address));

  final Pointer<Int64> _mem;
  final Finalizer<int> _finalizer = Finalizer<int>((_) {});

  /// Per-instance bookkeeping, not shared.
  int viewCalls = 0;
  final List<int> releaseCalls = [];
  final List<Finalizable> attached = [];
  final List<Finalizable> detached = [];

  int get address => _mem.address;

  /// Effective releases across all isolates.
  int get effectiveReleases => _mem[1];

  /// Allocates a frame with deterministic non-zero pixels and returns its id.
  int createFrame(int width, int height, {int? stride, bool zeros = false}) {
    final s = stride ?? width * 4;
    final id = _mem[2] + 1;
    _mem[2] = id;
    final base = _header + (id - 1) * _perFrame;
    final pixels = calloc<Uint8>(s * height);
    if (!zeros) {
      for (var i = 0; i < s * height; i++) {
        pixels[i] = (i * 7 + 3) & 0xff;
      }
    }
    _mem[base] = 1;
    _mem[base + 1] = pixels.address;
    _mem[base + 2] = width;
    _mem[base + 3] = height;
    _mem[base + 4] = s;
    _mem[0] = _mem[0] + 1;
    return id;
  }

  bool _valid(int id) => id >= 1 && id <= _maxFrames;

  @override
  FrameView? view(int frameId) {
    viewCalls++;
    if (!_valid(frameId)) return null;
    final base = _header + (frameId - 1) * _perFrame;
    if (_mem[base] == 0) return null;
    return FrameView(
      Pointer<Uint8>.fromAddress(_mem[base + 1]),
      _mem[base + 2],
      _mem[base + 3],
      _mem[base + 4],
    );
  }

  @override
  void release(int frameId) {
    releaseCalls.add(frameId);
    if (!_valid(frameId)) return;
    final base = _header + (frameId - 1) * _perFrame;
    if (_mem[base] == 0) return;
    _mem[base] = 0;
    _mem[0] = _mem[0] - 1;
    _mem[1] = _mem[1] + 1;
  }

  @override
  int get liveCount => _mem[0];

  @override
  void attach(Finalizable owner, int frameId) {
    attached.add(owner);
    _finalizer.attach(owner, frameId, detach: owner);
  }

  @override
  void detach(Finalizable owner) {
    detached.add(owner);
    _finalizer.detach(owner);
  }
}

/// A scripted [CapturePlatform] that records every capture and release.
final class FakeCapturePlatform implements CapturePlatform {
  FakeCapturePlatform({required this.s0, this.exe = 'EscapeFromTarkov.exe'});

  @override
  final FakeFrameRegistry frames = FakeFrameRegistry.create();

  /// What `snapshot` returns (null: window gone).
  WindowSnapshot? s0;

  /// What `processName` returns.
  String? exe;

  /// Pre and post snapshots of the next capture (default: [s0]).
  WindowSnapshot? pre;
  WindowSnapshot? post;
  bool allZero = false;
  RawCaptureError? captureError;

  final List<({int hwnd, CaptureRect rect})> captureCalls = [];
  int processNameCalls = 0;
  int snapshotCalls = 0;
  int _qpc = 1000;

  @override
  WindowSnapshot? snapshot(int hwnd) {
    snapshotCalls++;
    return s0;
  }

  @override
  String? processName(int pid) {
    processNameCalls++;
    return exe;
  }

  @override
  RawCaptureResult capture(int hwnd, CaptureRect desktopRect) {
    captureCalls.add((hwnd: hwnd, rect: desktopRect));
    final error = captureError;
    if (error != null) return error;
    final id = frames.createFrame(
      desktopRect.width,
      desktopRect.height,
      zeros: allZero,
    );
    final before = _qpc += 10;
    final after = _qpc += 10;
    return RawCaptureOk(
      RawCapture(
        frameId: id,
        qpcBefore: before,
        qpcAfter: after,
        allZero: allZero,
        pre: pre ?? s0!,
        post: post ?? s0!,
      ),
    );
  }

  @override
  int qpcNow() => _qpc += 10;

  @override
  int qpcFrequency() => 10000000;

  @override
  TriggerFailure? hookStart(
    String title,
    Pointer<NativeFunction<Void Function()>> signal,
  ) => null;

  @override
  TriggerFailure? hookStop() => null;

  @override
  TriggerDrain hookDrain() => const TriggerDrain([], 0);
}

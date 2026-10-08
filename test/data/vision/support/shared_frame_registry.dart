import 'dart:ffi' show Finalizable;

import 'package:blackgrid/data/capture/capture_frame.dart';
import 'package:blackgrid/data/capture/capture_service.dart'
    show FrameRegistryFactory;

import '../../capture/support/fake_capture_platform.dart';

/// Top-level so the closure captures one int and can be sent to the worker:
/// the worker's registry is another isolate's view of the same native state as
/// the [FakeFrameRegistry] at [address], so both isolates see one set of frame
/// slots and counters.
FrameRegistryFactory sharedFrameRegistryFactory(int address) =>
    () => FakeFrameRegistry.fromAddress(address);

/// A registry over the shared fake state whose finalizer really releases the
/// frame (the fake's own finalizer is a no-op) and that does not keep the
/// owners it attaches, so a dropped frame can be garbage collected.
final class FinalizingFrameRegistry implements FrameRegistry {
  FinalizingFrameRegistry(this._inner)
    : _finalizer = Finalizer<int>(_inner.release);

  final FakeFrameRegistry _inner;
  final Finalizer<int> _finalizer;

  @override
  FrameView? view(int frameId) => _inner.view(frameId);

  @override
  void release(int frameId) => _inner.release(frameId);

  @override
  int get liveCount => _inner.liveCount;

  @override
  void attach(Finalizable owner, int frameId) =>
      _finalizer.attach(owner, frameId, detach: owner);

  @override
  void detach(Finalizable owner) => _finalizer.detach(owner);
}

/// Applies allocation pressure until [done] holds or [attempts] run out. There
/// is no API to force a collection, and a finalizer runs from an event after
/// one, so each round yields to the event loop (a zero-length yield, not a
/// wait). The caller asserts the outcome.
Future<void> collectGarbageUntil(
  bool Function() done, {
  int attempts = 400,
}) async {
  final garbage = <List<int>>[];
  for (var round = 0; round < attempts && !done(); round++) {
    garbage.add(List<int>.filled(1 << 18, round));
    if (garbage.length > 8) garbage.clear();
    await Future<void>.delayed(Duration.zero);
  }
}

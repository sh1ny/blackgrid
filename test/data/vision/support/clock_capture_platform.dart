import 'package:blackgrid/data/capture/capture_native.dart';

import 'holdable_vision_native.dart';

/// A [CapturePlatform] that only provides the clock: `qpcNow` reads the shared
/// [FakeVisionClock]. Every other member is unsupported.
final class ClockCapturePlatform implements CapturePlatform {
  ClockCapturePlatform(int controlAddress)
    : _clock = FakeVisionClock.fromAddress(controlAddress);

  final FakeVisionClock _clock;

  @override
  int qpcNow() => _clock.now();

  @override
  int qpcFrequency() => 10000000;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('ClockCapturePlatform only provides qpcNow');
}

/// Top-level so the closure captures one int and can be sent to an isolate.
CapturePlatformFactory clockPlatformFactory(int controlAddress) =>
    () => ClockCapturePlatform(controlAddress);

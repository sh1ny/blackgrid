import 'dart:ffi';

import 'package:blackgrid/data/capture/capture_failure.dart';
import 'package:blackgrid/data/capture/capture_native.dart';

/// A [CapturePlatform] that only models the trigger hook, including the
/// native guard that stays held after a stop timeout. Everything else throws.
final class FakeHookPlatform implements CapturePlatform {
  /// Result of the next `hookStart` when the guard is free.
  TriggerFailure? startResult;

  /// Result of the next `hookStop`.
  TriggerFailure? stopResult;

  /// Drains returned in order; empty afterwards.
  final List<TriggerDrain> drains = [];

  bool guardHeld = false;
  final List<String> startTitles = [];
  int startCalls = 0;
  int stopCalls = 0;
  int drainCalls = 0;
  Pointer<NativeFunction<Void Function()>>? signal;

  /// What the native hook thread does: invoke the delivery callback.
  void fire() => signal!.asFunction<void Function()>()();

  @override
  TriggerFailure? hookStart(
    String title,
    Pointer<NativeFunction<Void Function()>> signal,
  ) {
    startCalls++;
    startTitles.add(title);
    if (guardHeld) return const AlreadyStarted();
    if (startResult != null) return startResult;
    guardHeld = true;
    this.signal = signal;
    return null;
  }

  @override
  TriggerFailure? hookStop() {
    stopCalls++;
    final result = stopResult;
    if (result is StopTimedOut) return result; // guard stays held
    guardHeld = false;
    return null;
  }

  @override
  TriggerDrain hookDrain() {
    drainCalls++;
    return drains.isEmpty ? const TriggerDrain([], 0) : drains.removeAt(0);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} is not modelled');
}

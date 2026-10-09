import 'dart:async';

import 'package:blackgrid/application/scan_coordinator.dart';
import 'package:blackgrid/data/capture/capture_failure.dart';
import 'package:blackgrid/data/capture/capture_frame.dart';
import 'package:blackgrid/data/capture/capture_snapshot.dart';
import 'package:blackgrid/data/capture/mouse_release_trigger_source.dart';
import 'package:blackgrid/data/vision/inspection_recognition.dart';
import 'package:blackgrid/data/vision/vision_job.dart';

/// An ordered record of what the fakes were asked to do.
typedef ScanEventLog = List<String>;

/// A hand-written [ScanVisionPort]. `start` and `close` can be held.
///
/// Like the real service, closing while a start is held completes that start
/// with a failure, and a closed worker reports its exit.
final class FakeScanVision implements ScanVisionPort {
  FakeScanVision(this.events, {this.name = 'vision'});

  final ScanEventLog events;
  final String name;

  /// Result of `start` when no [startGate] holds it.
  ScanFailure? startResult;

  /// When set, `start` completes only when this does.
  Completer<ScanFailure?>? startGate;

  /// When set, `close` completes only when this does. Closing still releases
  /// a held start, as the real service does.
  Completer<ScanFailure?>? closeGate;

  /// Whether a held `close` is answered by an exit report.
  bool exitOnClose = true;

  /// Completes once `start` was called.
  final Completer<void> startEntered = Completer<void>();

  int startCalls = 0;
  int closeCalls = 0;
  int invalidations = 0;
  ScanWorkerState _state = ScanWorkerState.idle;
  final Completer<void> _exit = Completer<void>();

  @override
  ScanFailure? unavailableReason;

  /// The worker exits by itself (a crash), with [reason].
  void crash(ScanFailure reason) {
    unavailableReason = reason;
    _state = ScanWorkerState.unavailable;
    if (!_exit.isCompleted) _exit.complete();
  }

  @override
  ScanWorkerState get state => _state;

  @override
  Future<void> get workerExit => _exit.future;

  @override
  Future<ScanFailure?> start() {
    startCalls++;
    events.add('$name.start');
    _state = ScanWorkerState.starting;
    if (!startEntered.isCompleted) startEntered.complete();
    final gate = startGate;
    if (gate != null) return gate.future;
    _state = ScanWorkerState.ready;
    return Future.value(startResult);
  }

  @override
  Future<VisionAnswer<InspectionRecognition>> submitFrame(
    CaptureFrame frame,
    InspectionRequest request,
  ) => throw UnimplementedError('The scan flow is not under test here.');

  @override
  void invalidate() => invalidations++;

  @override
  Future<ScanFailure?> close() {
    closeCalls++;
    events.add('$name.close');
    _state = ScanWorkerState.closing;
    final gate = startGate;
    if (gate != null && !gate.isCompleted) {
      gate.complete(
        const ScanFailure(ScanFailureCode.visionStartFailed, 'Service closed.'),
      );
    }
    Future<ScanFailure?> finish() async {
      _state = ScanWorkerState.closed;
      if (exitOnClose && !_exit.isCompleted) _exit.complete();
      return null;
    }

    final hold = closeGate;
    if (hold == null) return finish();
    return hold.future.then((_) => finish());
  }
}

/// A hand-written [ScanCapturePort].
final class FakeScanCapture implements ScanCapturePort {
  FakeScanCapture(this.events);

  final ScanEventLog events;
  int closeCalls = 0;
  final Completer<void> _exit = Completer<void>();

  @override
  ScanFailure? unavailableReason;

  /// The worker exits by itself (a crash), with [reason].
  void crash(ScanFailure reason) {
    unavailableReason = reason;
    if (!_exit.isCompleted) _exit.complete();
  }

  @override
  Future<CaptureResult> capture(TriggerEvent trigger, CaptureMode mode) =>
      throw UnimplementedError('The scan flow is not under test here.');

  @override
  Future<ScanFailure?> close() async {
    closeCalls++;
    events.add('capture.close');
    if (!_exit.isCompleted) _exit.complete();
    return null;
  }

  @override
  Future<void> get workerExit => _exit.future;
}

/// A hand-written [ScanTriggerPort].
final class FakeScanTrigger implements ScanTriggerPort {
  FakeScanTrigger(this.events);

  final ScanEventLog events;

  /// Result of the next `start`.
  TriggerFailure? startResult;

  /// Results of successive `stop` calls; null once exhausted.
  final List<TriggerFailure?> stopResults = [];

  int startCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;
  bool installed = false;

  final StreamController<ScanTrigger> _controller =
      StreamController<ScanTrigger>.broadcast(sync: true);

  /// Whether the coordinator currently listens for triggers.
  bool get hasListener => _controller.hasListener;

  /// Delivers [trigger] to whoever listens.
  void emit(ScanTrigger trigger) => _controller.add(trigger);

  @override
  TriggerFailure? start() {
    startCalls++;
    events.add('hook.start');
    final failure = startResult;
    if (failure == null) installed = true;
    return failure;
  }

  @override
  TriggerFailure? stop() {
    stopCalls++;
    events.add('hook.stop');
    final failure = stopResults.isEmpty ? null : stopResults.removeAt(0);
    if (failure == null) installed = false;
    return failure;
  }

  @override
  Future<TriggerFailure?> dispose() async {
    disposeCalls++;
    events.add('hook.dispose');
    await _controller.close();
    return null;
  }

  @override
  Stream<ScanTrigger> get triggers => _controller.stream;
}

/// A [ScanClock] over a plain counter.
final class FakeScanClock implements ScanClock {
  int now = 0;
  int frequency = 10000000;

  @override
  int qpcNow() => now;

  @override
  int qpcFrequency() => frequency;
}

/// A [ScanPlatform] over fakes.
final class FakeScanPlatform implements ScanPlatform {
  FakeScanPlatform(ScanEventLog events) : trigger = FakeScanTrigger(events);

  @override
  final FakeScanTrigger trigger;

  @override
  final FakeScanClock clock = FakeScanClock();
}

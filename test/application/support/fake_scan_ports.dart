import 'dart:async';
import 'dart:ffi';

import 'package:blackgrid/application/scan_coordinator.dart';
import 'package:blackgrid/data/capture/capture_failure.dart';
import 'package:blackgrid/data/capture/capture_frame.dart';
import 'package:blackgrid/data/capture/capture_snapshot.dart';
import 'package:blackgrid/data/capture/mouse_release_trigger_source.dart';
import 'package:blackgrid/data/vision/inspection_recognition.dart';
import 'package:blackgrid/data/vision/vision_job.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/title_matching.dart';

/// An ordered record of what the fakes were asked to do.
typedef ScanEventLog = List<String>;

/// A [ScanWaiter] that returns at once, so a rig never waits for a real timer.
Future<void> immediateScanWaiter(Duration _) => Future<void>.value();

/// A hand-written [ScanWaiter] that records every requested duration.
///
/// By default each wait returns at once. With [hold] set, each wait stays open
/// until the test calls [release].
final class FakeScanWaiter {
  FakeScanWaiter({this.hold = false});

  /// Whether a wait stays open until released.
  final bool hold;

  /// Every duration requested, in order.
  final CallLog<Duration> requests = CallLog<Duration>();
  final List<Completer<void>> _open = [];

  /// The [ScanWaiter] to hand to the coordinator.
  Future<void> call(Duration duration) {
    requests.add(duration);
    if (!hold) return Future<void>.value();
    final done = Completer<void>();
    _open.add(done);
    return done.future;
  }

  /// Completes the wait at [index] (in request order) if it is still open.
  void release(int index) {
    final done = _open[index];
    if (!done.isCompleted) done.complete();
  }
}

/// An append-only list whose entries can be awaited by index, so a test waits
/// for a call to arrive instead of sleeping.
final class CallLog<T> {
  final List<T> items = [];
  final List<(int, Completer<T>)> _waiters = [];

  int get length => items.length;

  T operator [](int index) => items[index];

  void add(T item) {
    items.add(item);
    for (final waiter in List.of(_waiters)) {
      if (items.length > waiter.$1) {
        _waiters.remove(waiter);
        waiter.$2.complete(items[waiter.$1]);
      }
    }
  }

  /// Completes with the entry at [index] once it exists.
  Future<T> at(int index) {
    if (items.length > index) return Future.value(items[index]);
    final done = Completer<T>();
    _waiters.add((index, done));
    return done.future;
  }
}

/// A frame registry that only counts releases.
final class FakeScanFrames implements FrameRegistry {
  final List<int> released = [];
  int _issued = 0;

  /// A frame owned by the caller, with the given provenance.
  CaptureFrame frame({
    int clientWidth = 2560,
    int clientHeight = 1440,
    int qpcBefore = 0,
    int qpcAfter = 0,
  }) {
    final id = ++_issued;
    return CaptureFrame(
      id,
      CaptureFrameMetadata(
        width: 4,
        height: 4,
        stride: 16,
        desktopLeft: 0,
        desktopTop: 0,
        requested: const CaptureRect(0, 0, 4, 4),
        captured: const CaptureRect(0, 0, 4, 4),
        clipped: false,
        clientWidth: clientWidth,
        clientHeight: clientHeight,
        dpi: 96,
        hwnd: 1,
        pid: 2,
        tid: 3,
        exeName: 'EscapeFromTarkov.exe',
        qpcBefore: qpcBefore,
        qpcAfter: qpcAfter,
        capturedAtUtc: DateTime.utc(2026, 10, 10),
        requestId: id,
      ),
      this,
    );
  }

  @override
  FrameView? view(int frameId) => null;

  @override
  void release(int frameId) => released.add(frameId);

  @override
  int get liveCount => _issued - released.length;

  @override
  void attach(Finalizable owner, int frameId) {}

  @override
  void detach(Finalizable owner) {}
}

/// One capture request the coordinator made; the test answers it.
final class FakeCaptureCall {
  FakeCaptureCall(this.trigger, this.mode);

  final TriggerEvent trigger;
  final CaptureMode mode;
  final Completer<CaptureResult> _answer = Completer<CaptureResult>();

  /// Answers with a frame the coordinator then owns.
  void succeed(CaptureFrame frame) => _answer.complete(CaptureSuccess(frame));

  /// Answers with a failure.
  void fail(CaptureFailure failure) =>
      _answer.complete(CaptureRejected(failure));
}

/// One frame submitted to the fake vision service; the test answers it.
///
/// Like the real service, answering releases the frame the service owns.
final class FakeVisionCall {
  FakeVisionCall(this.frame, this.request);

  final CaptureFrame frame;
  final InspectionRequest request;
  final Completer<VisionAnswer<InspectionRecognition>> _answer =
      Completer<VisionAnswer<InspectionRecognition>>();

  bool get isAnswered => _answer.isCompleted;

  /// Answers with [answer] and releases the frame.
  void answer(VisionAnswer<InspectionRecognition> answer) {
    if (_answer.isCompleted) return;
    frame.release();
    _answer.complete(answer);
  }

  /// Delivers [result] with the given worker stamps.
  void deliver(
    InspectionRecognition result, {
    int submitted = 0,
    int started = 0,
    int finished = 0,
  }) => answer(
    VisionDelivered<InspectionRecognition>(
      result,
      submittedQpc: submitted,
      startedQpc: started,
      finishedQpc: finished,
    ),
  );
}

/// One match request; the test completes it.
final class FakeMatchCall {
  FakeMatchCall({
    required this.index,
    required this.targeted,
    required this.fullClient,
    required this.mode,
    required this.runningWhenCalled,
  });

  final TitleMatchIndex index;
  final InspectionRecognition? targeted;
  final InspectionRecognition? fullClient;
  final GameMode mode;

  /// How many earlier match requests had not completed when this one began.
  final int runningWhenCalled;
  final Completer<RecognitionOutcome<InspectionEvidence>> _result =
      Completer<RecognitionOutcome<InspectionEvidence>>();

  bool get isCompleted => _result.isCompleted;

  /// Completes the match with [outcome].
  void complete(RecognitionOutcome<InspectionEvidence> outcome) =>
      _result.complete(outcome);
}

/// A hand-written [ScanMatcher] whose every request is held until completed.
final class FakeScanMatcher {
  final CallLog<FakeMatchCall> calls = CallLog<FakeMatchCall>();

  Future<RecognitionOutcome<InspectionEvidence>> call(
    TitleMatchIndex index, {
    required InspectionRecognition? targeted,
    InspectionRecognition? fullClient,
    required GameMode mode,
  }) {
    final running = calls.items.where((c) => !c.isCompleted).length;
    final entry = FakeMatchCall(
      index: index,
      targeted: targeted,
      fullClient: fullClient,
      mode: mode,
      runningWhenCalled: running,
    );
    calls.add(entry);
    return entry._result.future;
  }
}

/// A hand-written [ScanIndexBuilder] that builds the real index (cheap for a
/// tiny catalog) and can fail or be held.
final class FakeIndexBuilder {
  final CallLog<CatalogSnapshot> builds = CallLog<CatalogSnapshot>();

  /// Makes the next build throw.
  bool failNext = false;

  /// When set, a build completes only when this does.
  Completer<void>? hold;

  Future<TitleMatchIndex> call(CatalogSnapshot snapshot) async {
    builds.add(snapshot);
    final gate = hold;
    if (gate != null) await gate.future;
    if (failNext) {
      failNext = false;
      throw StateError('index build failed');
    }
    return TitleMatchIndex.build(snapshot);
  }
}

/// A hand-written [ScanVisionPort]. `start` and `close` can be held.
///
/// Like the real service, closing while a start is held completes that start
/// with a failure, and a closed worker reports its exit. Submitted frames wait
/// for the test to answer them; `invalidate` and `close` answer every waiting
/// request at once.
final class FakeScanVision implements ScanVisionPort {
  FakeScanVision(this.events, {this.name = 'vision'});

  final ScanEventLog events;
  final String name;

  /// Result of `start` when no [startGate] holds it.
  ScanFailure? startResult;

  /// When set, `start` completes only when this does.
  Completer<ScanFailure?>? startGate;

  /// When set, `close` completes only when this does, with its value.
  /// Closing still releases a held start, as the real service does.
  Completer<ScanFailure?>? closeGate;

  /// Whether a held `close` is answered by an exit report.
  bool exitOnClose = true;

  /// Completes once `start` was called.
  final Completer<void> startEntered = Completer<void>();

  /// Every frame submitted, in order.
  final CallLog<FakeVisionCall> calls = CallLog<FakeVisionCall>();

  int startCalls = 0;
  int closeCalls = 0;
  int invalidations = 0;

  /// Whether `invalidate` answers the waiting requests at once. A test turns
  /// this off to keep an invalidated job running past the invalidation.
  bool answerOnInvalidate = true;
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
  ) {
    events.add('$name.submit');
    final call = FakeVisionCall(frame, request);
    calls.add(call);
    return call._answer.future;
  }

  @override
  void invalidate() {
    invalidations++;
    events.add('$name.invalidate');
    if (!answerOnInvalidate) return;
    for (final call in calls.items) {
      call.answer(const VisionInvalidated<InspectionRecognition>(0));
    }
  }

  @override
  Future<ScanFailure?> close() {
    closeCalls++;
    events.add('$name.close');
    _state = ScanWorkerState.closing;
    for (final call in calls.items) {
      call.answer(const VisionClosed<InspectionRecognition>(0));
    }
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
    return hold.future.then((failure) async {
      await finish();
      return failure;
    });
  }
}

/// A hand-written [ScanCapturePort]. Every capture waits for the test to
/// answer it through the recorded [calls].
final class FakeScanCapture implements ScanCapturePort {
  FakeScanCapture(this.events);

  final ScanEventLog events;
  int closeCalls = 0;
  final Completer<void> _exit = Completer<void>();

  /// Every capture requested, in order.
  final CallLog<FakeCaptureCall> calls = CallLog<FakeCaptureCall>();

  @override
  ScanFailure? unavailableReason;

  /// The worker exits by itself (a crash), with [reason].
  void crash(ScanFailure reason) {
    unavailableReason = reason;
    if (!_exit.isCompleted) _exit.complete();
  }

  @override
  Future<CaptureResult> capture(TriggerEvent trigger, CaptureMode mode) {
    events.add('capture.${mode.name}');
    final call = FakeCaptureCall(trigger, mode);
    calls.add(call);
    return call._answer.future;
  }

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

  /// How many times the coordinator read the frequency.
  int frequencyReads = 0;

  @override
  int qpcNow() => now;

  @override
  int qpcFrequency() {
    frequencyReads++;
    return frequency;
  }
}

/// A [ScanPlatform] over fakes.
final class FakeScanPlatform implements ScanPlatform {
  FakeScanPlatform(ScanEventLog events) : trigger = FakeScanTrigger(events);

  @override
  final FakeScanTrigger trigger;

  @override
  final FakeScanClock clock = FakeScanClock();
}

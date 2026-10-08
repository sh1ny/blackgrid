import 'dart:async';
import 'dart:isolate';

import '../capture/capture_frame.dart';
import '../capture/capture_native.dart';
import '../capture/capture_service.dart'
    show FrameRegistryFactory, openDefaultFrameRegistry;
import 'vision_job.dart';
import 'vision_native.dart' show openVisionNative;
import 'vision_runtime.dart';

part 'vision_worker.dart';

/// Where a [VisionService] is in its life (design T2).
enum VisionServiceState {
  /// Constructed; no worker yet.
  idle,

  /// The worker is opening the runtime and validating the templates.
  starting,

  /// The worker is warm and no request is running.
  ready,

  /// A request is running in the worker.
  active,

  /// A request outlived its deadline and the worker has not replied yet.
  overrun,

  /// [VisionService.close] was called and the worker is draining.
  closing,

  /// The worker is gone and the service was closed.
  closed,

  /// The worker cannot run jobs; there is no respawn.
  unavailable,
}

/// Why [VisionService.start] did not reach `ready`.
sealed class VisionStartFailure {
  const VisionStartFailure();

  /// Human-readable description.
  String get message;
}

/// The runtime could not be opened; [failure] is its typed reason.
final class VisionRuntimeStartFailure extends VisionStartFailure {
  const VisionRuntimeStartFailure(this.failure);

  final VisionFailure failure;

  @override
  String get message => failure.message;
}

/// The template [name] is malformed, not 1 channel, or has zero variance. The
/// runtime the worker opened was disposed.
final class VisionInvalidTemplateStart extends VisionStartFailure {
  const VisionInvalidTemplateStart(this.name, this.detail);

  final String name;
  final String detail;

  @override
  String get message => 'Vision template "$name" is invalid: $detail';
}

/// The worker could not be started or ended before it was ready for a reason
/// that is not a runtime failure (spawn error, capture platform, close).
final class VisionWorkerStartFailure extends VisionStartFailure {
  const VisionWorkerStartFailure(this.message);

  @override
  final String message;
}

/// How [VisionService.close] ended.
enum VisionCloseResult {
  /// The worker disposed the runtime and exited within the drain.
  closed,

  /// The drain expired with a native call or the runtime open still running.
  /// The runtime was not disposed under it and the worker was not killed; it
  /// disposes and exits by itself once the call returns.
  shutdownIncomplete,
}

/// Runs vision jobs on one dedicated worker isolate that opens the runtime
/// once and keeps it, the OCR engine and the templates warm until shutdown
/// (design D1, D4, D7).
///
/// The UI isolate never opens the vision runtime. A failed start is final: the
/// service becomes [VisionServiceState.unavailable] and the worker is not
/// respawned.
///
/// Admission (design D1): at most one request is in the worker and one waits
/// in a single replaceable pending slot on this service. The worker has no
/// queue; the pending request is sent only after the active reply arrives, so
/// native calls never overlap. A request submitted before the worker is ready
/// is held unsent and admitted once it is.
///
/// Every request carries the generation current at submission and a deadline
/// measured from submission (design D2, D3). Later task groups add job error isolation and the bounded close.
final class VisionService<P, R> {
  /// Copies [templates] now, so later changes to the callers' bytes do not
  /// reach the worker.
  ///
  /// [jobFactory], [opener] and [platformFactory] are sent to the worker, so
  /// each must be a top-level function or a closure over sendable values.
  /// [qpcNow] is the caller-side clock for submission times and defaults to
  /// the platform's `qpcNow`; tests share one fake clock through both.
  VisionService({
    required this.runtimeDirectory,
    required this.jobFactory,
    List<VisionTemplate> templates = const [],
    this.opener = openVisionNative,
    this.platformFactory = openDefaultNativeCapturePlatform,
    this.registryFactory = openDefaultFrameRegistry,
    this._qpcNow,
    this.deadline = const Duration(milliseconds: 1500),
    this.closeDrain = const Duration(seconds: 2),
  }) : _templates = [for (final t in templates) _TemplateInit.copy(t)];

  /// Absolute path of the vision runtime directory.
  final String runtimeDirectory;

  /// Builds the job inside the worker.
  final VisionJobFactory<P, R> jobFactory;

  /// Opens the native libraries inside the worker.
  final VisionNativeOpener opener;

  /// Builds the capture platform inside the worker (and here, unless a
  /// [qpcNow] was given) for the QPC clock.
  final CapturePlatformFactory platformFactory;

  /// Builds the frame registry inside the worker, which adopts each frame
  /// ticket with it. Called on the first frame request.
  ///
  /// Must be a top-level function or a closure over sendable values. Tests
  /// pass a factory over shared state so both isolates see the same frames.
  final FrameRegistryFactory registryFactory;

  /// How long a request may take, measured from its submission.
  final Duration deadline;

  /// How long [close] waits for the worker before reporting
  /// [VisionCloseResult.shutdownIncomplete].
  final Duration closeDrain;

  final List<_TemplateInit> _templates;
  int Function()? _qpcNow;

  VisionServiceState _state = VisionServiceState.idle;
  VisionStartFailure? _startFailure;

  bool _spawned = false;
  bool _exited = false;
  RawReceivePort? _port;
  SendPort? _commands;
  final Completer<void> _exitSignal = Completer<void>();
  final Completer<VisionStartFailure?> _startResult =
      Completer<VisionStartFailure?>();

  int _nextSeq = 0;
  int _generation = 0;
  _Request<R>? _unsent;
  _Request<R>? _active;
  _Request<R>? _pending;
  Future<VisionCloseResult>? _closing;
  FrameRegistry? _registry;

  /// Completes when the active request's reply (or the worker's exit) arrives.
  /// Only set while [close] waits for the active call.
  Completer<void>? _activeDone;

  /// Where the service is now.
  VisionServiceState get state => _state;

  /// Why the service is unavailable, or null.
  VisionStartFailure? get unavailableReason => _startFailure;

  /// Whether the worker isolate is still alive.
  bool get workerRunning => _spawned && !_exited;

  /// Completes when the worker isolate has exited.
  Future<void> get workerExit => _exitSignal.future;

  /// Spawns the worker if needed and completes when it is ready (null) or
  /// when the service cannot be: the typed [VisionStartFailure]. Repeated
  /// calls share one start.
  Future<VisionStartFailure?> start() {
    if (_state == VisionServiceState.idle) {
      _state = VisionServiceState.starting;
      _spawn();
    }
    return _startResult.future;
  }

  /// Runs the job over the owned [image] with [params].
  ///
  /// The bytes are copied now, so the caller keeps its [image]. A malformed
  /// image is answered [VisionInvalidInput] at once: nothing is admitted and
  /// the pending request is left alone.
  ///
  /// Starts the service first if needed. With no request running the request
  /// is sent at once; otherwise it becomes the single pending request and
  /// replaces (answers [VisionSuperseded]) any earlier pending one.
  Future<VisionAnswer<R>> submit(VisionImage image, P params) {
    final submitted = _clock();
    final invalid = image.validate();
    if (invalid != null) {
      return Future.value(VisionInvalidInput<R>(submitted, invalid.reason));
    }
    return _admit(submitted, params, image: image);
  }

  /// Runs the job over the capture [frame] with [params], viewed as a BGRX
  /// 4-channel image. Admission is as for [submit].
  ///
  /// The service takes ownership: the caller must not use [frame] again. The
  /// service keeps it, finalizer attached, while the request waits, and hands
  /// it to the worker only when sending, so a service dropped without
  /// [close] cannot strand the frame. The frame is released exactly once on
  /// every outcome: by the worker once sent, by the service otherwise
  /// (superseded, invalidated, expired, closed or unavailable). A frame that
  /// is already released is answered [VisionInvalidInput].
  Future<VisionAnswer<R>> submitFrame(CaptureFrame frame, P params) {
    final submitted = _clock();
    if (frame.isReleased) {
      return Future.value(
        VisionInvalidInput<R>(submitted, 'frame is already released'),
      );
    }
    return _admit(submitted, params, frame: frame);
  }

  Future<VisionAnswer<R>> _admit(
    int submitted,
    P params, {
    VisionImage? image,
    CaptureFrame? frame,
  }) {
    switch (_state) {
      case VisionServiceState.unavailable:
        frame?.release();
        return Future.value(
          VisionUnavailableAnswer<R>(
            submitted,
            _startFailure?.message ?? 'Vision worker is unavailable.',
            failure: switch (_startFailure) {
              VisionRuntimeStartFailure(:final failure) => failure,
              _ => null,
            },
          ),
        );
      case VisionServiceState.closing || VisionServiceState.closed:
        frame?.release();
        return Future.value(VisionClosed<R>(submitted));
      case VisionServiceState.idle ||
          VisionServiceState.starting ||
          VisionServiceState.ready ||
          VisionServiceState.active ||
          VisionServiceState.overrun:
        break;
    }
    final request = _Request<R>(
      submitted,
      _generation,
      image == null ? null : _OwnedImageInit.copy(image),
      frame,
      params,
    );
    // The timer holds the service and request weakly: a pending frame must
    // stay collectable (and so finalized) if the owner drops the service.
    request.timer = Timer(
      deadline,
      _expireWeakly(WeakReference(this), WeakReference(request)),
    );
    unawaited(start());
    switch (_state) {
      case VisionServiceState.ready:
        _dispatch(request);
      case VisionServiceState.idle || VisionServiceState.starting
          when _unsent == null:
        _unsent = request;
      default:
        _setPending(request);
    }
    return request.completer.future;
  }

  /// Advances the generation: the unsent, pending and active requests are all
  /// answered [VisionInvalidated] at once, and none is answered again.
  ///
  /// The active request stays tracked until the worker replies, so its late
  /// result is discarded and no second native call starts. If that call
  /// outlasts the request's original deadline the service reports `overrun`
  /// without answering the caller again.
  void invalidate() {
    _generation++;
    final unsent = _unsent;
    final pending = _pending;
    _unsent = null;
    _pending = null;
    for (final request in [?unsent, ?pending]) {
      _finish(request, VisionInvalidated<R>(request.submittedQpc));
    }
    final active = _active;
    if (active == null || active.completer.isCompleted) return;
    _finish(active, VisionInvalidated<R>(active.submittedQpc));
    final remaining = deadline - active.age.elapsed;
    active.overrunTimer = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      () => _onOverrun(active),
    );
  }

  void _setPending(_Request<R> request) {
    final replaced = _pending;
    _pending = request;
    if (replaced != null) {
      _finish(replaced, VisionSuperseded<R>(replaced.submittedQpc));
    }
  }

  /// Sends [request] to the worker. Only called when nothing is in flight.
  void _dispatch(_Request<R> request) {
    final image = request.image;
    request.image = null;
    // Ownership of a frame moves out here, and only here: its finalizer is
    // detached and the worker adopts the ticket. The id stays on the request
    // until the reply, so a dead worker's ticket can be released by id.
    final ticket = request.frame?.handOff();
    request.frame = null;
    request.sentFrameId = ticket?.frameId;
    request.seq = ++_nextSeq;
    _active = request;
    _state = VisionServiceState.active;
    _commands!.send(_Run(request.seq, request.params, image, ticket));
  }

  /// The request's deadline passed before it was answered.
  void _onDeadline(_Request<R> request) {
    if (request.completer.isCompleted) return;
    if (identical(request, _active)) {
      // The native call is still running: stay busy until its reply arrives.
      _finish(request, VisionDeadlineExceeded<R>(request.submittedQpc));
      _onOverrun(request);
    } else {
      if (identical(request, _pending)) _pending = null;
      if (identical(request, _unsent)) _unsent = null;
      _finish(request, VisionDeadlineExceeded<R>(request.submittedQpc));
    }
  }

  /// The active request outlived its deadline: busy until the worker replies.
  void _onOverrun(_Request<R> request) {
    if (identical(request, _active) && _state == VisionServiceState.active) {
      _state = VisionServiceState.overrun;
    }
  }

  void _finish(_Request<R> request, VisionAnswer<R> answer) {
    request.timer?.cancel();
    request.timer = null;
    request.overrunTimer?.cancel();
    request.overrunTimer = null;
    request.image = null;
    // A frame that was never sent is released here, before the answer.
    request.frame?.release();
    request.frame = null;
    if (!request.completer.isCompleted) request.completer.complete(answer);
  }

  /// Stops admission at once and shuts the worker down.
  ///
  /// The generation advances, the unsent, pending and active requests are
  /// answered [VisionClosed] and their inputs released, and later submissions
  /// are answered [VisionClosed]. Close then waits up to [closeDrain] for the
  /// active native call to return, tells the worker to dispose the runtime and
  /// its scratch memory and to exit, and waits for it to do so within the same
  /// budget.
  ///
  /// Returns [VisionCloseResult.shutdownIncomplete] when the budget runs out
  /// first (a call or the runtime open is still running). The worker is never
  /// killed and the runtime is never disposed under a running call: the queued
  /// close makes the worker dispose and exit by itself once the call returns.
  /// Safe to call repeatedly; every call shares one result.
  Future<VisionCloseResult> close() => _closing ??= _close();

  Future<VisionCloseResult> _close() async {
    final budget = Stopwatch()..start();
    if (_state != VisionServiceState.unavailable) {
      _state = VisionServiceState.closing;
    }
    _generation++;
    if (!_startResult.isCompleted) {
      _startResult.complete(const VisionWorkerStartFailure('Service closed.'));
    }
    final unsent = _unsent;
    final pending = _pending;
    _unsent = null;
    _pending = null;
    for (final request in [?unsent, ?pending]) {
      _finish(request, VisionClosed<R>(request.submittedQpc));
    }
    final active = _active;
    if (active != null) {
      // Stays tracked until the worker replies, so its late result is
      // discarded and its frame (released by the worker) is not touched.
      _finish(active, VisionClosed<R>(active.submittedQpc));
    }
    if (!_spawned || _exited) {
      _state = VisionServiceState.closed;
      return VisionCloseResult.closed;
    }
    final done = _activeDone = active == null ? null : Completer<void>();
    final drained = await _waitFor(done?.future, closeDrain);
    // Queued behind a running call; a worker still opening gets it from the
    // late _Ready.
    _commands?.send(const _Close());
    if (!drained) {
      _state = VisionServiceState.closed;
      return VisionCloseResult.shutdownIncomplete;
    }
    final remaining = closeDrain - budget.elapsed;
    final exited = await _waitFor(
      _exitSignal.future,
      remaining.isNegative ? Duration.zero : remaining,
    );
    _state = VisionServiceState.closed;
    return exited
        ? VisionCloseResult.closed
        : VisionCloseResult.shutdownIncomplete;
  }

  /// Completes with true when [future] completes within [limit] (or is null),
  /// false when the limit passes first.
  Future<bool> _waitFor(Future<void>? future, Duration limit) {
    if (future == null) return Future.value(true);
    final result = Completer<bool>();
    final timer = Timer(limit, () {
      if (!result.isCompleted) result.complete(false);
    });
    future.then((_) {
      timer.cancel();
      if (!result.isCompleted) result.complete(true);
    });
    return result.future;
  }

  int _clock() {
    var clock = _qpcNow;
    if (clock == null) {
      try {
        clock = _qpcNow = platformFactory().qpcNow;
      } on Object {
        // The worker reports the same platform failure; timestamps are 0.
        return 0;
      }
    }
    return clock();
  }

  void _spawn() {
    _spawned = true;
    final port = RawReceivePort();
    _port = port;
    // Weak, so an abandoned service (and the frame it holds) can be collected.
    port.handler = _forwardWeakly(WeakReference(this), port);
    Isolate.spawn(
      _visionWorkerMain,
      _WorkerInit(
        replyTo: port.sendPort,
        runtimeDirectory: runtimeDirectory,
        opener: opener,
        platformFactory: platformFactory,
        registryFactory: registryFactory,
        jobFactory: jobFactory,
        templates: _templates,
      ),
      onExit: port.sendPort,
      onError: port.sendPort,
      debugName: 'bgv_worker',
    ).catchError((Object error) {
      _markUnavailable(
        VisionWorkerStartFailure('Vision worker failed to start: $error'),
      );
      _onExit();
      return Isolate.current;
    });
  }

  void _onMessage(Object? message) {
    switch (message) {
      case null:
        _onExit();
      case _Ready(:final commands):
        _commands = commands;
        if (_state == VisionServiceState.closing ||
            _state == VisionServiceState.closed) {
          commands.send(const _Close());
        } else {
          _state = VisionServiceState.ready;
          if (!_startResult.isCompleted) _startResult.complete(null);
          final first = _unsent;
          if (first != null) {
            _unsent = null;
            _dispatch(first);
          }
        }
      case _OpenFailed():
        _markUnavailable(message.toFailure());
      case _Reply():
        _onReply(message);
      case List<Object?>():
        _markUnavailable(
          VisionWorkerStartFailure('Vision worker error: ${message.first}'),
        );
      default:
        break;
    }
  }

  void _onReply(_Reply reply) {
    final active = _active;
    if (active == null || active.seq != reply.seq) return;
    _active = null;
    active.sentFrameId = null; // the worker released it before replying
    _signalActiveDone();
    // Delivered only while the caller still waits and the generation is
    // current. A late or stale result is discarded: the caller was already
    // answered, and the worker released the input before replying.
    if (!active.completer.isCompleted && active.generation == _generation) {
      _finish(active, switch (reply) {
        _ResultReply(:final result) => VisionDelivered<R>(
          result as R,
          submittedQpc: active.submittedQpc,
          startedQpc: reply.startedQpc,
          finishedQpc: reply.finishedQpc,
        ),
        _JobFailedReply(:final description) => VisionJobFailed<R>(
          description,
          submittedQpc: active.submittedQpc,
          startedQpc: reply.startedQpc,
          finishedQpc: reply.finishedQpc,
        ),
        _FailureReply(:final failure) => VisionFailureAnswer<R>(
          failure,
          submittedQpc: active.submittedQpc,
          startedQpc: reply.startedQpc,
          finishedQpc: reply.finishedQpc,
        ),
      });
    } else {
      _finish(active, VisionInvalidated<R>(active.submittedQpc));
    }
    if (_state == VisionServiceState.active ||
        _state == VisionServiceState.overrun) {
      _state = VisionServiceState.ready;
      final next = _pending;
      if (next != null) {
        _pending = null;
        _dispatch(next);
      }
    }
  }

  void _markUnavailable(VisionStartFailure failure) {
    if (_state == VisionServiceState.closing ||
        _state == VisionServiceState.closed ||
        _state == VisionServiceState.unavailable) {
      return;
    }
    _state = VisionServiceState.unavailable;
    _startFailure = failure;
    if (!_startResult.isCompleted) _startResult.complete(failure);
    _answerAll(
      (submitted) => VisionUnavailableAnswer<R>(
        submitted,
        failure.message,
        failure: switch (failure) {
          VisionRuntimeStartFailure(:final failure) => failure,
          _ => null,
        },
      ),
    );
  }

  void _onExit() {
    _exited = true;
    _port?.close();
    _port = null;
    _commands = null;
    _releaseSentFrame();
    _markUnavailable(
      const VisionWorkerStartFailure('Vision worker exited unexpectedly.'),
    );
    // A closing service has no failure to report; the sent request was
    // already answered.
    final active = _active;
    _active = null;
    if (active != null) {
      _finish(
        active,
        VisionUnavailableAnswer<R>(
          active.submittedQpc,
          'Vision worker exited unexpectedly.',
        ),
      );
    }
    _signalActiveDone();
    if (!_exitSignal.isCompleted) _exitSignal.complete();
  }

  void _signalActiveDone() {
    final done = _activeDone;
    if (done != null && !done.isCompleted) done.complete();
  }

  /// Releases the ticket of a request the worker never answered, by id. The
  /// release is generation-checked, so a frame the worker already released is
  /// a no-op.
  void _releaseSentFrame() {
    final id = _active?.sentFrameId;
    if (id == null) return;
    _active?.sentFrameId = null;
    try {
      (_registry ??= registryFactory()).release(id);
    } on Object {
      // No registry, no live slot to release.
    }
  }

  void _answerAll(VisionAnswer<R> Function(int submittedQpc) answer) {
    final active = _active;
    final pending = _pending;
    final unsent = _unsent;
    _active = null;
    _pending = null;
    _unsent = null;
    for (final request in [?active, ?unsent, ?pending]) {
      _finish(request, answer(request.submittedQpc));
    }
  }
}

/// One submitted request: in flight at the worker, or waiting in the pending
/// slot (then [image] or [frame] is still held).
final class _Request<R> {
  _Request(
    this.submittedQpc,
    this.generation,
    this.image,
    this.frame,
    this.params,
  );

  final int submittedQpc;
  final int generation;

  /// Time since submission, for the overrun timer's remaining deadline.
  final Stopwatch age = Stopwatch()..start();
  final Object? params;
  _OwnedImageInit? image;

  /// The adopted frame while the request is unsent; null once sent.
  CaptureFrame? frame;

  /// Id of the frame ticket sent to the worker and not yet seen answered.
  int? sentFrameId;
  int seq = 0;
  Timer? timer;

  /// Fires at the original deadline of an invalidated active request; moves
  /// the service to `overrun` without answering the caller again.
  Timer? overrunTimer;
  final Completer<VisionAnswer<R>> completer = Completer<VisionAnswer<R>>();
}

/// The port handler for [service]. Built outside the service's methods so its
/// closure context cannot capture the service itself: a captured service
/// would stay reachable from the open port and never be collected.
void Function(Object?) _forwardWeakly(
  WeakReference<VisionService<Object?, Object?>> service,
  RawReceivePort port,
) {
  SendPort? commands;
  return (Object? message) {
    final target = service.target;
    if (target != null) {
      target._onMessage(message);
      return;
    }
    // The service was dropped: stop the worker when it next speaks.
    switch (message) {
      case _Ready(commands: final sent):
        commands = sent;
        sent.send(const _Close());
      case _Reply():
        commands?.send(const _Close());
      case null:
        port.close();
      default:
        break;
    }
  };
}

/// The deadline callback for [request] on [service]. Built outside the
/// service's methods so its closure context cannot capture the service: a
/// pending timer must not keep an abandoned service reachable.
void Function() _expireWeakly<R>(
  WeakReference<VisionService<Object?, R>> service,
  WeakReference<_Request<R>> request,
) {
  return () {
    final expired = request.target;
    if (expired != null) service.target?._onDeadline(expired);
  };
}

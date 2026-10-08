import 'dart:async';
import 'dart:isolate';

import '../capture/capture_native.dart';
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
/// measured from submission (design D2, D3). Later task groups add frame inputs, job error isolation and the bounded close.
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
    this._qpcNow,
    this.deadline = const Duration(milliseconds: 1500),
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

  /// How long a request may take, measured from its submission.
  final Duration deadline;

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
  Future<void>? _closing;

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
  /// Starts the service first if needed. With no request running the request
  /// is sent at once; otherwise it becomes the single pending request and
  /// replaces (answers [VisionSuperseded]) any earlier pending one.
  Future<VisionAnswer<R>> submit(VisionImage image, P params) {
    final submitted = _clock();
    switch (_state) {
      case VisionServiceState.unavailable:
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
      _OwnedImageInit.copy(image),
      params,
    );
    request.timer = Timer(deadline, () => _onDeadline(request));
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
    final image = request.image!;
    request.image = null;
    request.seq = ++_nextSeq;
    _active = request;
    _state = VisionServiceState.active;
    _commands!.send(_Run(request.seq, image, request.params));
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
    if (!request.completer.isCompleted) request.completer.complete(answer);
  }

  /// Stops the worker: it disposes the runtime and exits. Completes when the
  /// worker is gone. Safe to call repeatedly.
  ///
  /// The bounded drain and `shutdownIncomplete` are added by a later task
  /// group; until then this waits for the worker without a limit.
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    if (_state != VisionServiceState.unavailable) {
      _state = VisionServiceState.closing;
    }
    _answerAll((submitted) => VisionClosed<R>(submitted));
    if (!_startResult.isCompleted) {
      _startResult.complete(const VisionWorkerStartFailure('Service closed.'));
    }
    if (_spawned && !_exited) {
      _commands?.send(const _Close());
      await _exitSignal.future;
    }
    if (_state == VisionServiceState.closing) {
      _state = VisionServiceState.closed;
    }
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
    final port = RawReceivePort(_onMessage);
    _port = port;
    Isolate.spawn(
      _visionWorkerMain,
      _WorkerInit(
        replyTo: port.sendPort,
        runtimeDirectory: runtimeDirectory,
        opener: opener,
        platformFactory: platformFactory,
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
    // Delivered only while the caller still waits and the generation is
    // current. A late or stale result is discarded: the caller was already
    // answered, and the worker released the input before replying.
    if (!active.completer.isCompleted && active.generation == _generation) {
      _finish(
        active,
        VisionDelivered<R>(
          reply.result as R,
          submittedQpc: active.submittedQpc,
          startedQpc: reply.startedQpc,
          finishedQpc: reply.finishedQpc,
        ),
      );
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
    _markUnavailable(
      const VisionWorkerStartFailure('Vision worker exited unexpectedly.'),
    );
    if (!_exitSignal.isCompleted) _exitSignal.complete();
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
/// slot (then [image] is still held).
final class _Request<R> {
  _Request(this.submittedQpc, this.generation, this.image, this.params);

  final int submittedQpc;
  final int generation;

  /// Time since submission, for the overrun timer's remaining deadline.
  final Stopwatch age = Stopwatch()..start();
  final Object? params;
  _OwnedImageInit? image;
  int seq = 0;
  Timer? timer;

  /// Fires at the original deadline of an invalidated active request; moves
  /// the service to `overrun` without answering the caller again.
  Timer? overrunTimer;
  final Completer<VisionAnswer<R>> completer = Completer<VisionAnswer<R>>();
}

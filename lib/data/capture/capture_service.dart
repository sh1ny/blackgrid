import 'dart:async';
import 'dart:isolate';

import 'capture_failure.dart';
import 'capture_frame.dart';
import 'capture_native.dart';
import 'capture_policy.dart';
import 'capture_snapshot.dart';

/// Frame registry used by the caller isolate to adopt tickets. Production
/// frames are process-wide, so any isolate's view of the registry can release
/// a frame by id.
typedef FrameRegistryFactory = FrameRegistry Function();

/// The default caller-side registry: the native one.
FrameRegistry openDefaultFrameRegistry() =>
    openDefaultNativeCapturePlatform().frames;

enum _State { idle, active, overrun, closing, closed, unavailable }

/// Runs captures on a dedicated worker isolate with single admission, a
/// deadline that never starts a second native call, and a draining close
/// (design D8).
///
/// The worker is spawned on first use and opens its own platform from
/// [platformFactory]. At most one request is admitted at a time and none is
/// ever queued. A ticket reply that no waiting caller receives is adopted and
/// released at once, in every state.
final class CaptureService {
  CaptureService({
    this.platformFactory = openDefaultNativeCapturePlatform,
    this.registryFactory = openDefaultFrameRegistry,
    this.deadline = const Duration(milliseconds: 500),
    this.closeDrain = const Duration(seconds: 2),
  });

  /// Top-level or static function run inside the worker isolate.
  final CapturePlatformFactory platformFactory;

  /// Called in the caller isolate on the first capture, before the worker is
  /// spawned, to adopt and release tickets.
  final FrameRegistryFactory registryFactory;
  final Duration deadline;
  final Duration closeDrain;

  _State _state = _State.idle;
  String _unavailableReason = '';
  int _nextSeq = 0;

  // Worker.
  bool _spawned = false;
  bool _exited = false;
  RawReceivePort? _port;
  SendPort? _commands;
  final Completer<void> _exitSignal = Completer<void>();

  // The admitted request. [_inflightSeq] stays set until the worker replies
  // (or exits), even after the caller was answered with timeout/closed.
  int? _inflightSeq;
  _Capture? _unsent;
  Completer<CaptureResult>? _caller;
  Timer? _deadlineTimer;
  Completer<void>? _inflightClear;

  FrameRegistry? _registry;
  Future<ShutdownIncomplete?>? _closing;

  /// Whether the worker isolate is still alive.
  bool get workerRunning => _spawned && !_exited;

  /// Waits until the worker isolate has exited.
  Future<void> get workerExit => _exitSignal.future;

  /// Behaves as if the worker reported an error, without touching the worker.
  void debugReportWorkerError(String reason) => _markUnavailable(reason);

  /// Requests one capture. Expected failures are returned, never thrown. On
  /// success the caller owns the returned frame.
  Future<CaptureResult> capture(
    TriggerEvent trigger,
    CaptureMode mode, {
    int? requestId,
  }) {
    switch (_state) {
      case _State.closing:
      case _State.closed:
        return Future.value(const CaptureRejected(CaptureClosed()));
      case _State.unavailable:
        return Future.value(
          CaptureRejected(CaptureUnavailable(_unavailableReason)),
        );
      case _State.active:
      case _State.overrun:
        return Future.value(const CaptureRejected(CaptureBusy()));
      case _State.idle:
        break;
    }
    // Open the caller registry before any frame can exist: a ticket that
    // cannot be adopted would hold one of the 4 native slots for good.
    if (_registry == null) {
      try {
        _registry = registryFactory();
      } on Object catch (error) {
        _markUnavailable('Capture frame registry cannot open: $error');
        return Future.value(
          CaptureRejected(CaptureUnavailable(_unavailableReason)),
        );
      }
    }
    final seq = ++_nextSeq;
    final request = _Capture(seq, requestId ?? seq, trigger, mode);
    final caller = Completer<CaptureResult>();
    _state = _State.active;
    _caller = caller;
    _inflightSeq = seq;
    _inflightClear = Completer<void>();
    _deadlineTimer = Timer(deadline, _onDeadline);
    final commands = _commands;
    if (commands != null) {
      commands.send(request);
    } else {
      _unsent = request;
      if (!_spawned) _spawn();
    }
    return caller.future;
  }

  /// Stops admission at once, waits up to [closeDrain] for the active native
  /// call, asks the worker to exit and returns null, or [ShutdownIncomplete]
  /// when the worker is still inside a native call (it is never killed). Safe
  /// to call repeatedly.
  Future<ShutdownIncomplete?> close() => _closing ??= _close();

  Future<ShutdownIncomplete?> _close() async {
    final clock = Stopwatch()..start();
    _state = _State.closing;
    _answerCaller(const CaptureRejected(CaptureClosed()));
    if (_unsent != null) {
      // Never reached the worker: nothing is in flight.
      _unsent = null;
      _clearInflight();
    }
    if (!_spawned || _exited) {
      _state = _State.closed;
      return null;
    }
    final drained = await _waitFor(_inflightClear?.future, closeDrain);
    _commands?.send(const _Close());
    if (!drained) {
      _state = _State.closed;
      return const ShutdownIncomplete();
    }
    final remaining = closeDrain - clock.elapsed;
    final exited = await _waitFor(
      _exitSignal.future,
      remaining.isNegative ? Duration.zero : remaining,
    );
    _state = _State.closed;
    return exited ? null : const ShutdownIncomplete();
  }

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

  void _spawn() {
    _spawned = true;
    final port = RawReceivePort(_onMessage);
    _port = port;
    Isolate.spawn(
      _captureWorkerMain,
      _WorkerInit(port.sendPort, platformFactory),
      onExit: port.sendPort,
      onError: port.sendPort,
      debugName: 'bgc_capture',
    ).catchError((Object error) {
      _markUnavailable('Capture worker failed to start: $error');
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
        if (_state == _State.closing || _state == _State.closed) {
          commands.send(const _Close());
        } else {
          final unsent = _unsent;
          _unsent = null;
          if (unsent != null) commands.send(unsent);
        }
      case _OpenFailed(:final reason):
        _markUnavailable(reason);
      case _Reply():
        _onReply(message);
      case _Closed():
        break;
      case List<Object?>():
        _markUnavailable('Capture worker error: ${message.first}');
      default:
        break;
    }
  }

  void _onReply(_Reply reply) {
    final mine = reply.seq == _inflightSeq;
    if (mine) _clearInflight();
    final caller = _caller;
    if (mine && _state == _State.active && caller != null) {
      _state = _State.idle;
      _answerCaller(_deliver(reply));
      return;
    }
    final ticket = reply.ticket;
    if (ticket != null) _release(ticket);
    if (mine && _state == _State.overrun) _state = _State.idle;
  }

  CaptureResult _deliver(_Reply reply) {
    final ticket = reply.ticket;
    if (ticket == null) {
      return CaptureRejected(
        reply.failure ?? const CaptureUnavailable('empty reply'),
      );
    }
    try {
      return CaptureSuccess(CaptureFrame.adopt(ticket, _frames));
    } on Object catch (error) {
      return CaptureRejected(CaptureUnavailable('cannot adopt frame: $error'));
    }
  }

  void _release(CaptureFrameTicket ticket) {
    try {
      CaptureFrame.adopt(ticket, _frames).release();
    } on Object {
      // No registry to release into; nothing more can be done here.
    }
  }

  // Set before the first request is admitted, so every reply can be adopted.
  FrameRegistry get _frames => _registry!;

  void _onDeadline() {
    if (_state != _State.active) return;
    _state = _State.overrun;
    _answerCaller(const CaptureRejected(CaptureTimeout()));
  }

  void _markUnavailable(String reason) {
    if (_state == _State.closing || _state == _State.closed) return;
    _state = _State.unavailable;
    _unavailableReason = reason;
    _unsent = null;
    _answerCaller(CaptureRejected(CaptureUnavailable(reason)));
  }

  void _onExit() {
    _exited = true;
    _port?.close();
    _port = null;
    _commands = null;
    _unsent = null;
    _markUnavailable(
      _unavailableReason.isEmpty
          ? 'Capture worker exited unexpectedly.'
          : _unavailableReason,
    );
    _clearInflight();
    if (!_exitSignal.isCompleted) _exitSignal.complete();
  }

  void _answerCaller(CaptureResult result) {
    _deadlineTimer?.cancel();
    _deadlineTimer = null;
    final caller = _caller;
    _caller = null;
    if (caller != null && !caller.isCompleted) caller.complete(result);
  }

  void _clearInflight() {
    _inflightSeq = null;
    final clear = _inflightClear;
    _inflightClear = null;
    if (clear != null && !clear.isCompleted) clear.complete();
  }
}

// --- Messages (all sendable plain data) ---

final class _WorkerInit {
  const _WorkerInit(this.replyTo, this.factory);

  final SendPort replyTo;
  final CapturePlatformFactory factory;
}

final class _Capture {
  const _Capture(this.seq, this.requestId, this.trigger, this.mode);

  final int seq;
  final int requestId;
  final TriggerEvent trigger;
  final CaptureMode mode;
}

final class _Close {
  const _Close();
}

final class _Flush {
  const _Flush();
}

final class _Ready {
  const _Ready(this.commands);

  final SendPort commands;
}

final class _OpenFailed {
  const _OpenFailed(this.reason);

  final String reason;
}

final class _Closed {
  const _Closed();
}

final class _Reply {
  const _Reply(this.seq, this.ticket, this.failure);

  final int seq;
  final CaptureFrameTicket? ticket;
  final CaptureFailure? failure;
}

// --- Worker isolate ---

void _captureWorkerMain(_WorkerInit init) {
  final CapturePlatform platform;
  try {
    platform = init.factory();
  } on Object catch (error) {
    init.replyTo.send(_OpenFailed('$error'));
    return;
  }
  final policy = CapturePolicy(platform);
  final commands = RawReceivePort();
  // The finished result waits here until the loop has seen every message that
  // was already queued, so a queued `close` can release it instead.
  _Reply? held;
  commands.handler = (Object? message) {
    switch (message) {
      case _Capture():
        final result = policy.capture(
          trigger: message.trigger,
          mode: message.mode,
          requestId: message.requestId,
        );
        held = switch (result) {
          CaptureSuccess(:final frame) => _Reply(
            message.seq,
            frame.handOff(),
            null,
          ),
          CaptureRejected(:final failure) => _Reply(message.seq, null, failure),
        };
        commands.sendPort.send(const _Flush());
      case _Flush():
        final reply = held;
        held = null;
        if (reply != null) init.replyTo.send(reply);
      case _Close():
        final ticket = held?.ticket;
        held = null;
        if (ticket != null) platform.frames.release(ticket.frameId);
        init.replyTo.send(const _Closed());
        commands.close();
      default:
        break;
    }
  };
  init.replyTo.send(_Ready(commands.sendPort));
}

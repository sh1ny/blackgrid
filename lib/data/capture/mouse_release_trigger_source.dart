import 'dart:async';
import 'dart:ffi';

import 'capture_failure.dart';
import 'capture_native.dart';
import 'capture_snapshot.dart';
import 'capture_target.dart';

/// One delivered mouse-release trigger.
final class ScanTrigger {
  const ScanTrigger(this.event, this.droppedBefore);

  final TriggerEvent event;

  /// Triggers the bounded native queue dropped before this one was delivered.
  final int droppedBefore;
}

/// Bridges the native mouse-release hook to a non-buffering broadcast stream.
///
/// The native thread only signals; the handler drains on the Dart isolate.
/// Triggers with no listener are dropped, never queued. Nothing under
/// `lib/application`, `lib/ui` or `lib/main.dart` references this source yet.
final class MouseReleaseTriggerSource {
  MouseReleaseTriggerSource(
    CapturePlatform platform, {
    String targetTitle = captureTargetTitle,
  }) : _platform = platform,
       _title = targetTitle;

  final CapturePlatform _platform;
  final String _title;
  final StreamController<ScanTrigger> _controller =
      StreamController<ScanTrigger>.broadcast();

  NativeCallable<Void Function()>? _callable;
  bool _active = false;
  bool _stuck = false;
  int _pendingDropped = 0;

  Stream<ScanTrigger> get triggers => _controller.stream;

  /// Installs the hook. Null means started.
  TriggerFailure? start() {
    // After a stop timed out, retry the stop: native succeeds only once the
    // stuck hook thread has ended, and only then may the old listener close.
    if (_stuck && stop() != null) return const AlreadyStarted();
    if (_callable != null) return const AlreadyStarted();
    final callable = NativeCallable<Void Function()>.listener(_onSignal);
    final failure = _platform.hookStart(_title, callable.nativeFunction);
    if (failure != null) {
      callable.close();
      return failure;
    }
    _callable = callable;
    _active = true;
    _pendingDropped = 0;
    return null;
  }

  /// Stops the hook. The listener closes only after native confirms the hook
  /// thread is gone; on [StopTimedOut] it stays open on purpose so a late
  /// delivery cannot call freed code, and later starts report
  /// [AlreadyStarted] until the stuck thread has ended.
  TriggerFailure? stop() {
    final callable = _callable;
    if (callable == null) return null;
    _active = false;
    final failure = _platform.hookStop();
    if (failure is StopTimedOut) {
      _stuck = true;
      return failure;
    }
    callable.close();
    _callable = null;
    _stuck = false;
    return null;
  }

  Future<void> dispose() async {
    stop();
    if (!_controller.isClosed) await _controller.close();
  }

  void _onSignal() {
    if (!_active) return;
    final drain = _platform.hookDrain();
    _pendingDropped += drain.dropped;
    for (final event in drain.events) {
      if (_controller.isClosed) return;
      _controller.add(ScanTrigger(event, _pendingDropped));
      _pendingDropped = 0;
    }
  }
}

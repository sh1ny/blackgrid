import 'dart:async';
import 'dart:ffi';

import '../../domain/settings.dart';
import 'capture_failure.dart';
import 'capture_native.dart';
import 'capture_snapshot.dart';
import 'capture_target.dart';

/// One delivered trigger, from a mouse release or the hotkey.
final class ScanTrigger {
  const ScanTrigger(this.event, this.droppedBefore);

  final TriggerEvent event;

  /// Triggers the bounded native queue dropped before this one was delivered.
  final int droppedBefore;
}

/// The outcome of [InputTriggerSource.setHotkey].
sealed class HotkeyResult {
  const HotkeyResult();
}

/// The hotkey is registered, or turned off.
final class HotkeyApplied extends HotkeyResult {
  const HotkeyApplied();
}

/// Another application holds the key; [win32] is the OS error code.
final class HotkeyUnavailable extends HotkeyResult {
  const HotkeyUnavailable(this.win32);

  final int win32;
}

/// The input thread did not answer within its window.
final class HotkeyTimedOut extends HotkeyResult {
  const HotkeyTimedOut();
}

/// The hook is not running.
final class HotkeyNotStarted extends HotkeyResult {
  const HotkeyNotStarted();
}

/// Native rejected the key code. Unreachable from [ScanHotkey], kept so the
/// mapping covers every native status.
final class HotkeyInvalidArgument extends HotkeyResult {
  const HotkeyInvalidArgument();
}

/// Bridges the native input hook (mouse release and hotkey) to a
/// non-buffering broadcast stream.
///
/// The native thread only signals; the handler drains on the Dart isolate.
/// Triggers with no listener, or for a paused listener, are dropped, never
/// queued: the bounded native queue is the only buffer. A listener's next
/// trigger counts what it missed in [ScanTrigger.droppedBefore].
final class InputTriggerSource {
  InputTriggerSource(
    CapturePlatform platform, {
    String targetTitle = captureTargetTitle,
  }) : _platform = platform,
       _title = targetTitle;

  final CapturePlatform _platform;
  final String _title;
  final List<_Listener> _listeners = [];
  bool _closed = false;

  NativeCallable<Void Function()>? _callable;
  bool _active = false;
  bool _stuck = false;

  late final Stream<ScanTrigger> triggers = Stream<ScanTrigger>.multi((
    controller,
  ) {
    if (_closed) {
      controller.closeSync();
      return;
    }
    final listener = _Listener(controller);
    _listeners.add(listener);
    controller.onCancel = () => _listeners.remove(listener);
  }, isBroadcast: true);

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
    for (final listener in _listeners) {
      listener.dropped = 0;
    }
    return null;
  }

  /// Registers [key] on the running hook thread, or turns the hotkey off for
  /// [ScanHotkey.off].
  ///
  /// While this source is not started, answers [HotkeyNotStarted] without
  /// calling native, matching the native contract. Every other native status
  /// maps to its [HotkeyResult].
  Future<HotkeyResult> setHotkey(ScanHotkey key) async {
    if (_callable == null) return const HotkeyNotStarted();
    final raw = _platform.hotkeySet(key.vk);
    return switch (raw.status) {
      bgcOk => const HotkeyApplied(),
      bgcHotkeyUnavailable => HotkeyUnavailable(raw.win32),
      bgcHotkeyTimedOut => const HotkeyTimedOut(),
      bgcNotStarted => const HotkeyNotStarted(),
      _ => const HotkeyInvalidArgument(),
    };
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

  /// Stops the hook and closes the stream. Null means the hook thread has
  /// ended; [StopTimedOut] means it may still run, so its listener stays
  /// open, and calling dispose again retries the stop.
  Future<TriggerFailure?> dispose() async {
    final failure = stop();
    if (!_closed) {
      _closed = true;
      // Synchronous close: a paused listener cannot hold dispose open.
      for (final listener in List.of(_listeners)) {
        listener.controller.closeSync();
      }
      _listeners.clear();
    }
    return failure;
  }

  void _onSignal() {
    if (!_active || _closed) return;
    final drain = _platform.hookDrain();
    for (final listener in List.of(_listeners)) {
      listener.dropped += drain.dropped;
      for (final event in drain.events) {
        if (listener.controller.isPaused) {
          listener.dropped++;
          continue;
        }
        // Delivered now, so nothing waits in a buffer if it pauses later.
        listener.controller.addSync(ScanTrigger(event, listener.dropped));
        listener.dropped = 0;
      }
    }
  }
}

final class _Listener {
  _Listener(this.controller);

  final MultiStreamController<ScanTrigger> controller;

  /// Triggers this listener missed since its last delivery.
  int dropped = 0;
}

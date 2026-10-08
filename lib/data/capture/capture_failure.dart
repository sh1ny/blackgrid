import 'capture_frame.dart';

/// Typed reasons a capture request or the capture service cannot deliver a
/// frame (design D3). Expected failures are returned, never thrown.
sealed class CaptureFailure {
  const CaptureFailure();

  /// Human-readable description naming the offending value.
  String get message;

  @override
  String toString() => message;
}

/// The window no longer exists, or its handle now belongs to another
/// process or thread.
final class TargetGone extends CaptureFailure {
  const TargetGone([this.detail = '']);

  final String detail;

  @override
  String get message => detail.isEmpty
      ? 'Target window is gone.'
      : 'Target window is gone: $detail';
}

/// Another window became foreground after the trigger.
final class TargetNotForeground extends CaptureFailure {
  const TargetNotForeground();

  @override
  String get message => 'Target window is no longer foreground.';
}

final class TargetMinimised extends CaptureFailure {
  const TargetMinimised();

  @override
  String get message => 'Target window is minimised.';
}

/// Which identity check rejected the window.
enum WrongTargetKind { executable, title }

/// The window is not the game: [value] is the offending title or executable
/// name (empty when an executable name could not be resolved).
final class WrongTarget extends CaptureFailure {
  const WrongTarget(this.kind, this.value);

  final WrongTargetKind kind;
  final String value;

  @override
  String get message => switch (kind) {
    WrongTargetKind.executable => 'Wrong target executable: "$value".',
    WrongTargetKind.title => 'Wrong target window title: "$value".',
  };
}

/// The planned region has an empty intersection with the client or the
/// virtual desktop, or the trigger point is outside the client.
final class RoiOutsideClient extends CaptureFailure {
  const RoiOutsideClient();

  @override
  String get message => 'Capture region lies outside the client area.';
}

/// The captured rectangle exceeds 8192 per side or 25,165,824 pixels.
final class CaptureTooLarge extends CaptureFailure {
  const CaptureTooLarge(this.width, this.height);

  final int width;
  final int height;

  @override
  String get message => 'Capture size ${width}x$height exceeds the bounds.';
}

/// The target differed from the validated snapshot before or after pixel
/// acquisition. The frame was released.
final class TargetChanged extends CaptureFailure {
  const TargetChanged([this.detail = '']);

  final String detail;

  @override
  String get message => detail.isEmpty
      ? 'Target changed during capture.'
      : 'Target changed during capture: $detail';
}

/// Every blue, green and red byte was zero. The frame was released.
final class BlankCapture extends CaptureFailure {
  const BlankCapture();

  @override
  String get message => 'Captured frame is blank.';
}

final class FrameBudgetExceeded extends CaptureFailure {
  const FrameBudgetExceeded();

  @override
  String get message => 'Four capture frames are already live.';
}

final class CaptureFailed extends CaptureFailure {
  const CaptureFailed(this.win32);

  final int win32;

  @override
  String get message => 'Capture failed with Win32 error $win32.';
}

final class CaptureBusy extends CaptureFailure {
  const CaptureBusy();

  @override
  String get message => 'Another capture is in progress.';
}

final class CaptureTimeout extends CaptureFailure {
  const CaptureTimeout();

  @override
  String get message => 'Capture did not answer within its deadline.';
}

final class CaptureClosed extends CaptureFailure {
  const CaptureClosed();

  @override
  String get message => 'Capture service is closed.';
}

final class CaptureUnavailable extends CaptureFailure {
  const CaptureUnavailable(this.reason);

  final String reason;

  @override
  String get message => 'Capture is unavailable: $reason';
}

/// A close outcome: a native call had not returned within the drain period,
/// so the worker was left running rather than killed mid-call.
final class ShutdownIncomplete extends CaptureFailure {
  const ShutdownIncomplete();

  @override
  String get message => 'Capture shutdown did not complete within its drain.';
}

/// Why the trigger hook could not start or stop (design D3).
sealed class TriggerFailure {
  const TriggerFailure();

  String get message;

  @override
  String toString() => message;
}

final class AlreadyStarted extends TriggerFailure {
  const AlreadyStarted();

  @override
  String get message => 'The mouse hook is already installed.';
}

final class TriggerUnavailable extends TriggerFailure {
  const TriggerUnavailable(this.win32);

  final int win32;

  @override
  String get message => 'The mouse hook was refused (Win32 error $win32).';
}

final class StopTimedOut extends TriggerFailure {
  const StopTimedOut();

  @override
  String get message => 'The mouse hook thread did not stop within 1 s.';
}

/// Outcome of a capture request in the isolate that ran the policy.
sealed class CaptureResult {
  const CaptureResult();
}

final class CaptureSuccess extends CaptureResult {
  const CaptureSuccess(this.frame);

  /// Owned by the receiver, who must release or hand it off exactly once.
  final CaptureFrame frame;
}

final class CaptureRejected extends CaptureResult {
  const CaptureRejected(this.failure);

  final CaptureFailure failure;
}

/// Thrown when a released or handed-off frame is read or handed off again.
/// No native memory is accessed.
final class FrameReleasedError extends Error {
  FrameReleasedError([this.frameId = 0]);

  final int frameId;

  @override
  String toString() => 'frameReleased: frame $frameId was already released.';
}

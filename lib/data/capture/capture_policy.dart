import 'capture_failure.dart';
import 'capture_frame.dart';
import 'capture_geometry.dart';
import 'capture_native.dart';
import 'capture_snapshot.dart';
import 'capture_target.dart';

/// Validates, plans, captures and checks coherence for one capture request
/// (design D3). Runs in the isolate that owns the [CapturePlatform] (the
/// capture worker). Expected failures are returned, never thrown.
///
/// A [CaptureSuccess] carries a [CaptureFrame] owned by the caller, which
/// releases it or sends `frame.handOff()` to the isolate that wants it.
final class CapturePolicy {
  CapturePolicy(this._platform, {DateTime Function()? utcNow})
    : _utcNow = utcNow ?? (() => DateTime.now().toUtc());

  final CapturePlatform _platform;
  final DateTime Function() _utcNow;

  // One-entry executable-name cache keyed by (hwnd, pid, tid) (design D6).
  ({int hwnd, int pid, int tid})? _cacheKey;
  String _cacheName = '';

  CaptureResult capture({
    required TriggerEvent trigger,
    required CaptureMode mode,
    required int requestId,
  }) {
    final s0 = _platform.snapshot(trigger.hwnd);
    if (s0 == null) return const CaptureRejected(TargetGone());
    final invalid = _validate(s0, trigger);
    if (invalid != null) return CaptureRejected(invalid);
    final exe = _executableOf(s0);
    if (!isCaptureTargetExecutable(exe)) {
      return CaptureRejected(WrongTarget(WrongTargetKind.executable, exe));
    }

    final planned = switch (mode) {
      CaptureMode.targeted => planTargeted(s0, x: trigger.x, y: trigger.y),
      CaptureMode.fallback => planFallback(s0),
    };
    final CapturePlan plan;
    switch (planned) {
      case PlanFailure(:final failure):
        return CaptureRejected(failure);
      case PlanOk(plan: final p):
        plan = p;
    }

    final raw = _platform.capture(s0.hwnd, plan.desktop);
    final RawCapture capture;
    switch (raw) {
      case RawCaptureError(:final failure):
        return CaptureRejected(failure);
      case RawCaptureOk(capture: final c):
        capture = c;
    }

    // From here the frame is ours: release it on every reject.
    final frames = _platform.frames;
    CaptureResult reject(CaptureFailure failure) {
      frames.release(capture.frameId);
      return CaptureRejected(failure);
    }

    if (!s0.coherentWith(capture.pre)) {
      return reject(
        TargetChanged('before capture: ${s0.describeDifference(capture.pre)}'),
      );
    }
    if (!s0.coherentWith(capture.post)) {
      return reject(
        TargetChanged('after capture: ${s0.describeDifference(capture.post)}'),
      );
    }
    if (capture.allZero) return reject(const BlankCapture());

    final view = frames.view(capture.frameId);
    if (view == null ||
        view.width != plan.captured.width ||
        view.height != plan.captured.height ||
        view.stride < view.width * 4) {
      return reject(
        const CaptureUnavailable('native frame does not match the plan'),
      );
    }
    final metadata = CaptureFrameMetadata(
      width: view.width,
      height: view.height,
      stride: view.stride,
      desktopLeft: plan.desktop.left,
      desktopTop: plan.desktop.top,
      requested: plan.requested,
      captured: plan.captured,
      clipped: plan.clipped,
      clientWidth: s0.client.width,
      clientHeight: s0.client.height,
      dpi: s0.dpi,
      hwnd: s0.hwnd,
      pid: s0.pid,
      tid: s0.tid,
      exeName: exe,
      qpcBefore: capture.qpcBefore,
      qpcAfter: capture.qpcAfter,
      capturedAtUtc: _utcNow(),
      requestId: requestId,
    );
    return CaptureSuccess(CaptureFrame(capture.frameId, metadata, frames));
  }

  /// Identity checks that need no executable name. Minimised is reported
  /// before foreground because a minimised window is never foreground.
  CaptureFailure? _validate(WindowSnapshot s, TriggerEvent t) {
    if (s.hwnd != t.hwnd) return const TargetGone('window handle differs');
    if (s.pid != t.pid || s.tid != t.tid) {
      return const TargetGone('handle belongs to another process or thread');
    }
    if (s.minimised) return const TargetMinimised();
    if (!s.foreground) return const TargetNotForeground();
    if (!isCaptureTargetTitle(s.title)) {
      return WrongTarget(WrongTargetKind.title, s.title);
    }
    return null;
  }

  String _executableOf(WindowSnapshot s) {
    final key = (hwnd: s.hwnd, pid: s.pid, tid: s.tid);
    if (_cacheKey == key) return _cacheName;
    final name = _platform.processName(s.pid);
    // A failed lookup is not cached, so the next request lists again.
    if (name == null || name.isEmpty) return '';
    _cacheKey = key;
    _cacheName = name;
    return name;
  }
}

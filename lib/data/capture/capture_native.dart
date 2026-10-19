import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';

import 'capture_failure.dart';
import 'capture_frame.dart';
import 'capture_snapshot.dart';

// --- Mirror of windows/capture/capture.h (ABI version 2) ---

const int bgcAbiVersion = 2;

const int bgcOk = 0;
const int bgcTargetGone = 1;
const int bgcFrameBudget = 2;
const int bgcCaptureFailed = 3;
const int bgcInvalidArgument = 4;
const int bgcAlreadyStarted = 5;
const int bgcUnavailable = 6;
const int bgcStopTimedOut = 7;
const int bgcNotStarted = 8;
const int bgcFrameReleased = 9;
const int bgcNotFound = 10;
const int bgcHotkeyUnavailable = 11;
const int bgcHotkeyTimedOut = 12;

const int bgcTriggerMouse = 0;
const int bgcTriggerHotkey = 1;

const int bgcRingCapacity = 16;
const int bgcFrameSlots = 4;
const int bgcTitleChars = 256;
const int bgcExeChars = 260;

/// `bgc_rect`, 16 bytes.
final class BgcRect extends Struct {
  @Int32()
  external int left;
  @Int32()
  external int top;
  @Int32()
  external int width;
  @Int32()
  external int height;
}

/// `bgc_window_snapshot`, 592 bytes.
final class BgcWindowSnapshot extends Struct {
  @Uint64()
  external int hwnd;
  @Uint32()
  external int pid;
  @Uint32()
  external int tid;
  @Uint32()
  external int minimised;
  @Uint32()
  external int foreground;
  @Uint32()
  external int dpi;
  @Uint32()
  external int reserved;
  external BgcRect client;
  external BgcRect monitor;
  external BgcRect virtualDesktop;
  @Array(bgcTitleChars)
  external Array<Uint16> title;
}

/// `bgc_trigger_event`, 40 bytes.
final class BgcTriggerEvent extends Struct {
  @Int32()
  external int x;
  @Int32()
  external int y;
  @Uint64()
  external int hwnd;
  @Uint32()
  external int pid;
  @Uint32()
  external int tid;
  @Int64()
  external int qpc;
  @Uint32()
  external int source;
  @Uint32()
  external int reserved;
}

/// `bgc_capture_result`, 1216 bytes.
final class BgcCaptureResult extends Struct {
  @Uint64()
  external int frameId;
  @Int64()
  external int qpcBefore;
  @Int64()
  external int qpcAfter;
  @Uint32()
  external int allZero;
  @Uint32()
  external int win32Error;
  external BgcWindowSnapshot pre;
  external BgcWindowSnapshot post;
}

/// `bgc_frame_view`, 24 bytes.
final class BgcFrameView extends Struct {
  external Pointer<Uint8> pixels;
  @Int32()
  external int width;
  @Int32()
  external int height;
  @Int32()
  external int stride;
  @Int32()
  external int reserved;
}

CaptureRect _rect(BgcRect r) => CaptureRect(r.left, r.top, r.width, r.height);

/// Decodes a native snapshot. Origins stay signed.
WindowSnapshot decodeWindowSnapshot(BgcWindowSnapshot s) {
  final units = <int>[];
  for (var i = 0; i < bgcTitleChars; i++) {
    final unit = s.title[i];
    if (unit == 0) break;
    units.add(unit);
  }
  return WindowSnapshot(
    hwnd: s.hwnd,
    pid: s.pid,
    tid: s.tid,
    minimised: s.minimised != 0,
    foreground: s.foreground != 0,
    dpi: s.dpi,
    client: _rect(s.client),
    monitor: _rect(s.monitor),
    virtualDesktop: _rect(s.virtualDesktop),
    title: String.fromCharCodes(units),
  );
}

TriggerEvent decodeTriggerEvent(BgcTriggerEvent e) => TriggerEvent(
  x: e.x,
  y: e.y,
  hwnd: e.hwnd,
  pid: e.pid,
  tid: e.tid,
  qpc: e.qpc,
  source: decodeTriggerSource(e.source),
);

/// Maps the native `source` field. `BGC_TRIGGER_HOTKEY` is [TriggerSource.hotkey];
/// `BGC_TRIGGER_MOUSE` and any unknown value are [TriggerSource.mouse], the
/// source every event had before ABI 2.
TriggerSource decodeTriggerSource(int source) =>
    source == bgcTriggerHotkey ? TriggerSource.hotkey : TriggerSource.mouse;

// --- Platform seam ---

/// A successful native acquisition. The caller owns [frameId].
final class RawCapture {
  const RawCapture({
    required this.frameId,
    required this.qpcBefore,
    required this.qpcAfter,
    required this.allZero,
    required this.pre,
    required this.post,
  });

  final int frameId;
  final int qpcBefore;
  final int qpcAfter;
  final bool allZero;
  final WindowSnapshot pre;
  final WindowSnapshot post;
}

sealed class RawCaptureResult {
  const RawCaptureResult();
}

final class RawCaptureOk extends RawCaptureResult {
  const RawCaptureOk(this.capture);

  final RawCapture capture;
}

/// Native refused or failed; no frame slot stays reserved.
final class RawCaptureError extends RawCaptureResult {
  const RawCaptureError(this.failure);

  final CaptureFailure failure;
}

/// What one `bgc_hook_drain` returned.
final class TriggerDrain {
  const TriggerDrain(this.events, this.dropped);

  final List<TriggerEvent> events;
  final int dropped;
}

/// What one `bgc_hotkey_set` returned: the native [status] and, for
/// `BGC_HOTKEY_UNAVAILABLE`, the OS error code in [win32].
final class RawHotkeyStatus {
  const RawHotkeyStatus(this.status, [this.win32 = 0]);

  final int status;
  final int win32;
}

/// Everything Dart needs from the native capture library. Production uses
/// [NativeCapturePlatform]; tests and the worker factory supply fakes.
abstract interface class CapturePlatform {
  /// The frame store for frames this platform produces.
  FrameRegistry get frames;

  /// Null when the window is gone (`BGC_TARGET_GONE`).
  WindowSnapshot? snapshot(int hwnd);

  /// Executable file name of [pid] from a process listing, or null when it
  /// is not listed or the listing failed. Never opens the process.
  String? processName(int pid);

  /// Acquires [desktopRect] (signed desktop pixels).
  RawCaptureResult capture(int hwnd, CaptureRect desktopRect);

  int qpcNow();
  int qpcFrequency();

  /// Starts the hook thread; [signal] must be a `NativeCallable.listener`
  /// pointer. Null means started.
  TriggerFailure? hookStart(
    String title,
    Pointer<NativeFunction<Void Function()>> signal,
  );

  /// Null means stopped (or nothing was installed).
  TriggerFailure? hookStop();

  TriggerDrain hookDrain();

  /// Registers [vk] (0 turns the hotkey off, 0x70..0x87 is F1..F24) on the
  /// running input thread. Blocks up to the native 1 s answer window.
  RawHotkeyStatus hotkeySet(int vk);
}

/// Builds a platform inside the isolate that will use it. Must be a top-level
/// or static function so it can be passed to `Isolate.spawn`.
typedef CapturePlatformFactory = CapturePlatform Function();

// --- Loader ---

/// Why the library could not be opened (missing file, hash or ABI mismatch).
final class CaptureLibraryException implements Exception {
  const CaptureLibraryException(this.reason);

  final String reason;

  @override
  String toString() => 'CaptureLibraryException: $reason';
}

const String captureLibraryName = 'blackgrid_capture.dll';

/// `<dir of the running executable>/blackgrid_capture.dll`.
String defaultCaptureLibraryPath() {
  final dir = File(Platform.resolvedExecutable).parent.path;
  return '$dir${Platform.pathSeparator}$captureLibraryName';
}

/// Checks the absolute path, the `<dll>.sha256` binding and the file hash
/// without opening the library. Returns a reason, or null when it matches.
String? verifyCaptureBinding(String path) {
  final dll = File(path);
  if (!dll.isAbsolute) {
    return 'Capture library requires an explicit absolute app-local path.';
  }
  final binding = File('$path.sha256');
  if (!dll.existsSync() || !binding.existsSync()) {
    return 'App-local capture library/hash binding is missing.';
  }
  if (sha256.convert(dll.readAsBytesSync()).toString() !=
      binding.readAsStringSync().trim()) {
    return 'App-local capture library hash does not match its build binding.';
  }
  return null;
}

/// Opens the verified app-local library with the default path. Top-level so
/// a worker isolate can use it as a [CapturePlatformFactory].
CapturePlatform openDefaultNativeCapturePlatform() =>
    NativeCapturePlatform.open(defaultCaptureLibraryPath());

/// Frame registry backed by the native slot registry and its finalizer entry.
final class NativeFrameRegistry implements FrameRegistry {
  NativeFrameRegistry._(DynamicLibrary library)
    : _info = library
          .lookupFunction<
            Int32 Function(Uint64, Pointer<BgcFrameView>),
            int Function(int, Pointer<BgcFrameView>)
          >('bgc_frame_info'),
      _release = library
          .lookupFunction<Void Function(Uint64), void Function(int)>(
            'bgc_frame_release',
          ),
      _liveCount = library.lookupFunction<Uint32 Function(), int Function()>(
        'bgc_frame_live_count',
      ),
      _finalizer = NativeFinalizer(
        library.lookup<NativeFinalizerFunction>('bgc_frame_finalize'),
      );

  final int Function(int, Pointer<BgcFrameView>) _info;
  final void Function(int) _release;
  final int Function() _liveCount;
  final NativeFinalizer _finalizer;

  @override
  FrameView? view(int frameId) {
    final out = calloc<BgcFrameView>();
    try {
      if (_info(frameId, out) != bgcOk) return null;
      final v = out.ref;
      return FrameView(v.pixels, v.width, v.height, v.stride);
    } finally {
      calloc.free(out);
    }
  }

  @override
  void release(int frameId) => _release(frameId);

  @override
  int get liveCount => _liveCount();

  @override
  void attach(Finalizable owner, int frameId) {
    // The token is the frame id as a pointer value (bgc_frame_finalize).
    _finalizer.attach(owner, Pointer<Void>.fromAddress(frameId), detach: owner);
  }

  @override
  void detach(Finalizable owner) => _finalizer.detach(owner);
}

/// The real `blackgrid_capture.dll` behind the [CapturePlatform] seam.
final class NativeCapturePlatform implements CapturePlatform {
  NativeCapturePlatform._(this._library, this.frames)
    : _hookStart = _library
          .lookupFunction<
            Int32 Function(
              Pointer<Uint16>,
              Pointer<NativeFunction<Void Function()>>,
              Pointer<Uint32>,
            ),
            int Function(
              Pointer<Uint16>,
              Pointer<NativeFunction<Void Function()>>,
              Pointer<Uint32>,
            )
          >('bgc_hook_start'),
      _hookStop = _library.lookupFunction<Int32 Function(), int Function()>(
        'bgc_hook_stop',
      ),
      _hookDrain = _library
          .lookupFunction<
            Uint32 Function(Pointer<BgcTriggerEvent>, Uint32, Pointer<Uint32>),
            int Function(Pointer<BgcTriggerEvent>, int, Pointer<Uint32>)
          >('bgc_hook_drain'),
      _hotkeySet = _library
          .lookupFunction<
            Int32 Function(Uint32, Pointer<Uint32>),
            int Function(int, Pointer<Uint32>)
          >('bgc_hotkey_set'),
      _snapshot = _library
          .lookupFunction<
            Int32 Function(Uint64, Pointer<BgcWindowSnapshot>),
            int Function(int, Pointer<BgcWindowSnapshot>)
          >('bgc_snapshot'),
      _processName = _library
          .lookupFunction<
            Int32 Function(Uint32, Pointer<Uint16>, Uint32),
            int Function(int, Pointer<Uint16>, int)
          >('bgc_process_name'),
      _capture = _library
          .lookupFunction<
            Int32 Function(Uint64, Pointer<BgcRect>, Pointer<BgcCaptureResult>),
            int Function(int, Pointer<BgcRect>, Pointer<BgcCaptureResult>)
          >('bgc_capture'),
      _qpcNow = _library.lookupFunction<Int64 Function(), int Function()>(
        'bgc_qpc_now',
      ),
      _qpcFrequency = _library.lookupFunction<Int64 Function(), int Function()>(
        'bgc_qpc_frequency',
      );

  /// Verifies the absolute path, `.sha256` binding and `bgc_abi()` before any
  /// other lookup (mirrors panel OCR). Throws [CaptureLibraryException].
  factory NativeCapturePlatform.open(String path) {
    final problem = verifyCaptureBinding(path);
    if (problem != null) throw CaptureLibraryException(problem);
    final DynamicLibrary library;
    try {
      library = DynamicLibrary.open(path);
    } on ArgumentError catch (e) {
      throw CaptureLibraryException('Capture library failed to load: $e');
    }
    final abi = library.lookupFunction<Uint32 Function(), int Function()>(
      'bgc_abi',
    )();
    if (abi != bgcAbiVersion) {
      throw CaptureLibraryException(
        'Capture library ABI mismatch: expected $bgcAbiVersion, got $abi.',
      );
    }
    return NativeCapturePlatform._(library, NativeFrameRegistry._(library));
  }

  // Held so the library stays loaded for the platform's lifetime.
  // ignore: unused_field
  final DynamicLibrary _library;
  final int Function(
    Pointer<Uint16>,
    Pointer<NativeFunction<Void Function()>>,
    Pointer<Uint32>,
  )
  _hookStart;
  final int Function() _hookStop;
  final int Function(Pointer<BgcTriggerEvent>, int, Pointer<Uint32>) _hookDrain;
  final int Function(int, Pointer<Uint32>) _hotkeySet;
  final int Function(int, Pointer<BgcWindowSnapshot>) _snapshot;
  final int Function(int, Pointer<Uint16>, int) _processName;
  final int Function(int, Pointer<BgcRect>, Pointer<BgcCaptureResult>) _capture;
  final int Function() _qpcNow;
  final int Function() _qpcFrequency;

  @override
  final FrameRegistry frames;

  @override
  WindowSnapshot? snapshot(int hwnd) {
    final out = calloc<BgcWindowSnapshot>();
    try {
      if (_snapshot(hwnd, out) != bgcOk) return null;
      return decodeWindowSnapshot(out.ref);
    } finally {
      calloc.free(out);
    }
  }

  @override
  String? processName(int pid) {
    final buffer = calloc<Uint16>(bgcExeChars);
    try {
      if (_processName(pid, buffer, bgcExeChars) != bgcOk) return null;
      final units = <int>[];
      for (var i = 0; i < bgcExeChars; i++) {
        final unit = buffer[i];
        if (unit == 0) break;
        units.add(unit);
      }
      return String.fromCharCodes(units);
    } finally {
      calloc.free(buffer);
    }
  }

  @override
  RawCaptureResult capture(int hwnd, CaptureRect desktopRect) {
    final rect = calloc<BgcRect>();
    final out = calloc<BgcCaptureResult>();
    try {
      rect.ref
        ..left = desktopRect.left
        ..top = desktopRect.top
        ..width = desktopRect.width
        ..height = desktopRect.height;
      final status = _capture(hwnd, rect, out);
      final result = out.ref;
      return switch (status) {
        bgcOk => RawCaptureOk(
          RawCapture(
            frameId: result.frameId,
            qpcBefore: result.qpcBefore,
            qpcAfter: result.qpcAfter,
            allZero: result.allZero != 0,
            pre: decodeWindowSnapshot(result.pre),
            post: decodeWindowSnapshot(result.post),
          ),
        ),
        bgcTargetGone => const RawCaptureError(TargetGone()),
        bgcFrameBudget => const RawCaptureError(FrameBudgetExceeded()),
        bgcCaptureFailed => RawCaptureError(CaptureFailed(result.win32Error)),
        _ => RawCaptureError(
          CaptureUnavailable('native capture returned status $status'),
        ),
      };
    } finally {
      calloc.free(rect);
      calloc.free(out);
    }
  }

  @override
  int qpcNow() => _qpcNow();

  @override
  int qpcFrequency() => _qpcFrequency();

  @override
  TriggerFailure? hookStart(
    String title,
    Pointer<NativeFunction<Void Function()>> signal,
  ) {
    final units = title.codeUnits;
    final text = calloc<Uint16>(units.length + 1);
    final win32 = calloc<Uint32>();
    try {
      for (var i = 0; i < units.length; i++) {
        text[i] = units[i];
      }
      final status = _hookStart(text, signal, win32);
      return switch (status) {
        bgcOk => null,
        bgcAlreadyStarted => const AlreadyStarted(),
        _ => TriggerUnavailable(win32.value),
      };
    } finally {
      calloc.free(text);
      calloc.free(win32);
    }
  }

  @override
  TriggerFailure? hookStop() {
    final status = _hookStop();
    return switch (status) {
      bgcStopTimedOut => const StopTimedOut(),
      _ => null,
    };
  }

  @override
  RawHotkeyStatus hotkeySet(int vk) {
    final win32 = calloc<Uint32>();
    try {
      final status = _hotkeySet(vk, win32);
      return RawHotkeyStatus(status, win32.value);
    } finally {
      calloc.free(win32);
    }
  }

  @override
  TriggerDrain hookDrain() {
    final events = calloc<BgcTriggerEvent>(bgcRingCapacity);
    final dropped = calloc<Uint32>();
    try {
      final count = _hookDrain(events, bgcRingCapacity, dropped);
      return TriggerDrain([
        for (var i = 0; i < count && i < bgcRingCapacity; i++)
          decodeTriggerEvent(events[i]),
      ], dropped.value);
    } finally {
      calloc.free(events);
      calloc.free(dropped);
    }
  }
}

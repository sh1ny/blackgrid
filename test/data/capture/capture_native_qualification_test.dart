@Tags(['qualification'])
library;

import 'dart:ffi';
import 'dart:io';

import 'package:blackgrid/data/capture/capture_failure.dart';
import 'package:blackgrid/data/capture/capture_native.dart';
import 'package:blackgrid/data/capture/capture_snapshot.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/native_guard.dart';

/// Loads the real, hash-bound `blackgrid_capture.dll` from a built Release
/// bundle (run `flutter build windows --release` first). It never captures the
/// foreground window: the only pixels taken are an 8x8 rectangle under a
/// hidden window this test creates. It skips unless the run confirms no game is
/// running (`BLACKGRID_NO_GAMES_RUNNING=1`) and no known game is listed
/// (AGENTS.md).
void main() {
  final bundle =
      Platform.environment['BLACKGRID_RELEASE_BUNDLE'] ??
      'build/windows/x64/runner/Release';
  final dllPath = File('$bundle${Platform.pathSeparator}blackgrid_capture.dll')
      .absolute
      .path;
  final skip = _skipReason();

  late NativeCapturePlatform platform;
  late void Function(Pointer<Void>) finalizeEntry;

  setUpAll(() {
    if (skip != null) return;
    platform = NativeCapturePlatform.open(dllPath);
    finalizeEntry = DynamicLibrary.open(dllPath)
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('bgc_frame_finalize');
  });

  test('abi and struct sizes match capture.h', () {
    // open() already verified the sidecar and bgc_abi() == 2.
    expect(sizeOf<BgcRect>(), 16);
    expect(sizeOf<BgcWindowSnapshot>(), 592);
    expect(sizeOf<BgcTriggerEvent>(), 40);
    expect(sizeOf<BgcCaptureResult>(), 1216);
    expect(sizeOf<BgcFrameView>(), 24);
  }, skip: skip);

  test('snapshot of destroyed handle is targetGone', () {
    final live = platform.frames.liveCount;
    final hwnd = _createHiddenWindow();
    expect(platform.snapshot(hwnd), isNotNull);
    expect(_destroyWindow(hwnd), isNonZero);

    expect(platform.snapshot(hwnd), isNull);
    expect(platform.snapshot(0), isNull);
    final capture = platform.capture(hwnd, const CaptureRect(0, 0, 8, 8));
    expect(
      capture,
      isA<RawCaptureError>().having(
        (e) => e.failure,
        'failure',
        isA<TargetGone>(),
      ),
    );
    expect(platform.frames.liveCount, live);
  }, skip: skip);

  test('hook starts and stops and drains nothing after stop', () {
    final signal = NativeCallable<Void Function()>.listener(() {});
    try {
      // A title no window has: the hook installs but never accepts a release.
      expect(
        platform.hookStart(
          'blackgrid-qualification-none',
          signal.nativeFunction,
        ),
        isNull,
      );
      final whileRunning = platform.hookDrain();
      expect(whileRunning.events, isEmpty);
      expect(platform.hookStop(), isNull);

      final afterStop = platform.hookDrain();
      expect(afterStop.events, isEmpty);
      expect(afterStop.dropped, 0);
    } finally {
      signal.close();
    }
  }, skip: skip);

  test('second hook start returns alreadyStarted', () {
    final first = NativeCallable<Void Function()>.listener(() {});
    final second = NativeCallable<Void Function()>.listener(() {});
    try {
      expect(
        platform.hookStart(
          'blackgrid-qualification-none',
          first.nativeFunction,
        ),
        isNull,
      );
      expect(
        platform.hookStart(
          'blackgrid-qualification-none',
          second.nativeFunction,
        ),
        isA<AlreadyStarted>(),
      );
      expect(platform.hookStop(), isNull);
    } finally {
      first.close();
      second.close();
    }
  }, skip: skip);

  test('finalizer entry releases the slot', () {
    final live = platform.frames.liveCount;
    final hwnd = _createHiddenWindow();
    try {
      final snapshot = platform.snapshot(hwnd)!;
      final raw = platform.capture(hwnd, snapshot.client);
      expect(raw, isA<RawCaptureOk>());
      final frameId = (raw as RawCaptureOk).capture.frameId;
      expect(platform.frames.liveCount, live + 1);

      // What NativeFinalizer calls when an owner drops a frame unreleased.
      finalizeEntry(Pointer<Void>.fromAddress(frameId));
      expect(platform.frames.liveCount, live);
      expect(platform.frames.view(frameId), isNull);
      platform.frames.release(frameId); // stale id: a no-op
      expect(platform.frames.liveCount, live);
    } finally {
      _destroyWindow(hwnd);
    }
  }, skip: skip);
}

String? _skipReason() => nativeCaptureSkipReason(
  isWindows: Platform.isWindows,
  environment: Platform.environment,
  listProcesses: () => Process.runSync('tasklist', ['/FO', 'CSV', '/NH']),
);

final _user32 = DynamicLibrary.open('user32.dll');
final _createWindowEx = _user32
    .lookupFunction<
      IntPtr Function(
        Uint32,
        Pointer<Utf16>,
        Pointer<Utf16>,
        Uint32,
        Int32,
        Int32,
        Int32,
        Int32,
        IntPtr,
        IntPtr,
        IntPtr,
        Pointer<Void>,
      ),
      int Function(
        int,
        Pointer<Utf16>,
        Pointer<Utf16>,
        int,
        int,
        int,
        int,
        int,
        int,
        int,
        int,
        Pointer<Void>,
      )
    >('CreateWindowExW');
final _destroy = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('DestroyWindow');

/// A hidden 8x8 popup owned by this process. Create and destroy it in one
/// synchronous stretch: windows belong to the creating OS thread.
int _createHiddenWindow() {
  const wsPopup = 0x80000000;
  final className = 'STATIC'.toNativeUtf16();
  final title = 'blackgrid capture qualification'.toNativeUtf16();
  try {
    final hwnd = _createWindowEx(
      0,
      className,
      title,
      wsPopup,
      0,
      0,
      8,
      8,
      0,
      0,
      0,
      nullptr,
    );
    expect(hwnd, isNonZero, reason: 'CreateWindowExW failed');
    return hwnd;
  } finally {
    malloc.free(className);
    malloc.free(title);
  }
}

int _destroyWindow(int hwnd) => _destroy(hwnd);

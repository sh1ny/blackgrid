import 'dart:ffi';
import 'dart:io';

import 'package:blackgrid/data/capture/capture_failure.dart';
import 'package:blackgrid/data/capture/capture_native.dart';
import 'package:blackgrid/data/capture/capture_snapshot.dart';
import 'package:ffi/ffi.dart';

import 'fake_capture_platform.dart';

/// Native memory shared by the test isolate and the worker isolate: slot 0 is
/// the hold flag (1 = the next/current capture blocks synchronously).
const holdSlot = 0;

Pointer<Int64> allocateControl() => calloc<Int64>(4);

const holdableHwnd = 0x30A2E;
const holdablePid = 4242;
const holdableTid = 777;

const holdableTrigger = TriggerEvent(
  x: 900,
  y: 500,
  hwnd: holdableHwnd,
  pid: holdablePid,
  tid: holdableTid,
  qpc: 500,
  source: TriggerSource.mouse,
);

/// Top-level so the closure only captures two ints and can be sent to an
/// isolate.
CapturePlatformFactory holdableFactory(
  int registryAddress,
  int controlAddress,
) =>
    () => HoldableCapturePlatform(registryAddress, controlAddress);

/// A factory that fails to open, for the worker open-failure path.
CapturePlatform failingFactory() =>
    throw const CaptureLibraryException('fixture: cannot open library');

/// A platform whose `capture` blocks the whole worker isolate inside
/// synchronous code while the control flag is set, like a slow native call.
final class HoldableCapturePlatform implements CapturePlatform {
  HoldableCapturePlatform(int registryAddress, int controlAddress)
    : frames = FakeFrameRegistry.fromAddress(registryAddress),
      _control = Pointer<Int64>.fromAddress(controlAddress);

  @override
  final FakeFrameRegistry frames;
  final Pointer<Int64> _control;
  int _qpc = 1000;

  static const _snapshot = WindowSnapshot(
    hwnd: holdableHwnd,
    pid: holdablePid,
    tid: holdableTid,
    minimised: false,
    foreground: true,
    dpi: 96,
    client: CaptureRect(0, 0, 1920, 1080),
    monitor: CaptureRect(0, 0, 1920, 1080),
    virtualDesktop: CaptureRect(0, 0, 1920, 1080),
    title: 'EscapeFromTarkov',
  );

  @override
  WindowSnapshot? snapshot(int hwnd) => _snapshot;

  @override
  String? processName(int pid) => 'EscapeFromTarkov.exe';

  @override
  RawCaptureResult capture(int hwnd, CaptureRect desktopRect) {
    while (_control[holdSlot] == 1) {
      sleep(const Duration(milliseconds: 2));
    }
    final id = frames.createFrame(desktopRect.width, desktopRect.height);
    return RawCaptureOk(
      RawCapture(
        frameId: id,
        qpcBefore: _qpc += 10,
        qpcAfter: _qpc += 10,
        allZero: false,
        pre: _snapshot,
        post: _snapshot,
      ),
    );
  }

  @override
  int qpcNow() => _qpc += 10;

  @override
  int qpcFrequency() => 10000000;

  @override
  TriggerFailure? hookStart(
    String title,
    Pointer<NativeFunction<Void Function()>> signal,
  ) => null;

  @override
  TriggerFailure? hookStop() => null;

  @override
  TriggerDrain hookDrain() => const TriggerDrain([], 0);

  @override
  RawHotkeyStatus hotkeySet(int vk) => const RawHotkeyStatus(bgcOk);
}

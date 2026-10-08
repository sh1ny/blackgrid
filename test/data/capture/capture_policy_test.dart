import 'dart:ffi';

import 'package:blackgrid/data/capture/capture_failure.dart';
import 'package:blackgrid/data/capture/capture_frame.dart';
import 'package:blackgrid/data/capture/capture_native.dart';
import 'package:blackgrid/data/capture/capture_policy.dart';
import 'package:blackgrid/data/capture/capture_snapshot.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_capture_platform.dart';

const _hwnd = 0x30A2E;
const _pid = 4242;
const _tid = 777;

WindowSnapshot target({
  int hwnd = _hwnd,
  int pid = _pid,
  int tid = _tid,
  bool minimised = false,
  bool foreground = true,
  int dpi = 96,
  CaptureRect client = const CaptureRect(0, 0, 1920, 1080),
  String title = 'EscapeFromTarkov',
}) => WindowSnapshot(
  hwnd: hwnd,
  pid: pid,
  tid: tid,
  minimised: minimised,
  foreground: foreground,
  dpi: dpi,
  client: client,
  monitor: const CaptureRect(0, 0, 1920, 1080),
  virtualDesktop: const CaptureRect(0, 0, 1920, 1080),
  title: title,
);

TriggerEvent trigger({
  int x = 900,
  int y = 500,
  int hwnd = _hwnd,
  int pid = _pid,
  int tid = _tid,
  int qpc = 500,
}) => TriggerEvent(x: x, y: y, hwnd: hwnd, pid: pid, tid: tid, qpc: qpc);

CaptureFailure rejected(CaptureResult result) {
  expect(result, isA<CaptureRejected>(), reason: '$result');
  return (result as CaptureRejected).failure;
}

CaptureFrame succeeded(CaptureResult result) {
  expect(result, isA<CaptureSuccess>(), reason: '$result');
  return (result as CaptureSuccess).frame;
}

void main() {
  late FakeCapturePlatform platform;
  late CapturePolicy policy;

  setUp(() {
    platform = FakeCapturePlatform(s0: target());
    policy = CapturePolicy(
      platform,
      utcNow: () => DateTime.utc(2026, 10, 8, 12),
    );
  });

  CaptureResult run({
    TriggerEvent? t,
    CaptureMode mode = CaptureMode.targeted,
    int requestId = 1,
  }) =>
      policy.capture(trigger: t ?? trigger(), mode: mode, requestId: requestId);

  void expectNoCaptureNoFrames() {
    expect(platform.captureCalls, isEmpty);
    expect(platform.frames.liveCount, 0);
  }

  test('snapshot decode keeps signed negative origins', () {
    expect(sizeOf<BgcRect>(), 16);
    expect(sizeOf<BgcWindowSnapshot>(), 592);
    expect(sizeOf<BgcTriggerEvent>(), 32);
    expect(sizeOf<BgcCaptureResult>(), 1216);
    expect(sizeOf<BgcFrameView>(), 24);
    final p = calloc<BgcWindowSnapshot>();
    addTearDown(() => calloc.free(p));
    final s = p.ref;
    s.hwnd = _hwnd;
    s.pid = _pid;
    s.tid = _tid;
    s.foreground = 1;
    s.dpi = 144;
    s.client
      ..left = -2560
      ..top = -360
      ..width = 2560
      ..height = 1440;
    s.monitor
      ..left = -2560
      ..top = -360
      ..width = 2560
      ..height = 1440;
    s.virtualDesktop
      ..left = -2560
      ..top = -360
      ..width = 4480
      ..height = 1800;
    const title = 'EscapeFromTarkov';
    for (var i = 0; i < title.length; i++) {
      s.title[i] = title.codeUnitAt(i);
    }
    final decoded = decodeWindowSnapshot(s);
    expect(decoded.client, const CaptureRect(-2560, -360, 2560, 1440));
    expect(decoded.dpi, 144);
    expect(decoded.monitor.left, isNegative);
    expect(decoded.virtualDesktop.left, -2560);
    expect(decoded.title, 'EscapeFromTarkov');
    expect(decoded.foreground, isTrue);
    expect(decoded.minimised, isFalse);
  });

  test('valid target passes validation', () {
    final frame = succeeded(run());
    expect(platform.captureCalls, hasLength(1));
    expect(platform.captureCalls.single.hwnd, _hwnd);
    expect(
      platform.captureCalls.single.rect,
      const CaptureRect(875, 475, 650, 50),
    );
    expect(platform.frames.releaseCalls, isEmpty);
    expect(platform.frames.liveCount, 1);
    frame.release();
  });

  test('foreground change is targetNotForeground without capture', () {
    platform.s0 = target(foreground: false);
    expect(rejected(run()), isA<TargetNotForeground>());
    expectNoCaptureNoFrames();
  });

  test('minimised target fails without capture', () {
    platform.s0 = target(minimised: true);
    expect(rejected(run()), isA<TargetMinimised>());
    expectNoCaptureNoFrames();
    // A minimised window is normally not foreground either: still minimised.
    platform.s0 = target(minimised: true, foreground: false);
    expect(rejected(run()), isA<TargetMinimised>());
    expectNoCaptureNoFrames();
  });

  test('wrong executable is wrongTarget without capture', () {
    platform.exe = 'notepad.exe';
    final failure = rejected(run());
    expect(failure, isA<WrongTarget>());
    expect((failure as WrongTarget).kind, WrongTargetKind.executable);
    expect(failure.value, 'notepad.exe');
    expectNoCaptureNoFrames();
    // The title is checked too.
    platform.s0 = target(title: 'Notepad');
    final byTitle = rejected(run());
    expect((byTitle as WrongTarget).kind, WrongTargetKind.title);
    expect(byTitle.value, 'Notepad');
    expectNoCaptureNoFrames();
  });

  test('pid change is targetGone without capture', () {
    platform.s0 = target(pid: _pid + 1);
    expect(rejected(run()), isA<TargetGone>());
    expectNoCaptureNoFrames();
    platform.s0 = target(tid: _tid + 1);
    expect(rejected(run()), isA<TargetGone>());
    platform.s0 = null;
    expect(rejected(run()), isA<TargetGone>());
    expectNoCaptureNoFrames();
  });

  test('stable pre and post return the frame', () {
    final frame = succeeded(run());
    expect(frame.metadata.hwnd, _hwnd);
    expect(frame.metadata.dpi, 96);
    expect(frame.metadata.captured, const CaptureRect(875, 475, 650, 50));
    expect(platform.frames.liveCount, 1);
    frame.release();
  });

  void expectChangedAndReleased(CaptureResult result) {
    expect(rejected(result), isA<TargetChanged>());
    expect(platform.captureCalls, hasLength(1));
    expect(platform.frames.releaseCalls, [1]);
    expect(platform.frames.liveCount, 0);
  }

  test(
    'pre snapshot differing from validated is targetChanged and releases',
    () {
      platform.pre = target(foreground: false);
      expectChangedAndReleased(run());
    },
  );

  test('moved client is targetChanged and releases', () {
    platform.post = target(client: const CaptureRect(40, 0, 1920, 1080));
    expectChangedAndReleased(run());
  });

  test('dpi change is targetChanged and releases', () {
    platform.post = target(dpi: 144);
    expectChangedAndReleased(run());
  });

  test('allZero frame is blankCapture and released', () {
    platform.allZero = true;
    expect(rejected(run()), isA<BlankCapture>());
    expect(platform.captureCalls, hasLength(1));
    expect(platform.frames.releaseCalls, [1]);
    expect(platform.frames.liveCount, 0);
  });

  test('targeted frame reports layout and desktop origin', () {
    final frame = succeeded(run());
    final m = frame.metadata;
    expect(m.width, 650);
    expect(m.height, 50);
    expect(m.stride, greaterThanOrEqualTo(2600));
    expect(m.pixelFormat, CapturePixelFormat.bgrx);
    expect(m.rowOrder, CaptureRowOrder.topDown);
    expect(m.desktopOrigin, (x: 875, y: 475));
    frame.release();
  });

  test('frame carries request id identity and ordered timestamps', () {
    final frame = succeeded(run(t: trigger(qpc: 500), requestId: 42));
    final m = frame.metadata;
    expect(m.requestId, 42);
    expect(m.clipped, isFalse);
    expect(m.hwnd, _hwnd);
    expect(m.pid, _pid);
    expect(m.tid, _tid);
    expect(m.exeName, 'EscapeFromTarkov.exe');
    expect(m.qpcBefore, greaterThanOrEqualTo(500));
    expect(m.qpcAfter, greaterThanOrEqualTo(m.qpcBefore));
    expect(m.capturedAtUtc, DateTime.utc(2026, 10, 8, 12));
    expect(m.capturedAtUtc.isUtc, isTrue);
    frame.release();
  });

  test('clipped frame reports both rectangles', () {
    final frame = succeeded(run(t: trigger(x: 1500, y: 500)));
    final m = frame.metadata;
    expect(m.requested, const CaptureRect(1475, 475, 650, 50));
    expect(m.captured, const CaptureRect(1475, 475, 445, 50));
    expect(m.clipped, isTrue);
    expect(m.width, 445);
    expect(m.height, 50);
    frame.release();
  });

  test('fallback captures the whole client and BE executable is allowed', () {
    platform.exe = 'escapefromtarkov_be.EXE';
    final frame = succeeded(run(mode: CaptureMode.fallback));
    expect(
      platform.captureCalls.single.rect,
      const CaptureRect(0, 0, 1920, 1080),
    );
    expect(frame.metadata.exeName, 'escapefromtarkov_be.EXE');
    frame.release();
  });

  test('native capture failures pass through and hold no frame', () {
    platform.captureError = const RawCaptureError(FrameBudgetExceeded());
    expect(rejected(run()), isA<FrameBudgetExceeded>());
    expect(platform.frames.liveCount, 0);
  });

  test('executable name is cached per hwnd pid tid', () {
    succeeded(run()).release();
    succeeded(run()).release();
    expect(platform.processNameCalls, 1);
    // A different thread id is a different key: re-list.
    platform.s0 = target(tid: _tid + 1);
    succeeded(run(t: trigger(tid: _tid + 1))).release();
    expect(platform.processNameCalls, 2);
    // One entry only: returning to the first key re-lists.
    platform.s0 = target();
    succeeded(run()).release();
    expect(platform.processNameCalls, 3);
  });
}

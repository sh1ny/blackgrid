import 'dart:async';
import 'dart:isolate';

import 'package:blackgrid/data/capture/capture_failure.dart';
import 'package:blackgrid/data/capture/capture_frame.dart';
import 'package:blackgrid/data/capture/capture_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_capture_platform.dart';

CaptureFrameMetadata metadata({int width = 4, int height = 2}) =>
    CaptureFrameMetadata(
      width: width,
      height: height,
      stride: width * 4,
      desktopLeft: -10,
      desktopTop: 20,
      requested: CaptureRect(0, 0, width, height),
      captured: CaptureRect(0, 0, width, height),
      clipped: false,
      clientWidth: 1920,
      clientHeight: 1080,
      dpi: 96,
      hwnd: 1,
      pid: 2,
      tid: 3,
      exeName: 'EscapeFromTarkov.exe',
      qpcBefore: 10,
      qpcAfter: 20,
      capturedAtUtc: DateTime.utc(2026, 10, 8),
      requestId: 7,
    );

CaptureFrame newFrame(FakeFrameRegistry registry) {
  final id = registry.createFrame(4, 2);
  return CaptureFrame(id, metadata(), registry);
}

/// Receiver isolate: adopts the ticket, reports a pixel, waits for the
/// sender to act, then reads again and releases.
void _receiver(List<Object> message) {
  final toMain = message[0] as SendPort;
  final ticket = message[1] as CaptureFrameTicket;
  final registry = FakeFrameRegistry.fromAddress(message[2] as int);
  final frame = CaptureFrame.adopt(ticket, registry);
  final inbox = ReceivePort();
  toMain.send([
    'adopted',
    inbox.sendPort,
    frame.withPixels((p) => p[1]),
    registry.liveCount,
  ]);
  inbox.listen((_) {
    final pixel = frame.withPixels((p) => p[1]);
    frame.release();
    toMain.send(['done', pixel, registry.liveCount, frame.isReleased]);
    inbox.close();
  });
}

void main() {
  test('pixels after release throw frameReleased', () {
    final registry = FakeFrameRegistry.create();
    final frame = newFrame(registry);
    expect(frame.withPixels((p) => p.length), 4 * 2 * 4);
    expect(frame.withPixels((p) => p[0]), 3);
    frame.release();
    final viewCalls = registry.viewCalls;
    expect(
      () => frame.withPixels((p) => p[0]),
      throwsA(isA<FrameReleasedError>()),
    );
    expect(() => frame.handOff(), throwsA(isA<FrameReleasedError>()));
    expect(registry.viewCalls, viewCalls, reason: 'no native access');
    expect(frame.isReleased, isTrue);
  });

  test('release and handOff are refused while pixels are lent', () {
    final registry = FakeFrameRegistry.create();
    final frame = newFrame(registry);
    frame.withPixels((p) {
      expect(frame.release, throwsStateError);
      expect(frame.handOff, throwsStateError);
      // Nested borrows keep the frame lent until the outermost one ends.
      frame.withPixels((inner) => expect(inner[0], 3));
      expect(frame.release, throwsStateError);
      expect(p[0], 3, reason: 'the slot is still live');
    });
    expect(frame.isReleased, isFalse);
    expect(registry.liveCount, 1);
    frame.release();
    expect(registry.liveCount, 0);
  });

  test('a lend ends when the callback throws', () {
    final registry = FakeFrameRegistry.create();
    final frame = newFrame(registry);
    expect(
      () => frame.withPixels<void>((_) => throw const FormatException('x')),
      throwsFormatException,
    );
    frame.release();
    expect(registry.liveCount, 0);
  });

  test('an asynchronous callback is refused before it runs', () {
    final registry = FakeFrameRegistry.create();
    final frame = newFrame(registry);
    final viewCalls = registry.viewCalls;
    var ran = false;
    final callbacks = <Object? Function()>[
      () => frame.withPixels((p) async {
        ran = true;
        await null;
        return p[0];
      }),
      () => frame.withPixels<void>((p) async {
        ran = true;
        await null;
      }),
      () => frame.withPixels<Object?>((p) async => ran = true),
      () => frame.withPixels<Object?>((p) => Future.value(ran = true)),
    ];
    for (final call in callbacks) {
      expect(call, throwsArgumentError);
    }
    expect(ran, isFalse, reason: 'the view never reaches async work');
    expect(registry.viewCalls, viewCalls, reason: 'no native access');
    frame.release();
    expect(registry.liveCount, 0);
  });

  test('second release is a no-op', () {
    final registry = FakeFrameRegistry.create();
    final other = newFrame(registry);
    final frame = newFrame(registry);
    expect(registry.liveCount, 2);
    frame.release();
    expect(registry.liveCount, 1);
    frame.release();
    expect(registry.liveCount, 1);
    expect(registry.releaseCalls, [frame.frameId], reason: 'one native call');
    expect(registry.detached, contains(frame));
    expect(other.isReleased, isFalse);
    other.release();
  });

  test('a new frame attaches a finalizer and exposes its layout', () {
    final registry = FakeFrameRegistry.create();
    final frame = newFrame(registry);
    expect(registry.attached, [frame]);
    expect(frame.metadata.stride, 16);
    expect(frame.metadata.desktopOrigin, (x: -10, y: 20));
    frame.release();
  });

  test('handOff moves ownership across isolates', () async {
    final registry = FakeFrameRegistry.create();
    final frame = newFrame(registry);
    final ticket = frame.handOff();

    // The sender's object is dead and its finalizer is detached.
    expect(frame.isReleased, isTrue);
    expect(registry.detached, contains(frame));
    expect(registry.liveCount, 1, reason: 'hand-off does not free the slot');
    expect(ticket.frameId, frame.frameId);
    expect(ticket.metadata.requestId, 7);

    final fromReceiver = ReceivePort();
    final events = StreamIterator(fromReceiver);
    await Isolate.spawn(_receiver, [
      fromReceiver.sendPort,
      ticket,
      registry.address,
    ]);
    expect(await events.moveNext(), isTrue);
    final adopted = events.current as List;
    expect(adopted[0], 'adopted');
    expect(adopted[2], 10, reason: 'receiver read pixel 1 = 1 * 7 + 3');
    expect(adopted[3], 1);

    // The sender can no longer read, and its release leaves the frame live.
    expect(
      () => frame.withPixels((p) => p[0]),
      throwsA(isA<FrameReleasedError>()),
    );
    frame.release();
    expect(registry.liveCount, 1);
    expect(registry.releaseCalls, isEmpty);

    (adopted[1] as SendPort).send('go');
    expect(await events.moveNext(), isTrue);
    final done = events.current as List;
    expect(done[0], 'done');
    expect(done[1], 10, reason: 'receiver still reads after sender release');
    expect(done[2], 0);
    expect(done[3], isTrue);
    expect(registry.liveCount, 0);
    await events.cancel();
  });

  test('fake registry refuses a frame beyond its capacity', () {
    final registry = FakeFrameRegistry.create();
    for (var i = 0; i < 8; i++) {
      registry.release(registry.createFrame(1, 1));
    }
    // Ids are never reused, so a ninth frame would write past the block.
    expect(() => registry.createFrame(1, 1), throwsStateError);
  });
}

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:blackgrid/domain/settings.dart';

import 'package:blackgrid/data/capture/capture_failure.dart';
import 'package:blackgrid/data/capture/capture_native.dart';
import 'package:blackgrid/data/capture/capture_snapshot.dart';
import 'package:blackgrid/data/capture/capture_target.dart';
import 'package:blackgrid/data/capture/input_trigger_source.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_hook_platform.dart';

TriggerEvent _event(int qpc) => TriggerEvent(
  x: 10,
  y: 20,
  hwnd: 1,
  pid: 2,
  tid: 3,
  qpc: qpc,
  source: TriggerSource.mouse,
);

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  late FakeHookPlatform native;
  late InputTriggerSource source;
  late List<ScanTrigger> received;

  setUp(() {
    native = FakeHookPlatform();
    source = InputTriggerSource(native);
    received = [];
    source.triggers.listen(received.add);
  });

  tearDown(() async {
    await source.dispose();
  });

  test(
    'starts the hook with the target title and drains on a signal',
    () async {
      expect(source.start(), isNull);
      expect(native.startTitles, [captureTargetTitle]);
      native.drains.add(TriggerDrain([_event(1)], 0));
      native.fire();
      await _settle();
      expect(native.drainCalls, 1);
      expect(received, hasLength(1));
      expect(received.single.event.qpc, 1);
      expect(received.single.droppedBefore, 0);
    },
  );

  test('the first event after drops carries the dropped count', () async {
    source.start();
    native.drains.add(TriggerDrain([_event(1), _event(2)], 5));
    native.fire();
    await _settle();
    expect(received.map((t) => t.droppedBefore), [5, 0]);

    // Drops reported with no event wait for the next delivered trigger.
    native.drains.add(const TriggerDrain([], 3));
    native.fire();
    await _settle();
    expect(received, hasLength(2));
    native.drains.add(TriggerDrain([_event(3)], 0));
    native.fire();
    await _settle();
    expect(received.last.droppedBefore, 3);
  });

  test('events without a listener are dropped, not buffered', () async {
    final quiet = FakeHookPlatform();
    final bare = InputTriggerSource(quiet);
    addTearDown(bare.dispose);
    bare.start();
    quiet.drains.add(TriggerDrain([_event(1)], 0));
    quiet.fire();
    await _settle();
    final late = <ScanTrigger>[];
    bare.triggers.listen(late.add);
    await _settle();
    expect(late, isEmpty);
  });

  test('a second start returns alreadyStarted', () {
    expect(source.start(), isNull);
    expect(source.start(), isA<AlreadyStarted>());
    expect(native.stopCalls, 0);
    // The running hook is untouched.
    native.drains.add(TriggerDrain([_event(1)], 0));
    native.fire();
  });

  test('an OS refusal returns unavailable with the win32 code', () {
    native.startResult = const TriggerUnavailable(1428);
    final failure = source.start();
    expect(failure, isA<TriggerUnavailable>());
    expect((failure! as TriggerUnavailable).win32, 1428);
    // Nothing is running, so a later start may succeed.
    native.startResult = null;
    expect(source.start(), isNull);
  });

  test('stop closes the listener and ignores later signals', () async {
    source.start();
    final signalFn = native.signal!.asFunction<void Function()>();
    expect(source.stop(), isNull);
    native.drains.add(TriggerDrain([_event(1)], 0));
    // The callable is closed: calling would be unsafe, so only the source's
    // own state is observable here.
    expect(native.drainCalls, 0);
    expect(received, isEmpty);
    expect(signalFn, isNotNull);
    expect(source.start(), isNull);
  });

  test('stopTimedOut keeps the listener open and blocks restart', () async {
    source.start();
    native.stopResult = const StopTimedOut();
    expect(source.stop(), isA<StopTimedOut>());
    expect(native.guardHeld, isTrue);

    // The callable stays open: a late delivery still reaches the handler
    // without touching freed code, but is not emitted.
    native.drains.add(TriggerDrain([_event(1)], 0));
    native.fire();
    await _settle();
    expect(received, isEmpty);

    expect(source.start(), isA<AlreadyStarted>());
  });

  test('restart succeeds once the stuck hook thread has ended', () {
    source.start();
    native.stopResult = const StopTimedOut();
    expect(source.stop(), isA<StopTimedOut>());
    expect(source.start(), isA<AlreadyStarted>());

    // The stuck thread ends: native stop now succeeds and frees the guard.
    native.stopResult = null;
    expect(source.start(), isNull);
    expect(native.guardHeld, isTrue);
    expect(source.stop(), isNull);
  });

  test('dispose reports a stop timeout and keeps the listener', () async {
    final stuck = InputTriggerSource(native);
    final seen = <ScanTrigger>[];
    stuck.triggers.listen(seen.add);
    expect(stuck.start(), isNull);
    native.stopResult = const StopTimedOut();

    expect(await stuck.dispose(), isA<StopTimedOut>());
    // The listener is still open: a late signal reaches the handler safely
    // and emits nothing.
    native.drains.add(TriggerDrain([_event(1)], 0));
    native.fire();
    await _settle();
    expect(seen, isEmpty);
    native.stopResult = null;
    expect(await stuck.dispose(), isNull);
  });

  test('dispose of a running source reports success', () async {
    expect(source.start(), isNull);
    expect(await source.dispose(), isNull);
    expect(native.guardHeld, isFalse);
  });

  test('a paused listener drops triggers instead of buffering them', () async {
    source.start();
    final paused = <ScanTrigger>[];
    final subscription = source.triggers.listen(paused.add)..pause();
    native.drains.add(TriggerDrain([_event(1), _event(2)], 1));
    native.fire();
    await _settle();
    // The active listener still gets both; the paused one gets nothing.
    expect(received.map((t) => t.event.qpc), [1, 2]);
    subscription.resume();
    await _settle();
    expect(paused, isEmpty, reason: 'no stale trigger replays on resume');

    native.drains.add(TriggerDrain([_event(3)], 0));
    native.fire();
    await _settle();
    expect(paused.single.event.qpc, 3);
    // One native drop plus the two triggers skipped while paused.
    expect(paused.single.droppedBefore, 3);
    expect(received.last.droppedBefore, 0);
  });

  test('dispose does not wait for a paused listener', () async {
    source.start();
    source.triggers.listen((_) {}).pause();
    native.drains.add(TriggerDrain([_event(1)], 0));
    native.fire();
    await _settle();
    expect(await source.dispose().timeout(const Duration(seconds: 1)), isNull);
  });

  test('a listener added after dispose is closed at once', () async {
    await source.dispose();
    var done = false;
    source.triggers.listen((_) {}, onDone: () => done = true);
    await _settle();
    expect(done, isTrue);
  });

  test('drained events carry their trigger source', () async {
    source.start();
    native.drains.add(
      TriggerDrain([
        _event(1),
        const TriggerEvent(
          x: 0,
          y: 0,
          hwnd: 1,
          pid: 2,
          tid: 3,
          qpc: 2,
          source: TriggerSource.hotkey,
        ),
      ], 0),
    );
    native.fire();
    await _settle();
    expect(received.map((t) => t.event.source), [
      TriggerSource.mouse,
      TriggerSource.hotkey,
    ]);
  });

  test('decodeTriggerEvent reads the native source value', () {
    final p = calloc<BgcTriggerEvent>();
    addTearDown(() => calloc.free(p));
    expect(decodeTriggerEvent(p.ref).source, TriggerSource.mouse);
    p.ref.source = 1;
    expect(decodeTriggerEvent(p.ref).source, TriggerSource.hotkey);
  });

  test('BgcTriggerEvent is 40 bytes with source at offset 32', () {
    expect(sizeOf<BgcTriggerEvent>(), 40);
    final p = calloc<BgcTriggerEvent>();
    addTearDown(() => calloc.free(p));
    p.ref
      ..qpc = 0x1122334455667788
      ..source = 1
      ..reserved = 0;
    final bytes = p.cast<Uint8>().asTypedList(40);
    // Little-endian uint32 at offsets 32 and 36.
    expect(bytes.sublist(32, 36), [1, 0, 0, 0]);
    expect(bytes.sublist(36, 40), [0, 0, 0, 0]);
    // qpc stays at offset 24.
    expect(bytes[24], 0x88);
    expect(bytes[31], 0x11);
  });

  group('setHotkey maps every native status to a typed result', () {
    test('a key is applied with its virtual-key code', () async {
      source.start();
      expect(await source.setHotkey(ScanHotkey.f9), isA<HotkeyApplied>());
      expect(native.hotkeyCalls, [0x78]);
    });

    test('off is applied with virtual-key code 0', () async {
      source.start();
      expect(await source.setHotkey(ScanHotkey.off), isA<HotkeyApplied>());
      expect(native.hotkeyCalls, [0]);
    });

    test('a key held by another application is unavailable', () async {
      source.start();
      native.hotkeyResults.add(
        const RawHotkeyStatus(bgcHotkeyUnavailable, 1409),
      );
      final result = await source.setHotkey(ScanHotkey.f1);
      expect(result, isA<HotkeyUnavailable>());
      expect((result as HotkeyUnavailable).win32, 1409);
      expect(native.hotkeyCalls, [0x70]);
    });

    test('a thread that does not answer is timed out', () async {
      source.start();
      native.hotkeyResults.add(const RawHotkeyStatus(bgcHotkeyTimedOut));
      expect(await source.setHotkey(ScanHotkey.f24), isA<HotkeyTimedOut>());
      expect(native.hotkeyCalls, [0x87]);
    });

    test('native not-started maps to notStarted', () async {
      source.start();
      native.hotkeyResults.add(const RawHotkeyStatus(bgcNotStarted));
      expect(await source.setHotkey(ScanHotkey.f2), isA<HotkeyNotStarted>());
    });

    test('native invalid-argument maps to invalidArgument', () async {
      source.start();
      native.hotkeyResults.add(const RawHotkeyStatus(bgcInvalidArgument));
      expect(
        await source.setHotkey(ScanHotkey.f2),
        isA<HotkeyInvalidArgument>(),
      );
    });

    test(
      'a stopped source answers notStarted without calling native',
      () async {
        expect(await source.setHotkey(ScanHotkey.f9), isA<HotkeyNotStarted>());
        expect(native.hotkeyCalls, isEmpty);
      },
    );
  });
}

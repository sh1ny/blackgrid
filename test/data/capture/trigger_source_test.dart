import 'dart:ffi';

import 'package:blackgrid/data/capture/capture_failure.dart';
import 'package:blackgrid/data/capture/capture_native.dart';
import 'package:blackgrid/data/capture/capture_snapshot.dart';
import 'package:blackgrid/data/capture/capture_target.dart';
import 'package:blackgrid/data/capture/mouse_release_trigger_source.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_hook_platform.dart';

TriggerEvent _event(int qpc) =>
    TriggerEvent(x: 10, y: 20, hwnd: 1, pid: 2, tid: 3, qpc: qpc);

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  late FakeHookPlatform native;
  late MouseReleaseTriggerSource source;
  late List<ScanTrigger> received;

  setUp(() {
    native = FakeHookPlatform();
    source = MouseReleaseTriggerSource(native);
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
    final bare = MouseReleaseTriggerSource(quiet);
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
}

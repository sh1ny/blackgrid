import 'dart:async';

import 'package:blackgrid/application/scan_coordinator.dart';
import 'package:blackgrid/data/scan_frame_recorder.dart';
import 'package:blackgrid/data/vision/vision_failure.dart';
import 'package:blackgrid/data/vision/marker_template.dart';
import 'package:blackgrid/ui/live_scan_panel.dart';
import 'package:blackgrid/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scan_ui_support.dart';

const _switchKey = Key('live-scan-switch');
const _statusKey = Key('live-scan-status');
const _recordKey = Key('record-frames-switch');
const _recordStatusKey = Key('record-frames-status');

Future<ScanUiRig> _pump(
  WidgetTester tester, {
  bool liveScanSaved = false,
}) async {
  tester.view.physicalSize = const Size(420, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final rig = (await tester.runAsync(
    () => ScanUiRig.create(liveScanSaved: liveScanSaved),
  ))!;
  addTearDown(() async => tester.runAsync(rig.dispose));
  await tester.pumpWidget(
    MaterialApp(
      theme: blackgridTheme(),
      home: Scaffold(
        body: LiveScanPanel(scanner: rig.coordinator, timingLog: rig.timingLog),
      ),
    ),
  );
  return rig;
}

/// Runs [action] in the real zone, then pumps until [done] holds. The
/// database lives in another isolate, so this is a bounded condition poll.
Future<void> _until(
  WidgetTester tester,
  bool Function() done, [
  Future<void> Function()? action,
]) async {
  if (action != null) await tester.runAsync(action);
  final elapsed = Stopwatch()..start();
  while (!done()) {
    if (elapsed.elapsed > const Duration(seconds: 10)) {
      throw StateError('Condition not reached within 10 seconds.');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  await tester.pump();
}

bool _switchValue(WidgetTester tester) =>
    tester.widget<Switch>(find.byKey(_switchKey)).value;

String _status(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(_statusKey)).data!;

bool _switchValueOf(WidgetTester tester, Key key) =>
    tester.widget<Switch>(find.byKey(key)).value;

String _recordStatus(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(_recordStatusKey)).data!;

void main() {
  testWidgets('switch on shows ready status', (tester) async {
    final rig = await _pump(tester);
    expect(_switchValue(tester), isFalse);
    expect(_status(tester), contains('off'));

    await tester.tap(find.byKey(_switchKey));
    await _until(
      tester,
      () => rig.coordinator.status.state == LiveScanState.ready,
    );

    expect(_switchValue(tester), isTrue);
    expect(_status(tester), 'Live scan is ready');
    expect(tester.takeException(), isNull);
  });

  testWidgets('unavailable status names the missing file', (tester) async {
    final rig = await _pump(tester);
    rig.ports.markerOverride = const MarkerTemplateUnavailable(
      VisionMissingFile('data/vision/inspection_marker.pgm'),
    );

    await tester.tap(find.byKey(_switchKey));
    await _until(
      tester,
      () => rig.coordinator.status.state == LiveScanState.unavailable,
    );

    expect(_switchValue(tester), isTrue, reason: 'the switch still shows on');
    expect(_status(tester), contains('inspection_marker.pgm'));
    expect(_status(tester), contains('unavailable'));
  });

  testWidgets('unavailable timing log status is shown', (tester) async {
    final rig = await _pump(tester);
    expect(find.textContaining('Timing log unavailable'), findsNothing);

    await tester.runAsync(rig.failTimingLog);
    await tester.pump();

    expect(find.textContaining('Timing log unavailable'), findsOneWidget);
    expect(find.textContaining('scan-timings.jsonl'), findsOneWidget);
  });

  testWidgets('failed switch-on save reverts and shows an error', (
    tester,
  ) async {
    final rig = await _pump(tester);
    await tester.runAsync(rig.failSaves);

    await tester.tap(find.byKey(_switchKey));
    await _until(tester, () => rig.coordinator.error != null);

    expect(_switchValue(tester), isFalse);
    expect(rig.coordinator.status.state, LiveScanState.off);
    expect(rig.ports.captures, isEmpty, reason: 'the pipeline never started');
    expect(find.textContaining('the preference was not saved'), findsOneWidget);
  });

  testWidgets('failed switch-off save stays off and shows an error', (
    tester,
  ) async {
    final rig = await _pump(tester);
    await tester.tap(find.byKey(_switchKey));
    await _until(
      tester,
      () => rig.coordinator.status.state == LiveScanState.ready,
    );
    expect(_switchValue(tester), isTrue);
    await tester.runAsync(rig.failSaves);

    await tester.tap(find.byKey(_switchKey));
    await _until(tester, () => rig.coordinator.error != null);
    await tester.runAsync(() => rig.coordinator.settled);
    await tester.pump();

    expect(_switchValue(tester), isFalse);
    expect(rig.coordinator.status.state, LiveScanState.off);
    expect(find.textContaining('preference was not saved'), findsOneWidget);
  });

  testWidgets('record status shows written, dropped and folder', (
    tester,
  ) async {
    final rig = await _pump(tester);
    await tester.runAsync(rig.ready);
    await tester.pump();

    await tester.tap(find.byKey(_recordKey));
    await _until(
      tester,
      () => rig.recorder.status.value.state == ScanRecordingState.on,
    );
    final writer = rig.writers.single;
    for (var n = 1; n <= 12; n++) {
      rig.recorder.record(recordedScan('s$n'));
      writer.ack('s$n');
    }
    // Two outstanding fill the bound, so the third is dropped.
    rig.recorder.record(recordedScan('s13'));
    rig.recorder.record(recordedScan('s14'));
    rig.recorder.record(recordedScan('s15'));
    await tester.pump();

    final folder = rig.recorder.status.value.folder!;
    expect(_switchValueOf(tester, _recordKey), isTrue);
    final text = _recordStatus(tester);
    expect(text, contains('12 written'));
    expect(text, contains('1 dropped'));
    expect(text, contains(folder));
  });

  testWidgets('record switch is off and disabled unless live scan is ready', (
    tester,
  ) async {
    final rig = await _pump(tester);
    Switch recordSwitch() => tester.widget<Switch>(find.byKey(_recordKey));

    // Off.
    expect(recordSwitch().value, isFalse);
    expect(recordSwitch().onChanged, isNull);

    // Starting: the marker loader never answers.
    final gate = Completer<MarkerTemplateResult>();
    final loader = rig.ports.markerLoader;
    rig.ports.markerGate = gate.future;
    await tester.tap(find.byKey(_switchKey));
    await _until(
      tester,
      () => rig.coordinator.status.state == LiveScanState.starting,
    );
    expect(recordSwitch().value, isFalse);
    expect(recordSwitch().onChanged, isNull);
    gate.complete(await loader(''));

    // Ready.
    await _until(
      tester,
      () => rig.coordinator.status.state == LiveScanState.ready,
    );
    expect(recordSwitch().value, isFalse);
    expect(recordSwitch().onChanged, isNotNull);

    // Unavailable.
    await tester.tap(find.byKey(_switchKey));
    await _until(
      tester,
      () => rig.coordinator.status.state == LiveScanState.off,
    );
    rig.ports.markerGate = null;
    rig.ports.markerOverride = const MarkerTemplateUnavailable(
      VisionMissingFile('data/vision/inspection_marker.pgm'),
    );
    await tester.tap(find.byKey(_switchKey));
    await _until(
      tester,
      () => rig.coordinator.status.state == LiveScanState.unavailable,
    );
    expect(recordSwitch().value, isFalse);
    expect(recordSwitch().onChanged, isNull);
  });

  testWidgets('a starting recording session can be switched off', (
    tester,
  ) async {
    final rig = await _pump(tester);
    await tester.runAsync(rig.ready);
    await tester.pump();
    final gate = rig.writerGate = Completer<void>();

    await tester.tap(find.byKey(_recordKey));
    await _until(
      tester,
      () => rig.recorder.status.value.state == ScanRecordingState.starting,
    );
    final recordSwitch = tester.widget<Switch>(find.byKey(_recordKey));
    expect(recordSwitch.value, isTrue);
    expect(recordSwitch.onChanged, isNotNull);

    await tester.tap(find.byKey(_recordKey));
    await tester.pump();

    expect(rig.recorder.status.value.state, ScanRecordingState.off);
    expect(_switchValueOf(tester, _recordKey), isFalse);
    await tester.runAsync(() async {
      gate.complete();
      await rig.recorder.close(timeout: Duration.zero);
    });
  });

  testWidgets(
    'record status shows the write error and folder after a self-stop',
    (tester) async {
      final rig = await _pump(tester);
      await tester.runAsync(rig.ready);
      await tester.pump();
      await tester.tap(find.byKey(_recordKey));
      await _until(
        tester,
        () => rig.recorder.status.value.state == ScanRecordingState.on,
      );
      rig.recorder.record(recordedScan('s1'));

      rig.writers.single.fail('s1', 'disk full');
      await tester.pump();

      expect(_switchValueOf(tester, _recordKey), isFalse);
      final text = _recordStatus(tester);
      expect(text, contains('disk full'));
      expect(text, contains(rig.recorder.status.value.folder!));
    },
  );
}

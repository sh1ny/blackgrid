import 'package:blackgrid/application/scan_coordinator.dart';
import 'package:blackgrid/data/vision/vision_failure.dart';
import 'package:blackgrid/data/vision/marker_template.dart';
import 'package:blackgrid/ui/live_scan_panel.dart';
import 'package:blackgrid/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scan_ui_support.dart';

const _switchKey = Key('live-scan-switch');
const _statusKey = Key('live-scan-status');

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
}

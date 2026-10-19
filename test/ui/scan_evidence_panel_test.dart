import 'package:blackgrid/application/scan_coordinator.dart';
import 'package:blackgrid/data/capture/capture_failure.dart';
import 'package:blackgrid/data/capture/capture_snapshot.dart';
import 'package:blackgrid/data/vision/inspection_evidence.dart';
import 'package:blackgrid/domain/title_matching.dart';
import 'package:blackgrid/ui/scan_evidence_panel.dart';
import 'package:blackgrid/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scan_ui_support.dart';

/// Ticks per millisecond of the fake clock (10 MHz).
const _msTicks = 10000;

Future<ScanUiRig> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(340, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final rig = (await tester.runAsync(ScanUiRig.create))!;
  addTearDown(() async => tester.runAsync(rig.dispose));
  await tester.runAsync(rig.ready);
  await tester.pumpWidget(
    MaterialApp(
      theme: blackgridTheme(),
      home: Scaffold(
        body: ScanEvidencePanel(scanner: rig.coordinator, catalog: rig.catalog),
      ),
    ),
  );
  return rig;
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

/// Pumps until the crop has been decoded by the engine. The decode runs off
/// the test zone, so this is a bounded poll on that single signal.
Future<void> _untilCrop(WidgetTester tester) async {
  final elapsed = Stopwatch()..start();
  while (find.byKey(const Key('scan-crop-image')).evaluate().isEmpty) {
    if (elapsed.elapsed > const Duration(seconds: 10)) {
      throw StateError('The crop was not decoded within 10 seconds.');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
}

/// Drives one targeted scan to an accepted result with stage stamps.
Future<void> _accept(
  WidgetTester tester,
  ScanUiRig rig, {
  int index = 0,
  int trigger = 1000,
  int captureMs = 40,
  int visionMs = 90,
  int publishMs = 180,
}) async {
  await tester.runAsync(() async {
    final ports = rig.ports;
    ports.fire(trigger);
    await ports.captureOk(index, at: trigger + captureMs * _msTicks);
    final evidence = scanEvidence();
    await ports.visionDeliver(
      index,
      scanRecognised(InspectionFrameKind.targeted, [evidence]),
      at: trigger + visionMs * _msTicks,
    );
    final call = await rig.matcher.calls.at(index);
    ports.clock.now = trigger + publishMs * _msTicks;
    call.complete(scanAccepted(evidence));
    await reportPublished(rig.coordinator, index + 1);
  });
  await tester.pump();
}

/// Drives scan [index] + 1 to a `belowSimilarity` rejection over both passes.
/// Its evidence has no crop, so a crop on screen can only be the accepted one.
Future<void> _reject(
  WidgetTester tester,
  ScanUiRig rig, {
  required int index,
  int trigger = 5000000,
  String text = 'FILTERBYITEM',
}) async {
  await tester.runAsync(() async {
    final ports = rig.ports;
    ports.fire(trigger);
    await ports.captureOk(index * 2 - 1, at: trigger + 30 * _msTicks);
    final first = scanEvidence(text: text, score: 0.88, withCrop: false);
    await ports.visionDeliver(
      index,
      scanRecognised(InspectionFrameKind.targeted, [first]),
      at: trigger + 60 * _msTicks,
    );
    (await rig.matcher.calls.at(index)).complete(scanBelowSimilarity(first));
    await ports.captureOk(index * 2, at: trigger + 70 * _msTicks);
    final second = scanEvidence(text: text, score: 0.88, withCrop: false);
    await ports.visionDeliver(
      index + 1,
      scanRecognised(InspectionFrameKind.fullClient, [second]),
      at: trigger + 90 * _msTicks,
    );
    rig.ports.clock.now = trigger + 120 * _msTicks;
    (await rig.matcher.calls.at(index + 1))
        .complete(scanBelowSimilarity(second));
    await reportPublished(rig.coordinator, 2);
  });
  await tester.pump();
}

void main() {
  testWidgets('fallback phase shows fallback underway', (tester) async {
    final rig = await _pump(tester);
    expect(find.byKey(const Key('scan-phase')), findsNothing);

    await tester.runAsync(() async {
      rig.ports.fire(1000);
      await rig.ports.captureOk(0);
    });
    await tester.pump();
    expect(_text(tester, 'scan-phase'), 'Scan running: targeted');
    expect(find.text('Fallback underway'), findsNothing);

    await tester.runAsync(() async {
      await rig.ports.visionDeliver(
        0,
        scanRecognised(InspectionFrameKind.targeted, []),
      );
      (await rig.matcher.calls.at(0)).complete(
        const OutcomeRejected<InspectionEvidence>(OutcomeRejectReason.noMarker),
      );
      await rig.ports.capture.calls.at(1);
    });
    await tester.pump();

    expect(_text(tester, 'scan-phase'), 'Fallback underway');
    expect(find.text('No scan published yet'), findsOneWidget);
  });

  testWidgets('superseded scan shows only the newer phase', (tester) async {
    final rig = await _pump(tester);
    await tester.runAsync(() async {
      rig.ports.fire(1000);
      await rig.ports.captureOk(0);
      await rig.ports.visionDeliver(
        0,
        scanRecognised(InspectionFrameKind.targeted, []),
      );
      (await rig.matcher.calls.at(0)).complete(
        const OutcomeRejected<InspectionEvidence>(OutcomeRejectReason.noMarker),
      );
      final fallback = await rig.ports.capture.calls.at(1);
      rig.ports.fire(2000);
      fallback.succeed(rig.ports.frames.frame());
      await rig.ports.capture.calls.at(2);
    });
    await tester.pump();

    expect(rig.coordinator.phase, ScanPhase.targeted);
    expect(_text(tester, 'scan-phase'), 'Scan running: targeted');
    expect(find.text('Fallback underway'), findsNothing);
    expect(rig.coordinator.latest, isNull);
    expect(find.text('No scan published yet'), findsOneWidget);
    expect(find.byKey(const Key('scan-end')), findsNothing);
  });

  testWidgets('accepted report shows item, pass, score, crop and text', (
    tester,
  ) async {
    final rig = await _pump(tester);
    await _accept(tester, rig);
    await _untilCrop(tester);

    expect(find.byKey(const Key('scan-phase')), findsNothing);
    expect(_text(tester, 'scan-end'), 'Accepted');
    expect(_text(tester, 'scan-item'), contains(scanItemName));
    expect(_text(tester, 'scan-item'), contains(scanItemId));
    expect(_text(tester, 'scan-pass'), 'Pass: targeted');
    expect(_text(tester, 'scan-marker'), contains('0.93'));
    expect(_text(tester, 'scan-text'), contains(scanItemName));
    final crop = tester.widget<RawImage>(
      find.byKey(const Key('scan-crop-image')),
    );
    expect((crop.image!.width, crop.image!.height), (4, 4));
    expect(_text(tester, 'scan-best'), contains('0.97'));
    expect(_text(tester, 'scan-runner-up'), contains('0.31'));
    expect(_text(tester, 'scan-margin'), contains('0.66'));
    expect(find.byKey(const Key('scan-reason')), findsNothing);
  });

  testWidgets('rejected report labels best candidate not accepted', (
    tester,
  ) async {
    final rig = await _pump(tester);
    await tester.runAsync(() async {
      final ports = rig.ports;
      ports.fire(1000);
      await ports.captureOk(0);
      final first = scanEvidence(text: 'Rejected Candidat');
      await ports.visionDeliver(
        0,
        scanRecognised(InspectionFrameKind.targeted, [first]),
      );
      (await rig.matcher.calls.at(0)).complete(scanBelowSimilarity(first));
      await ports.captureOk(1);
      final second = scanEvidence(text: 'Rejected Candidat', base: 100);
      await ports.visionDeliver(
        1,
        scanRecognised(InspectionFrameKind.fullClient, [second]),
      );
      (await rig.matcher.calls.at(1)).complete(scanBelowSimilarity(second));
      await reportPublished(rig.coordinator, 1);
    });
    await tester.pump();
    await _untilCrop(tester);

    expect(_text(tester, 'scan-end'), 'Rejected');
    expect(_text(tester, 'scan-reason'), 'Reason: belowSimilarity');
    final best = _text(tester, 'scan-best');
    expect(best, contains('not accepted'));
    expect(best, contains(scanOtherName));
    expect(best, contains('0.41'));
    expect(find.byKey(const Key('scan-item')), findsNothing);
    expect(find.textContaining('Accepted'), findsNothing);
  });

  testWidgets('noMarker report shows the best marker score without an entry', (
    tester,
  ) async {
    final rig = await _pump(tester);
    await tester.runAsync(() async {
      final ports = rig.ports;
      ports.fire(1000);
      await ports.captureOk(0);
      await ports.visionDeliver(
        0,
        scanRecognised(InspectionFrameKind.targeted, []),
      );
      (await rig.matcher.calls.at(0)).complete(
        const OutcomeRejected<InspectionEvidence>(OutcomeRejectReason.noMarker),
      );
      await ports.captureOk(1);
      await ports.visionDeliver(
        1,
        scanRecognised(InspectionFrameKind.fullClient, []),
      );
      (await rig.matcher.calls.at(1)).complete(
        const OutcomeRejected<InspectionEvidence>(OutcomeRejectReason.noMarker),
      );
      await reportPublished(rig.coordinator, 1);
    });
    await tester.pump();

    expect(_text(tester, 'scan-reason'), 'Reason: noMarker');
    expect(_text(tester, 'scan-marker'), contains('0.20'));
    expect(_text(tester, 'scan-crop-placeholder'), 'No title crop');
    expect(_text(tester, 'scan-text'), contains('(none)'));
    expect(find.byKey(const Key('scan-crop-image')), findsNothing);
  });

  testWidgets('failed report shows failure and no candidate', (tester) async {
    final rig = await _pump(tester);
    await tester.runAsync(() async {
      rig.ports.fire(1000);
      await rig.ports.captureOk(0);
      await rig.ports.visionTimeout(0);
      await reportPublished(rig.coordinator, 1);
    });
    await tester.pump();

    expect(_text(tester, 'scan-end'), 'Failed');
    expect(_text(tester, 'scan-reason'), 'Failure: visionTimeout');
    expect(find.byKey(const Key('scan-best')), findsNothing);
    expect(find.byKey(const Key('scan-item')), findsNothing);
    expect(find.text('No candidate'), findsOneWidget);
  });

  testWidgets('rejection after an accepted item keeps it and shows a note', (
    tester,
  ) async {
    final rig = await _pump(tester);
    await _accept(tester, rig);
    await _reject(tester, rig, index: 1);

    expect(_text(tester, 'scan-end'), 'Accepted');
    expect(_text(tester, 'scan-item'), contains(scanItemName));
    expect(find.text('Last scan not accepted'), findsOneWidget);
    expect(_text(tester, 'scan-note-reason'), contains('belowSimilarity'));
    expect(_text(tester, 'scan-note-text'), contains('FILTERBYITEM'));
    expect(_text(tester, 'scan-note-marker'), contains('0.88'));
    final best = _text(tester, 'scan-note-best');
    expect(best, contains('not accepted'));
    expect(best, contains(scanOtherName));
    expect(
      tester.getTopLeft(find.text('Last scan not accepted')).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('scan-end'))).dy),
    );
  });

  testWidgets("after a rejection the crop is the accepted scan's and "
      "timings are the latest's", (tester) async {
    final rig = await _pump(tester);
    await _accept(tester, rig);
    await _reject(tester, rig, index: 1);
    await _untilCrop(tester);

    final crop = tester.widget<RawImage>(
      find.byKey(const Key('scan-crop-image')),
    );
    expect((crop.image!.width, crop.image!.height), (4, 4));
    expect(_text(tester, 'scan-timings-label'), contains('Scan #2'));
    expect(_text(tester, 'scan-timing-total'), 'Total 120 ms');
    expect(find.text('Scan #1'), findsOneWidget);
  });

  testWidgets('failure after an accepted item shows a failure note', (
    tester,
  ) async {
    final rig = await _pump(tester);
    await _accept(tester, rig);
    await tester.runAsync(() async {
      rig.ports.fire(5000000);
      (await rig.ports.capture.calls.at(1)).fail(const TargetNotForeground());
      await reportPublished(rig.coordinator, 2);
    });
    await tester.pump();

    expect(_text(tester, 'scan-end'), 'Accepted');
    expect(_text(tester, 'scan-item'), contains(scanItemName));
    expect(find.text('Last scan not accepted'), findsOneWidget);
    expect(_text(tester, 'scan-note-reason'), contains('targetNotForeground'));
    expect(find.byKey(const Key('scan-note-best')), findsNothing);
  });

  testWidgets('a newer acceptance removes the note', (tester) async {
    final rig = await _pump(tester);
    await _accept(tester, rig);
    await _reject(tester, rig, index: 1);
    expect(find.text('Last scan not accepted'), findsOneWidget);

    await tester.runAsync(() async {
      final ports = rig.ports;
      ports.fire(9000000);
      await ports.captureOk(3, at: 9000000 + 40 * _msTicks);
      final evidence = scanEvidence();
      await ports.visionDeliver(
        3,
        scanRecognised(InspectionFrameKind.targeted, [evidence]),
        at: 9000000 + 90 * _msTicks,
      );
      (await rig.matcher.calls.at(3)).complete(scanAccepted(evidence));
      await reportPublished(rig.coordinator, 3);
    });
    await tester.pump();

    expect(find.text('Last scan not accepted'), findsNothing);
    expect(find.byKey(const Key('scan-note-reason')), findsNothing);
    expect(find.text('Scan #3'), findsOneWidget);
    expect(_text(tester, 'scan-end'), 'Accepted');
  });

  testWidgets('timings show stage and total ms', (tester) async {
    final rig = await _pump(tester);
    await _accept(tester, rig, captureMs: 40, publishMs: 180);

    expect(_text(tester, 'scan-timing-targeted-capture'), 'Capture 40 ms');
    expect(_text(tester, 'scan-timing-targeted-vision'), 'Vision 90 ms');
    expect(_text(tester, 'scan-timing-targeted-matching'), 'Matching 180 ms');
    expect(_text(tester, 'scan-timing-total'), 'Total 180 ms');
  });

  testWidgets('absent stages are shown as absent, not 0', (tester) async {
    final rig = await _pump(tester);
    await tester.runAsync(() async {
      rig.ports.fire(1000);
      (await rig.ports.capture.calls.at(0)).fail(const TargetNotForeground());
      await reportPublished(rig.coordinator, 1);
    });
    await tester.pump();

    expect(_text(tester, 'scan-timing-targeted-vision'), 'Vision absent');
    expect(_text(tester, 'scan-timing-targeted-matching'), 'Matching absent');
    expect(find.text('Vision 0 ms'), findsNothing);
    expect(find.text('Matching 0 ms'), findsNothing);
    expect(find.byKey(const Key('scan-timing-fallback-capture')), findsNothing);
  });

  testWidgets('recent list shows the 10 newest scans, newest first', (
    tester,
  ) async {
    final rig = await _pump(tester);
    for (var i = 0; i < 11; i++) {
      await _accept(tester, rig, index: i, trigger: 1000 + i * 1000000);
    }

    for (var id = 2; id <= 11; id++) {
      expect(find.byKey(Key('scan-recent-$id')), findsOneWidget);
    }
    expect(find.byKey(const Key('scan-recent-1')), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(const Key('scan-recent-11'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('scan-recent-10'))).dy),
    );
    final row = _text(tester, 'scan-recent-11');
    expect(row, contains('Accepted'));
    expect(row, contains(scanItemName));
    expect(row, contains('180 ms'));
  });

  testWidgets('recent list labels hotkey scans', (tester) async {
    final rig = await _pump(tester);
    await tester.runAsync(() async {
      final ports = rig.ports;
      for (final (index, source) in [
        TriggerSource.hotkey,
        TriggerSource.mouse,
      ].indexed) {
        ports.fire(1000 + index * 1000, source: source);
        await ports.captureOk(index);
        final evidence = scanEvidence();
        await ports.visionDeliver(
          index,
          scanRecognised(InspectionFrameKind.targeted, [evidence]),
        );
        (await rig.matcher.calls.at(index)).complete(scanAccepted(evidence));
        await reportPublished(rig.coordinator, index + 1);
      }
    });
    await tester.pump();

    expect(_text(tester, 'scan-recent-1'), contains('hotkey'));
    expect(_text(tester, 'scan-recent-2'), isNot(contains('hotkey')));
  });
}

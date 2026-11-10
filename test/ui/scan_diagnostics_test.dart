import 'package:blackgrid/application/scan_coordinator.dart';
import 'package:blackgrid/data/capture/capture_failure.dart';
import 'package:blackgrid/data/capture/capture_snapshot.dart';
import 'package:blackgrid/data/vision/inspection_evidence.dart';
import 'package:blackgrid/domain/title_matching.dart';
import 'package:blackgrid/ui/ember/ember_theme.dart';
import 'package:blackgrid/ui/labels.dart';
import 'package:blackgrid/ui/scan_evidence_panel.dart';
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
      theme: blackgridTheme(Brightness.dark),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ScanDiagnostics(
            scanner: rig.coordinator,
            catalog: rig.catalog,
          ),
        ),
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
  String id = scanItemId,
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
    call.complete(scanAccepted(evidence, id: id));
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
  testWidgets(
    'accepted scan shows number, item id, pass, score, crop and text',
    (tester) async {
      final rig = await _pump(tester);
      await _accept(tester, rig);
      await _untilCrop(tester);

      expect(find.text('Scan #1'), findsOneWidget);
      expect(_text(tester, 'scan-end'), 'Accepted');
      expect(_text(tester, 'scan-item-id'), contains(scanItemId));
      expect(
        _text(tester, 'scan-pass'),
        contains(scanPassLabel(ScanPass.targeted)),
      );
      expect(_text(tester, 'scan-marker'), contains('0.93'));
      expect(_text(tester, 'scan-text'), contains(scanItemName));
      final crop = tester.widget<RawImage>(
        find.byKey(const Key('scan-crop-image')),
      );
      expect((crop.image!.width, crop.image!.height), (4, 4));
      expect(_text(tester, 'scan-best'), contains('0.97'));
      expect(_text(tester, 'scan-runner-up'), contains('0.31'));
      expect(_text(tester, 'scan-margin'), contains('0.66'));
      expect(find.byKey(const Key('scan-reason-code')), findsNothing);
    },
  );

  testWidgets('a later rejection shows its code and text and keeps the '
      'accepted crop', (tester) async {
    final rig = await _pump(tester);
    await _accept(tester, rig);
    await _reject(tester, rig, index: 1);
    await _untilCrop(tester);

    expect(_text(tester, 'scan-note-code'), contains('belowSimilarity'));
    expect(_text(tester, 'scan-note-text'), contains('FILTERBYITEM'));
    expect(_text(tester, 'scan-note-marker'), contains('0.88'));
    expect(find.text('Scan #1'), findsOneWidget);
    final crop = tester.widget<RawImage>(
      find.byKey(const Key('scan-crop-image')),
    );
    expect((crop.image!.width, crop.image!.height), (4, 4));
  });

  testWidgets('a failed scan shows its code and message and no crop', (
    tester,
  ) async {
    final rig = await _pump(tester);
    await tester.runAsync(() async {
      rig.ports.fire(1000);
      await rig.ports.captureOk(0);
      await rig.ports.visionTimeout(0);
      await reportPublished(rig.coordinator, 1);
    });
    await tester.pump();

    expect(_text(tester, 'scan-end'), 'Failed');
    expect(_text(tester, 'scan-reason-code'), contains('visionTimeout'));
    expect(find.byKey(const Key('scan-failure-message')), findsOneWidget);
    expect(find.byKey(const Key('scan-crop-image')), findsNothing);
  });

  testWidgets(
    'before any scan it says none is published and shows no timings',
    (tester) async {
      await _pump(tester);

      expect(find.text('No scan published yet'), findsOneWidget);
      expect(find.byKey(const Key('scan-timings-label')), findsNothing);
      expect(find.byKey(const Key('scan-timing-total')), findsNothing);
      expect(find.textContaining(' ms'), findsNothing);
      expect(find.byKey(const Key('scan-crop-image')), findsNothing);
    },
  );

  testWidgets('timings show stage and total ms labelled with the scan number', (
    tester,
  ) async {
    final rig = await _pump(tester);
    await _accept(tester, rig, captureMs: 40, publishMs: 180);

    expect(_text(tester, 'scan-timings-label'), contains('Scan #1'));
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

  testWidgets("after a rejection the timings are the new scan's", (
    tester,
  ) async {
    final rig = await _pump(tester);
    await _accept(tester, rig);
    await _reject(tester, rig, index: 1);

    expect(_text(tester, 'scan-timings-label'), contains('Scan #2'));
    expect(_text(tester, 'scan-timing-total'), 'Total 120 ms');
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
    expect(_text(tester, 'scan-recent-11'), contains(scanItemName));
    final row = _text(tester, 'scan-recent-detail-11');
    expect(row, contains('Accepted'));
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

  testWidgets(
    'a rejected recent entry gives a plain reason and its end state',
    (tester) async {
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
          const OutcomeRejected<InspectionEvidence>(
            OutcomeRejectReason.noMarker,
          ),
        );
        await ports.captureOk(1);
        await ports.visionDeliver(
          1,
          scanRecognised(InspectionFrameKind.fullClient, []),
        );
        (await rig.matcher.calls.at(1)).complete(
          const OutcomeRejected<InspectionEvidence>(
            OutcomeRejectReason.noMarker,
          ),
        );
        await reportPublished(rig.coordinator, 1);
      });
      await tester.pump();

      final plain = _text(tester, 'scan-recent-1');
      expect(plain, contains(scanRejectReasonLabel(ScanRejectReason.noMarker)));
      expect(plain, isNot(contains('noMarker')));
      expect(_text(tester, 'scan-recent-detail-1'), contains('Rejected'));
    },
  );

  testWidgets('an empty recent list says there are no scans yet', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('No scans yet'), findsOneWidget);
    expect(find.byKey(const Key('scan-recent-1')), findsNothing);
  });
}

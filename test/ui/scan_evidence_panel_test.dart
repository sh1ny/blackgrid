import 'package:blackgrid/application/scan_coordinator.dart';
import 'package:blackgrid/data/capture/capture_failure.dart';
import 'package:blackgrid/data/vision/inspection_evidence.dart';
import 'package:blackgrid/domain/title_matching.dart';
import 'package:blackgrid/ui/labels.dart';
import 'package:blackgrid/ui/scan_evidence_panel.dart';
import 'package:blackgrid/ui/scanner_sections.dart';
import 'package:blackgrid/ui/ember/ember_theme.dart';
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
          child: ScanEvidenceSection(
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

/// Whether [word] appears in any text on screen, ignoring case.
bool _anyTextHas(WidgetTester tester, String word) => tester
    .widgetList<Text>(find.byType(Text))
    .any((t) => (t.data ?? '').toLowerCase().contains(word.toLowerCase()));

/// Expects none of the evidence that Diagnostics keeps: no ID, pass, score,
/// crop, OCR text, code, timing, recent list or Details control.
void _expectNoDiagnostics() {
  for (final key in [
    'scan-end',
    'scan-pass',
    'scan-marker',
    'scan-text',
    'scan-best',
    'scan-runner-up',
    'scan-margin',
    'scan-item-id',
    'scan-crop-image',
    'scan-crop-placeholder',
    'scan-reason-code',
    'scan-failure-message',
    'scan-fallback-failure',
    'scan-note-code',
    'scan-note-text',
    'scan-note-marker',
    'scan-timings-label',
    'scan-timing-total',
    'scan-recent-1',
    'scan-recent-detail-1',
    'scan-recent-none',
  ]) {
    expect(find.byKey(Key(key)), findsNothing, reason: key);
  }
  expect(find.text('Details'), findsNothing);
  expect(find.text('Recent scans'), findsNothing);
  expect(find.byType(RawImage), findsNothing);
  expect(find.textContaining(' ms'), findsNothing);
  expect(find.textContaining('Marker score'), findsNothing);
  expect(find.textContaining('OCR text'), findsNothing);
  expect(find.textContaining('Code:'), findsNothing);
  expect(find.textContaining('Item ID'), findsNothing);
  expect(find.textContaining('Pass:'), findsNothing);
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
  testWidgets('fallback phase says it is trying a wider scan', (tester) async {
    final rig = await _pump(tester);
    expect(find.byKey(const Key('scan-phase')), findsNothing);

    await tester.runAsync(() async {
      rig.ports.fire(1000);
      await rig.ports.captureOk(0);
    });
    await tester.pump();
    expect(_text(tester, 'scan-phase'), 'Reading the item…');
    expect(_anyTextHas(tester, 'targeted'), isFalse);

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

    expect(_text(tester, 'scan-phase'), 'Trying a wider scan…');
    expect(_anyTextHas(tester, 'fallback'), isFalse);
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
    expect(_text(tester, 'scan-phase'), 'Reading the item…');
    expect(find.text('Trying a wider scan…'), findsNothing);
    expect(rig.coordinator.latest, isNull);
    expect(find.text('No scan published yet'), findsOneWidget);
    expect(find.byKey(const Key('scan-end')), findsNothing);
  });

  testWidgets('subtitle avoids internal vocabulary', (tester) async {
    await _pump(tester);
    final panel = tester.widget<ScannerSection>(find.byType(ScannerSection));
    final subtitle = panel.subtitle.toLowerCase();
    for (final banned in [
      'canonical',
      'identity',
      'durable',
      'dpapi',
      'authority',
      'authorized',
      'normalized',
      'm1',
      'gross rub',
      'session-only',
    ]) {
      expect(subtitle, isNot(contains(banned)));
    }
  });

  testWidgets('before any scan it says none is published', (tester) async {
    await _pump(tester);

    expect(find.text('No scan published yet'), findsOneWidget);
    expect(find.byKey(const Key('scan-item')), findsNothing);
    expect(find.byKey(const Key('scan-phase')), findsNothing);
    expect(find.text('None yet'), findsNothing);
    _expectNoDiagnostics();
  });

  testWidgets('accepted report shows only the item name', (tester) async {
    final rig = await _pump(tester);
    await _accept(tester, rig);

    expect(find.byKey(const Key('scan-phase')), findsNothing);
    expect(_text(tester, 'scan-item'), scanItemName);
    expect(find.byKey(const Key('scan-reason')), findsNothing);
    expect(find.textContaining(scanItemId), findsNothing);
    expect(find.textContaining('0.93'), findsNothing);
    expect(find.textContaining('Accepted'), findsNothing);
    _expectNoDiagnostics();
  });

  testWidgets('a newer accepted scan replaces the shown item', (tester) async {
    final rig = await _pump(tester);
    await _accept(tester, rig);
    expect(_text(tester, 'scan-item'), scanItemName);

    await _accept(tester, rig, index: 1, trigger: 2000000, id: scanOtherId);

    expect(_text(tester, 'scan-item'), scanOtherName);
  });

  testWidgets(
    'rejected report gives a plain reason with the best candidate not accepted',
    (tester) async {
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

      expect(
        _text(tester, 'scan-reason'),
        scanRejectReasonLabel(ScanRejectReason.belowSimilarity),
      );
      expect(_text(tester, 'scan-candidate'), '$scanOtherName (not accepted)');
      expect(find.byKey(const Key('scan-item')), findsNothing);
      expect(find.textContaining('belowSimilarity'), findsNothing);
      expect(find.textContaining('0.41'), findsNothing);
      expect(find.textContaining('Accepted'), findsNothing);
      _expectNoDiagnostics();
    },
  );

  testWidgets('noMarker report uses plain words and shows no evidence', (
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

    expect(
      _text(tester, 'scan-reason'),
      scanRejectReasonLabel(ScanRejectReason.noMarker),
    );
    expect(find.textContaining('noMarker'), findsNothing);
    expect(find.textContaining('0.20'), findsNothing);
    expect(find.text('No title crop'), findsNothing);
    _expectNoDiagnostics();
  });

  testWidgets('failed report gives a plain reason and no code', (tester) async {
    final rig = await _pump(tester);
    await tester.runAsync(() async {
      rig.ports.fire(1000);
      await rig.ports.captureOk(0);
      await rig.ports.visionTimeout(0);
      await reportPublished(rig.coordinator, 1);
    });
    await tester.pump();

    expect(
      _text(tester, 'scan-reason'),
      scanFailureCodeLabel(ScanFailureCode.visionTimeout),
    );
    expect(find.textContaining('visionTimeout'), findsNothing);
    expect(find.byKey(const Key('scan-candidate')), findsNothing);
    expect(find.byKey(const Key('scan-item')), findsNothing);
    expect(find.text('No candidate'), findsOneWidget);
    _expectNoDiagnostics();
  });

  testWidgets(
    'rejection after an accepted item keeps it and shows a plain note',
    (tester) async {
      final rig = await _pump(tester);
      await _accept(tester, rig);
      await _reject(tester, rig, index: 1);

      expect(_text(tester, 'scan-item'), scanItemName);
      expect(
        _text(tester, 'scan-note-reason'),
        'Last scan not recognised: '
        '${scanRejectReasonLabel(ScanRejectReason.belowSimilarity)}',
      );
      expect(_text(tester, 'scan-note-best'), '$scanOtherName (not accepted)');
      expect(find.textContaining('belowSimilarity'), findsNothing);
      expect(find.textContaining('FILTERBYITEM'), findsNothing);
      expect(
        tester.getTopLeft(find.byKey(const Key('scan-note-reason'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('scan-item'))).dy),
      );
      _expectNoDiagnostics();
    },
  );

  testWidgets('after a rejection the Scanner shows no crop and no timing', (
    tester,
  ) async {
    final rig = await _pump(tester);
    await _accept(tester, rig);
    await _reject(tester, rig, index: 1);

    expect(find.byKey(const Key('scan-crop-image')), findsNothing);
    expect(find.byKey(const Key('scan-crop-placeholder')), findsNothing);
    expect(find.byType(RawImage), findsNothing);
    expect(find.byKey(const Key('scan-timings-label')), findsNothing);
    expect(find.byKey(const Key('scan-timing-total')), findsNothing);
    expect(find.textContaining(' ms'), findsNothing);
    expect(find.textContaining('Scan #'), findsNothing);
    expect(find.text('Details'), findsNothing);
  });

  testWidgets(
    'failure after an accepted item says the game window was not in front',
    (tester) async {
      final rig = await _pump(tester);
      await _accept(tester, rig);
      await tester.runAsync(() async {
        rig.ports.fire(5000000);
        (await rig.ports.capture.calls.at(1)).fail(const TargetNotForeground());
        await reportPublished(rig.coordinator, 2);
      });
      await tester.pump();

      expect(_text(tester, 'scan-item'), scanItemName);
      expect(
        _text(tester, 'scan-note-reason'),
        'Last scan not recognised: '
        '${scanFailureCodeLabel(ScanFailureCode.targetNotForeground)}',
      );
      expect(find.textContaining('targetNotForeground'), findsNothing);
      expect(find.byKey(const Key('scan-note-best')), findsNothing);
      expect(find.text('No candidate'), findsOneWidget);
      _expectNoDiagnostics();
    },
  );

  testWidgets('a newer acceptance removes the note', (tester) async {
    final rig = await _pump(tester);
    await _accept(tester, rig);
    await _reject(tester, rig, index: 1);
    expect(find.byKey(const Key('scan-note-reason')), findsOneWidget);

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

    expect(find.byKey(const Key('scan-note-reason')), findsNothing);
    expect(_text(tester, 'scan-item'), scanItemName);
  });
}

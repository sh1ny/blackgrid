import 'package:blackgrid/application/scan_epoch.dart';
import 'package:blackgrid/application/selection_controller.dart';
import 'package:blackgrid/data/vision/inspection_fir.dart';
import 'package:blackgrid/domain/inspection_context.dart';
import 'package:blackgrid/ui/answer_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/m1_harness.dart';
import '../support/m1_widget_harness.dart';

Finder _inFir(Finder target) =>
    find.descendant(of: find.byType(FirControls), matching: target);

Future<void> _accept(
  WidgetTester tester,
  M1Harness h,
  InspectionFirReason reason,
  int reportId,
) async {
  await tester.runAsync(
    () => h.services.selection.selectScan(
      reportId: reportId,
      itemId: 'item-b',
      mode: h.services.catalog.mode,
      catalogRevision: h.services.catalog.snapshot!.revision,
      epoch: const ScanEpoch(1, 1),
      detectedFir: InspectionFirReading(reason: reason),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectSource(WidgetTester tester, String text) {
  final source = _inFir(find.byKey(const Key('fir-source')));
  expect(source, findsOneWidget);
  expect(tester.widget<Text>(source).data, text);
  expect(tester.getSemantics(source).label, text);
}

void _expectSelected(WidgetTester tester, FirState value) {
  final button = tester.widget<SegmentedButton<FirState>>(
    _inFir(find.byType(SegmentedButton<FirState>)),
  );
  expect(button.selected, {value});
}

void main() {
  for (final area in ['nav-map', 'nav-scanner']) {
    testWidgets('different segment establishes manual override on $area', (
      tester,
    ) async {
      final h = await pumpM1(tester);
      await tester.tap(find.byKey(Key(area)));
      await _accept(tester, h, InspectionFirReason.iconFound, 1);
      final scan = h.services.selection.scan!;
      _expectSource(tester, 'From scan');
      _expectSelected(tester, FirState.yes);
      await tester.tap(_inFir(find.text('No')));
      await tester.pump();
      _expectSelected(tester, FirState.no);
      _expectSource(tester, 'Manual override');
      expect(h.services.selection.firOverride, FirState.no);
      expect(scan.detectedFir.value, FirState.yes);
    });

    testWidgets('explicit Unknown overrides detected Yes on $area', (
      tester,
    ) async {
      final h = await pumpM1(tester);
      await tester.tap(find.byKey(Key(area)));
      await _accept(tester, h, InspectionFirReason.iconFound, 1);
      await tester.tap(_inFir(find.text('Unknown')));
      await tester.pump();
      _expectSelected(tester, FirState.unknown);
      _expectSource(tester, 'Manual override');
      expect(h.services.selection.firOverride, FirState.unknown);
      expect(h.services.selection.scan!.detectedFir.value, FirState.yes);
    });

    for (final (reason, value, label) in [
      (InspectionFirReason.iconFound, FirState.yes, 'Yes'),
      (InspectionFirReason.cornerUnreadable, FirState.unknown, 'Unknown'),
    ]) {
      testWidgets(
        'press selected automatic $label establishes persistent manual $label on $area',
        (tester) async {
          final h = await pumpM1(tester);
          await tester.tap(find.byKey(Key(area)));
          await _accept(tester, h, reason, 1);
          final reading = h.services.selection.scan!.detectedFir;
          _expectSelected(tester, value);
          // Check the actual selected-segment tap, not a controller call.
          await tester.tap(_inFir(find.text(label)));
          await tester.pump();
          expect(h.services.selection.firSource, FirSource.manual);
          _expectSource(tester, 'Manual override');
          _expectSelected(tester, value);
          await tester.runAsync(() => h.services.catalog.refresh());
          await tester.runAsync(() => h.services.progress.refresh());
          await tester.pumpAndSettle();
          expect(h.services.selection.firOverride, value);
          expect(h.services.selection.scan!.detectedFir, same(reading));
          _expectSelected(tester, value);
          _expectSource(tester, 'Manual override');
        },
      );
    }

    testWidgets(
      'cut-off and unreadable reasons appear with shared FIR control on $area',
      (tester) async {
        final h = await pumpM1(tester);
        await tester.tap(find.byKey(Key(area)));
        for (final (id, reason, caption) in [
          (1, InspectionFirReason.cornerCutOff, 'From scan · corner cut off'),
          (
            2,
            InspectionFirReason.cornerUnreadable,
            'From scan · corner unreadable',
          ),
        ]) {
          await _accept(tester, h, reason, id);
          _expectSelected(tester, FirState.unknown);
          _expectSource(tester, caption);
        }
      },
    );
  }

  testWidgets('keyboard activation establishes override for selected segment', (
    tester,
  ) async {
    final h = await pumpM1(tester);
    await _accept(tester, h, InspectionFirReason.iconFound, 1);
    final element = tester.element(_inFir(find.text('Yes')));
    Focus.of(element).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(h.services.selection.firOverride, FirState.yes);
    _expectSource(tester, 'Manual override');
    _expectSelected(tester, FirState.yes);
  });
}

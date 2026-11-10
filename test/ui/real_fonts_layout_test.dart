// Width checks that need the app's real fonts (see loadRealFonts). Every test
// in this file runs with Geist and Literata loaded.
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/inspection_context.dart';
import 'package:blackgrid/domain/verdict_reason.dart';
import 'package:blackgrid/ui/answer_strip.dart';
import 'package:blackgrid/ui/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/m1/catalog/fixture.dart' show progressWire;
import '../support/m1_harness.dart';
import '../support/m1_widget_harness.dart';
import '../support/real_fonts.dart';

Finder _inStrip(Finder matching) => find.descendant(
  of: find.byKey(const Key('answer-strip')),
  matching: matching,
);

void main() {
  testWidgets('workspace-shell: Wide top bar fits at 1300px', (tester) async {
    await tester.runAsync(loadRealFonts);
    await pumpM1(tester, size: const Size(1300, 870));
    final bar = find.byKey(const Key('shell-top-bar'));
    final barRect = tester.getRect(bar);
    final labels = ['Stats', 'Import', 'Settings'];
    final rects = [
      for (final label in labels)
        tester.getRect(
          find.descendant(
            of: bar,
            matching: find.widgetWithText(TextButton, label),
          ),
        ),
    ];
    expect(rects[0].left, lessThan(rects[1].left));
    expect(rects[1].left, lessThan(rects[2].left));
    expect(rects[2].right, lessThanOrEqualTo(barRect.right));
    expect(barRect.right, lessThanOrEqualTo(1300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace-shell: Long reason with Found in raid at 1300px', (
    tester,
  ) async {
    await tester.runAsync(loadRealFonts);
    const token = 'PVP_synthetic-fixture-only';
    final longName = 'Long task name ${'y' * 100}';
    tester.view.physicalSize = const Size(1300, 870);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final h = (await tester.runAsync(() async {
      final result = M1Harness(
        shapeWire: (wire) {
          wire['tasks_en'] = {
            'data': {'task-a name': longName},
          };
          wire['token'] = {
            'success': true,
            'permissions': ['GP'],
            'token': token,
            'owner': 'synthetic-owner',
            'note': 'Synthetic',
            'calls': 0,
            'gameMode': 'pvp',
          };
          wire['progress'] = progressWire();
        },
      );
      result.credentials.values[GameMode.pvp] = token;
      await result.initialize();
      await result.services.progress.refresh();
      await result.services.selection.selectManual(
        result.services.catalog.snapshot!.items['item-a']!,
      );
      result.services.selection.setFir(FirState.yes);
      return result;
    }))!;
    addTearDown(h.dispose);
    await tester.pumpWidget(BlackgridApp(services: h.services));
    await tester.pumpAndSettle();
    final reasonText = verdictReason(h.services.selection.decision!);
    expect(reasonText.length, greaterThanOrEqualTo(120));
    final reason = _inStrip(find.byKey(const Key('answer-verdict-reason')));
    expect(tester.widget<Text>(reason).data, reasonText);
    expect(tester.widget<Text>(reason).maxLines, isNull);
    final plate = tester.getRect(
      _inStrip(find.byKey(const Key('verdict-plate'))),
    );
    final fir = tester.getRect(_inStrip(find.byType(FirControls)));
    final price = tester.getRect(
      _inStrip(find.byKey(const Key('answer-price'))),
    );
    final strip = tester.getRect(find.byKey(const Key('answer-strip')));
    for (final rect in [plate, fir, price]) {
      expect(rect.left, greaterThanOrEqualTo(strip.left));
      expect(rect.right, lessThanOrEqualTo(strip.right));
    }
    final beside = (fir.center.dy - plate.center.dy).abs() <= 4;
    final under = fir.top >= plate.bottom && (fir.left - plate.left).abs() <= 1;
    expect(beside || under, isTrue, reason: 'plate $plate fir $fir');
    expect(
      tester.renderObject<RenderParagraph>(reason).didExceedMaxLines,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });
}

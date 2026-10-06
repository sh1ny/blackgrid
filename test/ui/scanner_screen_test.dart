import 'package:blackgrid/domain/inspection_context.dart';
import 'package:blackgrid/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/m1_widget_harness.dart';

void main() {
  testWidgets(
    'search manual select FIR tab switch share projection without accepted scan',
    (tester) async {
      final h = await pumpM1(tester);
      await tester.tap(find.byKey(const Key('nav-scanner')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Synthetic component');
      await tester.pump();
      expect(
        find.widgetWithText(ListTile, 'Synthetic component'),
        findsOneWidget,
      );
      await tapM1Async(
        tester,
        find.widgetWithText(ListTile, 'Synthetic component'),
        () => h.services.history.rows.length == 1,
      );
      expect(h.services.selection.item!.id, 'item-a');
      expect(h.services.history.rows.length, 1);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Yes'));
      await tester.pumpAndSettle();
      expect(h.services.selection.fir, FirState.yes);
      final decision = h.services.selection.decision;
      await tester.tap(find.byKey(const Key('nav-map')));
      await tester.pumpAndSettle();
      expect(h.services.selection.decision, same(decision));
      expect(find.text('No accepted scan this session'), findsOneWidget);
      await tester.tap(find.byKey(const Key('nav-scanner')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Synthetic component',
      );
      expect(h.services.selection.fir, FirState.yes);
      expect(h.services.scans.hasAcceptedScan, isFalse);
      await tester.enterText(find.byType(TextField), 'item-b');
      await tester.pump();
      await tapM1Async(
        tester,
        find.widgetWithText(ListTile, 'Alternative component'),
        () => h.services.history.rows.any((row) => row.itemId == 'item-b'),
      );
      expect(h.services.selection.fir, FirState.unknown);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('persistence error appears without successful identity history', (
    tester,
  ) async {
    final h = await pumpM1(tester);
    await tester.runAsync(
      () => h.db.customStatement(
        "CREATE TRIGGER fail_activity BEFORE INSERT ON activity_records BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
      ),
    );
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'item-a');
    await tester.pump();
    await tapM1Async(
      tester,
      find.widgetWithText(ListTile, 'Synthetic component'),
      () => h.services.selection.error != null,
    );
    expect(
      find.descendant(
        of: find.byWidgetPredicate(
          (widget) =>
              widget is GridPanel &&
              widget.title == 'Current manual inspection',
        ),
        matching: find.textContaining('not recorded'),
      ),
      findsOneWidget,
    );
    expect(h.services.history.rows, isEmpty);
  });
}

import 'package:blackgrid/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/m1_widget_harness.dart';

void main() {
  testWidgets(
    'Map reference hierarchy keeps broad honest workspace and compact status rail',
    (tester) async {
      await pumpM1(tester, size: const Size(1912, 823));
      final workspace = tester.getRect(
        find.byWidgetPredicate((w) => w is GridPanel && w.title == 'SHORELINE'),
      );
      final active = tester.getRect(
        find.byWidgetPredicate(
          (w) => w is GridPanel && w.title == 'Active map',
        ),
      );
      expect(workspace.left, 14);
      expect(workspace.width / (1912 - 42), closeTo(.70, .01));
      expect(active.left, greaterThan(workspace.right));
      expect(
        find.textContaining('native artwork is outside M1'),
        findsOneWidget,
      );
      expect(find.text('No accepted scan this session'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'pin editor saves finite off-map record and invalid coordinate gives feedback',
    (tester) async {
      final h = await pumpM1(tester, size: const Size(1912, 823));
      await tester.tap(find.text('Add pin'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Pin label'),
        'Synthetic durable marker',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Normalized X'),
        'not a coordinate',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Normalized Y'),
        '1.5',
      );
      await tester.tap(find.text('Save pin'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('finite normalized coordinates'),
        findsOneWidget,
      );
      expect(h.services.settings.pins, isEmpty);
      await tester.enterText(
        find.widgetWithText(TextField, 'Normalized X'),
        '-.2',
      );
      await tapM1Async(
        tester,
        find.text('Save pin'),
        () => h.services.settings.pins.isNotEmpty,
      );
      expect(h.services.settings.pins.single.x, -.2);
      expect(find.text('Synthetic durable marker'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

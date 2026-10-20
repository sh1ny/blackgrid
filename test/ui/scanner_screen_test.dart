import 'package:blackgrid/application/scan_coordinator.dart';
import 'package:blackgrid/application/scan_epoch.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/inspection_context.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:blackgrid/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../application/support/history_wait.dart';
import '../support/m1_widget_harness.dart';
import 'support/scan_ui_support.dart';

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
      expect(find.text('Latest accepted scan'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) => w is GridPanel && w.title == 'Active map',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is GridPanel && w.icon == Icons.center_focus_strong,
        ),
        findsOneWidget,
      );
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
  testWidgets('accepted scan drives the decision card', (tester) async {
    final ports = ScanFakePorts();
    final h = await pumpM1(tester, scanPorts: ports);
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Synthetic component');
    await tester.pump();
    await tapM1Async(
      tester,
      find.widgetWithText(ListTile, 'Synthetic component'),
      () => h.services.history.rows.length == 1,
    );
    GridPanel titled(String title) => tester.widget<GridPanel>(
      find.byWidgetPredicate((w) => w is GridPanel && w.title == title),
    );
    expect(
      titled('Current manual inspection').subtitle,
      contains('not an accepted scan'),
    );

    final report = (await tester.runAsync(
      () => publishTargetedScan(
        h.services.scanner,
        ports,
        text: 'Alternative component',
      ),
    ))!;
    await tester.pump();
    await tester.runAsync(
      () => untilRow(
        h.services.history,
        (row) => row.source == ActivitySource.scan,
      ),
    );
    await tester.pumpAndSettle();

    expect((report.end as ScanAccepted).itemId, 'item-b');
    final card = find.byWidgetPredicate(
      (w) => w is GridPanel && w.title == 'Accepted scan',
    );
    expect(card, findsOneWidget);
    expect(
      tester.widget<GridPanel>(card).subtitle,
      matches(RegExp(r'^Scanned .+ ago')),
    );
    expect(h.services.selection.item!.id, 'item-b');
    expect(h.services.selection.scan, isNotNull);
    expect(
      find.descendant(of: card, matching: find.text('Alternative component')),
      findsWidgets,
    );
    expect(
      find.descendant(of: card, matching: find.text('Synthetic component')),
      findsNothing,
    );
    final rows = h.services.history.rows;
    expect(rows.length, 2);
    expect(rows.map((row) => (row.itemId, row.source)).toSet(), {
      ('item-a', ActivitySource.manual),
      ('item-b', ActivitySource.scan),
    });
    final history = find.byWidgetPredicate(
      (w) => w is GridPanel && w.title == 'Recent item activity',
    );
    expect(
      find.descendant(of: history, matching: find.textContaining(' • Scan\n')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: history,
        matching: find.textContaining(' • manual\n'),
      ),
      findsOneWidget,
    );
  });
  testWidgets('retired scan shows the scan-again message', (tester) async {
    final h = await pumpM1(tester);
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    final selection = h.services.selection;
    await tester.runAsync(
      () => selection.selectScan(
        reportId: 1,
        itemId: 'item-a',
        mode: GameMode.pvp,
        catalogRevision: h.services.catalog.snapshot!.revision,
        epoch: const ScanEpoch(0, 0),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Accepted scan'), findsOneWidget);

    selection.retireScan();
    await tester.pumpAndSettle();

    expect(
      find.text('Last scan was in an earlier mode or session; scan again'),
      findsOneWidget,
    );
    expect(find.text('Accepted scan'), findsNothing);
  });
}

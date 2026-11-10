import 'package:blackgrid/application/scan_coordinator.dart';
import 'package:blackgrid/application/scan_epoch.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/inspection_context.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:blackgrid/ui/evidence_panels.dart';
import 'package:blackgrid/ui/labels.dart';
import 'package:blackgrid/ui/map_screen.dart';
import 'package:blackgrid/ui/scanner_sections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../application/support/history_wait.dart';
import '../support/m1_harness.dart';
import '../support/m1_widget_harness.dart';
import 'support/scan_ui_support.dart';

void main() {
  testWidgets(
    'scanner-evidence: Scanner functions remain reachable without the old rail',
    (tester) async {
      await pumpM1(tester);
      await tester.tap(find.byKey(const Key('nav-scanner')));
      await tester.pumpAndSettle();
      expect(find.text('Picking an item here does not scan.'), findsNothing);
      expect(find.text('Type an item name.'), findsNothing);
      expect(find.widgetWithText(TextField, 'Search items…'), findsOneWidget);
      expect(find.byKey(const Key('status-game-mode')), findsOneWidget);
      expect(find.byKey(const Key('status-item-data')), findsOneWidget);
      expect(find.byKey(const Key('status-tracker')), findsOneWidget);
    },
  );
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
      // The raid timer strip sits above the Scanner; scroll the row in.
      await tester.ensureVisible(
        find.widgetWithText(ListTile, 'Synthetic component'),
      );
      await tester.pump();
      await tapM1Async(
        tester,
        find.widgetWithText(ListTile, 'Synthetic component'),
        () => h.services.history.rows.length == 1,
      );
      expect(h.services.selection.item!.id, 'item-a');
      expect(h.services.history.rows.length, 1);
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('answer-strip')),
          matching: find.text('Yes'),
        ),
      );
      await tester.pumpAndSettle();
      expect(h.services.selection.fir, FirState.yes);
      final decision = h.services.selection.decision;
      await tester.tap(find.byKey(const Key('nav-map')));
      await tester.pumpAndSettle();
      expect(h.services.selection.decision, same(decision));
      expect(find.text('Latest accepted scan'), findsNothing);
      expect(find.byType(MapScreen), findsOneWidget);
      expect(find.text('Active map'), findsNothing);
      expect(find.byKey(const Key('answer-strip')), findsOneWidget);
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
      // The raid timer strip sits above the Scanner; scroll the row in.
      await tester.ensureVisible(
        find.widgetWithText(ListTile, 'Alternative component'),
      );
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
    // The raid timer strip sits above the Scanner; scroll the row in.
    await tester.ensureVisible(
      find.widgetWithText(ListTile, 'Synthetic component'),
    );
    await tester.pump();
    await tapM1Async(
      tester,
      find.widgetWithText(ListTile, 'Synthetic component'),
      () => h.services.selection.error != null,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('answer-strip')),
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
    // The raid timer strip sits above the Scanner; scroll the row in.
    await tester.ensureVisible(
      find.widgetWithText(ListTile, 'Synthetic component'),
    );
    await tester.pump();
    await tapM1Async(
      tester,
      find.widgetWithText(ListTile, 'Synthetic component'),
      () => h.services.history.rows.length == 1,
    );
    String provenance() =>
        tester.widget<Text>(find.byKey(const Key('answer-provenance'))).data!;
    Finder inStrip(String text) => find.descendant(
      of: find.byKey(const Key('answer-strip')),
      matching: find.text(text),
    );
    expect(provenance(), 'Chosen by hand');
    expect(inStrip('Synthetic component'), findsOneWidget);

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
    // The strip is driven by the accepted scan.
    expect(provenance(), matches(RegExp(r'^Accepted scan · ')));
    expect(inStrip('Alternative component'), findsOneWidget);
    expect(inStrip('Synthetic component'), findsNothing);
    expect(h.services.selection.item!.id, 'item-b');
    expect(h.services.selection.scan, isNotNull);
    // So are the sections under it: Why shows item-b's needs.
    expect(
      find.descendant(
        of: find.byType(WhySection),
        matching: find.byKey(const Key('why-summary')),
      ),
      findsOneWidget,
    );
    final rows = h.services.history.rows;
    expect(rows.length, 2);
    expect(rows.map((row) => (row.itemId, row.source)).toSet(), {
      ('item-a', ActivitySource.manual),
      ('item-b', ActivitySource.scan),
    });
    // Recent items lists both rows as one-line X14 rows, with no source
    // subtitle.
    final history = find.byType(HistoryPanel);
    expect(history, findsOneWidget);
    expect(
      find.descendant(of: history, matching: find.byType(ListTile)),
      findsNWidgets(2),
    );
    for (final name in ['Synthetic component', 'Alternative component']) {
      expect(
        find.descendant(of: history, matching: find.text(name)),
        findsOneWidget,
        reason: name,
      );
    }
    for (final source in ActivitySource.values) {
      expect(
        find.descendant(
          of: history,
          matching: find.textContaining(' • ${activitySourceLabel(source)}'),
        ),
        findsNothing,
      );
    }
  });
  Future<M1Harness> pumpWithScan(WidgetTester tester) async {
    final ports = ScanFakePorts();
    final h = await pumpM1(tester, scanPorts: ports);
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => publishTargetedScan(
        h.services.scanner,
        ports,
        text: 'Alternative component',
      ),
    );
    await tester.pumpAndSettle();
    return h;
  }

  testWidgets('the Scanner has no Details control', (tester) async {
    await pumpWithScan(tester);

    expect(find.byKey(const Key('scan-item')), findsOneWidget);
    expect(find.text('Details'), findsNothing);
    expect(find.byKey(const Key('scan-marker')), findsNothing);
    expect(find.byKey(const Key('scan-best')), findsNothing);
    expect(find.byKey(const Key('scan-timing-total')), findsNothing);
    expect(find.byKey(const Key('scan-timings-label')), findsNothing);
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
    expect(find.text('Accepted scan · just now'), findsOneWidget);

    selection.retireScan();
    await tester.pumpAndSettle();

    expect(
      find.text('Last scan was in an earlier mode or session; scan again'),
      findsOneWidget,
    );
    expect(find.text('Accepted scan · just now'), findsNothing);
  });
}

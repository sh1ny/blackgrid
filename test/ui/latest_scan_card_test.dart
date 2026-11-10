import 'package:blackgrid/application/app_services.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/data/vision/inspection_evidence.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:blackgrid/ui/evidence_panels.dart';
import 'package:blackgrid/ui/panels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../application/support/history_wait.dart';
import '../support/m1_harness.dart';
import '../support/m1_widget_harness.dart';
import '../support/map_widget_harness.dart';
import 'support/scan_ui_support.dart';

const _back = 'Back to latest scan';

Finder _card(String title) =>
    find.byWidgetPredicate((w) => w is GridPanel && w.title == title);
Finder get _backInStrip => find.descendant(
  of: find.byKey(const Key('answer-strip')),
  matching: find.text(_back),
);

/// Drives one real targeted scan for "Alternative component" (`item-b`) and
/// waits until it is recorded as a scan row.
Future<void> _acceptB(
  WidgetTester tester,
  AppServices services,
  ScanFakePorts ports,
) async {
  await tester.runAsync(
    () => publishTargetedScan(
      services.scanner,
      ports,
      text: 'Alternative component',
    ),
  );
  await tester.runAsync(
    () => untilRow(services.history, (r) => r.source == ActivitySource.scan),
  );
  await tester.pumpAndSettle();
}

/// Opens the stored row for `item-a` through the Scanner history panel.
Future<void> _openHistoryA(WidgetTester tester, M1Harness h) async {
  await tester.tap(find.byKey(const Key('nav-scanner')));
  await tester.pumpAndSettle();
  await tapM1Async(
    tester,
    find.descendant(
      of: find.byType(HistoryPanel),
      matching: find.widgetWithText(ListTile, 'Synthetic component'),
    ),
    () =>
        h.services.selection.isHistory && !h.services.selection.loadingHistory,
  );
}

Future<void> _selectAByHand(WidgetTester tester, M1Harness h) =>
    tester.runAsync(
      () => h.services.selection.selectManual(
        h.services.catalog.snapshot!.items['item-a']!,
      ),
    );

void main() {
  testWidgets('Back to latest scan closes history on Map and Scanner', (
    tester,
  ) async {
    final ports = ScanFakePorts();
    final h = await pumpM1(tester, scanPorts: ports);
    final selection = h.services.selection;
    await _acceptB(tester, h.services, ports);
    await _selectAByHand(tester, h);
    await tester.pumpAndSettle();
    expect(h.services.scans.latest?.itemId, 'item-b');
    final acceptedAt = h.services.scans.latest!.acceptedAt;

    for (final screen in ['nav-map', 'nav-scanner']) {
      // A history row for another item is open on the card.
      await _openHistoryA(tester, h);
      expect(selection.isHistory, isTrue);
      await tester.tap(find.byKey(Key(screen)));
      await tester.pumpAndSettle();
      expect(_backInStrip, findsOneWidget);

      await tester.tap(_backInStrip);
      await tester.pumpAndSettle();

      expect(selection.isHistory, isFalse);
      expect(selection.selectedId, 'item-b');
      expect(selection.scan?.acceptedAt, acceptedAt);
      expect(_backInStrip, findsNothing);
      expect(h.services.scans.latest?.itemId, 'item-b');
    }
    // Neither return recorded history: item-a manual and item-b scan only.
    expect(h.services.history.rows, hasLength(2));
  });

  testWidgets('no Back action while the latest scan is shown', (tester) async {
    final ports = ScanFakePorts();
    final h = await pumpM1(tester, scanPorts: ports);
    await _acceptB(tester, h.services, ports);
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();

    expect(h.services.selection.scan?.itemId, 'item-b');
    expect(find.byKey(const Key('answer-provenance')), findsOneWidget);
    expect(_backInStrip, findsNothing);
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    expect(_backInStrip, findsNothing);
  });

  testWidgets('no Back action without or after clearing a latest scan', (
    tester,
  ) async {
    final ports = ScanFakePorts();
    final h = await pumpM1(tester, scanPorts: ports);
    await _selectAByHand(tester, h);
    await tester.pumpAndSettle();
    expect(h.services.scans.latest, isNull);
    expect(_backInStrip, findsNothing);

    await _acceptB(tester, h.services, ports);
    await _selectAByHand(tester, h);
    await tester.pumpAndSettle();
    expect(_backInStrip, findsOneWidget);

    // A mode change clears the latest scan.
    await tester.runAsync(() => h.services.setMode(GameMode.pve));
    await tester.pumpAndSettle();
    expect(h.services.scans.latest, isNull);
    expect(_backInStrip, findsNothing);
    await _openHistoryAnyRow(tester, h);
    expect(_backInStrip, findsNothing);
  });

  testWidgets('latest-accepted-scan: No separate panel', (tester) async {
    await pumpMapFixture(tester, scanPorts: ScanFakePorts());
    expect(find.byKey(const Key('nav-map')), findsOneWidget);
    expect(find.text('Latest accepted scan'), findsNothing);
    expect(_card('Latest accepted scan'), findsNothing);
    expect(_card('Accepted scan'), findsNothing);
    // The rail's panels are gone; the picker and the shared strip remain.
    expect(_card('Active map'), findsNothing);
    expect(find.byKey(const Key('map-picker')), findsOneWidget);
    expect(find.byKey(const Key('answer-strip')), findsOneWidget);
  });

  testWidgets('latest-accepted-scan: Scan accepted with Map open', (
    tester,
  ) async {
    final ports = ScanFakePorts();
    final h = await pumpMapFixture(tester, scanPorts: ports);
    expect(find.byKey(const Key('map-picker')), findsOneWidget);

    await _acceptB(tester, h.services, ports);

    // Still on Map: the strip carries the scan, and no panel sits beside it.
    expect(find.byKey(const Key('map-picker')), findsOneWidget);
    final strip = find.byKey(const Key('answer-strip'));
    expect(
      find.descendant(
        of: strip,
        matching: find.text('Accepted scan · just now'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: strip, matching: find.text('Alternative component')),
      findsWidgets,
    );
    expect(_card('Accepted scan'), findsNothing);
    expect(_card('Active map'), findsNothing);
    expect(h.services.scans.latest?.itemId, 'item-b');
    expect(h.services.selection.scan?.itemId, 'item-b');
  });

  testWidgets('a fenced scan with Map open changes nothing', (tester) async {
    final ports = ScanFakePorts();
    final h = await pumpM1(tester, scanPorts: ports);
    await tester.runAsync(() async {
      await h.services.scanner.setLiveScan(true);
      await h.services.scanner.settled;
      ports.fire(1000);
      await ports.captureOk(0);
      // The mode changes while the scan is in flight.
      await h.services.setMode(GameMode.pve);
      await ports.visionDeliver(
        0,
        scanRecognised(InspectionFrameKind.targeted, [
          scanEvidence(text: 'Alternative component'),
        ]),
      );
      await h.services.scanner.settled;
    });
    await tester.pumpAndSettle();

    expect(h.services.scans.latest, isNull);
    expect(h.services.selection.scan, isNull);
    expect(_card('Accepted scan'), findsNothing);
    expect(_backInStrip, findsNothing);
    expect(
      h.services.history.rows.where((r) => r.source == ActivitySource.scan),
      isEmpty,
    );
  });
}

/// Opens whichever history row is first on Scanner, then returns to Map.
Future<void> _openHistoryAnyRow(WidgetTester tester, M1Harness h) async {
  await tester.tap(find.byKey(const Key('nav-scanner')));
  await tester.pumpAndSettle();
  final row = find.descendant(
    of: find.byType(HistoryPanel),
    matching: find.byType(ListTile),
  );
  await tapM1Async(
    tester,
    row.first,
    () =>
        h.services.selection.isHistory && !h.services.selection.loadingHistory,
  );
}

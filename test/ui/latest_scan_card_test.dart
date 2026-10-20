import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/data/vision/inspection_evidence.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:blackgrid/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../application/support/history_wait.dart';
import '../support/m1_harness.dart';
import '../support/m1_widget_harness.dart';
import 'support/scan_ui_support.dart';

const _back = 'Back to latest scan';

Finder _card(String title) =>
    find.byWidgetPredicate((w) => w is GridPanel && w.title == title);

/// Drives one real targeted scan for "Alternative component" (`item-b`) and
/// waits until it is recorded as a scan row.
Future<void> _acceptB(
  WidgetTester tester,
  M1Harness h,
  ScanFakePorts ports,
) async {
  await tester.runAsync(
    () => publishTargetedScan(
      h.services.scanner,
      ports,
      text: 'Alternative component',
    ),
  );
  await tester.runAsync(
    () => untilRow(h.services.history, (r) => r.source == ActivitySource.scan),
  );
  await tester.pumpAndSettle();
}

/// Opens the stored row for `item-a` through the Scanner history panel.
Future<void> _openHistoryA(WidgetTester tester, M1Harness h) async {
  await tester.tap(find.byKey(const Key('nav-scanner')));
  await tester.pumpAndSettle();
  await tapM1Async(
    tester,
    find.widgetWithText(ListTile, 'Synthetic component'),
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
    await _acceptB(tester, h, ports);
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
      expect(_card('History inspection'), findsOneWidget);
      expect(find.text(_back), findsOneWidget);

      await tester.tap(find.text(_back));
      await tester.pumpAndSettle();

      expect(selection.isHistory, isFalse);
      expect(selection.selectedId, 'item-b');
      expect(selection.scan?.acceptedAt, acceptedAt);
      expect(_card('Accepted scan'), findsOneWidget);
      expect(_card('History inspection'), findsNothing);
      expect(find.text(_back), findsNothing);
      expect(h.services.scans.latest?.itemId, 'item-b');
    }
    // Neither return recorded history: item-a manual and item-b scan only.
    expect(h.services.history.rows, hasLength(2));
  });

  testWidgets('no Back action while the latest scan is shown', (tester) async {
    final ports = ScanFakePorts();
    final h = await pumpM1(tester, scanPorts: ports);
    await _acceptB(tester, h, ports);

    expect(h.services.selection.scan?.itemId, 'item-b');
    expect(_card('Accepted scan'), findsOneWidget);
    expect(find.text(_back), findsNothing);
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    expect(find.text(_back), findsNothing);
  });

  testWidgets('no Back action without or after clearing a latest scan', (
    tester,
  ) async {
    final ports = ScanFakePorts();
    final h = await pumpM1(tester, scanPorts: ports);
    await _selectAByHand(tester, h);
    await tester.pumpAndSettle();
    expect(h.services.scans.latest, isNull);
    expect(find.text(_back), findsNothing);

    await _acceptB(tester, h, ports);
    await _selectAByHand(tester, h);
    await tester.pumpAndSettle();
    expect(find.text(_back), findsOneWidget);

    // A mode change clears the latest scan.
    await tester.runAsync(() => h.services.setMode(GameMode.pve));
    await tester.pumpAndSettle();
    expect(h.services.scans.latest, isNull);
    expect(find.text(_back), findsNothing);
    await _openHistoryAnyRow(tester, h);
    expect(find.text(_back), findsNothing);
  });

  testWidgets('a scan accepted with Map open shows on Map\'s card', (
    tester,
  ) async {
    final ports = ScanFakePorts();
    final h = await pumpM1(tester, scanPorts: ports);
    expect(find.byKey(const Key('nav-map')), findsOneWidget);
    expect(_card('Active map'), findsOneWidget);

    await _acceptB(tester, h, ports);

    expect(_card('Accepted scan'), findsOneWidget);
    expect(
      find.descendant(
        of: _card('Accepted scan'),
        matching: find.text('Alternative component'),
      ),
      findsWidgets,
    );
    expect(h.services.scans.latest?.itemId, 'item-b');
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
    expect(find.text(_back), findsNothing);
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
    of: _card('Recent item activity'),
    matching: find.byType(ListTile),
  );
  await tapM1Async(
    tester,
    row.first,
    () =>
        h.services.selection.isHistory && !h.services.selection.loadingHistory,
  );
}

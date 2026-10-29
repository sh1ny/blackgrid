import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:blackgrid/ui/evidence_panels.dart';
import 'package:blackgrid/ui/labels.dart';
import 'package:blackgrid/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/m1_harness.dart';

void main() {
  Future<M1Harness> showHistory(
    WidgetTester tester, {
    required String itemId,
    required DateTime observedAt,
    ActivitySource source = ActivitySource.manual,
  }) async {
    final h = (await tester.runAsync(() async {
      final result = M1Harness();
      await result.initialize();
      await result.db.recordActivity(
        itemId,
        GameMode.pvp,
        observedAt,
        source: source,
      );
      await result.services.history.load();
      return result;
    }))!;
    addTearDown(h.dispose);
    tester.view.physicalSize = const Size(700, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: blackgridTheme(),
        home: Scaffold(body: HistoryPanel(services: h.services)),
      ),
    );
    await tester.pump();
    return h;
  }

  testWidgets('an imported scan row says Imported scan', (tester) async {
    await showHistory(
      tester,
      itemId: 'item-a',
      observedAt: DateTime.now(),
      source: ActivitySource.importedScan,
    );

    expect(find.textContaining('Imported scan'), findsOneWidget);
    expect(find.textContaining('importedScan'), findsNothing);
    expect(find.text('Items you picked or scanned'), findsOneWidget);
  });

  testWidgets('a row observed today shows its local time without ISO', (
    tester,
  ) async {
    final observed = DateTime.now();
    await showHistory(tester, itemId: 'item-a', observedAt: observed);

    final time = localTimeLabel(observed, now: DateTime.now());
    expect(find.textContaining(time), findsOneWidget);
    expect(find.textContaining(RegExp(r'\d{4}-\d{2}-\d{2}T')), findsNothing);
    expect(find.textContaining('Z'), findsNothing);
  });

  testWidgets('a row whose item has no name shows its id', (tester) async {
    await showHistory(tester, itemId: 'ghost-item', observedAt: DateTime.now());

    expect(find.text('ghost-item'), findsOneWidget);
  });
}

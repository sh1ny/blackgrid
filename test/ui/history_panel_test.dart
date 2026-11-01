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
    String itemId = 'item-a',
    DateTime? observedAt,
    ActivitySource source = ActivitySource.manual,
    bool seed = true,
  }) async {
    final h = (await tester.runAsync(() async {
      final result = M1Harness();
      await result.initialize();
      if (seed) {
        await result.db.recordActivity(
          itemId,
          GameMode.pvp,
          observedAt ?? DateTime.now(),
          source: source,
        );
      }
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

  testWidgets('a record failure shows its message above the listed entries', (
    tester,
  ) async {
    final h = await showHistory(tester, itemId: 'ghost-item');
    await tester.runAsync(() async {
      await h.db.customStatement(
        'CREATE TRIGGER no_activity BEFORE INSERT ON activity_records '
        "BEGIN SELECT RAISE(ABORT, 'synthetic'); END",
      );
      final recorded = await h.services.history.record(
        'item-b',
        GameMode.pvp,
        DateTime.now(),
        source: ActivitySource.scan,
      );
      expect(recorded, isFalse);
    });
    await tester.pump();

    final message = find.text('The accepted scan was not recorded in history.');
    expect(message, findsOneWidget);
    expect(find.text('ghost-item'), findsOneWidget);
    expect(
      tester.getTopLeft(message).dy,
      lessThan(tester.getTopLeft(find.text('ghost-item')).dy),
    );
  });

  testWidgets('empty history shows No items yet and no error', (tester) async {
    await showHistory(tester, seed: false);

    expect(find.text('No items yet.'), findsOneWidget);
    expect(find.textContaining('could not'), findsNothing);
    expect(find.textContaining('not recorded'), findsNothing);
  });
}

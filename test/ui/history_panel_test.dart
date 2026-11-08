import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/decision.dart';
import 'package:blackgrid/ui/item_icon.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:blackgrid/ui/evidence_panels.dart';
import 'package:blackgrid/ui/labels.dart';
import 'package:blackgrid/ui/ember/ember_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/m1_harness.dart';

void main() {
  Future<M1Harness> showHistory(
    WidgetTester tester, {
    String itemId = 'item-a',
    DateTime? observedAt,
    ActivitySource source = ActivitySource.manual,
    Recommendation? verdict,
    GameMode mode = GameMode.pvp,
    bool seed = true,
  }) async {
    final h = (await tester.runAsync(() async {
      final result = M1Harness();
      await result.initialize();
      if (seed) {
        await result.db.recordActivity(
          itemId,
          mode,
          observedAt ?? DateTime.now(),
          source: source,
          verdict: verdict,
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
        theme: blackgridTheme(Brightness.dark),
        home: Scaffold(body: HistoryPanel(services: h.services)),
      ),
    );
    await tester.pump();
    return h;
  }

  testWidgets('history rows fit the inspector at text scale two', (
    tester,
  ) async {
    final h = await showHistory(
      tester,
      verdict: Recommendation.keep,
      observedAt: DateTime(2020),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: blackgridTheme(Brightness.dark),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 352,
                height: 400,
                child: HistoryPanel(services: h.services),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byTooltip('Recorded verdict: Keep'), findsOneWidget);
    expect(find.byType(ListTile), findsOneWidget);
    final tile = find.byType(ListTile);
    final bounds = tester.getRect(tile);
    for (final element
        in find.descendant(of: tile, matching: find.byType(Text)).evaluate()) {
      final textBounds = tester.getRect(
        find.byElementPredicate((candidate) => identical(candidate, element)),
      );
      expect(textBounds.top, greaterThanOrEqualTo(bounds.top));
      expect(textBounds.bottom, lessThanOrEqualTo(bounds.bottom));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace-shell: History selection', (tester) async {
    final h = await showHistory(tester);
    await tester.runAsync(() async {
      await h.db.recordActivity(
        'item-a',
        GameMode.pvp,
        DateTime.now(),
        verdict: Recommendation.keep,
      );
      await h.services.history.load();
    });
    await tester.pump();
    expect(find.byType(ItemIcon), findsOneWidget);
    expect(find.byTooltip('Recorded verdict: Keep'), findsOneWidget);
    expect(tester.getSize(find.byType(ListTile)).height, 38);
    await tester.tap(find.byType(ListTile));
    await tester.pump();
    expect(h.services.selection.historyRow?.verdict, Recommendation.keep);
  });

  testWidgets('workspace-shell: Missing history picture', (tester) async {
    final h = await showHistory(tester, itemId: 'missing-item');
    expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
    await tester.tap(find.byType(ListTile));
    await tester.pump();
    expect(h.services.selection.historyRow?.itemId, 'missing-item');
  });

  testWidgets('workspace-shell: Legacy history verdict', (tester) async {
    await showHistory(tester);
    expect(find.byTooltip('Verdict not recorded'), findsOneWidget);
  });

  for (final verdict in Recommendation.values) {
    testWidgets('recorded indicator names ${verdict.name}', (tester) async {
      await showHistory(tester, verdict: verdict);
      expect(
        find.byTooltip('Recorded verdict: ${recommendationLabel(verdict)}'),
        findsOneWidget,
      );
    });
  }

  testWidgets(
    'history from another mode uses a fallback without current mode image',
    (tester) async {
      final h = await showHistory(
        tester,
        mode: GameMode.pve,
        verdict: Recommendation.keep,
      );
      expect(find.byType(ItemIcon), findsNothing);
      expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
      await tester.tap(find.byType(ListTile));
      await tester.pump();
      expect(h.services.selection.historyRow?.mode, GameMode.pve);
    },
  );

  testWidgets(
    'recorded indicator does not change when inspected advice differs',
    (tester) async {
      final h = await showHistory(tester);
      await tester.runAsync(
        () => h.services.selection.selectManual(
          h.services.catalog.snapshot!.items['item-a']!,
        ),
      );
      final current = h.services.selection.decision!.recommendation;
      final recorded = current == Recommendation.keep
          ? Recommendation.trader
          : Recommendation.keep;
      await tester.runAsync(() async {
        await h.db.recordActivity(
          'item-a',
          GameMode.pvp,
          DateTime.now(),
          verdict: recorded,
        );
        await h.services.history.load();
        await h.services.selection.openHistory(h.services.history.rows.single);
      });
      await tester.pump();
      expect(h.services.selection.decision!.recommendation, current);
      expect(
        find.byTooltip('Recorded verdict: ${recommendationLabel(recorded)}'),
        findsOneWidget,
      );
    },
  );

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

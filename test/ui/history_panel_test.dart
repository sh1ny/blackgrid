import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/decision.dart';
import 'package:blackgrid/ui/item_icon.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:blackgrid/ui/evidence_panels.dart';
import 'package:blackgrid/ui/labels.dart';
import 'package:blackgrid/ui/ember/ember_theme.dart';
import 'package:blackgrid/ui/ember/theme_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/m1/catalog/fixture.dart' show fixtureNow;
import '../support/m1_harness.dart';

/// One activity to record before the panel is shown.
typedef _Seed = ({
  String itemId,
  DateTime at,
  GameMode mode,
  ActivitySource source,
});

void main() {
  Future<M1Harness> showHistory(
    WidgetTester tester, {
    String itemId = 'item-a',
    DateTime? observedAt,
    ActivitySource source = ActivitySource.manual,
    Recommendation? verdict,
    GameMode mode = GameMode.pvp,
    bool seed = true,
    List<_Seed>? seeds,
    DateTime Function()? clock,
    Duration period = const Duration(seconds: 5),
  }) async {
    final h = (await tester.runAsync(() async {
      final result = M1Harness();
      await result.initialize();
      for (final row in seeds ?? const <_Seed>[]) {
        await result.db.recordActivity(
          row.itemId,
          row.mode,
          row.at,
          source: row.source,
        );
      }
      if (seed && seeds == null) {
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
        home: Scaffold(
          body: HistoryPanel(
            services: h.services,
            clock: clock,
            period: period,
          ),
        ),
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
      observedAt: fixtureNow,
      source: ActivitySource.importedScan,
    );

    expect(find.text('Imported scan'), findsOneWidget);
    expect(find.textContaining('importedScan'), findsNothing);
    expect(find.text('Items you picked or scanned'), findsOneWidget);
  });

  testWidgets('a row observed today shows its local time without ISO', (
    tester,
  ) async {
    await showHistory(
      tester,
      itemId: 'item-a',
      observedAt: fixtureNow.subtract(const Duration(minutes: 3)),
    );

    expect(find.text('3 min'), findsOneWidget);
    expect(find.textContaining(RegExp(r'\d{4}-\d{2}-\d{2}T')), findsNothing);
    expect(find.textContaining('Z'), findsNothing);
    expect(find.textContaining('T'), findsNothing);
  });

  testWidgets('player-facing-text: Earlier day', (tester) async {
    await showHistory(
      tester,
      itemId: 'item-a',
      observedAt: fixtureNow.subtract(const Duration(days: 2)),
    );

    expect(find.text('2 d'), findsOneWidget);
  });

  testWidgets('scanner-workspace: Relative ages', (tester) async {
    _Seed seed(String id, Duration ago) => (
      itemId: id,
      at: fixtureNow.subtract(ago),
      mode: GameMode.pvp,
      source: ActivitySource.manual,
    );
    await showHistory(
      tester,
      seeds: [
        seed('one', const Duration(seconds: 5)),
        seed('two', const Duration(seconds: 12)),
        seed('three', const Duration(minutes: 3)),
        seed('four', const Duration(hours: 5)),
        seed('five', const Duration(days: 2)),
      ],
    );

    for (final age in ['just now', '12 s', '3 min', '5 h', '2 d']) {
      expect(find.text(age), findsOneWidget, reason: age);
    }
  });

  testWidgets('scanner-workspace: Ages move on while shown', (tester) async {
    var now = fixtureNow;
    await showHistory(
      tester,
      observedAt: fixtureNow,
      clock: () => now,
      period: const Duration(milliseconds: 10),
    );
    expect(find.text('just now'), findsOneWidget);

    now = fixtureNow.add(const Duration(minutes: 3));
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('3 min'), findsOneWidget);
    expect(find.text('just now'), findsNothing);
  });

  testWidgets('scanner-workspace: History read fails', (tester) async {
    final h = await showHistory(tester, itemId: 'ghost-item');
    await tester.runAsync(() async {
      await h.db.customStatement(
        'CREATE TRIGGER no_activity BEFORE INSERT ON activity_records '
        "BEGIN SELECT RAISE(ABORT, 'synthetic'); END",
      );
      await h.services.history.record(
        'item-b',
        GameMode.pvp,
        fixtureNow,
        source: ActivitySource.scan,
      );
    });
    await tester.pump();

    final message = find.text('The accepted scan was not recorded in history.');
    expect(message, findsOneWidget);
    expect(
      tester.widget<Text>(message).style?.color,
      tester.element(message).ember.errInk,
    );
    expect(
      tester.getTopLeft(message).dy,
      greaterThan(tester.getTopLeft(find.text('Recent items')).dy),
    );
    await tester.tap(find.text('ghost-item'));
    await tester.pump();
    expect(h.services.selection.historyRow?.itemId, 'ghost-item');
  });

  testWidgets('workspace-shell: Rows from another game mode', (tester) async {
    _Seed seed(GameMode mode) => (
      itemId: 'item-a',
      at: fixtureNow,
      mode: mode,
      source: ActivitySource.manual,
    );
    await showHistory(tester, seeds: [seed(GameMode.pvp), seed(GameMode.pve)]);

    expect(find.byType(ListTile), findsNWidgets(2));
    expect(find.text('PvE'), findsOneWidget);
    expect(find.text('PvP'), findsNothing);
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

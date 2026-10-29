import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/m1/catalog/fixture.dart';
import '../support/m1_widget_harness.dart';

void main() {
  for (final liveCurrent in [false, true]) {
    for (final stored in [false, true]) {
      testWidgets(
        'review 10 history source never borrows ${liveCurrent ? 'current' : 'missing'} live catalog ${stored ? 'with' : 'without'} stored snapshot',
        (tester) async {
          final h = await pumpM1(
            tester,
            mode: liveCurrent ? GameMode.pvp : GameMode.unknown,
          );
          await tester.runAsync(() async {
            if (!liveCurrent) await h.services.setMode(GameMode.pvp);
            if (stored) {
              await h.db.commitCatalog(fixtureCatalog(mode: GameMode.pve));
            }
            await h.db.recordActivity('item-a', GameMode.pve, fixtureNow);
            await h.services.history.load();
            await h.services.selection.openHistory(
              h.services.history.rows.single,
            );
          });
          await tester.tap(find.byKey(const Key('nav-scanner')));
          await tester.pumpAndSettle();
          final panel = find.byWidgetPredicate(
            (w) => w is GridPanel && w.title == 'Data sources',
          );
          expect(
            find.descendant(of: panel, matching: find.text('Game mode: PvE')),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: panel,
              matching: find.textContaining(
                stored
                    ? 'Item data: out of date · updated '
                    : 'Item data: not downloaded yet',
              ),
            ),
            findsOneWidget,
          );
          if (!stored) {
            expect(
              find.descendant(
                of: panel,
                matching: find.textContaining('updated'),
              ),
              findsNothing,
            );
          }
          expect(h.services.catalog.mode, GameMode.pvp);
        },
      );
    }
  }
  testWidgets(
    'history UI opens stored mode then returns unchanged live mode and manual identity',
    (tester) async {
      final h = await pumpM1(tester);
      await tester.runAsync(() async {
        await h.services.setMode(GameMode.pve);
        await h.services.catalog.refresh();
        await h.services.selection.selectManual(
          h.services.catalog.snapshot!.items['item-a']!,
        );
        await h.services.setMode(GameMode.pvp);
        await h.services.catalog.refresh();
        await h.services.selection.selectManual(
          h.services.catalog.snapshot!.items['item-b']!,
        );
      });
      await tester.tap(find.byKey(const Key('nav-scanner')));
      await tester.pumpAndSettle();
      await tapM1Async(
        tester,
        find.widgetWithText(ListTile, 'item-a'),
        () =>
            !h.services.selection.loadingHistory &&
            h.services.selection.item?.id == 'item-a',
      );
      expect(h.services.selection.inspectionMode, GameMode.pve);
      expect(h.services.catalog.mode, GameMode.pvp);
      expect(find.textContaining('Saved from PvE'), findsOneWidget);
      await tester.tap(find.byTooltip('Close history inspection'));
      await tester.pumpAndSettle();
      expect(h.services.selection.item!.id, 'item-b');
      expect(h.services.catalog.mode, GameMode.pvp);
      expect(h.services.scans.hasAcceptedScan, isFalse);
    },
  );
  testWidgets(
    'independent history scroll offset survives retained navigation',
    (tester) async {
      final h = await pumpM1(tester);
      await tester.runAsync(() async {
        for (var i = 0; i < 35; i++) {
          await h.db.recordActivity(
            'synthetic-history-$i',
            GameMode.pvp,
            fixtureNow.add(Duration(seconds: i)),
          );
        }
        await h.services.history.load();
      });
      await tester.tap(find.byKey(const Key('nav-scanner')));
      await tester.pumpAndSettle();
      final panel = find.byWidgetPredicate(
        (w) => w is GridPanel && w.title == 'Recent item activity',
      );
      final list = find.descendant(of: panel, matching: find.byType(ListView));
      await tester.drag(list, const Offset(0, -350));
      await tester.pumpAndSettle();
      final scroll = find.descendant(
        of: panel,
        matching: find.byType(Scrollable),
      );
      final offset = tester.state<ScrollableState>(scroll).position.pixels;
      expect(offset, greaterThan(0));
      await tester.tap(find.byKey(const Key('nav-map')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav-scanner')));
      await tester.pumpAndSettle();
      expect(tester.state<ScrollableState>(scroll).position.pixels, offset);
      expect(tester.takeException(), isNull);
    },
  );
}

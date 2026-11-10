import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/ui/evidence_panels.dart';
import 'package:blackgrid/ui/scanner_sections.dart';
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
          // The history item is read from its own mode's saved item data,
          // never from the live PvP catalog that is also loaded here.
          final selection = h.services.selection;
          expect(selection.inspectionMode, GameMode.pve);
          expect(
            selection.inspectionCatalog?.mode,
            stored ? GameMode.pve : null,
          );
          final strip = find.byKey(const Key('answer-strip'));
          final why = find.byType(WhySection, skipOffstage: false);
          final prices = find.byType(PricesSection, skipOffstage: false);
          for (final section in [why, prices]) {
            expect(
              find.descendant(
                of: section,
                matching: find.text(
                  'Item data unavailable',
                  skipOffstage: false,
                ),
              ),
              stored ? findsNothing : findsOneWidget,
            );
          }
          if (stored) {
            expect(
              find.descendant(
                of: strip,
                matching: find.textContaining('saved '),
              ),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: strip,
                matching: find.textContaining(' in PvE'),
              ),
              findsOneWidget,
            );
            expect(selection.item?.name, 'Synthetic component');
          } else {
            expect(
              find.descendant(
                of: strip,
                matching: find.text('Item data unavailable'),
              ),
              findsOneWidget,
            );
            expect(find.text('Synthetic component'), findsNothing);
            expect(selection.item, isNull);
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
      expect(
        find.descendant(
          of: find.byKey(const Key('answer-strip')),
          matching: find.textContaining('Current advice · saved '),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('in PvE'), findsWidgets);
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('answer-strip')),
          matching: find.byTooltip('Close history inspection'),
        ),
      );
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
      final panel = find.byType(HistoryPanel);
      final scroll = find.descendant(
        of: panel,
        matching: find.byType(Scrollable),
      );
      await tester.drag(scroll, const Offset(0, -350));
      await tester.pumpAndSettle();
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

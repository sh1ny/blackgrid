import 'package:blackgrid/application/scan_correction.dart';
import 'package:blackgrid/data/catalog_normalizer.dart';
import 'package:blackgrid/application/scan_epoch.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/title_matching.dart';
import 'package:blackgrid/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/m1/catalog/fixture.dart';
import '../support/m1_harness.dart';
import '../support/m1_widget_harness.dart';

CatalogItem _item(String id, String name, {bool? noFlea = false}) =>
    CatalogItem(
      id: id,
      name: name,
      normalizedName: name.toLowerCase(),
      width: 1,
      height: 1,
      noFlea: noFlea,
      minLevelForFlea: 0,
      fleaPrice: 400,
      quoteAt: fixtureNow,
      sellOffers: const [
        CashOffer(traderId: 'trader-a', currency: 'RUB', price: 120),
      ],
    );

CatalogSnapshot _snapshot(
  Map<String, String> names, {
  Map<String, CatalogItem> extra = const {},
}) => CatalogSnapshot(
  mode: GameMode.pvp,
  revision: 'card-revision',
  observedAt: fixtureNow,
  items: {
    for (final e in names.entries) e.key: _item(e.key, e.value),
    ...extra,
  },
  traders: const {
    'trader-a': CatalogTrader(id: 'trader-a', name: 'Synthetic Alpha'),
  },
  requirements: const [],
  sourceTimestamps: {for (final key in catalogDatasets) key: fixtureNow},
);

/// The epoch the M1 harness's services hold once initialised in PvP.
const _harnessEpoch = ScanEpoch(2, 2);

ScanCorrectionOffer _offer({
  int reportId = 7,
  String text = 'plate',
  List<TitleCandidate> candidates = const [
    TitleCandidate('bravo', .87),
    TitleCandidate('gone', .61),
    TitleCandidate('charlie', .5),
  ],
}) => ScanCorrectionOffer(
  reportId: reportId,
  epoch: _harnessEpoch,
  mode: GameMode.pvp,
  catalogRevision: 'card-revision',
  ocrText: text,
  candidates: candidates,
  query: text,
);

const _names = {
  'alpha': 'Alpha shown',
  'bravo': 'Bravo plate',
  'charlie': 'Charlie plate',
};

/// Mounts the app on Map, shows `alpha` and offers a correction.
Future<M1Harness> _arrange(
  WidgetTester tester, {
  Map<String, String> names = _names,
  Map<String, CatalogItem> extra = const {},
  ScanCorrectionOffer? offer,
  bool showAlpha = true,
}) async {
  final h = await pumpM1(tester);
  h.services.catalog.snapshot = _snapshot(names, extra: extra);
  final selection = h.services.selection;
  if (showAlpha) {
    await tester.runAsync(
      () =>
          selection.selectManual(h.services.catalog.snapshot!.items['alpha']!),
    );
  }
  selection.offerCorrection(offer ?? _offer());
  await tester.tap(find.byKey(const Key('nav-map')));
  await tester.pumpAndSettle();
  return h;
}

GridPanel _panel(WidgetTester tester) => tester.widget<GridPanel>(
  find.byWidgetPredicate(
    (w) => w is GridPanel && w.icon == Icons.center_focus_strong,
  ),
);

TextEditingController _field(WidgetTester tester, {required int index}) =>
    tester
        .widget<TextField>(
          find
              .byKey(const Key('correction-query'), skipOffstage: false)
              .at(index),
        )
        .controller!;

void main() {
  testWidgets(
    'Map card shows the offer next to the item and a pick selects it',
    (tester) async {
      final h = await _arrange(tester);
      expect(find.text('Alpha shown'), findsOneWidget);
      expect(find.byKey(const Key('correction-offer')), findsOneWidget);
      expect(find.text('Scan #7 not accepted — pick the item'), findsOneWidget);
      // Candidates carry their similarity; the one the catalog lacks is out.
      expect(find.text('Bravo plate • 0.87'), findsOneWidget);
      expect(find.text('Charlie plate • 0.50'), findsOneWidget);
      expect(find.textContaining('0.61'), findsNothing);

      await tester.runAsync(
        () => tester.tap(find.byKey(const Key('correction-candidate-bravo'))),
      );
      await tester.pumpAndSettle();
      expect(h.services.selection.selectedId, 'bravo');
      expect(h.services.selection.correction?.reportId, 7);
      expect(h.services.selection.scan, isNull);
      expect(find.byKey(const Key('correction-offer')), findsNothing);
      expect(find.text('Corrected scan'), findsOneWidget);
      expect(find.text('Bravo plate'), findsOneWidget);
    },
  );

  testWidgets('the offer text is shared by the mounted Scanner and Map cards', (
    tester,
  ) async {
    await _arrange(tester);
    expect(find.byKey(const Key('correction-query')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('correction-query')), 'brav');
    await tester.pump();
    expect(_field(tester, index: 0).text, 'brav');
    expect(_field(tester, index: 1).text, 'brav');
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('correction-query')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('correction-query')))
          .controller!
          .text,
      'brav',
    );
    await tester.enterText(find.byKey(const Key('correction-query')), 'charl');
    await tester.pump();
    expect(_field(tester, index: 0).text, 'charl');
    expect(_field(tester, index: 1).text, 'charl');
  });

  testWidgets('a picked correction is titled and aged as not accepted', (
    tester,
  ) async {
    final h = await _arrange(tester);
    await tester.runAsync(
      () => h.services.selection.selectCorrection(7, 'bravo'),
    );
    await tester.pumpAndSettle();
    final panel = _panel(tester);
    expect(panel.title, 'Corrected scan');
    expect(
      panel.subtitle,
      'Corrected from scan #7 • 0 s ago • not an accepted scan',
    );
  });

  testWidgets('Dismiss removes the offer and keeps the item', (tester) async {
    final h = await _arrange(tester);
    await tester.tap(find.byKey(const Key('correction-dismiss')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('correction-offer')), findsNothing);
    expect(h.services.selection.correctionOffer, isNull);
    expect(find.text('Alpha shown'), findsOneWidget);
    expect(_panel(tester).title, 'Current manual inspection');
  });

  testWidgets('the offer shows in place of the hint when nothing is selected', (
    tester,
  ) async {
    await _arrange(tester, showAlpha: false);
    expect(find.byKey(const Key('correction-offer')), findsOneWidget);
    expect(find.text('Find an item to inspect'), findsNothing);
    expect(find.byKey(const Key('correction-offer-status')), findsNothing);
  });

  testWidgets('an unresolved selection keeps its status beside the offer', (
    tester,
  ) async {
    final h = await pumpM1(tester);
    h.services.catalog.snapshot = _snapshot(_names);
    final selection = h.services.selection;
    await tester.runAsync(
      () =>
          selection.selectManual(h.services.catalog.snapshot!.items['alpha']!),
    );
    // The live catalog loses the selected identity, then an offer arrives.
    h.services.catalog.snapshot = _snapshot({
      'bravo': 'Bravo plate',
      'charlie': 'Charlie plate',
    });
    selection.offerCorrection(_offer());
    await tester.tap(find.byKey(const Key('nav-map')));
    await tester.pumpAndSettle();
    expect(selection.selectedId, 'alpha');
    expect(selection.item, isNull);
    expect(find.byKey(const Key('correction-offer')), findsOneWidget);
    expect(
      find.text('Identity retained • catalog unavailable'),
      findsOneWidget,
    );
  });

  testWidgets('search results are capped at 8 and an empty search says so', (
    tester,
  ) async {
    final names = {
      'alpha': 'Alpha shown',
      for (var i = 0; i < 10; i++) 'f$i': 'Filler $i',
    };
    await _arrange(
      tester,
      names: names,
      offer: _offer(text: 'filler'),
    );
    expect(
      find.byWidgetPredicate(
        (w) => w.key.toString().startsWith("[<'correction-result-"),
      ),
      findsNWidgets(correctionSearchLimit),
    );
    await tester.enterText(find.byKey(const Key('correction-query')), 'zzzz');
    await tester.pump();
    expect(find.byKey(const Key('correction-no-match')), findsOneWidget);
    expect(find.text('No items match'), findsOneWidget);
  });

  group('same-name candidates', () {
    // IDs end in the suffixes the offer shows.
    const flea = 'weapon-4b423c';
    const noFlea = 'weapon-045d88';

    ScanCorrectionOffer weaponOffer({
      String text = 'zzzz',
      List<TitleCandidate> candidates = const [
        TitleCandidate(flea, 1.0),
        TitleCandidate(noFlea, .909),
      ],
    }) => _offer(text: text, candidates: candidates);

    Map<String, CatalogItem> weapons({bool? secondNoFlea = true}) => {
      flea: _item(flea, 'Weapon case'),
      noFlea: _item(noFlea, 'Weapon case', noFlea: secondNoFlea),
    };

    testWidgets('same-name candidates show flea status and id suffix', (
      tester,
    ) async {
      await _arrange(tester, extra: weapons(), offer: weaponOffer());
      final first = find.text('Weapon case · flea · 4b423c • 1.00');
      final second = find.text('Weapon case · no flea · 045d88 • 0.91');
      expect(first, findsOneWidget);
      expect(second, findsOneWidget);
      final order = [
        for (final w in tester.widgetList(
          find.byWidgetPredicate(
            (w) => w.key.toString().startsWith("[<'correction-candidate-"),
          ),
        ))
          (w.key! as ValueKey<String>).value,
      ];
      expect(order, [
        'correction-candidate-$flea',
        'correction-candidate-$noFlea',
      ]);
    });

    testWidgets('a lone same-name candidate shows name and score only', (
      tester,
    ) async {
      await _arrange(
        tester,
        extra: {
          flea: _item(flea, 'Weapon case'),
          'item-case': _item('item-case', 'Item case'),
        },
        offer: weaponOffer(
          candidates: const [
            TitleCandidate(flea, 1.0),
            TitleCandidate('item-case', .8),
          ],
        ),
      );
      expect(find.text('Weapon case • 1.00'), findsOneWidget);
      expect(find.text('Item case • 0.80'), findsOneWidget);
      expect(find.textContaining('flea'), findsNothing);
    });

    testWidgets('unknown flea status shows flea unknown', (tester) async {
      await _arrange(
        tester,
        extra: weapons(secondNoFlea: null),
        offer: weaponOffer(),
      );
      expect(
        find.text('Weapon case · flea unknown · 045d88 • 0.91'),
        findsOneWidget,
      );
      expect(find.text('Weapon case · flea · 045d88 • 0.91'), findsNothing);
    });

    testWidgets('a search row in a same-name group is labelled', (
      tester,
    ) async {
      String id(int n) => 'wc0000${n.toString().padLeft(2, '0')}';
      await _arrange(
        tester,
        extra: {
          for (var n = 0; n < 12; n++)
            id(n): _item(id(n), 'Weapon case', noFlea: n.isOdd),
        },
        offer: _offer(
          text: 'weapon case',
          candidates: [for (var n = 0; n < 5; n++) TitleCandidate(id(n), 1.0)],
        ),
      );
      // The sixth variant is not a candidate; the search finds it.
      expect(find.byKey(Key('correction-candidate-${id(5)}')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(Key('correction-result-${id(5)}')),
          matching: find.text('Weapon case · no flea · 000005'),
        ),
        findsOneWidget,
      );
      expect(find.text('Weapon case · flea · 000000 • 1.00'), findsOneWidget);
    });

    testWidgets('picking the no-flea variant selects it', (tester) async {
      final h = await _arrange(tester, extra: weapons(), offer: weaponOffer());
      final pick = find.byKey(const Key('correction-candidate-$noFlea'));
      await tester.ensureVisible(pick);
      await tester.pumpAndSettle();
      await tester.runAsync(() => tester.tap(pick));
      await tester.pumpAndSettle();
      expect(h.services.selection.selectedId, noFlea);
      expect(h.services.selection.correction?.reportId, 7);
      expect(find.text('Corrected scan'), findsOneWidget);
      expect(find.text('Weapon case'), findsOneWidget);
    });
  });
}

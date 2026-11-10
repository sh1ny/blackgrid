import 'package:blackgrid/application/scan_correction.dart';
import 'package:blackgrid/data/catalog_normalizer.dart';
import 'package:blackgrid/application/scan_epoch.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/title_matching.dart';
import 'package:blackgrid/ui/panels.dart';
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
  Size size = const Size(1672, 941),
  double scale = 1,
}) async {
  final h = await pumpM1(tester, size: size, scale: scale);
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

Finder _answerText(String text) => find.descendant(
  of: find.byKey(const Key('answer-strip')),
  matching: find.text(text),
);

TextEditingController _field(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const Key('correction-query')))
    .controller!;

void main() {
  for (final selected in [false, true]) {
    testWidgets(
      'correction stays usable at enlarged text with selected=$selected',
      (tester) async {
        await _arrange(
          tester,
          showAlpha: selected,
          size: const Size(960, 720),
          scale: 2,
        );
        expect(find.byKey(const Key('correction-offer')), findsOneWidget);
        final query = find.byKey(const Key('correction-query'));
        await tester.ensureVisible(query);
        await tester.pumpAndSettle();
        expect(query, findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('the offer says the last scan was not accepted without its '
      'number', (tester) async {
    await _arrange(tester);
    expect(_answerText('Alpha shown'), findsOneWidget);
    expect(find.byKey(const Key('correction-offer')), findsOneWidget);
    expect(find.text('Last scan not accepted — pick the item'), findsOneWidget);
    expect(find.textContaining('#7'), findsNothing);
    expect(find.textContaining('Scan #'), findsNothing);
    expect(find.text('Read: plate'), findsOneWidget);
    expect(find.byKey(const Key('correction-query')), findsOneWidget);
    expect(_field(tester).text, 'plate');
  });

  testWidgets('the offer lists candidates in rank order without scores', (
    tester,
  ) async {
    final h = await _arrange(tester);
    // The candidate the catalog lacks is out; the rest keep their rank.
    final order = [
      for (final w in tester.widgetList(
        find.byWidgetPredicate(
          (w) => w.key.toString().startsWith("[<'correction-candidate-"),
        ),
      ))
        (w.key! as ValueKey<String>).value,
    ];
    expect(order, [
      'correction-candidate-bravo',
      'correction-candidate-charlie',
    ]);
    for (final (id, name) in [
      ('bravo', 'Bravo plate'),
      ('charlie', 'Charlie plate'),
    ]) {
      expect(
        find.descendant(
          of: find.byKey(Key('correction-candidate-$id')),
          matching: find.text(name),
        ),
        findsOneWidget,
      );
    }
    expect(find.textContaining('0.87'), findsNothing);
    expect(find.textContaining('0.50'), findsNothing);
    expect(find.textContaining('0.61'), findsNothing);
    expect(find.textContaining(' • 0.'), findsNothing);

    await tester.runAsync(
      () => tester.tap(find.byKey(const Key('correction-candidate-bravo'))),
    );
    await tester.pumpAndSettle();
    expect(h.services.selection.selectedId, 'bravo');
    expect(h.services.selection.correction?.reportId, 7);
    expect(h.services.selection.scan, isNull);
    expect(find.byKey(const Key('correction-offer')), findsNothing);
    expect(
      _answerText('Corrected from a scan · just now · chosen by hand'),
      findsOneWidget,
    );
    expect(_answerText('Bravo plate'), findsOneWidget);
  });

  testWidgets('the shared offer and query persist across Scanner and Map', (
    tester,
  ) async {
    await _arrange(tester);
    expect(find.byKey(const Key('correction-query')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('correction-query')), 'brav');
    await tester.pump();
    expect(_field(tester).text, 'brav');
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
    expect(_field(tester).text, 'charl');
  });

  testWidgets('a picked correction is titled and aged as not accepted', (
    tester,
  ) async {
    final h = await _arrange(tester);
    await tester.runAsync(
      () => h.services.selection.selectCorrection(7, 'bravo'),
    );
    await tester.pumpAndSettle();
    // Item details live on Scanner; the Map inspector holds the working lists.
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    await showInspectorPanel(tester, 'Corrected scan');
    final panel = _panel(tester);
    expect(panel.title, 'Corrected scan');
    expect(panel.subtitle, 'Corrected from a scan • 0 s ago • chosen by hand');
    expect(panel.subtitle, isNot(contains('#7')));
  });

  testWidgets('a search pick is labelled corrected from a scan', (
    tester,
  ) async {
    final h = await _arrange(
      tester,
      extra: {'delta': _item('delta', 'Delta plate')},
    );
    // `delta` is not one of the candidates; only the search lists it.
    expect(find.byKey(const Key('correction-candidate-delta')), findsNothing);
    final result = find.byKey(const Key('correction-result-delta'));
    await tester.ensureVisible(result);
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(result));
    await tester.pumpAndSettle();
    expect(h.services.selection.selectedId, 'delta');
    expect(h.services.selection.correction?.reportId, 7);
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    await showInspectorPanel(tester, 'Corrected scan');
    expect(
      _panel(tester).subtitle,
      'Corrected from a scan • 0 s ago • chosen by hand',
    );
  });

  testWidgets('Dismiss removes the offer and keeps the item', (tester) async {
    final h = await _arrange(tester);
    await tester.tap(find.byKey(const Key('correction-dismiss')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('correction-offer')), findsNothing);
    expect(h.services.selection.correctionOffer, isNull);
    expect(_answerText('Alpha shown'), findsOneWidget);
    // Item details live on Scanner; the Map inspector holds the working lists.
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    await showInspectorPanel(tester, 'Picked item');
    expect(_panel(tester).title, 'Picked item');
  });

  testWidgets('the offer shows in place of the hint when nothing is selected', (
    tester,
  ) async {
    await _arrange(tester, showAlpha: false);
    expect(find.byKey(const Key('correction-offer')), findsOneWidget);
    expect(_answerText('Find an item'), findsNothing);
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
    expect(_answerText('Item data unavailable'), findsOneWidget);
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
      final first = find.text('Weapon case · flea · 4b423c');
      final second = find.text('Weapon case · no flea · 045d88');
      expect(first, findsOneWidget);
      expect(second, findsOneWidget);
      expect(find.textContaining('1.00'), findsNothing);
      expect(find.textContaining('0.91'), findsNothing);
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

    testWidgets('a lone same-name candidate shows its name only', (
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
      expect(find.text('Weapon case'), findsOneWidget);
      expect(find.text('Item case'), findsOneWidget);
      expect(find.textContaining('1.00'), findsNothing);
      expect(find.textContaining('0.80'), findsNothing);
      expect(find.textContaining('· flea'), findsNothing);
    });

    testWidgets('unknown flea status shows flea unknown', (tester) async {
      await _arrange(
        tester,
        extra: weapons(secondNoFlea: null),
        offer: weaponOffer(),
      );
      expect(find.text('Weapon case · flea unknown · 045d88'), findsOneWidget);
      expect(find.text('Weapon case · flea · 045d88'), findsNothing);
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
      expect(
        find.descendant(
          of: find.byKey(Key('correction-candidate-${id(0)}')),
          matching: find.text('Weapon case · flea · 000000'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('1.00'), findsNothing);
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
      expect(
        _answerText('Corrected from a scan · just now · chosen by hand'),
        findsOneWidget,
      );
      expect(_answerText('Weapon case'), findsOneWidget);
    });
  });
}

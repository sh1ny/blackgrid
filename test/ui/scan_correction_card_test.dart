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

CatalogItem _item(String id, String name) => CatalogItem(
  id: id,
  name: name,
  normalizedName: name.toLowerCase(),
  width: 1,
  height: 1,
  noFlea: false,
  minLevelForFlea: 0,
  fleaPrice: 400,
  quoteAt: fixtureNow,
  sellOffers: const [
    CashOffer(traderId: 'trader-a', currency: 'RUB', price: 120),
  ],
);

CatalogSnapshot _snapshot(Map<String, String> names) => CatalogSnapshot(
  mode: GameMode.pvp,
  revision: 'card-revision',
  observedAt: fixtureNow,
  items: {for (final e in names.entries) e.key: _item(e.key, e.value)},
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
  ScanCorrectionOffer? offer,
  bool showAlpha = true,
}) async {
  final h = await pumpM1(tester);
  h.services.catalog.snapshot = _snapshot(names);
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
}

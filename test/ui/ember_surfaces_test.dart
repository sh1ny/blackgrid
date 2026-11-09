import 'package:blackgrid/ui/ember/ember_theme.dart';
import 'package:blackgrid/ui/ember/ember_tokens.dart';
import 'package:blackgrid/ui/panels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/m1_widget_harness.dart';
import '../support/map_widget_harness.dart';

Future<void> _pumpPanels(WidgetTester tester, Brightness brightness) =>
    tester.pumpWidget(
      MaterialApp(
        theme: blackgridTheme(brightness),
        themeAnimationDuration: Duration.zero,
        home: Scaffold(
          body: Column(
            children: [
              GridPanel(
                title: 'Plain panel',
                icon: Icons.search,
                child: const Text('body'),
              ),
              CollapsibleGridPanel(
                title: 'Folding panel',
                icon: Icons.map_outlined,
                expanded: true,
                onExpandedChanged: (_) {},
                child: const Text('folded body'),
              ),
            ],
          ),
        ),
      ),
    );

Material _surface(WidgetTester tester, Type panel) => tester.widget<Material>(
  find
      .descendant(of: find.byType(panel), matching: find.byType(Material))
      .first,
);

void main() {
  testWidgets(
    'docked panels use panel colour, hairline and no elevation in both rooms',
    (tester) async {
      for (final brightness in Brightness.values) {
        await _pumpPanels(tester, brightness);
        final ember = blackgridTheme(brightness).extension<EmberColors>()!;
        for (final (panel, title) in [
          (GridPanel, 'Plain panel'),
          (CollapsibleGridPanel, 'Folding panel'),
        ]) {
          final surface = _surface(tester, panel);
          expect(surface.color, ember.panel, reason: '$panel colour');
          expect(surface.elevation, 0, reason: '$panel elevation');
          expect(surface.shadowColor, isNull, reason: '$panel shadow');
          final shape = surface.shape! as RoundedRectangleBorder;
          expect(shape.side.color, ember.hairline, reason: '$panel hairline');
          expect(shape.side.width, 1);
          expect(shape.borderRadius, BorderRadius.circular(EmberRadius.l));

          final padding = tester.widget<Padding>(
            find
                .descendant(
                  of: find.byType(panel),
                  matching: find.byType(Padding),
                )
                .first,
          );
          expect(padding.padding, const EdgeInsets.all(18));

          final icon = tester.widget<Icon>(
            find
                .descendant(of: find.byType(panel), matching: find.byType(Icon))
                .first,
          );
          expect(icon.size, EmberSize.icon);
          expect(icon.color, ember.inkSecondary);

          final style = tester.widget<Text>(find.text(title)).style!;
          expect(style.fontFamily, EmberType.uiHeading.fontFamily);
          expect(style.fontWeight, EmberType.uiHeading.fontWeight);
          expect(style.fontSize, EmberType.uiHeading.fontSize);
          expect(style.color, ember.ink);
        }
      }
    },
  );

  testWidgets('section labels are sentence case', (tester) async {
    await pumpM1(tester);
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    expect(find.text('Manual inspection'), findsNothing);
    expect(find.text('Recent scans'), findsNothing);
    for (final old in ['LIVE SCAN', 'MANUAL INSPECTION', 'RECENT SCANS']) {
      expect(find.text(old), findsNothing);
    }
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Live scan'), findsOneWidget);
    expect(find.text('LIVE SCAN'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nav-map')));
    await tester.pumpAndSettle();
    final titles = [
      for (final panel in tester.widgetList<GridPanel>(find.byType(GridPanel)))
        panel.title,
    ];
    expect(titles, isNotEmpty);
    for (final title in titles) {
      expect(title, isNot(title.toUpperCase()), reason: '"$title" is shouting');
    }
  });

  testWidgets('brand lockup keeps its capitals', (tester) async {
    await pumpM1(tester);
    expect(find.text('BLACKGRID'), findsOneWidget);
    expect(find.text('TRACK. PLAN. SURVIVE.'), findsOneWidget);
  });

  testWidgets(
    'map message uses dark-room ink on the map ground in the light room',
    (tester) async {
      final harness = await pumpMapFixture(tester, artwork: false);
      expect(
        Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
        Brightness.light,
        reason: 'the test platform defaults to the light room',
      );
      final error = harness.services.maps.error;
      expect(error, isNotNull, reason: 'artwork must be missing here');
      final text = tester.widget<Text>(find.text(error!));
      // The map ground is dark in both rooms (DESIGN.md X6), so text drawn on
      // it takes the dark room's ink.
      expect(text.style?.color, EmberColors.dark.inkSecondary);
    },
  );

  testWidgets('the selected search result keeps opaque text', (tester) async {
    await pumpM1(tester);
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Synthetic component');
    await tester.pumpAndSettle();
    final tile = tester.widget<ListTile>(
      find.descendant(
        of: find.byKey(const Key('top-search-results')),
        matching: find.widgetWithText(ListTile, 'Synthetic component'),
      ),
    );
    final ember = Theme.of(tester.element(find.byType(Scaffold).first))
        .extension<EmberColors>()!;
    expect(tile.selected, isTrue);
    // selectedColor is the text and icon colour, so it must be opaque; the
    // soft accent is a fill and belongs in selectedTileColor.
    expect(tile.selectedColor, ember.accentText);
    expect(tile.selectedTileColor, ember.accentSoft);
  });
}

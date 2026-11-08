import 'package:blackgrid/ui/ember/ember_theme.dart';
import 'package:blackgrid/ui/ember/ember_tokens.dart';
import 'package:blackgrid/ui/panels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/m1_widget_harness.dart';

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
    expect(find.text('Live scan'), findsOneWidget);
    expect(find.text('Manual inspection'), findsOneWidget);
    expect(find.text('Recent scans'), findsOneWidget);
    for (final old in ['LIVE SCAN', 'MANUAL INSPECTION', 'RECENT SCANS']) {
      expect(find.text(old), findsNothing);
    }

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
}

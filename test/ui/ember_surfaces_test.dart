import 'dart:async';

import 'package:blackgrid/application/local_stats_controller.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/local_stats.dart';
import 'package:blackgrid/domain/raid_lifecycle.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:blackgrid/ui/ember/ember_theme.dart';
import 'package:blackgrid/ui/ember/ember_tokens.dart';
import 'package:blackgrid/ui/map_inspector.dart';
import 'package:blackgrid/ui/panels.dart';
import 'package:blackgrid/ui/stats_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// A stats store that holds nothing; the dialog only needs it to answer.
final class _EmptyStatsStore implements LocalStatsStore {
  @override
  Future<void> recordRaid(RaidStatRow row) async {}

  @override
  Future<void> recordSale(FleaSaleRow row) async {}

  @override
  Future<LocalStatsTotals> readTotals(GameMode mode) async =>
      LocalStatsTotals.empty;

  @override
  Future<DateTime?> readSince() async => null;

  @override
  Future<void> clear(DateTime now) async {}
}

/// Expects the open dialog to carry the Ember dialog surface of [ember], with
/// 12px corners and its title in the Title role.
void _expectEmberDialogSurface(
  WidgetTester tester,
  EmberColors ember,
  String title,
) {
  final surface = tester.widget<Material>(
    find
        .descendant(of: find.byType(Dialog), matching: find.byType(Material))
        .first,
  );
  expect(surface.color, ember.raised);
  final shape = surface.shape! as RoundedRectangleBorder;
  expect(shape.borderRadius, BorderRadius.circular(EmberRadius.l));
  expect(shape.side.color, ember.hairlineStrong);
  final style = DefaultTextStyle.of(tester.element(find.text(title))).style;
  expect(style.fontFamily, EmberType.title.fontFamily);
  expect(style.fontSize, EmberType.title.fontSize);
  expect(style.color, ember.ink);
}

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
    final h = await pumpM1(tester);
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    expect(find.text('Scan evidence'), findsOneWidget);
    expect(find.text('Manual inspection'), findsNothing);
    expect(find.text('Recent scans'), findsNothing);
    for (final old in [
      'SCAN EVIDENCE',
      'LIVE SCAN',
      'MANUAL INSPECTION',
      'RECENT SCANS',
    ]) {
      expect(find.text(old), findsNothing);
    }
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(TextButton, 'Settings'));
      await tester.pumpAndSettle();
      await h.services.localProgress.settled;
    });
    expect(find.byKey(const Key('settings-title-liveScan')), findsOneWidget);
    expect(find.text('LIVE SCAN'), findsNothing);
    // Recent scans lives in Diagnostics, which starts collapsed.
    expect(find.text('Recent scans'), findsNothing);
    final toggle = find.byKey(const Key('settings-diagnostics-toggle'));
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('Recent scans'), findsOneWidget);
    expect(find.text('RECENT SCANS'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Back to Scanner'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nav-map')));
    await tester.pumpAndSettle();
    // The map picker shows the map's display name, not shouted.
    final picker = find.byKey(const Key('map-picker'));
    expect(picker, findsOneWidget);
    final pickerLabel = tester
        .widget<Text>(find.descendant(of: picker, matching: find.byType(Text)))
        .data!;
    expect(pickerLabel, isNotEmpty);
    expect(pickerLabel, isNot(pickerLabel.toUpperCase()));
    expect(find.text(pickerLabel), findsWidgets);
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

  testWidgets('interface-theme: Stats dialog', (tester) async {
    for (final brightness in Brightness.values) {
      final lifecycle = StreamController<RaidTransition>.broadcast(sync: true);
      addTearDown(lifecycle.close);
      final controller = LocalStatsController(
        transitions: lifecycle.stream,
        modeChanges: ValueNotifier(GameMode.pvp),
        mode: () => GameMode.pvp,
        store: _EmptyStatsStore(),
        clock: () => DateTime(2026, 11, 2, 9),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: blackgridTheme(brightness),
          themeAnimationDuration: Duration.zero,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showStats(context, controller),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final ember = blackgridTheme(brightness).extension<EmberColors>()!;
      _expectEmberDialogSurface(tester, ember, 'PvP stats');
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(FilledButton),
        ),
        findsOneWidget,
        reason: 'one primary action in $brightness',
      );
      expect(find.widgetWithText(FilledButton, 'Close'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Clear stats'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('interface-theme: Confirm dialog', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final h = (await tester.runAsync(MapWidgetHarness.create))!;
    addTearDown(h.dispose);
    final pin = CustomPin(
      id: 'pin-camp',
      mapId: 'shoreline',
      x: .8,
      y: .8,
      frame: 'legacy-normalized',
      frameRevision: 0,
      label: 'Camp',
      updatedAt: DateTime.utc(2026),
    );
    expect(
      await tester.runAsync(() => h.services.settings.savePin(pin)),
      isTrue,
    );
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: blackgridTheme(brightness),
          themeAnimationDuration: Duration.zero,
          home: Scaffold(
            body: SingleChildScrollView(
              child: MapInspector(
                services: h.services,
                clock: () => DateTime.utc(2026),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pin-remove-pin-camp')));
      await tester.pumpAndSettle();

      final ember = blackgridTheme(brightness).extension<EmberColors>()!;
      _expectEmberDialogSurface(tester, ember, 'Remove pin record?');
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(FilledButton),
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Remove'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(h.services.settings.pins, hasLength(1), reason: 'Escape cancels');
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('interface-theme: Marker list sheet', (tester) async {
    await pumpMapFixture(tester);
    for (final brightness in Brightness.values) {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Browse markers'));
      await tester.pumpAndSettle();

      final ember = blackgridTheme(brightness).extension<EmberColors>()!;
      final surface = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(surface.color, ember.panel, reason: 'panel in $brightness');
      final shape = surface.shape! as RoundedRectangleBorder;
      expect(
        shape.borderRadius,
        const BorderRadius.vertical(top: Radius.circular(EmberRadius.l)),
      );
      final title =
          DefaultTextStyle.of(
            tester.element(find.text('Visible map markers and pins')),
          ).style.merge(
            tester
                .widget<Text>(find.text('Visible map markers and pins'))
                .style,
          );
      expect(title.fontFamily, EmberType.title.fontFamily);
      expect(title.fontSize, EmberType.title.fontSize);
      expect(title.color, ember.ink);

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    }
  });
}

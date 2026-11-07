import 'dart:convert';

import 'package:blackgrid/application/map_controller.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/map_coordinates.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:blackgrid/maps/prepared_map.dart';
import 'package:blackgrid/ui/pin_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../fixtures/m1/catalog/fixture.dart';
import '../support/map_widget_harness.dart';

Map<String, Object?> _popupMarkerJson({
  required String id,
  required String category,
  required String filterKey,
  required String name,
  required String floorId,
  required double x,
  required double z,
  Map<String, Object?> details = const {},
  Map<String, Object?> source = const {'mapId': 'shoreline'},
}) => {
  'id': id,
  'category': category,
  'filterKey': filterKey,
  'name': name,
  'floorId': floorId,
  'position': {'x': x, 'z': z},
  'details': details,
  'source': source,
  'outline': const [],
};

Map<String, List<PreparedMarker>> _popupMarkers(
  MapController controller,
  Map<String, List<Map<String, Object?>>> inventory,
) => {
  for (final map in controller.pack!.maps)
    map.id: switch (inventory[map.id]) {
      final markers? => [
        for (final marker in markers)
          PreparedMarker.fromJson(Map<String, dynamic>.from(marker)),
      ],
      null => map.markers,
    },
};

Finder get _viewport => find.byKey(const Key('native-map-viewport'));
Finder get _markerBrowser => find.ancestor(
  of: find.byIcon(Icons.list),
  matching: find.byType(OutlinedButton),
);

Offset _project(WidgetTester tester, MapWidgetHarness h, ScenePoint point) {
  final projected = h.services.maps.transform.sceneToViewport(point);
  return tester.getTopLeft(_viewport) + Offset(projected.x, projected.y);
}

Offset _uncoveredArtworkPoint(WidgetTester tester, MapWidgetHarness h) {
  final viewport = tester.getRect(_viewport);
  final popup = tester.getRect(find.byKey(const ValueKey('marker-popup')));
  for (final point in [
    ScenePoint(20, 128),
    ScenePoint(236, 128),
    ScenePoint(128, 20),
    ScenePoint(128, 236),
  ]) {
    final screen = _project(tester, h, point);
    final local = screen - viewport.topLeft;
    if (viewport.contains(screen) &&
        !popup.contains(screen) &&
        h.services.maps.pinCreationAt(ViewportPoint(local.dx, local.dy)) !=
            null) {
      return screen;
    }
  }
  throw StateError('No uncovered artwork point remains in the fixture.');
}

Future<void> _select(
  WidgetTester tester,
  MapWidgetHarness h,
  ScenePoint p,
) async {
  await tester.tapAt(_project(tester, h, p));
  await settleMapFixture(tester, h);
}

Future<void> _openMarkerBrowser(WidgetTester tester) async {
  await tester.tap(_markerBrowser);
  await tester.pumpAndSettle();
}

Future<Finder> _ensureBrowserEntryVisible(
  WidgetTester tester,
  String title,
) async {
  final row = find.widgetWithText(ListTile, title);
  final list = find.byKey(const ValueKey('marker-browser-list'));
  final scrollable = find.descendant(
    of: list,
    matching: find.byType(Scrollable),
  );
  await tester.scrollUntilVisible(row, 120, scrollable: scrollable);
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(tester.element(row), alignment: .5);
  await tester.pumpAndSettle();
  expect(row.hitTestable(), findsOneWidget);
  return row;
}

Future<void> _chooseBrowserEntry(WidgetTester tester, String title) async {
  final row = await _ensureBrowserEntryVisible(tester, title);
  await tester.tap(row);
  await tester.pumpAndSettle();
}

String? _focusedTooltip() {
  String? message;
  FocusManager.instance.primaryFocus?.context?.visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is Tooltip) {
      message = widget.message;
      return false;
    }
    return true;
  });
  return message;
}

void _expectFocusInside(Finder ancestor) {
  final focusedWidget = FocusManager.instance.primaryFocus?.context?.widget;
  expect(focusedWidget, isNotNull);
  expect(
    find.ancestor(of: find.byWidget(focusedWidget!), matching: ancestor),
    findsOneWidget,
  );
}

void main() {
  testWidgets('selection by badge browser and accessibility preserves view', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final h = await pumpMapFixture(tester);
      final transform = h.services.maps.transform;
      final scale = transform.scale;
      final viewPoint = transform.sceneToViewport(ScenePoint(64, 64));
      final viewCoordinates = (x: viewPoint.x, y: viewPoint.y);
      await _select(tester, h, ScenePoint(128, 128));
      expect(find.byTooltip('Close marker details'), findsOneWidget);
      expect(h.services.maps.transform.scale, scale);
      final afterSelection = h.services.maps.transform.sceneToViewport(
        ScenePoint(64, 64),
      );
      expect(afterSelection.x, viewCoordinates.x);
      expect(afterSelection.y, viewCoordinates.y);
      await tester.tap(find.byTooltip('Close marker details'));
      await settleMapFixture(tester, h);
      await _openMarkerBrowser(tester);
      await _chooseBrowserEntry(tester, 'Ground hazard');
      await settleMapFixture(tester, h);
      expect(find.byTooltip('Close marker details'), findsOneWidget);
      expect(h.services.maps.transform.scale, scale);
      final afterBrowser = h.services.maps.transform.sceneToViewport(
        ScenePoint(64, 64),
      );
      expect(afterBrowser.x, viewCoordinates.x);
      expect(afterBrowser.y, viewCoordinates.y);
      await tester.tap(find.byTooltip('Close marker details'));
      await settleMapFixture(tester, h);
      final painter = tester
          .widget<CustomPaint>(
            find
                .descendant(of: _viewport, matching: find.byType(CustomPaint))
                .first,
          )
          .painter!;
      final semanticMarker = painter
          .semanticsBuilder!(tester.getSize(_viewport))
          .singleWhere(
            (target) =>
                target.properties.label?.startsWith('Ground exit,') == true,
          );
      semanticMarker.properties.onTap!();
      await settleMapFixture(tester, h);
      expect(find.byTooltip('Close marker details'), findsOneWidget);
      final afterAccessibility = h.services.maps.transform.sceneToViewport(
        ScenePoint(64, 64),
      );
      expect(afterAccessibility.x, viewCoordinates.x);
      expect(afterAccessibility.y, viewCoordinates.y);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('selecting another marker replaces the bubble', (tester) async {
    final h = await pumpMapFixture(tester);
    await _select(tester, h, ScenePoint(128, 128));
    expect(find.byTooltip('Close marker details'), findsOneWidget);
    await _openMarkerBrowser(tester);
    await _chooseBrowserEntry(tester, 'Ground hazard');
    await settleMapFixture(tester, h);
    expect(find.byTooltip('Close marker details'), findsOneWidget);
    expect(find.text('Ground exit'), findsNothing);
    expect(find.text('Ground hazard'), findsOneWidget);
  });

  testWidgets('stale browser result after content replacement is rejected', (
    tester,
  ) async {
    final h = await pumpMapFixture(tester);
    await _select(tester, h, ScenePoint(128, 128));
    await _openMarkerBrowser(tester);
    final generation = h.services.maps.contentGeneration;
    await tester.runAsync(() => h.services.settings.setMap('thelab'));
    await settleMapFixture(tester, h);
    expect(h.services.maps.contentGeneration, generation + 1);
    final staleRow = await _ensureBrowserEntryVisible(tester, 'Ground exit');
    await tester.tap(staleRow);
    await tester.pumpAndSettle();
    expect(find.text('Visible map markers and pins'), findsNothing);
    expect(find.byTooltip('Close marker details'), findsNothing);
    expect(h.services.maps.selectedMarkerProjection, isNull);
    await _openMarkerBrowser(tester);
    await _ensureBrowserEntryVisible(tester, 'Ground exit');
    expect(
      await tester.runAsync(
        () => h.services.settings.setMarker('PmcExtracts', false),
      ),
      isTrue,
    );
    await settleMapFixture(tester, h);
    final filteredRow = await _ensureBrowserEntryVisible(tester, 'Ground exit');
    await tester.tap(filteredRow);
    await tester.pumpAndSettle();
    expect(find.text('Visible map markers and pins'), findsNothing);
    expect(h.services.maps.selectedMarkerProjection, isNull);
  });

  testWidgets(
    'metadata generation swap updates all consumers without resetting view',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final h = await pumpMapFixture(tester);
        await tester.runAsync(
          () => h.services.settings.savePin(
            CustomPin(
              id: 'publication-pin',
              mapId: 'shoreline',
              x: .25,
              y: .25,
              frame: 'legacy-normalized',
              frameRevision: 0,
              label: 'Publication pin',
              updatedAt: DateTime.utc(2026),
            ),
          ),
        );
        await tester.runAsync(
          () => h.services.settings.setMarker('PmcExtracts', false),
        );
        await settleMapFixture(tester, h);
        await _select(tester, h, ScenePoint(64, 192));
        final map = h.services.maps;
        final originalMapId = map.selectedMapId;
        final originalTransform = map.transform;
        final originalFloor = map.floorSelection;
        final originalScene = map.scene;
        final originalPins = List.of(h.services.settings.pins);
        final originalFilters = Map.of(map.categoryVisibility);
        final generation = map.contentGeneration;
        final replacement = [
          _popupMarkerJson(
            id: 'new-switch',
            category: 'switches',
            filterKey: 'Switches',
            name: 'New switch',
            floorId: 'ground',
            x: 96,
            z: 96,
            details: {'id': 'new-switch'},
          ),
          _popupMarkerJson(
            id: 'new-exit',
            category: 'extracts',
            filterKey: 'SharedExtracts',
            name: 'New exit',
            floorId: 'ground',
            x: 160,
            z: 160,
            details: {
              'faction': 'PMC',
              'switches': ['new-switch'],
            },
            source: {'mapId': 'shoreline'},
          ),
        ];

        map.publishMarkers(
          _popupMarkers(map, {'shoreline': replacement, 'thelab': const []}),
          changed: true,
        );
        await settleMapFixture(tester, h);
        expect(map.selectedMapId, originalMapId);
        expect(map.transform.scale, originalTransform.scale);
        expect(map.transform.translationX, originalTransform.translationX);
        expect(map.transform.translationY, originalTransform.translationY);
        expect(map.floorSelection, same(originalFloor));
        expect(map.scene, same(originalScene));
        expect(h.services.settings.pins, originalPins);
        expect(map.categoryVisibility, originalFilters);
        expect(map.contentGeneration, generation + 1);
        expect(map.selectedMarkerProjection, isNull);
        expect(find.byTooltip('Close marker details'), findsNothing);

        final visibleIds = map.visibleMarkers().map(
          (marker) => marker.marker.id,
        );
        expect(visibleIds, ['new-switch', 'new-exit']);
        expect(map.applicableCategories, contains('Switches'));
        expect(map.applicableCategories, contains('SharedExtracts'));
        expect(map.applicableCategories, isNot(contains('Hazards')));
        final hitPoint = map
            .visibleMarkers()
            .singleWhere((marker) => marker.marker.id == 'new-exit')
            .viewportPoint;
        expect(map.hitTestMarker(hitPoint)?.marker.id, 'new-exit');

        await _openMarkerBrowser(tester);
        await _ensureBrowserEntryVisible(tester, 'New exit');
        expect(find.widgetWithText(ListTile, 'Ground exit'), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        final painter = tester
            .widget<CustomPaint>(
              find
                  .descendant(of: _viewport, matching: find.byType(CustomPaint))
                  .first,
            )
            .painter!;
        final accessibleNames = painter
            .semanticsBuilder!(tester.getSize(_viewport))
            .map((target) => target.properties.label ?? '')
            .toList();
        expect(accessibleNames.join(' '), contains('New exit'));
        expect(accessibleNames.join(' '), contains('New switch'));
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('unchanged marker snapshot retains selection', (tester) async {
    final h = await pumpMapFixture(tester);
    await _select(tester, h, ScenePoint(128, 128));
    final map = h.services.maps;
    final selectedId = map.selectedMarkerProjection?.marker.id;
    final generation = map.contentGeneration;
    // Refresh-status publication is owned by the separate map-data
    // controller slice; this map test covers structural no-op adoption.
    map.publishMarkers(_popupMarkers(map, const {}), changed: false);
    await settleMapFixture(tester, h);
    expect(map.contentGeneration, generation);
    expect(map.selectedMarkerProjection?.marker.id, selectedId);
    expect(find.byTooltip('Close marker details'), findsOneWidget);
  });

  testWidgets('refreshed marker selection shows new facts without a request', (
    tester,
  ) async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return http.Response('{}', 404);
    });
    final h = await pumpMapFixture(tester, client: client);
    final startupRequests = requests;
    final map = h.services.maps;
    map.publishMarkers(
      _popupMarkers(map, {
        'shoreline': [
          _popupMarkerJson(
            id: 'refreshed-exit',
            category: 'extracts',
            filterKey: 'PmcExtracts',
            name: 'Refreshed exit',
            floorId: 'ground',
            x: 128,
            z: 128,
            details: {
              'faction': 'PMC',
              'switches': ['refreshed-switch'],
            },
            source: {'mapId': 'shoreline'},
          ),
          _popupMarkerJson(
            id: 'refreshed-switch',
            category: 'switches',
            filterKey: 'Switches',
            name: 'Refreshed switch',
            floorId: 'ground',
            x: 160,
            z: 160,
            details: {'id': 'refreshed-switch'},
            source: {'mapId': 'shoreline'},
          ),
        ],
        'thelab': const [],
      }),
      changed: true,
    );
    await settleMapFixture(tester, h);
    expect(requests, startupRequests);
    await _select(tester, h, ScenePoint(128, 128));
    expect(requests, startupRequests);
    final popup = find.byKey(const ValueKey('marker-popup'));
    expect(
      find.descendant(of: popup, matching: find.text('Refreshed exit')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: popup,
        matching: find.text('Switch: Refreshed switch'),
      ),
      findsOneWidget,
    );
    expect(find.text('Ground exit'), findsNothing);
    final afterSelection = requests;
    await tester.pump();
    await tester.pump();
    expect(requests, afterSelection);
  });

  testWidgets('close clears selection bubble and linked highlights', (
    tester,
  ) async {
    final h = await pumpMapFixture(
      tester,
      extraMarkers: [
        {
          'id': 'popup-exit',
          'name': 'Popup exit',
          'floorId': 'ground',
          'category': 'extracts',
          'filterKey': 'PmcExtracts',
          'position': {'x': 96, 'z': 96},
          'details': {
            'switches': ['popup-switch'],
          },
          'source': {'mapId': 'shoreline'},
        },
        {
          'id': 'popup-switch',
          'name': 'Popup switch',
          'floorId': 'ground',
          'category': 'switches',
          'filterKey': 'Switches',
          'position': {'x': 160, 'z': 160},
          'details': {'id': 'popup-switch'},
          'source': {'mapId': 'shoreline'},
        },
      ],
    );
    await _select(tester, h, ScenePoint(96, 160));
    expect(h.services.maps.selectedMarkerProjection?.marker.id, 'popup-exit');
    final linkedSwitch = h.services.maps.visibleMarkers().singleWhere(
      (marker) => marker.marker.id == 'popup-switch',
    );
    expect(linkedSwitch.linkedHighlighted, isTrue);
    await tester.tap(find.byTooltip('Close marker details'));
    await settleMapFixture(tester, h);
    expect(h.services.maps.selectedMarkerProjection, isNull);
    expect(find.byTooltip('Close marker details'), findsNothing);
    expect(
      h.services.maps
          .visibleMarkers()
          .singleWhere((marker) => marker.marker.id == 'popup-switch')
          .linkedHighlighted,
      isFalse,
    );
  });

  testWidgets('selecting a pin clears marker and retains pin details', (
    tester,
  ) async {
    final h = await pumpMapFixture(tester);
    final pin = CustomPin(
      id: 'popup-pin',
      mapId: 'shoreline',
      x: .5,
      y: .5,
      frame: 'legacy-normalized',
      frameRevision: 0,
      label: 'Popup pin',
      updatedAt: DateTime.utc(2026),
    );
    await tester.runAsync(() => h.services.settings.savePin(pin));
    await settleMapFixture(tester, h);
    await _openMarkerBrowser(tester);
    await _chooseBrowserEntry(tester, 'Ground exit');
    await settleMapFixture(tester, h);
    expect(find.byTooltip('Close marker details'), findsOneWidget);
    await _openMarkerBrowser(tester);
    await _chooseBrowserEntry(tester, 'Popup pin');
    await settleMapFixture(tester, h);
    expect(find.textContaining('Popup pin'), findsOneWidget);
    expect(find.text('Edit pin'), findsOneWidget);
    expect(h.services.maps.selectedMarkerProjection, isNull);
    await tester.tap(find.text('Edit pin'));
    await tester.pumpAndSettle();
    expect(find.byType(PinEditor), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PinEditor),
        matching: find.byType(TextField),
      ),
      findsNWidgets(3),
    );
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    await _openMarkerBrowser(tester);
    await _chooseBrowserEntry(tester, 'Ground hazard');
    await settleMapFixture(tester, h);
    expect(find.text('Ground hazard'), findsOneWidget);
    expect(find.text('Edit pin'), findsNothing);
    expect(find.byTooltip('Close pin details'), findsNothing);
  });

  testWidgets('marker bubble shows summary without raw details', (
    tester,
  ) async {
    final h = await pumpMapFixture(tester);
    await _select(tester, h, ScenePoint(128, 128));

    final popup = find.byKey(const ValueKey('marker-popup'));
    expect(
      find.descendant(of: popup, matching: find.text('Ground exit')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: popup, matching: find.text('PMC extracts')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: popup,
        matching: find.textContaining('offline fixture details'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: popup, matching: find.text('Details')),
      findsNothing,
    );
  });

  testWidgets(
    'focused popup controls isolate all map navigation keys without stealing child input',
    (tester) async {
      final h = await pumpMapFixture(tester);
      await _select(tester, h, ScenePoint(128, 128));
      var attempts = 0;
      while (_focusedTooltip() != 'Close marker details' && attempts < 40) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        attempts++;
      }
      expect(_focusedTooltip(), 'Close marker details');

      final navigationKeys = [
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.home,
        LogicalKeyboardKey.add,
        LogicalKeyboardKey.equal,
        LogicalKeyboardKey.numpadAdd,
        LogicalKeyboardKey.minus,
        LogicalKeyboardKey.numpadSubtract,
        LogicalKeyboardKey.keyC,
        LogicalKeyboardKey.keyN,
        LogicalKeyboardKey.delete,
      ];
      for (final key in navigationKeys) {
        final before = h.services.maps.transform;
        await tester.sendKeyEvent(
          key,
          physicalKey: key == LogicalKeyboardKey.add
              ? PhysicalKeyboardKey.equal
              : null,
        );
        await settleMapFixture(tester, h);
        final after = h.services.maps.transform;
        expect(after.scale, before.scale, reason: '$key changed map scale');
        expect(
          after.translationX,
          before.translationX,
          reason: '$key changed map horizontal translation',
        );
        expect(
          after.translationY,
          before.translationY,
          reason: '$key changed map vertical translation',
        );
        expect(find.byType(PinEditor), findsNothing);
        expect(find.text('Visible map markers and pins'), findsNothing);
      }

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await settleMapFixture(tester, h);
      expect(find.byTooltip('Close marker details'), findsNothing);
      expect(h.services.maps.selectedMarkerProjection, isNull);

      await _select(tester, h, ScenePoint(128, 128));
      attempts = 0;
      while (_focusedTooltip() != 'Close marker details' && attempts < 40) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        attempts++;
      }
      expect(_focusedTooltip(), 'Close marker details');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settleMapFixture(tester, h);
      expect(find.byTooltip('Close marker details'), findsNothing);
      expect(h.services.maps.selectedMarkerProjection, isNull);
    },
  );

  testWidgets('empty canvas and Escape clear marker selection', (tester) async {
    final h = await pumpMapFixture(tester);
    await _select(tester, h, ScenePoint(128, 128));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settleMapFixture(tester, h);
    expect(find.byTooltip('Close marker details'), findsNothing);
    expect(h.services.maps.selectedMarkerProjection, isNull);
    await _select(tester, h, ScenePoint(128, 128));
    await tester.tapAt(_uncoveredArtworkPoint(tester, h));
    await settleMapFixture(tester, h);
    expect(find.byTooltip('Close marker details'), findsNothing);
    expect(h.services.maps.selectedMarkerProjection, isNull);
  });

  testWidgets('pan and zoom track the projected anchor at fixed text size', (
    tester,
  ) async {
    final h = await pumpMapFixture(tester);
    await _select(tester, h, ScenePoint(128, 128));
    final title = find.text('Ground exit');
    final fontSize = tester.widget<Text>(title).style?.fontSize;
    final oldBubble = tester.getRect(find.byTooltip('Close marker details'));
    h.services.maps.panBy(60, 25);
    await settleMapFixture(tester, h);
    final pannedBubble = tester.getRect(find.byTooltip('Close marker details'));
    expect(pannedBubble.topLeft, isNot(oldBubble.topLeft));
    h.services.maps.zoomAt(ViewportPoint(300, 200), 1.25);
    await settleMapFixture(tester, h);
    expect(tester.widget<Text>(title).style?.fontSize, fontSize);
  });

  testWidgets('edge placements clamp prefer below and tether to anchor', (
    tester,
  ) async {
    final h = await pumpMapFixture(
      tester,
      size: const Size(760, 900),
      scale: 1,
      extraMarkers: [
        for (final (id, x, z) in [
          ('edge-top-left', 4, 252),
          ('edge-bottom-right', 252, 4),
        ])
          {
            'id': id,
            'name': id,
            'floorId': 'ground',
            'category': 'lootLoose',
            'filterKey': 'lootLoose',
            'position': {'x': x, 'z': z},
            'details': const {},
            'source': {'mapId': 'shoreline'},
          },
      ],
    );
    for (final (point, markerName, shouldBeBelow) in [
      (ScenePoint(4, 4), 'edge-top-left', true),
      (ScenePoint(252, 252), 'edge-bottom-right', false),
    ]) {
      await _openMarkerBrowser(tester);
      await _chooseBrowserEntry(tester, markerName);
      await settleMapFixture(tester, h);
      expect(h.services.maps.selectedMarkerProjection?.marker.id, markerName);
      final popup = tester.getRect(find.byKey(const ValueKey('marker-popup')));
      final close = tester.getRect(find.byTooltip('Close marker details'));
      final viewport = tester.getRect(_viewport);
      final anchor = _project(tester, h, point);
      expect(viewport.contains(popup.topLeft), isTrue);
      expect(viewport.contains(popup.bottomRight), isTrue);
      expect(viewport.contains(close.topLeft), isTrue);
      expect(viewport.contains(close.bottomRight), isTrue);
      expect(
        shouldBeBelow ? popup.top >= anchor.dy : popup.bottom <= anchor.dy,
        isTrue,
      );
      expect(find.byKey(const ValueKey('marker-popup-tether')), findsOneWidget);
      expect(
        tester
            .getRect(find.byKey(const ValueKey('marker-popup-tether')))
            .inflate(24)
            .contains(anchor),
        isTrue,
      );
      await tester.tap(find.byTooltip('Close marker details'));
      await settleMapFixture(tester, h);
    }
  });

  testWidgets('offscreen anchor hides and restores the same bubble', (
    tester,
  ) async {
    final h = await pumpMapFixture(tester);
    await _select(tester, h, ScenePoint(128, 128));
    final selectedId = h.services.maps.selectedMarkerProjection!.marker.id;
    h.services.maps.panBy(-10000, 0);
    await settleMapFixture(tester, h);
    expect(h.services.maps.selectedMarkerProjection?.marker.id, selectedId);
    expect(find.byTooltip('Close marker details'), findsNothing);
    h.services.maps.panBy(10000, 0);
    await settleMapFixture(tester, h);
    expect(find.byTooltip('Close marker details'), findsOneWidget);
    expect(h.services.maps.selectedMarkerProjection?.marker.id, selectedId);
  });

  testWidgets(
    'floor category quest map and content invalidation clear selection',
    (tester) async {
      final h = await pumpMapFixture(
        tester,
        extraMarkers: [
          {
            'id': 'quest-marker',
            'name': 'Quest marker',
            'floorId': 'ground',
            'category': 'questObjectives',
            'filterKey': 'QuestObjectives',
            'position': {'x': 80, 'z': 128},
            'details': {
              'quest': {
                'name': 'Registered quest',
                'trader': {'name': 'Registered trader'},
              },
            },
            'source': {'mapId': 'shoreline'},
          },
        ],
      );
      await tester.tap(find.widgetWithText(FilterChip, 'Upper'));
      await settleMapFixture(tester, h);
      await _select(tester, h, ScenePoint(192, 64));
      expect(h.services.maps.selectedMarkerProjection?.marker.id, 'upper-exit');
      await tester.tap(find.widgetWithText(FilterChip, 'Upper'));
      await settleMapFixture(tester, h);
      expect(h.services.maps.selectedMarkerProjection, isNull);
      await tester.tap(find.widgetWithText(FilterChip, 'Upper'));
      await settleMapFixture(tester, h);
      expect(h.services.maps.selectedMarkerProjection, isNull);
      await _select(tester, h, ScenePoint(128, 128));
      expect(h.services.maps.selectedMarkerProjection, isNotNull);
      expect(
        await tester.runAsync(
          () => h.services.settings.setMarker('PmcExtracts', false),
        ),
        isTrue,
      );
      await settleMapFixture(tester, h);
      expect(h.services.maps.selectedMarkerProjection, isNull);
      expect(
        await tester.runAsync(
          () => h.services.settings.setMarker('PmcExtracts', true),
        ),
        isTrue,
      );
      await settleMapFixture(tester, h);
      expect(h.services.maps.selectedMarkerProjection, isNull);
      await _select(tester, h, ScenePoint(80, 128));
      expect(
        h.services.maps.selectedMarkerProjection?.marker.id,
        'quest-marker',
      );
      h.services.maps.setQuestFilters(name: 'different quest');
      await settleMapFixture(tester, h);
      expect(h.services.maps.selectedMarkerProjection, isNull);
      h.services.maps.setQuestFilters(name: '');
      await settleMapFixture(tester, h);
      expect(h.services.maps.selectedMarkerProjection, isNull);
      final generation = h.services.maps.contentGeneration;
      await _select(tester, h, ScenePoint(128, 128));
      await tester.runAsync(
        () => h.services.maps.initialize(selectedMapId: 'shoreline'),
      );
      await settleMapFixture(tester, h);
      expect(h.services.maps.contentGeneration, greaterThan(generation));
      expect(h.services.maps.selectedMarkerProjection, isNull);
      await _select(tester, h, ScenePoint(128, 128));
      await tester.runAsync(() => h.services.settings.setMap('thelab'));
      await settleMapFixture(tester, h);
      expect(h.services.maps.selectedMarkerProjection, isNull);
      expect(find.byTooltip('Close marker details'), findsNothing);
    },
  );

  testWidgets('search dimming keeps the selected bubble tracking', (
    tester,
  ) async {
    final h = await pumpMapFixture(tester);
    await _select(tester, h, ScenePoint(128, 128));
    h.services.maps.setSearch('no matching marker');
    await settleMapFixture(tester, h);
    expect(find.byTooltip('Close marker details'), findsOneWidget);
    expect(h.services.maps.selectedMarkerProjection?.dimmed, isTrue);
    final before = tester.getRect(find.byTooltip('Close marker details'));
    h.services.maps.panBy(24, 0);
    await settleMapFixture(tester, h);
    expect(
      tester.getRect(find.byTooltip('Close marker details')).topLeft,
      isNot(before.topLeft),
    );
  });

  testWidgets('bubble summary and wheel do not operate the map', (
    tester,
  ) async {
    final h = await pumpMapFixture(tester);
    await _select(tester, h, ScenePoint(128, 128));
    final scale = h.services.maps.transform.scale;
    final anchorBefore =
        h.services.maps.selectedMarkerProjection!.viewportPoint;
    final popupRect = tester.getRect(
      find.byKey(const ValueKey('marker-popup')),
    );
    final center = popupRect.center;
    expect(popupRect.contains(center), isTrue);
    final selectedId = h.services.maps.selectedMarkerProjection!.marker.id;
    tester.binding.handlePointerEvent(
      PointerScrollEvent(position: center, scrollDelta: const Offset(0, -120)),
    );
    await tester.pump();
    expect(h.services.maps.transform.scale, scale);
    expect(h.services.maps.selectedMarkerProjection?.marker.id, selectedId);
    final primaryPopup = tester.getRect(
      find.byKey(const ValueKey('marker-popup')),
    );
    final primaryPoint = primaryPopup.center;
    expect(primaryPopup.contains(primaryPoint), isTrue);
    await tester.tapAt(primaryPoint);
    await tester.pumpAndSettle();
    expect(h.services.maps.selectedMarkerProjection?.marker.id, selectedId);
    final currentPopup = tester.getRect(
      find.byKey(const ValueKey('marker-popup')),
    );
    final secondaryPoint = currentPopup.center;
    expect(currentPopup.contains(secondaryPoint), isTrue);
    final secondary = await tester.startGesture(
      secondaryPoint,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await secondary.up();
    await tester.pumpAndSettle();
    expect(h.services.maps.transform.scale, scale);
    final anchorAfter = h.services.maps.selectedMarkerProjection!.viewportPoint;
    expect(anchorAfter.x, anchorBefore.x);
    expect(anchorAfter.y, anchorBefore.y);
    expect(h.services.maps.selectedMarkerProjection?.marker.id, selectedId);
    expect(find.byType(PinEditor), findsNothing);
    expect(h.services.settings.pins, isEmpty);
    expect(find.byTooltip('Close marker details'), findsOneWidget);
  });

  testWidgets('uncovered canvas drag and wheel navigate with tracking', (
    tester,
  ) async {
    final h = await pumpMapFixture(tester);
    await _select(tester, h, ScenePoint(128, 128));
    final viewport = tester.getRect(_viewport);
    final anchorBefore =
        h.services.maps.selectedMarkerProjection!.viewportPoint;
    final drag = await tester.startGesture(
      viewport.bottomRight - const Offset(30, 30),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    expect(
      tester
          .getRect(find.byKey(const ValueKey('marker-popup')))
          .contains(viewport.bottomRight - const Offset(30, 30)),
      isFalse,
    );
    await drag.moveBy(const Offset(-20, 10));
    await tester.pump();
    await drag.moveBy(const Offset(-20, 10));
    await drag.up();
    await tester.pumpAndSettle();
    final afterDrag = h.services.maps.selectedMarkerProjection!.viewportPoint;
    expect(afterDrag.x, isNot(anchorBefore.x));
    expect(afterDrag.y, isNot(anchorBefore.y));
    final scale = h.services.maps.transform.scale;
    final wheelPoint = viewport.bottomRight - const Offset(25, 25);
    expect(
      tester
          .getRect(find.byKey(const ValueKey('marker-popup')))
          .contains(wheelPoint),
      isFalse,
    );
    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: wheelPoint,
        scrollDelta: const Offset(0, -120),
      ),
    );
    await tester.pumpAndSettle();
    expect(h.services.maps.transform.scale, greaterThan(scale));
    final contextPoint = _uncoveredArtworkPoint(tester, h);
    final contextClick = await tester.startGesture(
      contextPoint,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await contextClick.up();
    await tester.pumpAndSettle();
    expect(find.byType(PinEditor), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    final moved = h.services.maps.selectedMarkerProjection!.viewportPoint;
    expect(moved.x, isNot(afterDrag.x));
    expect(moved.y, isNot(afterDrag.y));
    expect(find.byTooltip('Close marker details'), findsOneWidget);
  });

  testWidgets('focused popup and help modal take keyboard precedence', (
    tester,
  ) async {
    final h = await pumpMapFixture(tester);
    await _select(tester, h, ScenePoint(128, 128));
    final popup = find.byKey(const ValueKey('marker-popup'));
    expect(popup, findsOneWidget);
    final before = h.services.maps.transform;
    var attempts = 0;
    while (_focusedTooltip() != 'Close marker details' && attempts < 40) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      attempts++;
    }
    expect(_focusedTooltip(), 'Close marker details');
    _expectFocusInside(popup);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pumpAndSettle();
    expect(find.byType(PinEditor), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(find.text('Remove pin record?'), findsNothing);
    final after = h.services.maps.transform;
    expect(after.scale, before.scale);
    expect(after.translationX, before.translationX);
    expect(after.translationY, before.translationY);
    await tester.tap(find.byTooltip('Map help'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byTooltip('Close marker details'), findsOneWidget);
    expect(h.services.maps.selectedMarkerProjection, isNotNull);
  });

  testWidgets(
    'labelled keyboard close clears selection and restores usable map focus',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final h = await pumpMapFixture(tester);
        await _select(tester, h, ScenePoint(128, 128));
        expect(find.byTooltip('Close marker details'), findsOneWidget);
        expect(find.bySemanticsLabel('Close marker details'), findsOneWidget);
        var attempts = 0;
        while (_focusedTooltip() != 'Close marker details' && attempts < 40) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          attempts++;
        }
        expect(_focusedTooltip(), 'Close marker details');
        _expectFocusInside(find.byKey(const ValueKey('marker-popup')));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await settleMapFixture(tester, h);
        expect(find.byTooltip('Close marker details'), findsNothing);
        expect(h.services.maps.selectedMarkerProjection, isNull);
        final beforeZoom = h.services.maps.transform.scale;
        await tester.sendKeyEvent(LogicalKeyboardKey.equal);
        await settleMapFixture(tester, h);
        expect(h.services.maps.transform.scale, greaterThan(beforeZoom));
        await _select(tester, h, ScenePoint(128, 128));
        attempts = 0;
        while (_focusedTooltip() != 'Close marker details' &&
            _focusedTooltip() != 'Details' &&
            attempts < 40) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          attempts++;
        }
        expect(_focusedTooltip(), anyOf('Close marker details', 'Details'));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settleMapFixture(tester, h);
        expect(find.byTooltip('Close marker details'), findsNothing);
        expect(h.services.maps.selectedMarkerProjection, isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'marker replacement resets summary scroll but same marker updates retain it',
    (tester) async {
      final wire = wireFixture();
      final longLockType = List<String>.filled(
        200,
        'Long lock detail',
      ).join(' ');
      var localizedKey = 'Popup key before refresh';
      final client = MockClient((request) async {
        final translations = wire['items_en'] as Map<String, dynamic>;
        final data = translations['data'] as Map<String, dynamic>;
        data['item-a Name'] = localizedKey;
        return http.Response(
          jsonEncode(wire[request.url.pathSegments.last] ?? {}),
          wire.containsKey(request.url.pathSegments.last) ? 200 : 404,
        );
      });
      final h = await pumpMapFixture(
        tester,
        client: client,
        extraMarkers: [
          {
            'id': 'catalog-lock',
            'name': 'Catalog lock',
            'floorId': 'ground',
            'category': 'locks',
            'filterKey': 'locks',
            'position': {'x': 96, 'z': 96},
            'details': {'key': 'item-a', 'lockType': longLockType},
            'source': {'mapId': 'shoreline'},
          },
          {
            'id': 'catalog-lock-second',
            'name': 'Second catalog lock',
            'floorId': 'ground',
            'category': 'locks',
            'filterKey': 'locks',
            'position': {'x': 160, 'z': 96},
            'details': {'key': 'item-a', 'lockType': longLockType},
            'source': {'mapId': 'shoreline'},
          },
        ],
      );

      await _select(tester, h, ScenePoint(96, 160));
      expect(
        h.services.maps.selectedMarkerProjection?.marker.id,
        'catalog-lock',
      );
      final scrollFinder = find.byKey(const ValueKey('marker-popup-scroll'));
      final scrollable = find.descendant(
        of: scrollFinder,
        matching: find.byType(Scrollable),
      );
      var scrollState = tester.state<ScrollableState>(scrollable);
      expect(scrollState.position.maxScrollExtent, greaterThan(0));
      await tester.drag(scrollFinder, const Offset(0, -120));
      await tester.pumpAndSettle();
      final retainedOffset = scrollState.position.pixels;
      expect(retainedOffset, greaterThan(0));

      h.services.maps.panBy(24, 12);
      await settleMapFixture(tester, h);
      scrollState = tester.state<ScrollableState>(scrollable);
      expect(scrollState.position.pixels, retainedOffset);

      localizedKey = 'Popup key after publication';
      await tester.runAsync(() => h.services.catalog.refresh());
      await tester.pumpAndSettle();
      expect(find.textContaining(localizedKey), findsOneWidget);
      scrollState = tester.state<ScrollableState>(scrollable);
      expect(scrollState.position.pixels, retainedOffset);

      await _openMarkerBrowser(tester);
      await _chooseBrowserEntry(tester, 'Second catalog lock');
      await settleMapFixture(tester, h);
      expect(
        h.services.maps.selectedMarkerProjection?.marker.id,
        'catalog-lock-second',
      );
      expect(find.text('Second catalog lock'), findsOneWidget);
      final replacementScrollState = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const ValueKey('marker-popup-scroll')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(
        replacementScrollState.position.maxScrollExtent,
        greaterThan(retainedOffset),
      );
      expect(replacementScrollState.position.pixels, 0);

      await tester.drag(scrollFinder, const Offset(0, -80));
      await tester.pumpAndSettle();
      final secondOffset = replacementScrollState.position.pixels;
      expect(secondOffset, greaterThan(0));

      await _openMarkerBrowser(tester);
      await _chooseBrowserEntry(tester, 'Catalog lock');
      await settleMapFixture(tester, h);
      expect(
        h.services.maps.selectedMarkerProjection?.marker.id,
        'catalog-lock',
      );
      expect(find.text('Catalog lock'), findsOneWidget);
      final returnedScrollState = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const ValueKey('marker-popup-scroll')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(
        returnedScrollState.position.maxScrollExtent,
        greaterThan(secondOffset),
      );
      expect(returnedScrollState.position.pixels, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'matching catalog publication updates open bubble without requests',
    (tester) async {
      final wire = wireFixture();
      var localizedKey = 'Popup key before refresh';
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        final translations = wire['items_en'] as Map<String, dynamic>;
        final data = translations['data'] as Map<String, dynamic>;
        data['item-a Name'] = localizedKey;
        return http.Response(
          jsonEncode(wire[request.url.pathSegments.last] ?? {}),
          wire.containsKey(request.url.pathSegments.last) ? 200 : 404,
        );
      });
      final h = await pumpMapFixture(
        tester,
        client: client,
        extraMarkers: [
          {
            'id': 'catalog-lock',
            'name': 'Catalog lock',
            'floorId': 'ground',
            'category': 'locks',
            'filterKey': 'locks',
            'position': {'x': 96, 'z': 96},
            'details': {'key': 'item-a', 'lockType': 'door'},
            'source': {'mapId': 'shoreline'},
          },
        ],
      );
      final startupRequests = requests;
      await _select(tester, h, ScenePoint(96, 160));
      expect(requests, startupRequests);
      expect(find.textContaining('Popup key before refresh'), findsOneWidget);
      localizedKey = 'Popup key after publication';
      await tester.runAsync(() => h.services.catalog.refresh());
      await tester.pumpAndSettle();
      expect(requests, greaterThan(startupRequests));
      expect(
        find.textContaining('Popup key after publication'),
        findsOneWidget,
      );
      expect(find.textContaining('Popup key before refresh'), findsNothing);
      final publicationRequests = requests;
      await tester.pump();
      await tester.pump();
      expect(requests, publicationRequests);
    },
  );

  testWidgets(
    'failed refresh retains matching last good key without requests',
    (tester) async {
      final wire = wireFixture();
      var requests = 0;
      var unavailable = false;
      final client = MockClient((request) async {
        requests++;
        if (unavailable) return http.Response('unavailable', 503);
        return http.Response(
          jsonEncode(wire[request.url.pathSegments.last] ?? {}),
          wire.containsKey(request.url.pathSegments.last) ? 200 : 404,
        );
      });
      final h = await pumpMapFixture(
        tester,
        client: client,
        extraMarkers: [
          {
            'id': 'catalog-lock',
            'name': 'Catalog lock',
            'floorId': 'ground',
            'category': 'locks',
            'filterKey': 'locks',
            'position': {'x': 96, 'z': 96},
            'details': {'key': 'item-a', 'lockType': 'door'},
            'source': {'mapId': 'shoreline'},
          },
        ],
      );
      final startupRequests = requests;
      await _select(tester, h, ScenePoint(96, 160));
      expect(requests, startupRequests);
      expect(find.textContaining('Synthetic component'), findsOneWidget);
      unavailable = true;
      await tester.runAsync(() => h.services.catalog.refresh());
      await tester.pumpAndSettle();
      expect(requests, greaterThan(startupRequests));
      expect(find.textContaining('Synthetic component'), findsOneWidget);
      final failedRefreshRequests = requests;
      await tester.pump();
      expect(requests, failedRefreshRequests);
      expect(h.services.catalog.snapshot, isNotNull);
      expect(h.services.catalog.mode, h.services.catalog.snapshot!.mode);
      await tester.runAsync(() => h.services.catalog.setMode(GameMode.pve));
      await tester.pumpAndSettle();
      expect(h.services.catalog.mode, GameMode.pve);
      expect(h.services.catalog.snapshot, isNull);
      expect(find.textContaining('Synthetic component'), findsNothing);
      final beforeColdFailure = requests;
      await tester.runAsync(() => h.services.catalog.refresh());
      await tester.pumpAndSettle();
      expect(requests, greaterThan(beforeColdFailure));
      expect(h.services.catalog.snapshot, isNull);
      expect(find.textContaining('Synthetic component'), findsNothing);
      final afterFailure = requests;
      await tester.pump();
      expect(requests, afterFailure);
    },
  );
}

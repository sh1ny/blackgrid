import 'package:blackgrid/domain/map_coordinates.dart';
import 'package:blackgrid/ui/marker_preferences.dart';
import 'package:blackgrid/ui/pin_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/m1_widget_harness.dart';
import '../support/map_widget_harness.dart';

Finder get _addPin => find.byKey(const ValueKey('pins-add'));
Finder _pinRow(String id) => find.byKey(ValueKey('pin-row-$id'));
Finder _pinRemove(String id) => find.byKey(ValueKey('pin-remove-$id'));
Finder _marker(String key) => find.byKey(ValueKey('marker-row-$key'));

/// Brings [target] into view in the inspector and asserts it can be pressed.
Future<void> _reveal(WidgetTester tester, Finder target) async {
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
}

/// Whether the inspector row for [key] is built and shows the shown state.
bool _shown(String key) {
  expect(_marker(key), findsOneWidget);
  return find
      .descendant(of: _marker(key), matching: find.byType(MarkerToggleSwitch))
      .evaluate()
      .map((element) => (element.widget as MarkerToggleSwitch).on)
      .single;
}

/// A prepared-pack marker on the ground floor with an explicit filter key.
Map<String, Object?> _extraMarker(String id, String category, String filter) =>
    {
      'id': id,
      'name': id,
      'floorId': 'ground',
      'category': category,
      'filterKey': filter,
      'position': {'x': 64, 'z': 64},
      'details': {'description': '$id offline fixture details'},
      'source': {'fixture': true},
    };

Future<void> _tapButton(
  WidgetTester tester,
  String label,
  bool Function() completed,
) async {
  final button = find.widgetWithText(TextButton, label);
  await _reveal(tester, button);
  await tapM1Async(tester, button, completed);
}

/// Opens the inspector when the window is narrow enough to start it closed.
Future<void> _openInspector(WidgetTester tester) async {
  if (find.byKey(const Key('shell-inspector')).evaluate().isEmpty) {
    await tester.tap(find.byKey(const Key('inspector-toggle')));
    await tester.pumpAndSettle();
  }
  expect(find.byKey(const Key('shell-inspector')), findsOneWidget);
}

void main() {
  testWidgets(
    'marker search survives show/hide-all and dimmed targets remain eligible',
    (tester) async {
      final h = await pumpMapFixture(tester);
      await tester.runAsync(
        () => h.services.settings.save(
          h.services.settings.settings.copyWith(saveMarkerFilters: true),
        ),
      );
      final search = find.byKey(const ValueKey('marker-section-search'));
      await _reveal(tester, search);
      await tester.enterText(search, 'exit, tunnel');
      await tester.pumpAndSettle();
      expect(h.services.maps.search, 'exit, tunnel');
      expect(
        h.services.maps
            .visibleMarkers()
            .where((marker) => marker.dimmed)
            .map((marker) => marker.marker.id),
        ['ground-hazard'],
      );
      // Dimming by search must not change what any row says is shown.
      for (final key in ['PmcExtracts', 'Hazards']) {
        await _reveal(tester, _marker(key));
        expect(_shown(key), isTrue, reason: '$key row while searching');
      }
      await _tapButton(
        tester,
        'Hide all',
        () => h.services.maps.visibleMarkers().isEmpty,
      );
      expect(h.services.maps.search, 'exit, tunnel');
      final hidden = (await tester.runAsync(
        () => h.services.database.readSettings(),
      ))!.settings;
      expect(hidden.markerFilters['PmcExtracts'], isFalse);
      expect(hidden.markerFilters, isNot(contains('extracts')));
      expect(hidden.markerFilters, isNot(contains('hazards')));
      await tester.runAsync(h.services.settings.load);
      await tester.pumpAndSettle();
      expect(h.services.maps.visibleMarkers(), isEmpty);
      await _reveal(tester, _marker('PmcExtracts'));
      expect(_shown('PmcExtracts'), isFalse);
      expect(_shown('Hazards'), isFalse);
      await tapM1Async(
        tester,
        _marker('PmcExtracts'),
        () => h.services.maps.visibleMarkers().length == 1,
      );
      expect(h.services.maps.visibleMarkers().single.marker.id, 'ground-exit');
      await _tapButton(
        tester,
        'Show all',
        () => h.services.maps.visibleMarkers().length == 2,
      );
      expect(
        h.services.maps.visibleMarkers().map((marker) => marker.marker.id),
        ['ground-exit', 'ground-hazard'],
      );
      await _reveal(tester, _marker('PmcExtracts'));
      expect(_shown('PmcExtracts'), isTrue);
      expect(_shown('Hazards'), isTrue);
      final shown = (await tester.runAsync(
        () => h.services.database.readSettings(),
      ))!.settings;
      expect(shown.markerFilters['PmcExtracts'], isTrue);
      expect(shown.markerFilters, isNot(contains('extracts')));
      expect(shown.markerFilters, isNot(contains('hazards')));
      await tester.runAsync(h.services.settings.load);
      await tester.pumpAndSettle();
      expect(h.services.maps.visibleMarkers(), hasLength(2));
      expect(h.services.maps.visibleMarkers().last.dimmed, isTrue);
      expect(
        h.services.maps
            .hitTestMarker(h.services.maps.visibleMarkers().last.viewportPoint)!
            .marker
            .id,
        'ground-hazard',
      );
      expect(h.services.scans.hasAcceptedScan, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Show all keeps saved entries of keys the map does not show', (
    tester,
  ) async {
    final h = await pumpMapFixture(tester);
    await tester.runAsync(
      () => h.services.settings.setMarker('ScavSpawns', false),
    );
    await tester.pumpAndSettle();
    expect(h.services.maps.applicableCategories, isNot(contains('ScavSpawns')));

    await _tapButton(
      tester,
      'Show all',
      () => h.services.settings.settings.markerFilters['PmcExtracts'] == true,
    );

    final stored = (await tester.runAsync(
      () => h.services.database.readSettings(),
    ))!.settings;
    expect(stored.markerFilters['ScavSpawns'], isFalse);
    expect(stored.markerFilters['PmcExtracts'], isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Hide all never saves an unsaveable key and settings reload', (
    tester,
  ) async {
    final h = await pumpMapFixture(
      tester,
      extraMarkers: [_extraMarker('zip', 'ziplines', 'Ziplines')],
    );
    expect(h.services.maps.applicableCategories, contains('Ziplines'));
    expect(_marker('Ziplines'), findsNothing);
    // Filters survive a reload only while Save marker filters is on.
    await tester.runAsync(
      () => h.services.settings.save(
        h.services.settings.settings.copyWith(saveMarkerFilters: true),
      ),
    );

    await _tapButton(
      tester,
      'Hide all',
      () => h.services.settings.settings.markerFilters['PmcExtracts'] == false,
    );

    final stored = (await tester.runAsync(
      () => h.services.database.readSettings(),
    ))!.settings;
    expect(stored.markerFilters['PmcExtracts'], isFalse);
    expect(stored.markerFilters['Hazards'], isFalse);
    expect(stored.markerFilters, isNot(contains('Ziplines')));
    await tester.runAsync(h.services.settings.load);
    await tester.pumpAndSettle();
    expect(
      h.services.settings.settings.markerFilters,
      isNot(contains('Ziplines')),
    );
    expect(h.services.maps.visibleMarkers().map((marker) => marker.marker.id), [
      'zip',
    ]);
    await _reveal(tester, _marker('PmcExtracts'));
    expect(_shown('PmcExtracts'), isFalse);
    expect(_shown('Hazards'), isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final (map, frame) in [
    ('shoreline', MapCoordinateFrame.legacyNormalized),
    ('thelab', MapCoordinateFrame.labsNativeNormalized),
  ]) {
    testWidgets(
      'pin-save regression: a new pin on $map saves with frame ${frame.wireName}',
      (tester) async {
        final h = await pumpMapFixture(tester);
        if (map != 'shoreline') {
          await tester.runAsync(() => h.services.settings.setMap(map));
          await settleMapFixture(tester, h);
        }
        await _reveal(tester, _addPin);
        await tester.tap(_addPin);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Pin label'),
          'P',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Position across (0–1)'),
          '0.25',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Position down (0–1)'),
          '0.75',
        );
        await tapM1Async(
          tester,
          find.text('Save pin'),
          () => h.services.settings.pins.isNotEmpty,
        );
        final saved = h.services.settings.pins.single;
        expect(saved.mapId, map);
        expect(saved.frame, frame.wireName);
        expect(saved.frameRevision, frame.revision);
      },
    );
  }

  for (final map in ['shoreline', 'thelab']) {
    testWidgets(
      '$map inspector pins edit and remove finite off-map pins without reframing them',
      (tester) async {
        final h = await pumpMapFixture(tester);
        if (map != 'shoreline') {
          await tester.runAsync(() => h.services.settings.setMap(map));
          await settleMapFixture(tester, h);
        }
        await _reveal(tester, _addPin);
        await tester.tap(_addPin);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Pin label'),
          'Durable off-map marker',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Position across (0–1)'),
          'not a coordinate',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Position down (0–1)'),
          '1.5',
        );
        await tester.tap(find.text('Save pin'));
        await tester.pumpAndSettle();
        expect(find.byType(PinEditor), findsOneWidget);
        expect(
          find.textContaining('a number for each position'),
          findsOneWidget,
        );
        expect(h.services.settings.pins, isEmpty);
        await tester.enterText(
          find.widgetWithText(TextField, 'Position across (0–1)'),
          '-.2',
        );
        await tapM1Async(
          tester,
          find.text('Save pin'),
          () => h.services.settings.pins.isNotEmpty,
        );
        final original = h.services.settings.pins.single;
        expect(original.mapId, map);
        expect(original.x, -.2);
        expect(original.y, 1.5);
        expect(
          original.frame,
          map == 'thelab' ? 'labs-native-normalized' : 'legacy-normalized',
        );
        expect(original.frameRevision, map == 'thelab' ? 1 : 0);
        expect(find.byType(PinEditor), findsNothing);
        // Off-map records remain discoverable even when no glyph is visible.
        await _reveal(tester, _pinRow(original.id));
        await tester.tap(_pinRow(original.id));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(
                find.widgetWithText(TextField, 'Position across (0–1)'),
              )
              .controller!
              .text,
          '-0.2',
        );
        expect(
          tester
              .widget<TextField>(
                find.widgetWithText(TextField, 'Position down (0–1)'),
              )
              .controller!
              .text,
          '1.5',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Pin label'),
          'Renamed off-map marker',
        );
        await tapM1Async(
          tester,
          find.text('Save pin'),
          () =>
              h.services.settings.pins.single.label == 'Renamed off-map marker',
        );
        final edited = h.services.settings.pins.single;
        expect(edited.id, original.id);
        expect(edited.mapId, original.mapId);
        expect(edited.x, original.x);
        expect(edited.y, original.y);
        expect(edited.frame, original.frame);
        expect(edited.frameRevision, original.frameRevision);
        expect(
          find.descendant(
            of: _pinRow(edited.id),
            matching: find.text(edited.label),
          ),
          findsOneWidget,
        );
        await _reveal(tester, _pinRemove(edited.id));
        await tester.tap(_pinRemove(edited.id));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();
        expect(h.services.settings.pins.single.id, original.id);
        await tester.tap(_pinRemove(edited.id));
        await tester.pumpAndSettle();
        await tapM1Async(
          tester,
          find.widgetWithText(FilledButton, 'Remove'),
          () => h.services.settings.pins.isEmpty,
        );
        expect(_pinRow(edited.id), findsNothing);
        expect(h.services.scans.hasAcceptedScan, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final layout in [
    (name: 'wide', size: const Size(1912, 823), scale: 1.0),
    (name: 'compact', size: const Size(760, 900), scale: 1.0),
    (name: 'compact enlarged text', size: const Size(760, 900), scale: 2.0),
  ]) {
    testWidgets('${layout.name} map controls remain reachable and usable', (
      tester,
    ) async {
      final h = await pumpMapFixture(
        tester,
        size: layout.size,
        scale: layout.scale,
      );
      expect(tester.takeException(), isNull, reason: 'after fixture');
      final fit = find.byTooltip('Fit map');
      await tester.ensureVisible(fit);
      await tester.pumpAndSettle();
      expect(fit.hitTestable(), findsOneWidget);
      await tester.tap(fit);
      await settleMapFixture(tester, h);
      final fitScale = h.services.maps.transform.scale;
      await tester.tap(find.byTooltip('Zoom in'));
      await settleMapFixture(tester, h);
      expect(h.services.maps.transform.scale, greaterThan(fitScale));
      await tester.tap(fit);
      await settleMapFixture(tester, h);
      expect(h.services.maps.transform.scale, closeTo(fitScale, 1e-9));
      final upper = find.descendant(
        of: find.byKey(const Key('map-floor-control')),
        matching: find.text('Upper'),
      );
      await tester.ensureVisible(upper);
      await tester.pumpAndSettle();
      expect(upper.hitTestable(), findsOneWidget);
      await tester.tap(upper);
      await settleMapFixture(tester, h);
      expect(h.services.maps.floorSelection!.isLayerVisible('upper'), isTrue);
      final addPin = find.byTooltip('Pin at view center');
      await tester.ensureVisible(addPin);
      await tester.pumpAndSettle();
      expect(addPin.hitTestable(), findsOneWidget);
      await tester.tap(addPin);
      await tester.pumpAndSettle();
      final label = find.widgetWithText(TextField, 'Pin label');
      await tester.ensureVisible(label);
      await tester.enterText(label, 'Reachable controls');
      final x = find.widgetWithText(TextField, 'Position across (0–1)');
      await tester.ensureVisible(x);
      await tester.enterText(x, '.5');
      final y = find.widgetWithText(TextField, 'Position down (0–1)');
      await tester.ensureVisible(y);
      await tester.enterText(y, '.5');
      await tapM1Async(
        tester,
        find.text('Save pin'),
        () => h.services.settings.pins.isNotEmpty,
      );
      // The saved pin is listed in the inspector, however narrow the window.
      await _openInspector(tester);
      final row = _pinRow(h.services.settings.pins.single.id);
      await _reveal(tester, row);
      expect(
        find.descendant(of: row, matching: find.text('Reachable controls')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/map_widget_harness.dart';

Finder get _helpButton => find.byTooltip('Map help');

Finder get _dialog => find.byType(AlertDialog);

Finder get _viewport => find.byKey(const Key('native-map-viewport'));

/// Every text shown in the open help dialog, joined with newlines.
String _dialogText(WidgetTester tester) => [
  for (final widget in tester.widgetList<Text>(
    find.descendant(of: _dialog, matching: find.byType(Text)),
  ))
    widget.data ?? widget.textSpan!.toPlainText(),
  for (final widget in tester.widgetList<RichText>(
    find.descendant(of: _dialog, matching: find.byType(RichText)),
  ))
    widget.text.toPlainText(),
].join('\n');

Future<void> _openHelp(WidgetTester tester) async {
  await tester.tap(_helpButton);
  await tester.pumpAndSettle();
  expect(_dialog, findsOneWidget);
}

/// Selects the harness's "Ground exit" extract by clicking its badge.
Future<void> _selectGroundExit(
  WidgetTester tester,
  MapWidgetHarness harness,
) async {
  final exit = harness.services.maps.visibleMarkers().singleWhere(
    (marker) => marker.marker.id == 'ground-exit',
  );
  final origin = tester.getTopLeft(_viewport);
  await tester.tapAt(
    origin + Offset(exit.viewportPoint.x, exit.viewportPoint.y),
  );
  await tester.pumpAndSettle();
  expect(find.byTooltip('Close marker details'), findsOneWidget);
}

bool _mapFocused() =>
    FocusManager.instance.primaryFocus?.debugLabel == 'Native map workspace';

void main() {
  testWidgets(
    'the help button opens and Close closes the help, keeping the selection',
    (tester) async {
      final harness = await pumpMapFixture(tester);
      await _selectGroundExit(tester, harness);
      final maps = harness.services.maps;
      final scale = maps.transform.scale;
      final pins = harness.services.settings.pins.length;

      await _openHelp(tester);
      expect(
        find.descendant(of: _dialog, matching: find.text('Map help')),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();

      expect(_dialog, findsNothing);
      expect(find.byTooltip('Close marker details'), findsOneWidget);
      expect(maps.transform.scale, scale);
      expect(harness.services.settings.pins.length, pins);
      expect(_mapFocused(), isTrue);
    },
  );

  testWidgets('the help button works with no artwork loaded', (tester) async {
    await pumpMapFixture(tester);
    await _openHelp(tester);
    final withArtwork = _dialogText(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();

    final harness = await pumpMapFixture(tester, artwork: false);
    final maps = harness.services.maps;
    expect(maps.scene, isNull, reason: 'artwork must be missing here');
    expect(maps.error, isNotNull);
    expect(tester.widget<IconButton>(_helpButtonButton).onPressed, isNotNull);
    await _openHelp(tester);
    expect(_dialogText(tester), withArtwork);
  });

  testWidgets('Escape closes the help and keeps the selected marker', (
    tester,
  ) async {
    final harness = await pumpMapFixture(tester);
    await _selectGroundExit(tester, harness);
    await _openHelp(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(_dialog, findsNothing);
    expect(find.byTooltip('Close marker details'), findsOneWidget);
    expect(_mapFocused(), isTrue);
  });

  group('help text', () {
    late String text;

    Future<void> open(WidgetTester tester) async {
      await pumpMapFixture(tester);
      await _openHelp(tester);
      text = _dialogText(tester);
    }

    testWidgets(
      'the help explains the screenshot key, folder and no-position case',
      (tester) async {
        await open(tester);
        expect(text, contains('Your position'));
        expect(text, contains("game's own screenshot key"));
        expect(text, contains('Screenshot folder'));
        expect(text, contains('Settings'));
        expect(text, contains('no position'));
        // The key is set in the game, so the help names none.
        expect(text, isNot(contains('PrtSc')));
        expect(text, isNot(contains('Print Screen')));
      },
    );

    testWidgets('the help text makes no screen-capture claim', (tester) async {
      await open(tester);
      expect(text, contains('never captures the screen'));
      final lower = text.toLowerCase();
      for (final claim in [
        'captures the screen to',
        'records the screen',
        'records your screen',
        'watches the screen',
        'watches the game screen',
        'watches your screen',
        'reads the screen',
      ]) {
        expect(lower, isNot(contains(claim)), reason: claim);
      }
    });

    testWidgets('the help lists every map control', (tester) async {
      await open(tester);
      expect(text, contains('Controls'));
      for (final control in [
        'Drag or arrow keys',
        'Mouse wheel or + / -',
        'Home',
        'C',
        'Enter',
        'N or right-click',
        'Delete',
        'Escape',
        'Hover over an extract',
      ]) {
        expect(text, contains(control), reason: control);
      }
      for (final action in [
        'Pan the map',
        'Zoom',
        'Fit the map',
        'Center on your position',
        'Browse markers',
        'Add a pin',
        'Remove the selected pin',
        'Clear the selection',
        'Show its area',
      ]) {
        expect(text, contains(action), reason: action);
      }
    });

    testWidgets('the help text has no filter keys or raw identifiers', (
      tester,
    ) async {
      await open(tester);
      for (final key in [
        'PmcExtracts',
        'ScavExtracts',
        'SharedExtracts',
        'Transits',
        'HazardZones',
        'CustomPins',
      ]) {
        expect(text, isNot(contains(key)), reason: key);
      }
      expect(
        RegExp('[a-z][A-Z]').allMatches(text).map((m) => m.group(0)),
        isEmpty,
        reason: 'camelCase identifier in the help text',
      );
    });
  });
}

Finder get _helpButtonButton =>
    find.ancestor(of: _helpButton, matching: find.byType(IconButton)).first;

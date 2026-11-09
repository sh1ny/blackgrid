import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:blackgrid/data/raid_panel_ocr.dart';
import 'package:blackgrid/domain/map_coordinates.dart';
import 'package:blackgrid/domain/raid_panel_text_parser.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:blackgrid/ui/map_screen.dart';
import 'package:blackgrid/ui/map_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/m1_widget_harness.dart';
import '../support/map_widget_harness.dart';

/// An OCR whose recognition never finishes until [gate] is completed.
final class _GatedOcr extends RaidPanelOcr {
  final gate = Completer<RaidPanelEvidence>();

  @override
  Future<RaidPanelEvidence> recognize(Uint8List imageBytes) => gate.future;
}

/// An OCR that finds no panel at once, so a read ends without a worker.
final class _InstantOcr extends RaidPanelOcr {
  @override
  Future<RaidPanelEvidence> recognize(Uint8List imageBytes) =>
      Future.value(RaidPanelEvidence(state: RaidPanelState.unavailable));
}

Finder get _viewport => find.byKey(const Key('native-map-viewport'));
Finder get _picker => find.byKey(const Key('map-picker'));
Finder get _readItem => find.byKey(const Key('map-picker-read-latest'));
Finder get _floorControl => find.byKey(const Key('map-floor-control'));
Finder get _actions => find.byKey(const Key('map-actions'));
Finder get _pinBar => find.byKey(const Key('map-pin-bar'));
Finder get _attribution => find.byKey(const Key('map-attribution'));
Finder get _snack => find.byType(SnackBar);

Finder _item(String id) => find.byKey(Key('map-picker-item-$id'));

/// The seven on-map action tooltips.
const _actionTooltips = [
  'Fit map',
  'Zoom in',
  'Zoom out',
  'Center on player',
  'Pin at view center',
  'Browse markers',
  'Map help',
];

IconButton _action(WidgetTester tester, String tooltip) => tester.widget(
  find.ancestor(of: find.byTooltip(tooltip), matching: find.byType(IconButton)),
);

MenuItemButton _menuItem(WidgetTester tester, Finder item) =>
    tester.widget<MenuItemButton>(item);

Future<void> _openPicker(WidgetTester tester) async {
  await tester.tap(_picker);
  await tester.pumpAndSettle();
}

/// Whether the picker entry for [id] shows the current-map check.
bool _checked(WidgetTester tester, String id) => find
    .descendant(of: _item(id), matching: find.byIcon(Icons.check))
    .evaluate()
    .isNotEmpty;

Future<void> _notifySettings(WidgetTester tester, MapWidgetHarness h) async {
  // ignore: invalid_use_of_protected_member
  h.services.settings.notifyListeners();
  await tester.pump();
}

CustomPin _pin(String label, {String mapId = 'shoreline'}) => CustomPin(
  id: 'pin-$label',
  mapId: mapId,
  x: .8,
  y: .8,
  frame: 'legacy-normalized',
  frameRevision: 0,
  label: label,
  updatedAt: DateTime.utc(2026),
);

/// Saves [pin] and taps it on the map so that it is the selected pin.
Future<void> _selectPin(
  WidgetTester tester,
  MapWidgetHarness h,
  CustomPin pin,
) async {
  expect(await tester.runAsync(() => h.services.settings.savePin(pin)), isTrue);
  await settleMapFixture(tester, h);
  final point = h.services.maps.projectPin(pin)!;
  await tester.tapAt(tester.getTopLeft(_viewport) + Offset(point.x, point.y));
  await settleMapFixture(tester, h);
}

/// Whether the map's pin semantics target for [label] reports as selected.
bool _pinSemanticsSelected(WidgetTester tester, String label) {
  final painter = tester
      .widget<CustomPaint>(
        find
            .descendant(of: _viewport, matching: find.byType(CustomPaint))
            .first,
      )
      .painter!;
  return painter.semanticsBuilder!(tester.getSize(_viewport))
      .singleWhere((target) => target.properties.label == '$label, saved pin')
      .properties
      .selected!;
}

/// Writes a tiny PNG modified an hour ago into a new temporary directory.
Future<File> _savedScreenshot(WidgetTester tester) async {
  final directory = await _tempDirectory(tester);
  final screenshot = File(
    '${directory.path}${Platform.pathSeparator}saved-panel.png',
  );
  await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.black, BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(8, 8);
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    await screenshot.writeAsBytes(
      png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
    );
    await screenshot.setLastModified(
      DateTime.now().toUtc().subtract(const Duration(hours: 1)),
    );
    image.dispose();
    picture.dispose();
  });
  return screenshot;
}

Future<Directory> _tempDirectory(WidgetTester tester) async {
  final directory = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('blackgrid-map-controls-'),
  ))!;
  addTearDown(() => directory.delete(recursive: true));
  return directory;
}

/// Points the screenshot input at [path] with log following off.
Future<void> _useScreenshotFolder(
  WidgetTester tester,
  MapWidgetHarness h,
  String path,
) async {
  await tester.runAsync(
    () => h.services.settings.setMapInputs(
      screenshotDirectory: path,
      followGameLogs: false,
    ),
  );
  await settleMapFixture(tester, h);
}

/// Pumps until [done], letting real I/O progress between frames.
Future<void> _until(WidgetTester tester, bool Function() done) async {
  final elapsed = Stopwatch()..start();
  while (!done()) {
    if (elapsed.elapsed > const Duration(seconds: 10)) {
      throw StateError('The expected state was not reached.');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

/// Taps [target] and waits until [done], letting real I/O and fake timers
/// progress between frames.
///
/// A menu entry starts its work in the test's fake-time zone, where the
/// watcher's short stability delay only fires when fake time moves.
Future<void> _tapAndWait(
  WidgetTester tester,
  Finder target,
  bool Function() done,
) async {
  await tester.tap(target);
  await _until(tester, done);
}

/// Chooses Read latest screenshot and waits for the snackbar that reports it.
Future<void> _readLatestForNotice(WidgetTester tester) async {
  await _openPicker(tester);
  expect(_menuItem(tester, _readItem).onPressed, isNotNull);
  await _tapAndWait(tester, _readItem, () => _snack.evaluate().isNotEmpty);
}

void main() {
  testWidgets('map-controls: Wide and narrow windows', (tester) async {
    for (final size in [const Size(1660, 870), const Size(960, 720)]) {
      await pumpMapFixture(tester, size: size);
      final bar = tester.getRect(find.byKey(const Key('shell-top-bar')));
      final strip = tester.getRect(find.byKey(const Key('answer-strip')));
      final map = tester.getRect(_viewport);
      expect(strip.top, greaterThanOrEqualTo(bar.bottom - .5), reason: '$size');
      expect(map.top, greaterThanOrEqualTo(strip.bottom - .5), reason: '$size');
      // The map is the whole main column: nothing sits beside it.
      final column = tester.getRect(find.byType(MapScreen));
      expect(map.width, greaterThan(column.width * .9), reason: '$size');
      for (final panel in [
        'Active map',
        'Marker preferences',
        'Manual item search',
        'Map saved-file inputs',
      ]) {
        expect(find.text(panel), findsNothing, reason: '$panel at $size');
      }
    }
  });

  testWidgets('map-controls: Normal use', (tester) async {
    final screenshot = await _savedScreenshot(tester);
    final h = await pumpMapFixture(tester, panelOcr: _InstantOcr());
    await _useScreenshotFolder(tester, h, screenshot.parent.path);
    final pin = _pin('Normal-use pin');
    expect(
      await tester.runAsync(() => h.services.settings.savePin(pin)),
      isTrue,
    );
    await tester.runAsync(h.services.mapSession.readLatest);
    await _until(
      tester,
      () =>
          h.services.mapSession.state.savedScreenshotPath != null &&
          !h.services.mapSession.state.readingLatest,
    );
    // The fixture really holds a saved screenshot, a pin and the map.
    expect(h.services.mapSession.state.savedScreenshotPath, screenshot.path);
    expect(h.services.settings.pins.map((p) => p.id), contains(pin.id));
    expect(h.services.maps.scene, isNotNull);

    expect(find.textContaining('Logs:'), findsNothing);
    expect(find.textContaining('Screenshots:'), findsNothing);
    expect(find.textContaining('Saved evidence'), findsNothing);
    expect(find.textContaining(screenshot.path), findsNothing);
    expect(find.textContaining(pin.frame), findsNothing);
    expect(find.textContaining('revision'), findsNothing);
    expect(find.textContaining(RegExp(r'X [-\d.]+ [•·] Y')), findsNothing);
    // The Map screen has no leftover debug or rail sections.
    for (final text in ['Diagnostics', 'Map saved-file inputs']) {
      expect(
        find.descendant(of: find.byType(MapScreen), matching: find.text(text)),
        findsNothing,
        reason: text,
      );
    }
    expect(
      find.descendant(
        of: find.byType(MapScreen),
        matching: find.textContaining('saved pins'),
      ),
      findsNothing,
    );
    expect(_attribution, findsOneWidget);
  });

  testWidgets('map-controls: Settings cannot be saved', (tester) async {
    final h = await pumpMapFixture(tester);
    await tester.runAsync(
      () => h.services.database.customStatement(
        "CREATE TRIGGER preference_failure BEFORE INSERT ON preferences BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
      ),
    );
    await tapM1Async(
      tester,
      find.byKey(const ValueKey('marker-row-PmcExtracts')),
      () => h.services.settings.error != null,
    );
    final error = h.services.settings.error!;
    expect(
      find.descendant(of: find.byType(MapScreen), matching: find.text(error)),
      findsOneWidget,
    );
    // The switch did not change: the failed save is not shown as applied.
    expect(
      h.services.settings.settings.markerFilters['PmcExtracts'] ?? true,
      isTrue,
    );
  });

  testWidgets('map-controls: Inspector closes over a loaded map', (
    tester,
  ) async {
    final h = await pumpMapFixture(tester);
    final maps = h.services.maps;
    final workspace = tester.state(find.byType(MapWorkspace));
    await tester.tap(find.byTooltip('Zoom in'));
    await settleMapFixture(tester, h);
    await tester.drag(_viewport, const Offset(35, -20));
    await settleMapFixture(tester, h);
    final before = maps.transform;
    expect(find.byKey(const Key('shell-inspector')), findsOneWidget);

    await tester.tap(find.byKey(const Key('inspector-toggle')));
    await settleMapFixture(tester, h);
    expect(find.byKey(const Key('shell-inspector')), findsNothing);
    expect(tester.state(find.byType(MapWorkspace)), same(workspace));
    expect(maps.transform.scale, before.scale);
    expect(maps.transform.translationX, before.translationX);
    expect(maps.transform.translationY, before.translationY);

    tester.view.physicalSize = const Size(960, 720);
    await settleMapFixture(tester, h);
    expect(tester.state(find.byType(MapWorkspace)), same(workspace));
    expect(maps.transform.scale, before.scale);
    expect(maps.transform.translationX, before.translationX);
    expect(maps.transform.translationY, before.translationY);
  });

  testWidgets('map-controls: Selected pin shows no debug text', (tester) async {
    final h = await pumpMapFixture(tester);
    final pin = _pin('Debug-free pin');
    await _selectPin(tester, h, pin);
    expect(
      find.descendant(of: _pinBar, matching: find.text(pin.label)),
      findsOneWidget,
    );
    expect(find.textContaining(pin.frame), findsNothing);
    expect(find.textContaining(RegExp(r'\br\d+\b')), findsNothing);
    expect(find.textContaining('revision'), findsNothing);
  });

  testWidgets('map-controls: Choosing a map', (tester) async {
    final h = await pumpMapFixture(tester);
    await tester.runAsync(
      () => h.services.settings.setMapInputs(followGameLogs: true),
    );
    await settleMapFixture(tester, h);
    expect(h.services.settings.settings.followGameLogs, isTrue);
    expect(
      find.descendant(of: _picker, matching: find.text('Shoreline')),
      findsOneWidget,
    );

    await _openPicker(tester);
    for (final id in supportedMaps) {
      expect(_item(id), findsOneWidget, reason: id);
    }
    expect(_checked(tester, 'shoreline'), isTrue);
    expect(_checked(tester, 'thelab'), isFalse);
    expect(find.textContaining('log following'), findsOneWidget);

    await tapM1Async(
      tester,
      _item('thelab'),
      () => h.services.settings.settings.selectedMap == 'thelab',
    );
    await settleMapFixture(tester, h);
    expect(h.services.settings.settings.followGameLogs, isFalse);
    expect(h.services.maps.selectedMapId, 'thelab');
    expect(
      find.descendant(of: _picker, matching: find.text('The Lab')),
      findsOneWidget,
    );
    await _openPicker(tester);
    expect(_checked(tester, 'thelab'), isTrue);
    expect(_checked(tester, 'shoreline'), isFalse);
  });

  testWidgets('map-controls: Picker while saving', (tester) async {
    final h = await pumpMapFixture(tester);
    h.services.settings.busy = true;
    await _notifySettings(tester, h);
    await _openPicker(tester);
    expect(_menuItem(tester, _item('thelab')).onPressed, isNull);
    await tester.tap(_item('thelab'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(h.services.settings.settings.selectedMap, 'shoreline');
    expect(h.services.maps.selectedMapId, 'shoreline');
    expect(_checked(tester, 'shoreline'), isTrue);
    h.services.settings.busy = false;
  });

  testWidgets('map-controls: Reading the latest screenshot', (tester) async {
    final screenshot = await _savedScreenshot(tester);
    final h = await pumpMapFixture(tester, panelOcr: _InstantOcr());
    await _useScreenshotFolder(tester, h, screenshot.parent.path);
    await _openPicker(tester);
    expect(
      find.descendant(
        of: _readItem,
        matching: find.text('Read latest screenshot'),
      ),
      findsOneWidget,
    );
    expect(_menuItem(tester, _readItem).onPressed, isNotNull);
    await _tapAndWait(
      tester,
      _readItem,
      () =>
          h.services.mapSession.state.savedScreenshotPath == screenshot.path &&
          !h.services.mapSession.state.readingLatest &&
          h.services.mapSession.state.raidEvidence != null,
    );
    expect(h.services.mapSession.state.assumedAssociation, isTrue);
    expect(h.services.maps.selectedMapId, 'shoreline');
    expect(_snack, findsNothing);
  });

  testWidgets('map-controls: No screenshot folder', (tester) async {
    final h = await pumpMapFixture(tester);
    expect(h.services.mapSession.state.screenshotDirectory, isEmpty);
    await _openPicker(tester);
    expect(_menuItem(tester, _readItem).onPressed, isNull);
    await tester.tap(_readItem, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(h.services.mapSession.state.readingLatest, isFalse);
    expect(h.services.mapSession.state.savedScreenshotPath, isNull);
    expect(_snack, findsNothing);
  });

  testWidgets('map-controls: A read is running', (tester) async {
    final screenshot = await _savedScreenshot(tester);
    final ocr = _GatedOcr();
    final h = await pumpMapFixture(tester, panelOcr: ocr);
    await _useScreenshotFolder(tester, h, screenshot.parent.path);
    try {
      await tester.runAsync(() async {
        unawaited(h.services.mapSession.readLatest());
      });
      await _until(
        tester,
        () => h.services.mapSession.state.processingScreenshot,
      );
      expect(h.services.mapSession.state.readingLatest, isTrue);
      await _openPicker(tester);
      expect(
        find.descendant(of: _readItem, matching: find.text('Reading latest…')),
        findsOneWidget,
      );
      expect(_menuItem(tester, _readItem).onPressed, isNull);
    } finally {
      // Release the gated recognition so that disposal does not wait on it.
      if (!ocr.gate.isCompleted) {
        ocr.gate.complete(RaidPanelEvidence(state: RaidPanelState.unavailable));
      }
      await _until(
        tester,
        () => !h.services.mapSession.state.processingScreenshot,
      );
    }
  });

  testWidgets('map-controls: Empty folder', (tester) async {
    final directory = await _tempDirectory(tester);
    final h = await pumpMapFixture(tester);
    await _useScreenshotFolder(tester, h, directory.path);
    await _readLatestForNotice(tester);
    expect(find.textContaining('no screenshot'), findsOneWidget);
    expect(h.services.mapSession.state.savedScreenshotPath, isNull);
    expect(h.services.maps.selectedMapId, 'shoreline');
  });

  testWidgets('map-controls: Screenshot cannot be read', (tester) async {
    final directory = await _tempDirectory(tester);
    // An empty file is the newest screenshot and holds nothing to read.
    final unreadable = File(
      '${directory.path}${Platform.pathSeparator}broken.png',
    );
    await tester.runAsync(() => unreadable.writeAsBytes(const []));
    final h = await pumpMapFixture(tester);
    await _useScreenshotFolder(tester, h, directory.path);
    await _readLatestForNotice(tester);
    expect(find.textContaining('could not be read'), findsOneWidget);
    expect(find.textContaining('broken.png'), findsNothing);
    expect(find.textContaining(directory.path), findsNothing);
    expect(find.textContaining('no screenshot'), findsNothing);
  });

  testWidgets('map-controls: Screenshot folder is unavailable', (tester) async {
    final directory = await _tempDirectory(tester);
    final missing = '${directory.path}${Platform.pathSeparator}absent';
    final h = await pumpMapFixture(tester);
    await _useScreenshotFolder(tester, h, missing);
    await _readLatestForNotice(tester);
    expect(find.textContaining('could not be read'), findsOneWidget);
    expect(find.textContaining('no screenshot'), findsNothing);
    expect(find.textContaining('empty'), findsNothing);
    expect(find.textContaining(missing), findsNothing);
  });

  testWidgets('map-controls: Choosing a floor', (tester) async {
    final h = await pumpMapFixture(tester);
    final maps = h.services.maps;
    SegmentedButton<String> control() =>
        tester.widget<SegmentedButton<String>>(_floorControl);
    Finder segment(String label) =>
        find.descendant(of: _floorControl, matching: find.text(label));
    // Beside the picker, on the same row.
    expect(
      (tester.getCenter(_floorControl).dy - tester.getCenter(_picker).dy).abs(),
      lessThan(8),
    );
    expect(segment('Ground'), findsOneWidget);
    expect(segment('Upper'), findsOneWidget);
    expect(segment('Auto'), findsNothing);
    expect(control().selected, {'ground'});

    await tester.tap(segment('Upper'));
    await settleMapFixture(tester, h);
    expect(maps.floorSelection!.isLayerVisible('upper'), isTrue);
    expect(control().selected, containsAll(['ground', 'upper']));

    await tester.tap(segment('Upper'));
    await settleMapFixture(tester, h);
    expect(maps.floorSelection!.isLayerVisible('upper'), isFalse);
    expect(control().selected, isNot(contains('upper')));

    // A map with automatic floors leads with Auto, which follows the player.
    await tester.runAsync(() => h.services.settings.setMap('thelab'));
    await settleMapFixture(tester, h);
    expect(maps.automaticFloorSupported, isTrue);
    expect(segment('Auto'), findsOneWidget);
    expect(control().selected, contains('auto'));
    await tester.tap(segment('Auto'));
    await settleMapFixture(tester, h);
    expect(maps.automaticFloorFollowing, isFalse);
    expect(control().selected, isNot(contains('auto')));
  });

  testWidgets('map-controls: Map with no floors', (tester) async {
    // A floor policy always has a base floor, so a map with no floors is one
    // that did not load: there is no policy to list.
    final h = await pumpMapFixture(tester, packFails: true);
    expect(h.services.maps.preparedMap, isNull);
    expect(_floorControl, findsNothing);
    expect(_picker, findsOneWidget);
  });

  testWidgets('map-controls: Artwork unavailable', (tester) async {
    final h = await pumpMapFixture(tester, artwork: false);
    expect(h.services.maps.error, isNotNull);
    expect(_floorControl, findsNothing);
    expect(
      find.descendant(of: _picker, matching: find.text('Shoreline')),
      findsOneWidget,
    );
    await _openPicker(tester);
    expect(_menuItem(tester, _item('thelab')).onPressed, isNotNull);
    await tester.tap(_item('thelab'));
    await settleMapFixture(tester, h);
    expect(_floorControl, findsNothing);
  });

  testWidgets('map-controls: Actions are reachable', (tester) async {
    final h = await pumpMapFixture(tester);
    h.services.maps.setPlayerSample(GamePoint(64, 192));
    await settleMapFixture(tester, h);
    final map = tester.getRect(_viewport);
    expect(_actions, findsOneWidget);
    for (final tooltip in _actionTooltips) {
      expect(find.byTooltip(tooltip), findsOneWidget, reason: tooltip);
      expect(_action(tester, tooltip).onPressed, isNotNull, reason: tooltip);
      final rect = tester.getRect(find.byTooltip(tooltip));
      expect(map.contains(rect.topLeft), isTrue, reason: '$tooltip on the map');
      expect(map.contains(rect.bottomRight), isTrue, reason: tooltip);
    }
    // The controls live in the viewport overlay, not in a toolbar above it.
    expect(find.widgetWithText(OutlinedButton, 'Fit map'), findsNothing);
  });

  testWidgets('map-controls: No position or no artwork', (tester) async {
    final h = await pumpMapFixture(tester, packFails: true);
    expect(h.services.maps.preparedMap, isNull);
    expect(h.services.maps.playerPosition, isNull);
    for (final tooltip in ['Center on player', 'Fit map']) {
      expect(_action(tester, tooltip).onPressed, isNull, reason: tooltip);
    }
    expect(_action(tester, 'Map help').onPressed, isNotNull);
  });

  testWidgets('map-controls: Keyboard on an on-map control', (tester) async {
    final h = await pumpMapFixture(tester);
    final scale = h.services.maps.transform.scale;
    var attempts = 0;
    bool onZoomIn() =>
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<Tooltip>()
            ?.message ==
        'Zoom in';
    while (!onZoomIn() && attempts++ < 80) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(onZoomIn(), isTrue, reason: 'Zoom in is keyboard reachable');
    expect(
      tester
          .getRect(_viewport)
          .contains(tester.getCenter(find.byTooltip('Zoom in'))),
      isTrue,
      reason: 'Zoom in is on the map',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settleMapFixture(tester, h);
    expect(h.services.maps.transform.scale, closeTo(scale * 1.25, 1e-9));
    expect(find.text('Visible map markers and pins'), findsNothing);
  });

  testWidgets('map-controls: Pin selected', (tester) async {
    final h = await pumpMapFixture(tester);
    expect(_pinBar, findsNothing);
    final height = tester.getSize(_viewport).height;
    final pin = _pin('Bar pin');
    await _selectPin(tester, h, pin);
    expect(_pinBar, findsOneWidget);
    expect(
      find.descendant(of: _pinBar, matching: find.text(pin.label)),
      findsOneWidget,
    );
    for (final key in ['map-pin-edit', 'map-pin-remove', 'map-pin-close']) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
    expect(tester.getSize(_viewport).height, height);
    final map = tester.getRect(_viewport);
    final bar = tester.getRect(_pinBar);
    expect(map.contains(bar.topLeft), isTrue);
    expect(map.contains(bar.bottomRight), isTrue);
  });

  testWidgets('map-controls: Pin closed', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final h = await pumpMapFixture(tester);
      final pin = _pin('Closing pin');
      await _selectPin(tester, h, pin);
      expect(_pinSemanticsSelected(tester, pin.label), isTrue);
      await tester.tap(find.byKey(const Key('map-pin-close')));
      await settleMapFixture(tester, h);
      expect(_pinBar, findsNothing);
      expect(_pinSemanticsSelected(tester, pin.label), isFalse);
      expect(h.services.settings.pins, hasLength(1));
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('map-controls: Actions while saving', (tester) async {
    final h = await pumpMapFixture(tester);
    await _selectPin(tester, h, _pin('Saving pin'));
    h.services.settings.busy = true;
    await _notifySettings(tester, h);
    TextButton button(String key) =>
        tester.widget<TextButton>(find.byKey(Key(key)));
    expect(button('map-pin-edit').onPressed, isNull);
    expect(button('map-pin-remove').onPressed, isNull);
    expect(button('map-pin-close').onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('map-pin-close')));
    await tester.pumpAndSettle();
    expect(_pinBar, findsNothing);
    h.services.settings.busy = false;
  });

  testWidgets('map-controls: overlays do not overlap at 960 px', (
    tester,
  ) async {
    final h = await pumpMapFixture(tester, size: const Size(960, 720));
    await _selectPin(tester, h, _pin('Geometry pin'));
    final map = tester.getRect(_viewport);
    final rects = {
      'picker': tester.getRect(_picker),
      'floor': tester.getRect(_floorControl),
      'actions': tester.getRect(_actions),
      'pin bar': tester.getRect(_pinBar),
      'attribution': tester.getRect(_attribution),
    };
    final names = rects.keys.toList();
    for (final name in names) {
      final rect = rects[name]!;
      expect(map.contains(rect.topLeft), isTrue, reason: '$name inside map');
      expect(
        map.contains(rect.bottomRight - const Offset(.5, .5)),
        isTrue,
        reason: '$name inside map',
      );
    }
    for (var i = 0; i < names.length; i++) {
      for (var j = i + 1; j < names.length; j++) {
        expect(
          rects[names[i]]!.overlaps(rects[names[j]]!),
          isFalse,
          reason:
              '${names[i]} ${rects[names[i]]} overlaps ${names[j]} '
              '${rects[names[j]]}',
        );
      }
    }
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:blackgrid/application/map_session_controller.dart';
import 'package:blackgrid/application/settings_controller.dart';
import 'package:blackgrid/domain/map_coordinates.dart';
import 'package:blackgrid/data/raid_panel_ocr.dart';
import 'package:blackgrid/domain/raid_panel_text_parser.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:blackgrid/ui/map_inspector.dart';
import 'package:blackgrid/ui/marker_popup.dart';
import 'package:blackgrid/ui/pin_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/map_widget_harness.dart';

/// A 1 x 1 PNG; the fake OCR never decodes it.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

/// An OCR that answers each read with the next scripted panel.
final class _ScriptedOcr extends RaidPanelOcr {
  _ScriptedOcr(this.panels);
  final List<RaidPanelEvidence> panels;

  @override
  Future<RaidPanelEvidence> recognize(Uint8List imageBytes) =>
      Future.value(panels.removeAt(0));
}

RaidPanelEvidence _matched(List<String> names) =>
    RaidPanelEvidence(state: RaidPanelState.recognized, extractNames: names);

/// Two extracts on the ground floor: one at the scene centre and one in its
/// corner, so that zooming in leaves the corner one outside the viewport.
final _extraMarkers = [
  {
    'id': 'alpha-exit',
    'name': 'Alpha gate',
    'floorId': 'ground',
    'category': 'extracts',
    'filterKey': 'PmcExtracts',
    'position': {'x': 240, 'z': 20},
    'details': {'description': 'Alpha gate offline fixture details'},
    'source': {'fixture': true},
  },
];

const _bothNames = ['Ground exit', 'Alpha gate'];

Finder get _inspector => find.byKey(const Key('map-inspector'));
Finder get _empty => find.byKey(const Key('raid-empty'));
Finder get _age => find.byKey(const Key('raid-age'));
Finder _raidRow(String id) => find.byKey(ValueKey('raid-row-$id'));
Finder get _anyRaidRow => find.byWidgetPredicate(
  (widget) => switch (widget.key) {
    ValueKey<String>(:final value) => value.startsWith('raid-row-'),
    _ => false,
  },
);
Finder _pinRow(String label) => find.byKey(ValueKey('pin-row-pin-$label'));
Finder _pinRemove(String label) =>
    find.byKey(ValueKey('pin-remove-pin-$label'));
Finder get _addPin => find.byKey(const Key('pins-add'));

CustomPin _pin(String label) => CustomPin(
  id: 'pin-$label',
  mapId: 'shoreline',
  x: .8,
  y: .8,
  frame: 'legacy-normalized',
  frameRevision: 0,
  label: label,
  updatedAt: DateTime.utc(2026),
);

/// Writes a screenshot modified at [modified] into a new folder and points the
/// Map's screenshot input at it, with log following off.
Future<Directory> _useFolder(WidgetTester tester, MapWidgetHarness h) async {
  final directory = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('blackgrid-map-inspector-'),
  ))!;
  addTearDown(() => directory.delete(recursive: true));
  await tester.runAsync(
    () => h.services.settings.setMapInputs(
      screenshotDirectory: directory.path,
      followGameLogs: false,
    ),
  );
  return directory;
}

/// Saves a screenshot in [directory] and reads it as the newest one.
Future<void> _read(
  WidgetTester tester,
  MapWidgetHarness h,
  Directory directory,
  String name,
  DateTime modified,
) async {
  final file = File('${directory.path}${Platform.pathSeparator}$name.png');
  final outcome = await tester.runAsync(() async {
    await file.writeAsBytes(_png);
    await file.setLastModified(modified);
    return h.services.mapSession.readLatest();
  });
  expect(outcome, isA<ReadLatestApplied>());
  await tester.pump();
}

/// Pumps the whole app on the fixture map with the inspector open.
Future<MapWidgetHarness> _pumpApp(
  WidgetTester tester, {
  List<RaidPanelEvidence> panels = const [],
}) => pumpMapFixture(
  tester,
  panelOcr: _ScriptedOcr([...panels]),
  extraMarkers: _extraMarkers,
);

/// Pumps only the inspector, with [clock] as its time source.
Future<MapWidgetHarness> _pumpInspector(
  WidgetTester tester, {
  required DateTime Function() clock,
  List<RaidPanelEvidence> panels = const [],
}) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final h = (await tester.runAsync(
    () => MapWidgetHarness.create(
      panelOcr: _ScriptedOcr([...panels]),
      extraMarkers: _extraMarkers,
    ),
  ))!;
  addTearDown(h.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MapInspector(services: h.services, clock: clock),
        ),
      ),
    ),
  );
  return h;
}

/// Matches [names] from a screenshot modified at [modified].
Future<void> _match(
  WidgetTester tester,
  MapWidgetHarness h,
  DateTime modified, [
  String name = 'first',
]) async {
  final directory = await _useFolder(tester, h);
  await _read(tester, h, directory, name, modified);
}

ViewportPoint _centre(MapWidgetHarness h) {
  final size = h.services.maps.viewportSize;
  return ViewportPoint(size.width / 2, size.height / 2);
}

/// Completes once [settings] is not saving; a tap that starts a save has
/// already set `busy` when it returns.
Future<void> _idle(SettingsController settings) {
  if (!settings.busy) return Future.value();
  final done = Completer<void>();
  void check() {
    if (settings.busy) return;
    settings.removeListener(check);
    done.complete();
  }

  settings.addListener(check);
  return done.future;
}

bool _inView(MapWidgetHarness h, String id) {
  final point = h.services.maps
      .visibleMarkers(margin: 0)
      .where((marker) => marker.marker.id == id);
  return point.isNotEmpty;
}

void main() {
  final modified = DateTime.utc(2026, 5, 1, 11, 50);
  final now = DateTime.utc(2026, 5, 1, 12);

  testWidgets('map-controls: Matched extracts', (tester) async {
    final h = await _pumpApp(tester, panels: [_matched(_bothNames)]);
    await _match(tester, h, modified);

    expect(_raidRow('ground-exit'), findsOneWidget);
    expect(_raidRow('alpha-exit'), findsOneWidget);
    expect(_empty, findsNothing);
    for (final id in ['ground-exit', 'alpha-exit']) {
      expect(
        find.descendant(
          of: _raidRow(id),
          matching: find.byWidgetPredicate(
            (widget) => widget is CustomPaint && widget.painter != null,
          ),
        ),
        findsOneWidget,
        reason: 'badge of $id',
      );
    }
    expect(
      find.descendant(
        of: _raidRow('alpha-exit'),
        matching: find.text('Alpha gate'),
      ),
      findsOneWidget,
    );

    await tester.tap(_raidRow('alpha-exit'));
    await tester.pump();
    expect(h.services.maps.selectedMarkerProjection?.marker.id, 'alpha-exit');
  });

  testWidgets('map-controls: No reading', (tester) async {
    final h = await _pumpApp(tester);

    expect(_inspector, findsOneWidget);
    expect(_empty, findsOneWidget);
    expect(_anyRaidRow, findsNothing);
    expect(_age, findsNothing);
    expect(h.services.mapSession.raidMatchedAt, isNull);
  });

  testWidgets('map-controls: No reading after an empty raid panel', (
    tester,
  ) async {
    final h = await _pumpApp(
      tester,
      panels: [RaidPanelEvidence(state: RaidPanelState.empty)],
    );
    await _match(tester, h, modified);

    expect(h.services.mapSession.raidMatchedAt, isNotNull);
    expect(_empty, findsOneWidget);
    expect(_anyRaidRow, findsNothing);
    expect(_age, findsNothing);
  });

  testWidgets('map-controls: Matched extract is hidden', (tester) async {
    final h = await _pumpApp(tester, panels: [_matched(_bothNames)]);
    await _match(tester, h, modified);
    expect(_raidRow('alpha-exit'), findsOneWidget);

    await tester.runAsync(
      () => h.services.settings.setMarker('PmcExtracts', false),
    );
    await settleMapFixture(tester, h);

    expect(_anyRaidRow, findsNothing);
    expect(_empty, findsOneWidget);
    // A stale request for the hidden marker selects nothing.
    h.services.maps.revealMarker('alpha-exit');
    expect(h.services.maps.selectedMarkerProjection, isNull);
  });

  testWidgets('map-controls: Matched extract outside the view', (tester) async {
    final h = await _pumpApp(tester, panels: [_matched(_bothNames)]);
    await _match(tester, h, modified);
    h.services.maps.zoomAt(_centre(h), 8);
    await settleMapFixture(tester, h);

    expect(_inView(h, 'alpha-exit'), isFalse);
    expect(_raidRow('alpha-exit'), findsOneWidget);
    expect(_raidRow('ground-exit'), findsOneWidget);
  });

  testWidgets('map-controls: Choosing an off-view row', (tester) async {
    final h = await _pumpApp(tester, panels: [_matched(_bothNames)]);
    await _match(tester, h, modified);
    h.services.maps.zoomAt(_centre(h), 8);
    await settleMapFixture(tester, h);
    final scale = h.services.maps.transform.scale;
    expect(_inView(h, 'alpha-exit'), isFalse);

    await tester.tap(_raidRow('alpha-exit'));
    await settleMapFixture(tester, h);

    expect(h.services.maps.transform.scale, scale);
    expect(_inView(h, 'alpha-exit'), isTrue);
    expect(h.services.maps.selectedMarkerProjection?.marker.id, 'alpha-exit');
    expect(find.byType(MarkerPopup), findsOneWidget);
  });

  testWidgets('map-controls: Choosing an in-view row', (tester) async {
    final h = await _pumpApp(tester, panels: [_matched(_bothNames)]);
    await _match(tester, h, modified);
    final before = h.services.maps.transform;
    expect(_inView(h, 'ground-exit'), isTrue);

    await tester.tap(_raidRow('ground-exit'));
    await settleMapFixture(tester, h);

    final after = h.services.maps.transform;
    expect(after.scale, before.scale);
    expect(after.translationX, before.translationX);
    expect(after.translationY, before.translationY);
    expect(find.byType(MarkerPopup), findsOneWidget);
  });

  testWidgets('map-controls: Selected pin gives way', (tester) async {
    final h = await _pumpApp(tester, panels: [_matched(_bothNames)]);
    await _match(tester, h, modified);
    final pin = _pin('Camp');
    expect(
      await tester.runAsync(() => h.services.settings.savePin(pin)),
      isTrue,
    );
    await settleMapFixture(tester, h);
    final point = h.services.maps.projectPin(pin)!;
    final viewport = find.byKey(const Key('native-map-viewport'));
    await tester.tapAt(tester.getTopLeft(viewport) + Offset(point.x, point.y));
    await settleMapFixture(tester, h);
    expect(find.byKey(const Key('map-pin-bar')), findsOneWidget);

    await tester.tap(_raidRow('ground-exit'));
    await settleMapFixture(tester, h);

    expect(find.byKey(const Key('map-pin-bar')), findsNothing);
    expect(h.services.maps.selectedMarkerProjection?.marker.id, 'ground-exit');
  });

  testWidgets('map-controls: Age advances', (tester) async {
    var clock = now;
    final h = await _pumpInspector(
      tester,
      clock: () => clock,
      panels: [_matched(_bothNames)],
    );
    await _match(tester, h, modified);

    expect(
      find.descendant(of: _age, matching: find.text('Screenshot 10 min ago')),
      findsOneWidget,
    );

    clock = now.add(const Duration(minutes: 1));
    await tester.pump(const Duration(minutes: 1));

    expect(
      find.descendant(of: _age, matching: find.text('Screenshot 11 min ago')),
      findsOneWidget,
    );
  });

  testWidgets('map-controls: Later non-panel screenshot', (tester) async {
    final h = await _pumpInspector(
      tester,
      clock: () => now,
      panels: [
        _matched(_bothNames),
        RaidPanelEvidence(state: RaidPanelState.partial),
      ],
    );
    final directory = await _useFolder(tester, h);
    await _read(tester, h, directory, 'first', modified);
    expect(
      find.descendant(of: _age, matching: find.text('Screenshot 10 min ago')),
      findsOneWidget,
    );

    await _read(
      tester,
      h,
      directory,
      'second',
      now.subtract(const Duration(minutes: 2)),
    );

    expect(
      h.services.mapSession.state.savedScreenshotModifiedAt?.toUtc(),
      now.subtract(const Duration(minutes: 2)),
    );
    expect(_raidRow('alpha-exit'), findsOneWidget);
    expect(
      find.descendant(of: _age, matching: find.text('Screenshot 10 min ago')),
      findsOneWidget,
    );
  });

  testWidgets('map-controls: Pins listed', (tester) async {
    final h = await _pumpInspector(tester, clock: () => now);
    for (final label in ['Camp', 'Bridge']) {
      expect(
        await tester.runAsync(() => h.services.settings.savePin(_pin(label))),
        isTrue,
      );
    }
    await tester.pump();

    for (final label in ['Camp', 'Bridge']) {
      expect(
        find.descendant(of: _pinRow(label), matching: find.text(label)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _pinRow(label),
          matching: find.byWidgetPredicate(
            (widget) => widget is CustomPaint && widget.painter != null,
          ),
        ),
        findsOneWidget,
        reason: 'badge of $label',
      );
    }
    for (final debug in ['legacy', 'revision', 'X 0', 'Y 0']) {
      expect(find.textContaining(debug), findsNothing);
    }

    await tester.tap(_pinRow('Camp'));
    await tester.pumpAndSettle();
    expect(find.byType(PinEditor), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is EditableText && widget.controller.text == 'Camp',
      ),
      findsOneWidget,
    );
  });

  testWidgets('map-controls: No pins', (tester) async {
    await _pumpInspector(tester, clock: () => now);

    expect(_addPin, findsOneWidget);
    expect(find.text('Add pin'), findsOneWidget);
    expect(find.text('No saved pins for this map'), findsOneWidget);
  });

  testWidgets('map-controls: Removal while saving', (tester) async {
    final h = await _pumpInspector(tester, clock: () => now);
    expect(
      await tester.runAsync(() => h.services.settings.savePin(_pin('Camp'))),
      isTrue,
    );
    await tester.pump();
    h.services.settings.busy = true;
    // ignore: invalid_use_of_protected_member
    h.services.settings.notifyListeners();
    await tester.pump();

    await tester.tap(_addPin, warnIfMissed: false);
    await tester.tap(_pinRow('Camp'), warnIfMissed: false);
    await tester.tap(_pinRemove('Camp'), warnIfMissed: false);
    await tester.pump();

    expect(find.byType(PinEditor), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(h.services.settings.pins, hasLength(1));
    h.services.settings.busy = false;
  });

  testWidgets('map-controls: Pin removal asks first', (tester) async {
    final h = await _pumpInspector(tester, clock: () => now);
    expect(
      await tester.runAsync(() => h.services.settings.savePin(_pin('Camp'))),
      isTrue,
    );
    await tester.pump();

    await tester.tap(_pinRemove('Camp'));
    await tester.pumpAndSettle();
    expect(find.text('Remove pin record?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(h.services.settings.pins, hasLength(1));

    await tester.tap(_pinRemove('Camp'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pump();
    await tester.runAsync(() => _idle(h.services.settings));
    await tester.pump();
    expect(h.services.settings.pins, isEmpty);
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:blackgrid/application/settings_controller.dart';
import 'package:blackgrid/domain/marker_categories.dart';
import 'package:blackgrid/maps/map_marker_icons.dart';
import 'package:blackgrid/ui/marker_preferences.dart';
import 'package:blackgrid/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/markers/icon_set.dart';
import '../support/map_widget_harness.dart';

const _manifestPath = 'assets/map_markers/manifest.json';
const _background = Color(0xFF090F0D);
const _exitGreen = Color(0xFF48D28B);
const _dangerRed = Color(0xFFFF5252);
const _utility = Color(0xFFB7A6F0);

/// The centre of a tile's 24 x 24 badge canvas.
const _centre = Offset(12, 12);

const _tinySvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
    '<circle cx="12" cy="12" r="6" fill="#FFFFFF"/></svg>';

const _icons = [
  ('PmcExtracts', 'exit'),
  ('ScavExtracts', 'exit'),
  ('Hazards', 'danger'),
  ('lootLoose', 'loot'),
  ('locks', 'utility'),
  ('BtrStops', 'utility'),
  ('stationaryWeapons', 'utility'),
  ('CustomPins', 'pin'),
];

String _vecPath(String key) =>
    'assets/map_markers/compiled/'
    '${iconFileName(key).replaceAll('.svg', '')}.vec';

ByteData _data(List<int> bytes) =>
    Uint8List.fromList(bytes).buffer.asByteData();

ByteData _manifest() => _data(
  utf8.encode(
    jsonEncode({
      'schemaVersion': 1,
      'scope': 'release',
      'background': '#090F0D',
      'badge': {'diameter': 24, 'selectedDiameter': 30, 'glyph': 16, 'ring': 2},
      'roles': {
        'exit': '#48D28B',
        'danger': '#FF5252',
        'loot': '#E8A04A',
        'utility': '#B7A6F0',
        'pin': '#40C4FF',
      },
      'icons': [
        for (final (key, role) in _icons)
          {
            'key': key,
            'file': iconFileName(key),
            'role': role,
            'sha256': 'ignored',
            'provenance': <String, Object?>{},
          },
      ],
    }),
  ),
);

/// Hand-written asset source that can hold the manifest until released and
/// can leave chosen glyph files out.
class _Assets {
  _Assets({this.missing = const {}});

  /// The keys whose compiled glyph is absent, so they fail to decode.
  final Set<String> missing;
  Completer<void>? manifestGate;

  late final Map<String, ByteData> _assets = {
    _manifestPath: _manifest(),
    for (final (key, _) in _icons)
      if (!missing.contains(key))
        _vecPath(key): _data(compileIconSvg(_tinySvg, 'tiny')),
  };

  Future<ByteData> load(String path) async {
    if (path == _manifestPath) await manifestGate?.future;
    final data = _assets[path];
    if (data == null) throw StateError('no asset $path');
    return data;
  }
}

class _Fixture {
  _Fixture(this.h, this.icons, this.assets);
  final MapWidgetHarness h;
  final MapMarkerIcons icons;
  final _Assets assets;
  SettingsController get settings => h.services.settings;
}

/// Pumps the grid for [keys] on a real [SettingsController].
///
/// [hidden] keys are saved as hidden first. [hold] keeps the manifest gated
/// until `assets.manifestGate` completes; the gate is created inside
/// `runAsync` because a completer from the fake-async zone never completes
/// from inside it. Without [hold] the icons are fully loaded.
Future<_Fixture> _pump(
  WidgetTester tester, {
  required List<String> keys,
  Set<String> hidden = const {},
  Set<String> missing = const {},
  bool hold = false,
}) async {
  tester.view.physicalSize = const Size(900, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final fixture = (await tester.runAsync(() async {
    final source = _Assets(missing: missing);
    if (hold) source.manifestGate = Completer<void>();
    final icons = MapMarkerIcons(load: source.load);
    final h = await MapWidgetHarness.create(markerIcons: icons);
    for (final key in hidden) {
      await h.services.settings.setMarker(key, false);
    }
    if (!hold) await icons.open();
    return _Fixture(h, icons, source);
  }))!;
  addTearDown(fixture.h.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: MarkerPreferencesGrid(
            services: fixture.h.services,
            keys: keys,
          ),
        ),
      ),
    ),
  );
  return fixture;
}

Finder _tile(String key) => find.byKey(ValueKey('marker-tile-$key'));

Finder get _anyTile => find.byWidgetPredicate(
  (widget) => switch (widget.key) {
    ValueKey<String>(:final value) => value.startsWith('marker-tile-'),
    _ => false,
  },
);

Finder _badge(String key) => find.descendant(
  of: _tile(key),
  matching: find.byWidgetPredicate(
    (widget) => widget is CustomPaint && widget.painter != null,
  ),
);

RenderObject _canvas(WidgetTester tester, String key) =>
    tester.renderObject(_badge(key));

/// Completes when [settings] is not saving; the save a tap starts has already
/// set `busy` by the time the tap returns.
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

Future<void> _click(WidgetTester tester, _Fixture f, String key) async {
  await tester.tap(_tile(key));
  await tester.runAsync(() => _idle(f.settings));
  await tester.pump();
}

bool _shown(_Fixture f, String key) =>
    f.settings.settings.markerFilters[key] ?? true;

/// A `drawImageRect` of the 64 x 64 source into a 16 x 16 square on [centre].
PaintPatternPredicate _glyphAt(
  Offset centre, {
  ui.Image? image,
  Color? colour,
}) => (Symbol name, List<dynamic> arguments) {
  if (name != #drawImageRect) return false;
  final destination = arguments[2] as Rect;
  if (destination != Rect.fromCenter(center: centre, width: 16, height: 16)) {
    return false;
  }
  if (image != null && !image.isCloneOf(arguments[0] as ui.Image)) {
    throw 'The glyph at $centre drew a different image.';
  }
  final paint = arguments[3] as Paint;
  if (colour != null &&
      paint.colorFilter != ColorFilter.mode(colour, BlendMode.srcIn)) {
    throw 'The glyph filter was ${paint.colorFilter}, not $colour srcIn.';
  }
  return true;
};

/// A circle drawn on [at] whose [style] matches.
PaintPatternPredicate _circleAt(
  Offset at, {
  required PaintingStyle style,
  double? radius,
  Color? colour,
}) => (Symbol name, List<dynamic> arguments) {
  if (name != #drawCircle || arguments[0] != at) return false;
  final paint = arguments[2] as Paint;
  if (paint.style != style) return false;
  if (radius != null && arguments[1] != radius) return false;
  if (colour != null && paint.color.toARGB32() != colour.toARGB32()) {
    return false;
  }
  return true;
};

/// Expects the disc and ring of one 24 px badge, in order.
PaintPattern _discAndRing({required Color ring, double opacity = 1}) => paints
  ..something(
    _circleAt(
      _centre,
      style: PaintingStyle.fill,
      radius: 11,
      colour: _background.withValues(alpha: opacity),
    ),
  )
  ..something(
    _circleAt(
      _centre,
      style: PaintingStyle.stroke,
      radius: 11,
      colour: ring.withValues(alpha: opacity),
    ),
  );

PaintPattern _dot(Color colour) => paints
  ..something(
    _circleAt(_centre, style: PaintingStyle.fill, radius: 3, colour: colour),
  );

void main() {
  testWidgets('shows one labelled tile per saveable map key plus Saved pins', (
    tester,
  ) async {
    await _pump(
      tester,
      keys: markerPreferenceKeys([
        'PmcExtracts',
        'Hazards',
        'lootLoose',
        'CustomPins',
      ]),
    );

    expect(_anyTile, findsNWidgets(4));
    for (final label in [
      'PMC extracts',
      'Hazards',
      'Loose loot',
      'Saved pins',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    for (final raw in ['PmcExtracts', 'lootLoose', 'CustomPins']) {
      expect(find.text(raw), findsNothing);
      expect(find.textContaining(raw), findsNothing);
    }
  });

  testWidgets('every tile has the same size whatever its label', (
    tester,
  ) async {
    await _pump(
      tester,
      keys: markerPreferenceKeys([
        'BtrStops',
        'stationaryWeapons',
        'locks',
        'CustomPins',
      ]),
    );

    final btr = tester.getSize(_tile('BtrStops'));
    expect(tester.getSize(_tile('stationaryWeapons')), btr);
    expect(tester.getSize(_tile('locks')), btr);
    expect(tester.getSize(_tile('CustomPins')), btr);
    expect(btr, const Size(88, 76));
    expect(find.text('Stationary weapons'), findsOneWidget);
  });

  testWidgets('map without markers shows only the Saved pins tile', (
    tester,
  ) async {
    await _pump(tester, keys: markerPreferenceKeys(['CustomPins']));

    expect(_anyTile, findsOneWidget);
    expect(_tile('CustomPins'), findsOneWidget);
    expect(find.text('Saved pins'), findsOneWidget);
  });

  testWidgets('clicking a shown tile hides its category', (tester) async {
    final f = await _pump(tester, keys: ['PmcExtracts', 'Hazards', 'locks']);
    expect(_shown(f, 'PmcExtracts'), isTrue);

    await _click(tester, f, 'PmcExtracts');

    expect(f.settings.settings.markerFilters['PmcExtracts'], isFalse);
    expect(_shown(f, 'Hazards'), isTrue);
    expect(_shown(f, 'locks'), isTrue);
    expect(
      find.descendant(
        of: _tile('PmcExtracts'),
        matching: find.byIcon(Icons.check),
      ),
      findsNothing,
      reason: 'the tile shows the hidden state',
    );
    expect(
      find.descendant(of: _tile('Hazards'), matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );
  });

  testWidgets('clicking a hidden tile shows its category', (tester) async {
    final f = await _pump(
      tester,
      keys: ['PmcExtracts', 'Hazards'],
      hidden: {'PmcExtracts'},
    );
    expect(_shown(f, 'PmcExtracts'), isFalse);

    await _click(tester, f, 'PmcExtracts');

    expect(f.settings.settings.markerFilters['PmcExtracts'], isTrue);
    expect(
      find.descendant(
        of: _tile('PmcExtracts'),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
  });

  testWidgets('tiles ignore clicks while settings are saving', (tester) async {
    final f = await _pump(tester, keys: ['PmcExtracts', 'Hazards']);
    InkWell ink(String key) => tester.widget<InkWell>(
      find.descendant(of: _tile(key), matching: find.byType(InkWell)),
    );
    expect(ink('Hazards').onTap, isNotNull);

    f.settings.busy = true;
    // ignore: invalid_use_of_protected_member
    f.settings.notifyListeners();
    await tester.pump();
    final before = f.settings.settings.markerFilters;

    expect(ink('Hazards').onTap, isNull);
    await tester.tap(_tile('Hazards'));
    await tester.pump();
    expect(f.settings.settings.markerFilters, before);
    expect(_shown(f, 'Hazards'), isTrue);

    f.settings.busy = false;
    // ignore: invalid_use_of_protected_member
    f.settings.notifyListeners();
    await tester.pump();
    expect(ink('Hazards').onTap, isNotNull);
  });

  testWidgets('shown tile has a check mark and hidden tile is dimmed', (
    tester,
  ) async {
    final f = await _pump(
      tester,
      keys: ['ScavExtracts', 'Hazards'],
      hidden: {'Hazards'},
    );
    Finder check(String key) =>
        find.descendant(of: _tile(key), matching: find.byIcon(Icons.check));
    Color? labelColour(String label) => tester
        .widget<Text>(
          find.descendant(
            of: find.byType(MarkerPreferencesGrid),
            matching: find.text(label),
          ),
        )
        .style
        ?.color;

    expect(check('ScavExtracts'), findsOneWidget);
    expect(check('Hazards'), findsNothing);
    expect(labelColour('Scav extracts'), GridColors.text);
    expect(labelColour('Hazards'), GridColors.muted);

    expect(_canvas(tester, 'ScavExtracts'), _discAndRing(ring: _exitGreen));
    expect(
      _canvas(tester, 'Hazards'),
      _discAndRing(ring: _dangerRed, opacity: dimmedMarkerOpacity),
    );
    expect(
      _canvas(tester, 'Hazards'),
      paints..something(
        _glyphAt(
          _centre,
          image: f.icons.icon('Hazards')!.glyph,
          colour: _dangerRed.withValues(alpha: dimmedMarkerOpacity),
        ),
      ),
    );
  });

  testWidgets('tile semantics are a toggle with label and state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final f = await _pump(tester, keys: ['Hazards'], hidden: {'Hazards'});

    expect(
      tester.getSemantics(_tile('Hazards')),
      matchesSemantics(
        label: 'Hazards',
        isButton: true,
        hasToggledState: true,
        isToggled: false,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );

    await _click(tester, f, 'Hazards');

    expect(
      tester.getSemantics(_tile('Hazards')),
      matchesSemantics(
        label: 'Hazards',
        isButton: true,
        hasToggledState: true,
        isToggled: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('loaded tile draws the category glyph in its role colour', (
    tester,
  ) async {
    final f = await _pump(tester, keys: ['PmcExtracts']);

    final pattern = _discAndRing(ring: _exitGreen)
      ..something(
        _glyphAt(
          _centre,
          image: f.icons.icon('PmcExtracts')!.glyph,
          colour: _exitGreen,
        ),
      );
    expect(_canvas(tester, 'PmcExtracts'), pattern);
    expect(_canvas(tester, 'PmcExtracts'), isNot(_dot(_exitGreen)));
  });

  testWidgets('tiles draw fallback badges and toggle while icons load', (
    tester,
  ) async {
    final f = await _pump(tester, keys: ['PmcExtracts', 'Hazards'], hold: true);
    expect(_canvas(tester, 'PmcExtracts'), _dot(_exitGreen));
    expect(_canvas(tester, 'Hazards'), _dot(_dangerRed));
    expect(
      _canvas(tester, 'Hazards'),
      isNot(paints..something(_glyphAt(_centre))),
    );

    await _click(tester, f, 'PmcExtracts');
    expect(f.settings.settings.markerFilters['PmcExtracts'], isFalse);
    expect(_canvas(tester, 'Hazards').debugNeedsPaint, isFalse);

    await tester.runAsync(() async {
      f.assets.manifestGate!.complete();
      await f.icons.open();
    });
    expect(
      _canvas(tester, 'Hazards').debugNeedsPaint,
      isTrue,
      reason: 'the loader notification marks the tile for repaint',
    );
    await tester.pump();

    expect(
      _canvas(tester, 'Hazards'),
      _discAndRing(ring: _dangerRed)..something(
        _glyphAt(
          _centre,
          image: f.icons.icon('Hazards')!.glyph,
          colour: _dangerRed,
        ),
      ),
    );
    expect(_canvas(tester, 'Hazards'), isNot(_dot(_dangerRed)));
  });

  testWidgets('a failed icon draws the fallback badge only on its tile', (
    tester,
  ) async {
    final f = await _pump(
      tester,
      keys: ['PmcExtracts', 'locks'],
      missing: {'locks'},
    );
    expect(f.icons.failures, isNotEmpty);

    expect(_canvas(tester, 'locks'), _discAndRing(ring: _utility));
    expect(_canvas(tester, 'locks'), _dot(_utility));
    expect(
      _canvas(tester, 'locks'),
      isNot(paints..something(_glyphAt(_centre))),
    );
    expect(
      _canvas(tester, 'PmcExtracts'),
      paints..something(
        _glyphAt(
          _centre,
          image: f.icons.icon('PmcExtracts')!.glyph,
          colour: _exitGreen,
        ),
      ),
    );
    expect(_canvas(tester, 'PmcExtracts'), isNot(_dot(_exitGreen)));
  });
}

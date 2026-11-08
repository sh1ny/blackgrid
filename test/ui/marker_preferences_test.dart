import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:blackgrid/application/settings_controller.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:blackgrid/maps/map_marker_icons.dart';
import 'package:blackgrid/ui/ember/theme_access.dart';
import 'package:blackgrid/ui/marker_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/markers/icon_set.dart';
import '../support/map_widget_harness.dart';

const _manifestPath = 'assets/map_markers/manifest.json';
const _background = Color(0xFF090F0D);
const _exitGreen = Color(0xFF48D28B);
const _dangerRed = Color(0xFFFF5252);
const _utility = Color(0xFFB7A6F0);

/// The centre of a row's 24 x 24 badge canvas.
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

/// A prepared-pack marker on the ground floor.
Map<String, Object?> _marker(
  String id,
  String filterKey, {
  String category = 'misc',
  Map<String, Object?> details = const {},
}) => {
  'id': id,
  'name': id,
  'floorId': 'ground',
  'category': category,
  'filterKey': filterKey,
  'position': {'x': 64, 'z': 64},
  'details': {'description': '$id offline fixture details', ...details},
  'source': {'fixture': true},
};

/// A quest marker whose quest comes from [trader].
Map<String, Object?> _quest(String id, String trader) => _marker(
  id,
  'QuestItems',
  category: 'quests',
  details: {
    'quest': {'name': 'Quest of $trader', 'trader': trader},
  },
);

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

/// Pumps the Markers section on a real [SettingsController].
///
/// The fixture map carries two `PmcExtracts` and one hazard; [extra] markers,
/// a [sourceCategory] for the hazard and [pins] change that. [hidden] keys are
/// saved as hidden first. [hold] keeps the manifest gated until
/// `assets.manifestGate` completes; the gate is created inside `runAsync`
/// because a completer from the fake-async zone never completes from inside
/// it. Without [hold] the icons are fully loaded. [packFails] leaves the map
/// without a prepared pack.
Future<_Fixture> _pump(
  WidgetTester tester, {
  List<Map<String, Object?>> extra = const [],
  String? sourceCategory,
  Set<String> hidden = const {},
  Set<String> missing = const {},
  List<CustomPin> pins = const [],
  bool hold = false,
  bool packFails = false,
}) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final fixture = (await tester.runAsync(() async {
    final source = _Assets(missing: missing);
    if (hold) source.manifestGate = Completer<void>();
    final icons = MapMarkerIcons(load: source.load);
    final h = await MapWidgetHarness.create(
      markerIcons: icons,
      extraMarkers: extra,
      sourceCategory: sourceCategory,
      packFails: packFails,
    );
    for (final key in hidden) {
      await h.services.settings.setMarker(key, false);
    }
    for (final pin in pins) {
      await h.services.settings.savePin(pin);
    }
    if (!hold) await icons.open();
    return _Fixture(h, icons, source);
  }))!;
  addTearDown(fixture.h.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MarkerPreferences(services: fixture.h.services),
        ),
      ),
    ),
  );
  return fixture;
}

Finder _row(String key) => find.byKey(ValueKey('marker-row-$key'));
Finder _switch(String key) => find.byKey(ValueKey('marker-switch-$key'));

Finder get _anyRow => find.byWidgetPredicate(
  (widget) => switch (widget.key) {
    ValueKey<String>(:final value) => value.startsWith('marker-row-'),
    _ => false,
  },
);

/// The keys of every row built, in screen order.
List<String> _rowKeys(WidgetTester tester) {
  const prefix = 'marker-row-';
  final rows = [
    for (final element in _anyRow.evaluate())
      (
        (element.widget.key! as ValueKey<String>).value.substring(
          prefix.length,
        ),
        tester.getTopLeft(find.byWidget(element.widget)).dy,
      ),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  return [for (final (key, _) in rows) key];
}

Finder _badge(String key) => find.descendant(
  of: _row(key),
  matching: find.byWidgetPredicate(
    (widget) => widget is CustomPaint && widget.painter != null,
  ),
);

RenderObject _canvas(WidgetTester tester, String key) =>
    tester.renderObject(_badge(key));

Finder _label(String key, String text) =>
    find.descendant(of: _row(key), matching: find.text(text));

bool _switchOn(WidgetTester tester, String key) =>
    tester.widget<MarkerToggleSwitch>(_switch(key)).on;

/// The `y` of the group heading [title].
double _heading(WidgetTester tester, String title) =>
    tester.getTopLeft(find.byKey(ValueKey('marker-group-$title'))).dy;

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

Future<void> _tap(WidgetTester tester, _Fixture f, Finder target) async {
  await tester.tap(target);
  await tester.runAsync(() => _idle(f.settings));
  await tester.pump();
}

Future<void> _click(WidgetTester tester, _Fixture f, String key) =>
    _tap(tester, f, _row(key));

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
  testWidgets('marker-preferences: Rows for the current map', (tester) async {
    await _pump(
      tester,
      extra: [
        _marker('pmc-3', 'PmcExtracts', category: 'extracts'),
        _marker('loot-1', 'lootLoose'),
        _marker('loot-2', 'lootLoose'),
      ],
      pins: [_pin('Camp')],
    );

    expect(_rowKeys(tester), [
      'PmcExtracts',
      'Hazards',
      'lootLoose',
      'CustomPins',
    ]);
    for (final (key, label, count) in [
      ('PmcExtracts', 'PMC extracts', '3'),
      ('Hazards', 'Hazards', '1'),
      ('lootLoose', 'Loose loot', '2'),
      ('CustomPins', 'Saved pins', '1'),
    ]) {
      expect(_label(key, label), findsOneWidget);
      expect(_label(key, count), findsOneWidget, reason: 'count of $key');
    }
    for (final raw in ['PmcExtracts', 'lootLoose', 'CustomPins']) {
      expect(find.text(raw), findsNothing);
      expect(find.textContaining(raw), findsNothing);
    }
  });

  testWidgets('marker-preferences: Unsaveable category gets no row', (
    tester,
  ) async {
    final f = await _pump(
      tester,
      sourceCategory: 'PmcExtracts',
      extra: [_marker('zip', 'Ziplines')],
    );

    expect(_rowKeys(tester), ['PmcExtracts', 'CustomPins']);
    expect(find.textContaining('Ziplines'), findsNothing);
    expect(
      f.h.services.maps.activeMarkers.any((m) => m.filterKey == 'Ziplines'),
      isTrue,
    );
    expect(f.h.services.maps.categoryVisibility['Ziplines'], isNot(false));
  });

  testWidgets('marker-preferences: Map with no markers', (tester) async {
    await _pump(tester, packFails: true);

    expect(_rowKeys(tester), ['CustomPins']);
    expect(find.text('Saved pins'), findsOneWidget);
  });

  testWidgets('marker-preferences: Grouped order', (tester) async {
    await _pump(
      tester,
      sourceCategory: 'locks',
      extra: [
        _marker('loot', 'lootLoose'),
        _marker('quest', 'QuestItems', category: 'quests'),
        _marker('boss', 'BossSpawns'),
      ],
    );

    expect(_rowKeys(tester), [
      'PmcExtracts',
      'QuestItems',
      'BossSpawns',
      'lootLoose',
      'locks',
      'CustomPins',
    ]);
    final headings = [
      'Extracts',
      'Quests',
      'Bosses',
      'Loot',
      'Utility',
      'Yours',
    ];
    final tops = [for (final title in headings) _heading(tester, title)];
    expect(tops, [...tops]..sort());
    for (final absent in ['Danger', 'Spawns']) {
      expect(find.text(absent), findsNothing);
    }
    expect(_label('BossSpawns', 'Bosses'), findsOneWidget);
  });

  testWidgets('marker-preferences: Map order does not matter', (tester) async {
    final f = await _pump(tester, sourceCategory: 'locks');
    final first = _rowKeys(tester);
    expect(first, ['PmcExtracts', 'locks', 'CustomPins']);

    final maps = f.h.services.maps;
    f.h.services.maps.publishMarkers({
      for (final map in maps.maps) map.id: map.markers.reversed.toList(),
    }, changed: true);
    await tester.pump();

    expect(maps.activeMarkers.first.filterKey, 'locks');
    expect(_rowKeys(tester), first);
  });

  testWidgets('marker-preferences: Hide one category', (tester) async {
    final f = await _pump(tester);

    await _click(tester, f, 'PmcExtracts');

    expect(f.settings.settings.markerFilters['PmcExtracts'], isFalse);
    expect(f.h.services.maps.categoryVisibility['PmcExtracts'], isFalse);
    expect(_shown(f, 'Hazards'), isTrue);
    expect(f.h.services.maps.categoryVisibility['Hazards'], isNot(false));
    expect(_switchOn(tester, 'PmcExtracts'), isFalse);
    expect(_switchOn(tester, 'Hazards'), isTrue);
  });

  testWidgets('marker-preferences: Click while saving', (tester) async {
    final f = await _pump(tester);
    f.settings.busy = true;
    // ignore: invalid_use_of_protected_member
    f.settings.notifyListeners();
    await tester.pump();
    final before = f.settings.settings.markerFilters;

    await tester.tap(_row('Hazards'));
    await tester.pump();

    expect(f.settings.settings.markerFilters, before);
    expect(_shown(f, 'Hazards'), isTrue);
    expect(_switchOn(tester, 'Hazards'), isTrue);
    f.settings.busy = false;
  });

  testWidgets('marker-preferences: Shown and hidden rows differ', (
    tester,
  ) async {
    final f = await _pump(
      tester,
      extra: [_marker('scav', 'ScavExtracts', category: 'extracts')],
      hidden: {'Hazards'},
    );
    Color? labelColour(String key, String label) =>
        tester.widget<Text>(_label(key, label)).style?.color;

    expect(_switchOn(tester, 'ScavExtracts'), isTrue);
    expect(_switchOn(tester, 'Hazards'), isFalse);
    final ember = tester.element(_row('Hazards')).ember;
    expect(labelColour('ScavExtracts', 'Scav extracts'), ember.ink);
    expect(labelColour('Hazards', 'Hazards'), isNot(ember.ink));

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

  testWidgets('marker-preferences: Semantics reflect the state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final f = await _pump(tester, hidden: {'Hazards'});

    expect(
      tester.getSemantics(_row('Hazards')),
      matchesSemantics(
        label: 'Hazards',
        hasToggledState: true,
        isToggled: false,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );

    await _click(tester, f, 'Hazards');

    expect(
      tester.getSemantics(_row('Hazards')),
      matchesSemantics(
        label: 'Hazards',
        hasToggledState: true,
        isToggled: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('marker-preferences: Icon row matches the map', (tester) async {
    final f = await _pump(tester);

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

  testWidgets('marker-preferences: Icons still loading', (tester) async {
    final f = await _pump(tester, hold: true);
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
      reason: 'the loader notification marks the row for repaint',
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

  testWidgets('a failed icon draws the fallback badge only on its row', (
    tester,
  ) async {
    final f = await _pump(tester, sourceCategory: 'locks', missing: {'locks'});
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

  testWidgets('marker-preferences: Hide all then Show all', (tester) async {
    final f = await _pump(tester, pins: [_pin('Camp')]);
    final keys = _rowKeys(tester);
    expect(find.text('Save marker filters'), findsNothing);

    await _tap(tester, f, find.widgetWithText(TextButton, 'Hide all'));

    for (final key in keys) {
      expect(_switchOn(tester, key), isFalse, reason: key);
      expect(f.settings.settings.markerFilters[key], isFalse, reason: key);
      expect(f.h.services.maps.categoryVisibility[key], isFalse, reason: key);
    }

    await _tap(tester, f, find.widgetWithText(TextButton, 'Show all'));

    for (final key in keys) {
      expect(_switchOn(tester, key), isTrue, reason: key);
      expect(_shown(f, key), isTrue, reason: key);
      expect(f.h.services.maps.categoryVisibility[key], isNot(false));
    }
  });

  testWidgets("marker-preferences: Show all keeps other maps' choices", (
    tester,
  ) async {
    final f = await _pump(tester, hidden: {'ScavSpawns'});
    expect(_rowKeys(tester), isNot(contains('ScavSpawns')));

    await _tap(tester, f, find.widgetWithText(TextButton, 'Show all'));

    expect(f.settings.settings.markerFilters['ScavSpawns'], isFalse);
  });

  testWidgets('marker-preferences: Bulk action with an unsaveable category', (
    tester,
  ) async {
    final f = await _pump(tester, extra: [_marker('zip', 'Ziplines')]);

    await _tap(tester, f, find.widgetWithText(TextButton, 'Hide all'));

    expect(f.settings.settings.markerFilters, isNot(contains('Ziplines')));
    expect(f.h.services.maps.categoryVisibility['Ziplines'], isNot(false));
    await tester.runAsync(f.settings.load);
    expect(f.settings.settings.markerFilters, isNot(contains('Ziplines')));
    expect(f.settings.error, isNull);
  });

  testWidgets('marker-preferences: Search dims without hiding', (tester) async {
    final f = await _pump(tester, hidden: {'Hazards'});

    await tester.enterText(
      find.byKey(const ValueKey('marker-section-search')),
      'tunnel',
    );
    await tester.pump();

    expect(f.h.services.maps.search, 'tunnel');
    expect(_switchOn(tester, 'PmcExtracts'), isTrue);
    expect(_switchOn(tester, 'Hazards'), isFalse);
    expect(_shown(f, 'PmcExtracts'), isTrue);
  });

  testWidgets('marker-preferences: Quest filter keeps tiles', (tester) async {
    final f = await _pump(
      tester,
      extra: [_quest('q-prapor', 'Prapor'), _quest('q-skier', 'Skier')],
    );

    await tester.tap(find.byKey(const ValueKey('trader-chip-Prapor')));
    await tester.pump();

    expect(f.h.services.maps.questTrader, 'Prapor');
    expect(_switchOn(tester, 'QuestItems'), isTrue);
    expect(_shown(f, 'QuestItems'), isTrue);
  });

  testWidgets('marker-preferences: Active trader absent from the map', (
    tester,
  ) async {
    final f = await _pump(tester, extra: [_quest('q-prapor', 'Prapor')]);
    ChoiceChip chip(String name) =>
        tester.widget(find.byKey(ValueKey('trader-chip-$name')));
    expect(find.byKey(const ValueKey('trader-chip-all')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('trader-chip-Prapor')));
    await tester.pump();
    expect(chip('Prapor').selected, isTrue);

    // The player switches to a map whose quests have no Prapor.
    final maps = f.h.services.maps;
    maps.publishMarkers({
      for (final map in maps.maps)
        map.id: [
          for (final marker in map.markers)
            if (marker.filterKey != 'QuestItems') marker,
        ],
    }, changed: true);
    await tester.pump();

    expect(maps.questTrader, 'Prapor');
    expect(chip('Prapor').selected, isTrue);
    expect(chip('all').selected, isFalse);

    await tester.tap(find.byKey(const ValueKey('trader-chip-all')));
    await tester.pump();

    expect(maps.questTrader, isEmpty);
    expect(find.byKey(const ValueKey('trader-chip-Prapor')), findsNothing);
    expect(chip('all').selected, isTrue);
  });

  testWidgets('marker facts are derived once per content generation', (
    tester,
  ) async {
    final f = await _pump(tester, extra: [_quest('q-prapor', 'Prapor')]);
    final maps = f.h.services.maps;
    final first = MarkerFacts.of(maps);
    expect(first.traders, ['Prapor']);

    maps.panBy(10, 5);
    maps.setSearch('exit');
    expect(identical(MarkerFacts.of(maps), first), isTrue);

    maps.publishMarkers({
      for (final map in maps.maps) map.id: map.markers,
    }, changed: true);
    expect(identical(MarkerFacts.of(maps), first), isFalse);
  });
}

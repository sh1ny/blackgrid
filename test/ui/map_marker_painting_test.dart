import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:blackgrid/domain/settings.dart';
import 'package:blackgrid/maps/map_marker_icons.dart';
import 'package:blackgrid/ui/map_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/markers/icon_set.dart';
import '../support/map_widget_harness.dart';

const _manifestPath = 'assets/map_markers/manifest.json';
const _background = Color(0xFF090F0D);
const _exitGreen = Color(0xFF48D28B);
const _dangerRed = Color(0xFFFF5252);
const _pinBlue = Color(0xFF40C4FF);
const _gold = Color(0xFFDCC05A);

const _tinySvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
    '<circle cx="12" cy="12" r="6" fill="#FFFFFF"/></svg>';

const _icons = [
  ('PmcExtracts', 'exit'),
  ('HazardZones', 'danger'),
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
      'roles': {'exit': '#48D28B', 'danger': '#FF5252', 'pin': '#40C4FF'},
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

/// Hand-written asset source that can hold the manifest until released.
class _Assets {
  _Assets({required this.assets});

  /// The complete icon set from tiny synthetic vectors.
  factory _Assets.full() {
    final vec = compileIconSvg(_tinySvg, 'tiny');
    return _Assets(
      assets: {
        _manifestPath: _manifest(),
        for (final (key, _) in _icons) _vecPath(key): _data(vec),
      },
    );
  }

  final Map<String, ByteData> assets;
  Completer<void>? manifestGate;

  Future<ByteData> load(String path) async {
    if (path == _manifestPath) await manifestGate?.future;
    final data = assets[path];
    if (data == null) throw StateError('no asset $path');
    return data;
  }
}

Map<String, Object?> _marker(
  String id,
  String name,
  String category,
  String filterKey,
  int x,
  int z, {
  List<Map<String, int>>? outline,
}) => {
  'id': id,
  'name': name,
  'floorId': 'ground',
  'category': category,
  'filterKey': filterKey,
  'position': {'x': x, 'z': z},
  'details': {'description': '$name offline fixture details'},
  'source': {'fixture': true},
  'outline': ?outline,
};

final _pin = CustomPin(
  id: 'camp',
  mapId: 'shoreline',
  x: .75,
  y: .25,
  frame: 'legacy-normalized',
  frameRevision: 0,
  label: 'Stash',
  updatedAt: DateTime.utc(2026),
);

class _Fixture {
  _Fixture(this.h, this.icons, this.assets);
  final MapWidgetHarness h;
  final MapMarkerIcons icons;
  final _Assets assets;

  Offset marker(String id) {
    final projected = h.services.maps.visibleMarkers().singleWhere(
      (m) => m.marker.id == id,
    );
    return Offset(projected.viewportPoint.x, projected.viewportPoint.y);
  }

  Offset get pin {
    final point = h.services.maps.projectPin(_pin)!;
    return Offset(point.x, point.y);
  }
}

/// Builds the synthetic map and pumps the workspace on it.
///
/// [assets] defaults to the full tiny icon set; [hold] keeps the manifest
/// gated until `assets.manifestGate` completes. The gate is created inside
/// `runAsync` because a completer from the fake-async zone never completes
/// from inside it.
Future<_Fixture> _pump(
  WidgetTester tester, {
  _Assets? assets,
  bool hold = false,
  bool withPin = true,
}) async {
  tester.view.physicalSize = const Size(900, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final fixture = (await tester.runAsync(() async {
    final source = assets ?? _Assets.full();
    if (hold) source.manifestGate = Completer<void>();
    final icons = MapMarkerIcons(load: source.load);
    final h = await MapWidgetHarness.create(
      markerIcons: icons,
      extraMarkers: [
        _marker(
          'zone',
          'Danger zone',
          'hazards',
          'HazardZones',
          200,
          64,
          outline: [
            {'x': 170, 'z': 30},
            {'x': 230, 'z': 30},
            {'x': 230, 'z': 100},
          ],
        ),
        _marker('mystery', 'Mystery', 'mystery', 'MysteryKey', 64, 64),
      ],
    );
    if (withPin) await h.services.settings.savePin(_pin);
    return _Fixture(h, icons, source);
  }))!;
  addTearDown(fixture.h.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(8),
          child: MapWorkspace(services: fixture.h.services),
        ),
      ),
    ),
  );
  await settleMapFixture(tester, fixture.h);
  return fixture;
}

Finder get _mapPaint => find.byWidgetPredicate(
  (widget) =>
      widget is CustomPaint && '${widget.painter.runtimeType}' == '_MapPainter',
);

RenderObject _canvas(WidgetTester tester) => tester.renderObject(_mapPaint);

/// A `drawImageRect` of the 64 × 64 source into a 16 × 16 square on [centre].
///
/// When [colour] is given, the call must also tint with `srcIn` in that
/// colour at medium quality.
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
  if (arguments[1] != const Rect.fromLTWH(0, 0, 64, 64)) {
    throw 'The glyph source was ${arguments[1]}, not 64 x 64.';
  }
  final paint = arguments[3] as Paint;
  if (colour != null) {
    if (paint.colorFilter != ColorFilter.mode(colour, BlendMode.srcIn)) {
      throw 'The glyph filter was ${paint.colorFilter}, not $colour srcIn.';
    }
    if (paint.filterQuality != FilterQuality.medium) {
      throw 'The glyph quality was ${paint.filterQuality}.';
    }
  }
  return true;
};

/// A circle drawn on [at]: the first one whose [style] matches.
///
/// `PaintPattern.circle` fails on the next circle anywhere, so it cannot pick
/// one marker out of several.
PaintPatternPredicate _circleAt(
  Offset at, {
  required PaintingStyle style,
  double? radius,
  Color? colour,
  double? strokeWidth,
}) => (Symbol name, List<dynamic> arguments) {
  if (name != #drawCircle || arguments[0] != at) return false;
  final paint = arguments[2] as Paint;
  if (paint.style != style) return false;
  if (radius != null && arguments[1] != radius) {
    throw 'The $style circle at $at had radius ${arguments[1]}, '
        'not $radius.';
  }
  if (colour != null && paint.color.toARGB32() != colour.toARGB32()) {
    throw 'The $style circle at $at was ${paint.color}, not $colour.';
  }
  if (strokeWidth != null && paint.strokeWidth != strokeWidth) {
    throw 'The ring at $at was ${paint.strokeWidth} wide.';
  }
  return true;
};

/// Expects the disc and ring of one badge of [radius] on [at], in order.
void _discAndRing(
  PaintPattern pattern,
  Offset at, {
  required Color ring,
  double opacity = 1,
  double radius = 11,
}) {
  pattern
    ..something(
      _circleAt(
        at,
        style: PaintingStyle.fill,
        radius: radius,
        colour: _background.withValues(alpha: opacity),
      ),
    )
    ..something(
      _circleAt(
        at,
        style: PaintingStyle.stroke,
        radius: radius,
        colour: ring.withValues(alpha: opacity),
        strokeWidth: 2,
      ),
    );
}

/// A filled 3 px dot on [at], the fallback badge's centre.
PaintPattern _dotAt(Offset at, [Color? colour]) => paints
  ..something(
    _circleAt(at, style: PaintingStyle.fill, radius: 3, colour: colour),
  );

/// Any circle on [at], whatever its size or style.
PaintPattern _anyCircleAt(Offset at) => paints
  ..something((name, arguments) => name == #drawCircle && arguments[0] == at);

Future<void> _loaded(WidgetTester tester, _Fixture fixture) async {
  await tester.runAsync(fixture.icons.open);
  await tester.pump();
}

void main() {
  testWidgets(
    'loaded icons: a PmcExtracts marker paints a 24 px exit-green badge with '
    'its glyph and no dot',
    (tester) async {
      final f = await _pump(tester);
      await _loaded(tester, f);
      final at = f.marker('ground-exit');

      final pattern = paints;
      _discAndRing(pattern, at, ring: _exitGreen);
      pattern.something(
        _glyphAt(
          at,
          image: f.icons.icon('PmcExtracts')!.glyph,
          colour: _exitGreen,
        ),
      );
      expect(_canvas(tester), pattern);
      expect(_canvas(tester), isNot(_dotAt(at)));
    },
  );

  testWidgets('a HazardZones marker paints its red polygon, then its danger '
      'badge', (tester) async {
    final f = await _pump(tester);
    await _loaded(tester, f);
    final at = f.marker('zone');

    final pattern = paints
      ..path(color: Colors.red.withValues(alpha: .16))
      ..path(color: Colors.redAccent);
    _discAndRing(pattern, at, ring: _dangerRed);
    pattern.something(
      _glyphAt(
        at,
        image: f.icons.icon('HazardZones')!.glyph,
        colour: _dangerRed,
      ),
    );
    expect(_canvas(tester), pattern);
  });

  testWidgets(
    'an unknown filter key paints a gold fallback dot while others paint '
    'glyphs',
    (tester) async {
      final f = await _pump(tester);
      await _loaded(tester, f);
      final unknown = f.marker('mystery');
      final known = f.marker('ground-exit');

      final pattern = paints;
      _discAndRing(pattern, unknown, ring: _gold);
      pattern.something(
        _circleAt(unknown, style: PaintingStyle.fill, radius: 3, colour: _gold),
      );
      expect(_canvas(tester), pattern);
      expect(
        _canvas(tester),
        paints..something(_glyphAt(known, colour: _exitGreen)),
      );
      expect(
        _canvas(tester),
        isNot(paints..something(_glyphAt(unknown))),
        reason: 'the fallback badge draws no glyph',
      );
    },
  );

  testWidgets('a dimmed marker paints disc, ring and glyph at 0.22 alpha', (
    tester,
  ) async {
    final f = await _pump(tester);
    await _loaded(tester, f);
    f.h.services.maps.setSearch('mystery');
    await tester.pump();
    final at = f.marker('ground-exit');

    final pattern = paints;
    _discAndRing(pattern, at, ring: _exitGreen, opacity: dimmedMarkerOpacity);
    pattern.something(
      _glyphAt(
        at,
        image: f.icons.icon('PmcExtracts')!.glyph,
        colour: _exitGreen.withValues(alpha: dimmedMarkerOpacity),
      ),
    );
    expect(_canvas(tester), pattern);
    expect(dimmedMarkerOpacity, 0.22);
  });

  testWidgets('a saved pin paints a light-blue CustomPins badge', (
    tester,
  ) async {
    final f = await _pump(tester);
    await _loaded(tester, f);
    final at = f.pin;

    final pattern = paints;
    _discAndRing(pattern, at, ring: _pinBlue);
    pattern.something(
      _glyphAt(at, image: f.icons.icon('CustomPins')!.glyph, colour: _pinBlue),
    );
    expect(_canvas(tester), pattern);
  });

  testWidgets('a pin not matching the search paints at 0.22 alpha', (
    tester,
  ) async {
    final f = await _pump(tester);
    await _loaded(tester, f);
    f.h.services.maps.setSearch('mystery');
    await tester.pump();
    final at = f.pin;

    final pattern = paints;
    _discAndRing(pattern, at, ring: _pinBlue, opacity: dimmedMarkerOpacity);
    pattern.something(
      _glyphAt(
        at,
        image: f.icons.icon('CustomPins')!.glyph,
        colour: _pinBlue.withValues(alpha: dimmedMarkerOpacity),
      ),
    );
    expect(_canvas(tester), pattern);
  });

  testWidgets('CustomPins off paints no pin badge', (tester) async {
    final f = await _pump(tester);
    await _loaded(tester, f);
    final at = f.pin;
    expect(
      _canvas(tester),
      _anyCircleAt(at),
      reason: 'the pin badge is painted while CustomPins is on',
    );

    await tester.runAsync(
      () => f.h.services.settings.setMarker('CustomPins', false),
    );
    await tester.pump();

    expect(_canvas(tester), isNot(_anyCircleAt(at)));
    expect(_canvas(tester), isNot(paints..something(_glyphAt(at))));
  });

  testWidgets('the map repaints with glyphs when loading completes', (
    tester,
  ) async {
    final f = await _pump(tester, hold: true);
    final at = f.marker('ground-exit');
    final fallback = paints;
    _discAndRing(fallback, at, ring: _exitGreen);
    fallback.something(
      _circleAt(at, style: PaintingStyle.fill, radius: 3, colour: _exitGreen),
    );
    expect(
      _canvas(tester),
      fallback,
      reason: 'before loading the exit paints its fallback badge',
    );
    expect(_canvas(tester), isNot(paints..something(_glyphAt(at))));
    expect(_canvas(tester).debugNeedsPaint, isFalse);

    await tester.runAsync(() async {
      f.assets.manifestGate!.complete();
      await f.icons.open();
    });

    expect(
      _canvas(tester).debugNeedsPaint,
      isTrue,
      reason: 'the loader notification marks the map for repaint',
    );
    await tester.pump();
    final pattern = paints;
    _discAndRing(pattern, at, ring: _exitGreen);
    pattern.something(
      _glyphAt(
        at,
        image: f.icons.icon('PmcExtracts')!.glyph,
        colour: _exitGreen,
      ),
    );
    expect(_canvas(tester), pattern);
    expect(_canvas(tester), isNot(_dotAt(at)));
  });

  testWidgets('with a failed manifest, tapping a marker still selects it', (
    tester,
  ) async {
    final f = await _pump(tester, assets: _Assets(assets: {}));
    await _loaded(tester, f);
    expect(f.icons.failures, isNotEmpty);
    final at = f.marker('ground-exit');

    final pattern = paints;
    _discAndRing(pattern, at, ring: _exitGreen);
    pattern.something(
      _circleAt(at, style: PaintingStyle.fill, radius: 3, colour: _exitGreen),
    );
    expect(_canvas(tester), pattern);
    expect(find.text('Ground exit'), findsNothing);

    final origin = tester.getTopLeft(
      find.byKey(const Key('native-map-viewport')),
    );
    await tester.tapAt(origin + at);
    await tester.pump();

    expect(find.text('Ground exit'), findsOneWidget);
    // The details panel resizes the viewport, which moves the marker.
    await tester.pump();
    final selected = paints;
    _discAndRing(
      selected,
      f.marker('ground-exit'),
      ring: _exitGreen,
      radius: 14,
    );
    expect(_canvas(tester), selected);
  });
}

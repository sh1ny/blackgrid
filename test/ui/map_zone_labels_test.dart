import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:blackgrid/domain/map_coordinates.dart';
import 'package:blackgrid/domain/map_zone_style.dart';
import 'package:blackgrid/maps/map_marker_icons.dart';
import 'package:blackgrid/ui/map_workspace.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/markers/icon_set.dart';
import '../support/map_widget_harness.dart';

const _manifestPath = 'assets/map_markers/manifest.json';
const _background = Color(0xFF090F0D);
const _mapFill = Color(0xFF253541);
const _exitGreen = Color(0xFF48D28B);
const _dangerRed = Color(0xFFFF5252);
const _questLime = Color(0xFFC5E063);
const _neutral = Color(0xFFC9CDBF);
const _ember = Color(0xFFE9A14B);
const _utilityViolet = Color(0xFFB7A6F0);
const _highlightCyan = Color(0xFF18FFFF);

const _tinySvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
    '<circle cx="12" cy="12" r="6" fill="#FFFFFF"/></svg>';

const _icons = [
  ('PmcExtracts', 'exit'),
  ('ScavExtracts', 'exit'),
  ('SharedExtracts', 'exit'),
  ('Transits', 'exit'),
  ('HazardZones', 'danger'),
  ('QuestObjectives', 'quest'),
  ('Switches', 'utility'),
  ('locks', 'utility'),
  ('CustomPins', 'pin'),
];

/// The test font draws every glyph as a square of one em.
const _fontSize = 12.0;

/// Where a label starts: right of the selected-size badge, plus a 4 px gap.
const _labelGap = Offset(19, 0);

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
        'quest': '#C5E063',
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

/// Hand-written asset source that can hold the manifest until released.
class _Assets {
  _Assets() {
    final vec = compileIconSvg(_tinySvg, 'tiny');
    assets = {
      _manifestPath: _manifest(),
      for (final (key, _) in _icons) _vecPath(key): _data(vec),
    };
  }

  late final Map<String, ByteData> assets;
  Completer<void>? manifestGate;

  Future<ByteData> load(String path) async {
    if (path == _manifestPath) await manifestGate?.future;
    final data = assets[path];
    if (data == null) throw StateError('no asset $path');
    return data;
  }
}

List<Map<String, int>> _triangle(
  int x0,
  int z0,
  int x1,
  int z1,
  int x2,
  int z2,
) => [
  {'x': x0, 'z': z0},
  {'x': x1, 'z': z1},
  {'x': x2, 'z': z2},
];

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

/// The harness already holds a PMC extract "Ground exit" at 128, 128.
///
/// Label rows sit on the left, zone outlines on the right, so a label never
/// crosses a polygon whose pixels a test samples. The name lengths differ so
/// the width of a label identifies it.
final _markers = [
  _marker('scav', 'Scav hatch', 'extracts', 'ScavExtracts', 30, 20),
  _marker('shared', 'Co-op', 'extracts', 'SharedExtracts', 30, 50),
  _marker(
    'pmc',
    'Med Tent Gate',
    'extracts',
    'PmcExtracts',
    30,
    80,
    outline: _triangle(10, 60, 80, 60, 80, 100),
  ),
  _marker(
    'transit',
    'Transit 7',
    'extracts',
    'Transits',
    30,
    110,
    outline: _triangle(10, 100, 40, 100, 40, 122),
  ),
  _marker('locks', 'Locked door', 'locks', 'locks', 65, 110),
  _marker('blank', '   ', 'extracts', 'SharedExtracts', 30, 170),
  _marker(
    'zone',
    'Danger zone',
    'hazards',
    'HazardZones',
    180,
    30,
    outline: _triangle(160, 15, 210, 15, 210, 50),
  ),
  _marker(
    'quest',
    'Dig here',
    'quests',
    'QuestObjectives',
    180,
    90,
    outline: _triangle(160, 75, 210, 75, 210, 110),
  ),
  _marker(
    'switch',
    'Power switch',
    'switches',
    'Switches',
    180,
    150,
    outline: _triangle(160, 135, 210, 135, 210, 170),
  ),
];

/// How many name labels the unfiltered map draws (two paragraphs each).
const _labelledMarkers = 5;

class _Fixture {
  _Fixture(this.h, this.icons, this.assets);
  final MapWidgetHarness h;
  final MapMarkerIcons icons;
  final _Assets assets;
  final boundary = GlobalKey();

  Offset marker(String id) {
    final projected = h.services.maps.visibleMarkers().singleWhere(
      (m) => m.marker.id == id,
    );
    return Offset(projected.viewportPoint.x, projected.viewportPoint.y);
  }

  List<Offset> outline(String id) => [
    for (final p
        in h.services.maps
            .visibleMarkers()
            .singleWhere((m) => m.marker.id == id)
            .outline)
      Offset(p.x, p.y),
  ];

  Rect outlineBounds(String id) => outline(id).fold<Rect?>(null, (rect, p) {
    final point = Rect.fromLTWH(p.dx, p.dy, 0, 0);
    return rect?.expandToInclude(point) ?? point;
  })!;

  /// A point inside the outline of [id], from the mean of its vertices.
  Offset inside(String id) {
    final points = outline(id);
    final sum = points.reduce((a, b) => a + b);
    return sum / points.length.toDouble();
  }
}

Future<_Fixture> _pump(WidgetTester tester, {bool hold = false}) async {
  tester.view.physicalSize = const Size(900, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final fixture = (await tester.runAsync(() async {
    final source = _Assets();
    if (hold) source.manifestGate = Completer<void>();
    final icons = MapMarkerIcons(load: source.load);
    final h = await MapWidgetHarness.create(
      markerIcons: icons,
      extraMarkers: _markers,
    );
    return _Fixture(h, icons, source);
  }))!;
  addTearDown(fixture.h.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(8),
          child: RepaintBoundary(
            key: fixture.boundary,
            child: MapWorkspace(services: fixture.h.services),
          ),
        ),
      ),
    ),
  );
  await settleMapFixture(tester, fixture.h);
  return fixture;
}

Future<_Fixture> _pumpLoaded(WidgetTester tester) async {
  final f = await _pump(tester);
  await tester.runAsync(f.icons.open);
  await tester.pump();
  return f;
}

Finder get _viewport => find.byKey(const Key('native-map-viewport'));

Finder get _mapPaint => find.byWidgetPredicate(
  (widget) =>
      widget is CustomPaint && '${widget.painter.runtimeType}' == '_MapPainter',
);

/// One recorded canvas call.
typedef _Call = (Symbol, List<dynamic>);

/// Every canvas call of the map painter, in paint order.
List<_Call> _calls(WidgetTester tester) {
  final calls = <_Call>[];
  expect(
    tester.renderObject(_mapPaint),
    paints..everything((name, arguments) {
      calls.add((name, List.of(arguments)));
      return true;
    }),
  );
  return calls;
}

/// Where each paragraph was drawn.
///
/// The painter disposes its text after drawing, so only the offset of a
/// recorded paragraph is readable.
List<Offset> _paragraphs(List<_Call> calls) => [
  for (final (name, arguments) in calls)
    if (name == #drawParagraph) arguments[1] as Offset,
];

/// The paragraphs that start right of [badge] and are centred on it.
///
/// A paragraph of the 12 px test font is 12 px tall, so its top is 6 px above
/// the badge point; a different font size would miss.
List<Offset> _labelAt(List<_Call> calls, Offset badge) => [
  for (final offset in _paragraphs(calls))
    if ((offset.dx - (badge.dx + _labelGap.dx)).abs() < .01 &&
        (offset.dy + _fontSize / 2 - badge.dy).abs() < .01)
      offset,
];

bool _sameColour(Color a, Color b) => a.toARGB32() == b.toARGB32();

bool _hasCircle(
  List<_Call> calls,
  Offset at, {
  required PaintingStyle style,
  required double radius,
  required Color colour,
}) => calls.any((call) {
  final (name, arguments) = call;
  if (name != #drawCircle || arguments[0] != at) return false;
  final paint = arguments[2] as Paint;
  return paint.style == style &&
      arguments[1] == radius &&
      _sameColour(paint.color, colour);
});

bool _anyCircleAt(List<_Call> calls, Offset at) =>
    calls.any((call) => call.$1 == #drawCircle && call.$2[0] == at);

/// A drawn outline of [bounds]: its fill at [fillAlpha], or its 2 px edge.
bool _hasOutline(
  List<_Call> calls,
  Rect bounds,
  Color colour, {
  required bool edge,
  double alpha = 1,
}) => calls.any((call) {
  final (name, arguments) = call;
  if (name != #drawPath) return false;
  final paint = arguments[1] as Paint;
  final got = (arguments[0] as Path).getBounds();
  if ((got.left - bounds.left).abs() > .01 ||
      (got.top - bounds.top).abs() > .01 ||
      (got.right - bounds.right).abs() > .01 ||
      (got.bottom - bounds.bottom).abs() > .01) {
    return false;
  }
  if (edge) {
    return paint.style == PaintingStyle.stroke &&
        paint.strokeWidth == 2 &&
        _sameColour(paint.color, colour.withValues(alpha: alpha));
  }
  return paint.style == PaintingStyle.fill &&
      _sameColour(paint.color, colour.withValues(alpha: alpha));
});

/// Whether [id]'s outline is drawn in [colour], both fill and edge.
bool _outlineDrawn(
  _Fixture f,
  List<_Call> calls,
  String id,
  Color colour, {
  bool dimmed = false,
}) =>
    _hasOutline(
      calls,
      f.outlineBounds(id),
      colour,
      edge: false,
      alpha: dimmed ? .035 : .16,
    ) &&
    _hasOutline(
      calls,
      f.outlineBounds(id),
      colour,
      edge: true,
      alpha: dimmed ? dimmedMarkerOpacity : 1,
    );

/// Any drawn path at all that is [bounds] sized.
bool _anyOutline(List<_Call> calls, Rect bounds) => calls.any((call) {
  if (call.$1 != #drawPath) return false;
  final got = (call.$2[0] as Path).getBounds();
  return (got.left - bounds.left).abs() < .01 &&
      (got.top - bounds.top).abs() < .01 &&
      (got.right - bounds.right).abs() < .01 &&
      (got.bottom - bounds.bottom).abs() < .01;
});

/// The pixel at [point] of the viewport, as the engine rendered it.
///
/// The test font draws each glyph as a solid one-em square, so the middle of
/// a label's first glyph shows the label's fill colour.
Future<Color> _pixel(WidgetTester tester, _Fixture f, Offset point) async {
  final boundary =
      f.boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final at =
      point +
      tester.getTopLeft(_viewport) -
      tester.getTopLeft(find.byKey(f.boundary));
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final width = image.width;
    final data = (await image.toByteData())!;
    image.dispose();
    final index = (at.dy.floor() * width + at.dx.floor()) * 4;
    return Color.fromARGB(
      data.getUint8(index + 3),
      data.getUint8(index),
      data.getUint8(index + 1),
      data.getUint8(index + 2),
    );
  }))!;
}

/// The middle of the first glyph of the label beside [badge].
Offset _labelCentre(Offset badge) =>
    badge + _labelGap + const Offset(_fontSize / 2, 0);

/// Expects the label beside [badge] to cover [chars] one-em glyphs: its last
/// glyph shows the label colour and the space after it does not.
Future<void> _expectLabelSpan(
  WidgetTester tester,
  _Fixture f,
  Offset badge,
  int chars,
) async {
  final last = _labelCentre(badge) + Offset((chars - 1) * _fontSize, 0);
  _expectColour(await _pixel(tester, f, last), _label(LabelFaction.pmc));
  expect(
    _distance(
      await _pixel(tester, f, last + const Offset(_fontSize, 0)),
      _label(LabelFaction.pmc),
    ),
    greaterThan(.1),
    reason: 'the label ends after $chars glyphs',
  );
}

double _distance(Color a, Color b) =>
    (a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs();

void _expectColour(Color got, Color want, {double tolerance = .02}) => expect(
  _distance(got, want),
  lessThan(tolerance * 3),
  reason: 'pixel $got should be $want',
);

/// Blends [top] at [opacity] over [base].
Color _over(Color top, Color base, double opacity) =>
    Color.lerp(base, top, opacity)!;

Future<TestGesture> _mouse(WidgetTester tester) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: const Offset(1, 1));
  addTearDown(gesture.removePointer);
  await tester.pump();
  return gesture;
}

Offset _global(WidgetTester tester, Offset viewportPoint) =>
    tester.getTopLeft(_viewport) + viewportPoint;

Color _label(LabelFaction faction) => Color(labelColourFor(faction));

void main() {
  testWidgets('a PmcExtracts marker paints its name right of its badge', (
    tester,
  ) async {
    final f = await _pumpLoaded(tester);
    final at = f.marker('pmc');
    final calls = _calls(tester);

    final label = _labelAt(calls, at);
    expect(label, hasLength(2), reason: 'a halo pass and a fill pass');
    await _expectLabelSpan(tester, f, at, 13);
    expect(
      _paragraphs(calls),
      hasLength(_labelledMarkers * 2),
      reason: 'locks, zones, quests and switches are never named',
    );
    expect(
      _hasCircle(
        calls,
        at,
        style: PaintingStyle.stroke,
        radius: 11,
        colour: _exitGreen,
      ),
      isTrue,
    );
    _expectColour(
      await _pixel(tester, f, _labelCentre(at)),
      _label(LabelFaction.pmc),
    );
    final beside = await _pixel(
      tester,
      f,
      Offset((at.dx + _labelGap.dx).floorToDouble() - 1, at.dy),
    );
    expect(
      _distance(beside, _background),
      lessThan(_distance(beside, _mapFill)),
      reason: 'the halo is the marker background colour',
    );
  });

  testWidgets('hiding ScavExtracts removes its badge and name only', (
    tester,
  ) async {
    final f = await _pumpLoaded(tester);
    final scav = f.marker('scav');
    final pmc = f.marker('pmc');
    expect(_labelAt(_calls(tester), scav), hasLength(2));

    await tester.runAsync(
      () => f.h.services.settings.setMarker('ScavExtracts', false),
    );
    await tester.pump();

    final calls = _calls(tester);
    expect(_labelAt(calls, scav), isEmpty);
    expect(_anyCircleAt(calls, scav), isFalse);
    expect(_labelAt(calls, pmc), hasLength(2));
    expect(_paragraphs(calls), hasLength((_labelledMarkers - 1) * 2));
  });

  testWidgets('a blank extract name paints its badge and no label', (
    tester,
  ) async {
    final f = await _pumpLoaded(tester);
    final blank = f.marker('blank');
    final calls = _calls(tester);

    expect(
      _hasCircle(
        calls,
        blank,
        style: PaintingStyle.stroke,
        radius: 11,
        colour: _exitGreen,
      ),
      isTrue,
    );
    expect(_labelAt(calls, blank), isEmpty);
    expect(_paragraphs(calls), hasLength(_labelledMarkers * 2));
  });

  testWidgets('map-zone-labels: Each faction draws its own colour', (
    tester,
  ) async {
    final f = await _pumpLoaded(tester);
    final calls = _calls(tester);
    final colours = <Color>[];
    for (final (id, want) in [
      ('pmc', const Color(0xFF7BE495)),
      ('scav', const Color(0xFFF59AB8)),
      ('shared', const Color(0xFF8CB4FF)),
      ('transit', const Color(0xFFD29BF2)),
    ]) {
      final at = f.marker(id);
      expect(
        _hasCircle(
          calls,
          at,
          style: PaintingStyle.stroke,
          radius: 11,
          colour: _exitGreen,
        ),
        isTrue,
        reason: '$id keeps the exit-green ring',
      );
      final pixel = await _pixel(tester, f, _labelCentre(at));
      _expectColour(pixel, want);
      colours.add(pixel);
    }
    expect({for (final c in colours) c.toARGB32()}, hasLength(4));
  });

  testWidgets('a raid-highlighted Scav extract keeps its Scav label colour', (
    tester,
  ) async {
    final f = await _pumpLoaded(tester);
    f.h.services.maps.setRaidHighlights({'scav'});
    await tester.pump();
    final at = f.marker('scav');
    final calls = _calls(tester);

    expect(
      _hasCircle(
        calls,
        at,
        style: PaintingStyle.stroke,
        radius: 14,
        colour: _highlightCyan,
      ),
      isTrue,
      reason: 'the badge turns cyan and grows',
    );
    expect(_labelAt(calls, at), hasLength(2));
    _expectColour(
      await _pixel(tester, f, _labelCentre(at)),
      _label(LabelFaction.scav),
    );
  });

  testWidgets('zooming moves the label but keeps its font size', (
    tester,
  ) async {
    final f = await _pumpLoaded(tester);
    final before = f.marker('pmc');
    final labelBefore = _labelAt(_calls(tester), before);
    expect(labelBefore, hasLength(2));

    f.h.services.maps.zoomAt(ViewportPoint(before.dx - 100, before.dy - 60), 2);
    await tester.pump();

    final after = f.marker('pmc');
    expect(after, isNot(before));
    final labelAfter = _labelAt(_calls(tester), after);
    expect(labelAfter, hasLength(2));
    await _expectLabelSpan(tester, f, after, 13);
  });

  testWidgets('a dimmed extract paints its name at 0.22 alpha', (tester) async {
    final f = await _pumpLoaded(tester);
    f.h.services.maps.setSearch('zzz');
    await tester.pump();
    final at = f.marker('shared');
    final calls = _calls(tester);

    expect(
      _hasCircle(
        calls,
        at,
        style: PaintingStyle.stroke,
        radius: 11,
        colour: _exitGreen.withValues(alpha: dimmedMarkerOpacity),
      ),
      isTrue,
    );
    expect(_labelAt(calls, at), hasLength(2));
    _expectColour(
      await _pixel(tester, f, _labelCentre(at)),
      _over(_label(LabelFaction.shared), _mapFill, dimmedMarkerOpacity),
    );
    expect(dimmedMarkerOpacity, 0.22);
  });

  testWidgets('names paint after outlines and before every badge', (
    tester,
  ) async {
    final f = await _pumpLoaded(tester);
    final calls = _calls(tester);
    final badges = [
      for (final m in f.h.services.maps.visibleMarkers())
        Offset(m.viewportPoint.x, m.viewportPoint.y),
    ];
    final locks = f.marker('locks');
    final transit = f.marker('transit');
    expect(
      locks.dx - transit.dx,
      inInclusiveRange(_labelGap.dx + 12, 9 * _fontSize),
      reason: 'the locks badge sits under the transit name',
    );

    int last(bool Function(_Call) test) => calls.lastIndexWhere(test);
    int first(bool Function(_Call) test) => calls.indexWhere(test);
    bool isOutline(_Call c) => c.$1 == #drawPath;
    bool isName(_Call c) => c.$1 == #drawParagraph;
    bool isBadge(_Call c) =>
        c.$1 == #drawCircle && badges.contains(c.$2[0] as Offset);

    expect(first(isOutline), isNonNegative);
    expect(first(isName), isNonNegative);
    expect(first(isBadge), isNonNegative);
    expect(last(isOutline), lessThan(first(isName)));
    expect(last(isName), lessThan(first(isBadge)));
    expect(
      _hasCircle(
        calls,
        locks,
        style: PaintingStyle.fill,
        radius: 11,
        colour: _background,
      ),
      isTrue,
    );
  });

  testWidgets('map-zone-labels: Categories draw their own outline colours', (
    tester,
  ) async {
    final f = await _pumpLoaded(tester);
    final calls = _calls(tester);

    expect(_outlineDrawn(f, calls, 'zone', _dangerRed), isTrue);
    expect(_outlineDrawn(f, calls, 'quest', _questLime), isTrue);
    expect(_outlineDrawn(f, calls, 'switch', _utilityViolet), isTrue);
    expect(_outlineDrawn(f, calls, 'quest', _dangerRed), isFalse);
  });

  testWidgets('map-zone-labels: Icons not loaded yet', (tester) async {
    final f = await _pump(tester, hold: true);
    final calls = _calls(tester);

    expect(_outlineDrawn(f, calls, 'quest', _neutral), isTrue);
    expect(_outlineDrawn(f, calls, 'quest', _dangerRed), isFalse);
    expect(_outlineDrawn(f, calls, 'zone', _dangerRed), isTrue);
  });

  testWidgets('an extract at rest paints no outline', (tester) async {
    final f = await _pumpLoaded(tester);
    final calls = _calls(tester);

    expect(_anyOutline(calls, f.outlineBounds('pmc')), isFalse);
    expect(_anyOutline(calls, f.outlineBounds('transit')), isFalse);
    expect(
      _anyOutline(calls, f.outlineBounds('zone')),
      isTrue,
      reason: 'a hazard zone outline is always drawn',
    );
    expect(_labelAt(calls, f.marker('pmc')), hasLength(2));
  });

  testWidgets(
    'hovering an extract badge paints its outline until the pointer leaves',
    (tester) async {
      final f = await _pumpLoaded(tester);
      final mouse = await _mouse(tester);
      final at = f.marker('pmc');

      await mouse.moveTo(_global(tester, at));
      await tester.pump();
      expect(_outlineDrawn(f, _calls(tester), 'pmc', _exitGreen), isTrue);
      expect(
        _anyOutline(_calls(tester), f.outlineBounds('transit')),
        isFalse,
        reason: 'only the hovered extract shows its outline',
      );

      await mouse.moveTo(_global(tester, const Offset(5, 5)));
      await tester.pump();
      expect(_anyOutline(_calls(tester), f.outlineBounds('pmc')), isFalse);
    },
  );

  testWidgets(
    'moving from the badge into the revealed area keeps the outline',
    (tester) async {
      final f = await _pumpLoaded(tester);
      final mouse = await _mouse(tester);
      final at = f.marker('pmc');
      final inside = f.inside('pmc');
      expect(
        (inside - at).distance,
        greaterThan(22),
        reason: 'the point is away from the badge hit radius',
      );

      await mouse.moveTo(_global(tester, at));
      await tester.pump();
      await mouse.moveTo(_global(tester, inside));
      await tester.pump();

      expect(_outlineDrawn(f, _calls(tester), 'pmc', _exitGreen), isTrue);
    },
  );

  testWidgets('moving the map under a still pointer re-checks the hover', (
    tester,
  ) async {
    final f = await _pumpLoaded(tester);
    final mouse = await _mouse(tester);
    final at = f.marker('pmc');

    await mouse.moveTo(_global(tester, at));
    await tester.pump();
    expect(_outlineDrawn(f, _calls(tester), 'pmc', _exitGreen), isTrue);

    // 100 game units left: the pointer then sits on empty map between the
    // extract column and the zone column, and the extract stays visible.
    final shift = (f.marker('quest').dx - at.dx) * 100 / 150;
    f.h.services.maps.panBy(-shift, 0);
    await tester.pump();
    expect(f.marker('pmc').dx, closeTo(at.dx - shift, .01));
    expect(
      _calls(tester).any(
        (call) =>
            call.$1 == #drawPath &&
            _sameColour((call.$2[1] as Paint).color, _exitGreen),
      ),
      isFalse,
      reason: 'the extract moved away from the pointer',
    );

    f.h.services.maps.panBy(shift, 0);
    await tester.pump();
    expect(
      _outlineDrawn(f, _calls(tester), 'pmc', _exitGreen),
      isTrue,
      reason: 'the extract moved back under the pointer',
    );
  });

  testWidgets('map-zone-labels: Selected outline is Ember', (tester) async {
    final f = await _pumpLoaded(tester);
    final mouse = await _mouse(tester);
    final at = f.marker('pmc');

    await mouse.moveTo(_global(tester, at));
    await tester.pump();
    expect(
      _outlineDrawn(f, _calls(tester), 'pmc', _exitGreen),
      isTrue,
      reason: 'a hovered extract draws exit green',
    );
    expect(_outlineDrawn(f, _calls(tester), 'pmc', _ember), isFalse);

    await mouse.down(_global(tester, at));
    await mouse.up();
    await tester.pump();
    await tester.pump();
    expect(find.text('Med Tent Gate'), findsOneWidget);
    expect(_outlineDrawn(f, _calls(tester), 'pmc', _ember), isTrue);
    expect(_outlineDrawn(f, _calls(tester), 'pmc', _exitGreen), isFalse);

    await mouse.moveTo(_global(tester, const Offset(5, 5)));
    await tester.pump();

    expect(
      _outlineDrawn(f, _calls(tester), 'pmc', _ember),
      isTrue,
      reason: 'the selected outline stays after the pointer leaves',
    );
  });

  testWidgets('leaving the viewport clears the hovered outline', (
    tester,
  ) async {
    final f = await _pumpLoaded(tester);
    final mouse = await _mouse(tester);
    final at = f.marker('pmc');

    await mouse.moveTo(_global(tester, at));
    await tester.pump();
    expect(_outlineDrawn(f, _calls(tester), 'pmc', _exitGreen), isTrue);

    await mouse.moveTo(_global(tester, const Offset(40, -30)));
    await tester.pump();

    expect(_anyOutline(_calls(tester), f.outlineBounds('pmc')), isFalse);
  });

  testWidgets("a hidden extract's semantics rect is its badge circle", (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final f = await _pumpLoaded(tester);
    await tester.pump();

    Size sizeOf(String name) =>
        find.semantics.byLabel(RegExp('^$name, ')).evaluate().single.rect.size;

    expect(
      sizeOf('Med Tent Gate'),
      const Size(44, 44),
      reason: 'a badge circle of radius 22, not the polygon bounds',
    );
    expect(sizeOf('Danger zone').width, greaterThan(44));

    final mouse = await _mouse(tester);
    await mouse.moveTo(_global(tester, f.marker('pmc')));
    await tester.pump();
    expect(sizeOf('Med Tent Gate').width, greaterThan(44));
    handle.dispose();
  });
}

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:blackgrid/application/map_controller.dart';
import 'package:blackgrid/domain/map_coordinates.dart';
import 'package:blackgrid/domain/map_zone_style.dart';
import 'package:blackgrid/maps/map_marker_icons.dart';
import 'package:blackgrid/ui/map_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/map_widget_harness.dart';

const _mapFill = Color(0xFF253541);

/// The test font draws every glyph as a square of one em, so a label's measured
/// size is its character count times the font size by the font size.
const _size80Font = 13.0;
const _size160Font = 16.0;

const _plainText = 'Alpha';
const _rotatedText = 'Rotated';
const _underText = 'Dorms';
const _rotatedDegrees = 30.0;

Map<String, Object?> _label(
  String text,
  int x,
  int z,
  num size, {
  num rotation = 0,
}) => {
  'text': text,
  'position': {'x': x, 'z': z},
  'rotation': rotation,
  'size': size,
  'floorIds': ['ground'],
};

/// Far apart, so placement never drops one. The third sits under the harness
/// "Ground exit" badge at game 128, 128.
final _labels = [
  _label(_plainText, 64, 64, 80),
  _label(_rotatedText, 192, 64, 160, rotation: _rotatedDegrees),
  _label(_underText, 128, 128, 80),
];

Map<String, Object?> _hazard() => {
  'id': 'zone',
  'name': 'Danger zone',
  'floorId': 'ground',
  'category': 'hazards',
  'filterKey': 'HazardZones',
  'position': {'x': 200, 'z': 200},
  'details': {'description': 'Danger zone offline fixture details'},
  'source': {'fixture': true},
  'outline': [
    {'x': 180, 'z': 180},
    {'x': 230, 'z': 180},
    {'x': 230, 'z': 230},
  ],
};

class _Fixture {
  _Fixture(this.h);
  final MapWidgetHarness h;
  final boundary = GlobalKey();

  MapController get maps => h.services.maps;

  /// The viewport anchor of the label with [text].
  Offset anchor(String text) {
    final label = maps.visiblePlaceLabels().singleWhere(
      (l) => l.label.text == text,
    );
    return Offset(label.viewportPoint.x, label.viewportPoint.y);
  }

  Offset marker(String id) {
    final p = maps.visibleMarkers().singleWhere((m) => m.marker.id == id);
    return Offset(p.viewportPoint.x, p.viewportPoint.y);
  }
}

Future<_Fixture> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final h = (await tester.runAsync(
    () => MapWidgetHarness.create(
      // Icons never load: outlines and badges still paint their fallbacks.
      markerIcons: MapMarkerIcons(load: (_) => Completer<ByteData>().future),
      extraMarkers: [_hazard()],
      extraLabels: _labels,
    ),
  ))!;
  addTearDown(h.dispose);
  final fixture = _Fixture(h);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(8),
          child: RepaintBoundary(
            key: fixture.boundary,
            child: MapWorkspace(services: h.services),
          ),
        ),
      ),
    ),
  );
  await settleMapFixture(tester, h);
  return fixture;
}

Finder get _viewport => find.byKey(const Key('native-map-viewport'));

Finder get _mapPaint => find.byWidgetPredicate(
  (widget) =>
      widget is CustomPaint && '${widget.painter.runtimeType}' == '_MapPainter',
);

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

bool _near(Offset a, Offset b) => (a - b).distance < .01;

/// Indices of the paragraphs of a label of [chars] glyphs at [font] px that are
/// drawn centred on [anchor]: after a translate to [anchor] and a clockwise
/// rotation of [degrees], at minus half the measured size.
List<int> _passes(
  List<_Call> calls,
  Offset anchor,
  int chars,
  double font, {
  double degrees = 0,
}) {
  final centred = Offset(-chars * font / 2, -font / 2);
  final result = <int>[];
  for (final (i, call) in calls.indexed) {
    if (call.$1 != #drawParagraph || !_near(call.$2[1] as Offset, centred)) {
      continue;
    }
    final translate = calls.lastIndexWhere((c) => c.$1 == #translate, i);
    if (translate < 0) continue;
    final to = Offset(
      calls[translate].$2[0] as double,
      calls[translate].$2[1] as double,
    );
    final rotate = calls.lastIndexWhere((c) => c.$1 == #rotate, i);
    if (_near(to, anchor) &&
        rotate > translate &&
        ((calls[rotate].$2[0] as double) - degrees * math.pi / 180).abs() <
            1e-9) {
      result.add(i);
    }
  }
  return result;
}

/// The pixel at [point] of the viewport, as the engine rendered it.
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

void _expectColour(Color got, Color want) {
  final distance =
      (got.r - want.r).abs() + (got.g - want.g).abs() + (got.b - want.b).abs();
  expect(distance, lessThan(.06), reason: 'pixel $got should be $want');
}

void main() {
  testWidgets('place label font size does not change with zoom', (
    tester,
  ) async {
    final f = await _pump(tester);
    final before = f.anchor(_plainText);
    expect(
      _passes(_calls(tester), before, _plainText.length, _size80Font),
      hasLength(2),
      reason: 'a halo pass and a fill pass at the 13 px size-80 font',
    );

    f.maps.zoomAt(ViewportPoint(before.dx - 100, before.dy - 60), 2);
    await tester.pump();

    final after = f.anchor(_plainText);
    expect(after, isNot(before), reason: 'the anchor moved with the zoom');
    expect(
      _passes(_calls(tester), after, _plainText.length, _size80Font),
      hasLength(2),
      reason: 'the same font size, so the same offset from the anchor',
    );
  });

  testWidgets('rotated label is drawn rotated about its anchor', (
    tester,
  ) async {
    final f = await _pump(tester);
    final anchor = f.anchor(_rotatedText);
    expect(
      _passes(
        _calls(tester),
        anchor,
        _rotatedText.length,
        _size160Font,
        degrees: _rotatedDegrees,
      ),
      hasLength(2),
      reason: 'halo and fill, rotated clockwise about the anchor',
    );
  });

  testWidgets('unrotated label is centred on its anchor', (tester) async {
    final f = await _pump(tester);
    final anchor = f.anchor(_plainText);
    final calls = _calls(tester);

    expect(
      _passes(calls, anchor, _plainText.length, _size80Font),
      hasLength(2),
    );
    final pixel = await _pixel(
      tester,
      f,
      anchor + const Offset(-_size80Font * 2, 0),
    );
    _expectColour(
      pixel,
      Color.lerp(_mapFill, const Color(placeLabelColour), placeLabelOpacity)!,
    );
  });

  testWidgets('place labels are drawn before outlines, names and badges', (
    tester,
  ) async {
    final f = await _pump(tester);
    final calls = _calls(tester);
    final badges = [
      for (final m in f.maps.visibleMarkers())
        Offset(m.viewportPoint.x, m.viewportPoint.y),
    ];

    final labelParagraphs = <int>[
      ..._passes(calls, f.anchor(_plainText), _plainText.length, _size80Font),
      ..._passes(
        calls,
        f.anchor(_rotatedText),
        _rotatedText.length,
        _size160Font,
        degrees: _rotatedDegrees,
      ),
      ..._passes(calls, f.anchor(_underText), _underText.length, _size80Font),
    ];
    expect(labelParagraphs, hasLength(6));
    final lastLabel = labelParagraphs.reduce(math.max);
    int first(bool Function(_Call) test) => calls.indexWhere(test);

    final outline = first((c) => c.$1 == #drawPath);
    final name = calls.indexWhere(
      (c) =>
          c.$1 == #drawParagraph && !labelParagraphs.contains(calls.indexOf(c)),
    );
    final badge = first(
      (c) => c.$1 == #drawCircle && badges.contains(c.$2[0] as Offset),
    );
    expect(outline, isNonNegative, reason: 'the hazard outline is drawn');
    expect(name, isNonNegative, reason: 'the extract name is drawn');
    expect(badge, isNonNegative, reason: 'a badge is drawn');
    expect(lastLabel, lessThan(outline));
    expect(lastLabel, lessThan(name));
    expect(lastLabel, lessThan(badge));
  });

  testWidgets('search leaves place label opacity unchanged', (tester) async {
    final f = await _pump(tester);
    final probe = f.anchor(_plainText) + const Offset(-_size80Font * 2, 0);
    final want = Color.lerp(
      _mapFill,
      const Color(placeLabelColour),
      placeLabelOpacity,
    )!;
    _expectColour(await _pixel(tester, f, probe), want);

    f.maps.setSearch('zzz');
    await tester.pump();

    expect(
      f.maps.visibleMarkers().every((m) => m.dimmed),
      isTrue,
      reason: 'the search dims every marker',
    );
    _expectColour(await _pixel(tester, f, probe), want);
  });

  testWidgets('click on a place label selects nothing', (tester) async {
    final f = await _pump(tester);
    final at = f.anchor(_plainText);

    await tester.tapAt(tester.getTopLeft(_viewport) + at);
    await tester.pump();

    expect(f.maps.selectedMarkerProjection, isNull);
  });

  testWidgets('click on a badge under a place label selects the marker', (
    tester,
  ) async {
    final f = await _pump(tester);
    final badge = f.marker('ground-exit');
    expect(
      (f.anchor(_underText) - badge).distance,
      lessThan(1),
      reason: 'the label is centred on the badge',
    );

    await tester.tapAt(tester.getTopLeft(_viewport) + badge);
    await tester.pump();

    expect(f.maps.selectedMarkerProjection?.marker.id, 'ground-exit');
  });

  testWidgets('place labels add no semantics targets', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    await tester.pump();

    expect(
      find.semantics.byLabel(RegExp('^Ground exit, ')),
      findsOneWidget,
      reason: 'the marker is still a target',
    );
    for (final text in [_plainText, _rotatedText, _underText]) {
      expect(find.semantics.byLabel(RegExp(text)), findsNothing);
    }
    handle.dispose();
  });
}

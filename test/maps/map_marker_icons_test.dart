import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:blackgrid/maps/map_marker_icons.dart';
import 'package:blackgrid/ui/ember/ember_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/markers/icon_set.dart';

const _manifestPath = 'assets/map_markers/manifest.json';
const _neutral = Color(0xFFC9CDBF);
const _ember = Color(0xFFE9A14B);
const _green = Color(0xFF48D28B);
const _red = Color(0xFFFF5252);
const _blue = Color(0xFF40C4FF);
const _cyan = Color(0xFF18FFFF);
const _utility = Color(0xFFB7A6F0);

const _tinySvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
    '<circle cx="12" cy="12" r="6" fill="#FFFFFF"/></svg>';

const _icons = [
  ('PmcExtracts', 'exit'),
  ('locks', 'utility'),
  ('lootLoose', 'loot'),
];

String _vecPath(String key) =>
    'assets/map_markers/compiled/'
    '${iconFileName(key).replaceAll('.svg', '')}.vec';

ByteData _data(List<int> bytes) =>
    Uint8List.fromList(bytes).buffer.asByteData();

ByteData _manifest({int schemaVersion = 1}) => _data(
  utf8.encode(
    jsonEncode({
      'schemaVersion': schemaVersion,
      'scope': 'release',
      'background': '#090F0D',
      'badge': {'diameter': 24, 'selectedDiameter': 30, 'glyph': 16, 'ring': 2},
      'roles': {
        'exit': '#48D28B',
        'utility': '#B7A6F0',
        'loot': '#7ED9C6',
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

/// Hand-written asset source: serves [assets], throws for anything else, and
/// can hold a path until its gate is completed.
class _FakeAssets {
  _FakeAssets(this.assets);

  final Map<String, ByteData> assets;
  final loaded = <String>[];
  final gates = <String, Completer<void>>{};
  final reached = <String, Completer<void>>{};

  Future<ByteData> load(String path) async {
    loaded.add(path);
    (reached[path] ??= Completer<void>()).complete();
    final gate = gates[path];
    if (gate != null) await gate.future;
    final data = assets[path];
    if (data == null) throw StateError('no asset $path');
    return data;
  }

  Future<void> waitReached(String path) =>
      (reached[path] ??= Completer<void>()).future;
}

_FakeAssets _fullSet({int schemaVersion = 1}) {
  final vec = compileIconSvg(_tinySvg, 'tiny');
  return _FakeAssets({
    _manifestPath: _manifest(schemaVersion: schemaVersion),
    for (final (key, _) in _icons) _vecPath(key): _data(vec),
  });
}

/// Paints one selected badge, as the map does, under whatever theme is active.
class _BadgePainter extends CustomPainter {
  _BadgePainter(this.icons);

  final MapMarkerIcons icons;

  @override
  void paint(Canvas canvas, Size size) => paintMarkerBadge(
    canvas,
    size.center(Offset.zero),
    icons,
    filterKey: 'locks',
    selected: true,
    highlighted: false,
    dimmed: false,
  );

  @override
  bool shouldRepaint(_BadgePainter oldDelegate) => false;
}

void main() {
  const geometry = MarkerBadgeGeometry.standard;

  group('markerBadgeStyle', () {
    test('map-marker-icons: Selected marker grows', () {
      final selected = markerBadgeStyle(
        role: _utility,
        selected: true,
        highlighted: false,
        dimmed: false,
        geometry: geometry,
      );
      expect(selected.colour, _ember);
      expect(selected.diameter, 30);
      expect(selected.opacity, 1);

      final other = markerBadgeStyle(
        role: _utility,
        selected: false,
        highlighted: false,
        dimmed: false,
        geometry: geometry,
      );
      expect(other.colour, _utility);
      expect(other.diameter, 24);
    });

    test('map-marker-icons: Selected and highlighted together', () {
      final style = markerBadgeStyle(
        role: _green,
        selected: true,
        highlighted: true,
        dimmed: false,
        geometry: geometry,
      );
      expect(style.colour, _ember);
      expect(style.colour, isNot(_cyan));
      expect(style.diameter, 30);

      final dimmed = markerBadgeStyle(
        role: _green,
        selected: true,
        highlighted: true,
        dimmed: true,
        geometry: geometry,
      );
      expect(dimmed.colour, _ember);
      expect(dimmed.opacity, 0.22);
    });

    testWidgets('map-marker-icons: Selected marker in the light room', (
      tester,
    ) async {
      final icons = MapMarkerIcons.disabled();
      addTearDown(icons.dispose);
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: blackgridTheme(brightness),
            home: CustomPaint(
              key: ValueKey(brightness),
              size: const Size(40, 40),
              painter: _BadgePainter(icons),
            ),
          ),
        );
        final canvas = tester.renderObject(find.byKey(ValueKey(brightness)));
        expect(
          canvas,
          paints..something((name, arguments) {
            if (name != #drawCircle) return false;
            final paint = arguments[2] as Paint;
            return paint.style == PaintingStyle.stroke &&
                paint.color.toARGB32() == _ember.toARGB32() &&
                arguments[1] == 14;
          }),
          reason: '${brightness.name} room draws the same Ember ring',
        );
      }
    });

    test('highlighted uses cyan and selectedDiameter', () {
      final style = markerBadgeStyle(
        role: _green,
        selected: false,
        highlighted: true,
        dimmed: false,
        geometry: geometry,
      );
      expect(style.colour, _cyan);
      expect(style.diameter, 30);
      expect(style.opacity, 1);
    });

    test('dimmed sets opacity 0.22', () {
      final style = markerBadgeStyle(
        role: _green,
        selected: false,
        highlighted: false,
        dimmed: true,
        geometry: geometry,
      );
      expect(style.colour, _green);
      expect(style.diameter, 24);
      expect(style.opacity, 0.22);
    });

    test('all eight flag permutations', () {
      for (final selected in [false, true]) {
        for (final highlighted in [false, true]) {
          for (final dimmed in [false, true]) {
            for (final role in <Color?>[_utility, null]) {
              final style = markerBadgeStyle(
                role: role,
                selected: selected,
                highlighted: highlighted,
                dimmed: dimmed,
                geometry: geometry,
              );
              final label =
                  'selected=$selected highlighted=$highlighted '
                  'dimmed=$dimmed role=$role';
              expect(
                style.colour,
                selected ? _ember : (highlighted ? _cyan : (role ?? _neutral)),
                reason: label,
              );
              expect(
                style.diameter,
                selected || highlighted ? 30 : 24,
                reason: label,
              );
              expect(style.opacity, dimmed ? 0.22 : 1, reason: label);
            }
          }
        }
      }
    });

    test('uses the geometry it is given', () {
      final style = markerBadgeStyle(
        role: null,
        selected: true,
        highlighted: false,
        dimmed: false,
        geometry: const MarkerBadgeGeometry(
          diameter: 20,
          selectedDiameter: 26,
          glyph: 12,
          ring: 1,
        ),
      );
      expect(style.diameter, 26);
    });
  });

  group('fallback colours', () {
    test('map-marker-icons: Fallback colours without a manifest', () {
      final icons = MapMarkerIcons(load: _fullSet().load);
      addTearDown(icons.dispose);
      for (final key in ['PmcExtracts', 'ScavExtracts', 'SharedExtracts']) {
        expect(icons.colourFor(key), _green, reason: key);
      }
      for (final key in ['Hazards', 'HazardZones']) {
        expect(icons.colourFor(key), _red, reason: key);
      }
      expect(icons.colourFor('CustomPins'), _blue);
      for (final key in ['lootLoose', 'Transits', 'locks', 'Unknown']) {
        expect(icons.colourFor(key), _neutral, reason: key);
      }
      expect(icons.geometry.diameter, 24);
      expect(icons.geometry.selectedDiameter, 30);
      expect(icons.geometry.glyph, 16);
      expect(icons.geometry.ring, 2);
      expect(icons.background, const Color(0xFF090F0D));
      expect(icons.icon('locks'), isNull);
    });
  });

  group('open', () {
    testWidgets('icon() is null for an unknown filter key and the style '
        'falls back to neutral grey', (tester) async {
      final icons = MapMarkerIcons(load: _fullSet().load);
      addTearDown(icons.dispose);
      await tester.runAsync(icons.open);

      expect(icons.icon('NotACategory'), isNull);
      expect(icons.icon('locks'), isNotNull);
      final style = markerBadgeStyle(
        role: icons.icon('NotACategory')?.colour,
        selected: false,
        highlighted: false,
        dimmed: false,
        geometry: icons.geometry,
      );
      expect(style.colour, _neutral);
      expect(icons.colourFor('NotACategory'), _neutral);
    });

    testWidgets('before open() completes every key has no glyph; completion '
        'notifies once', (tester) async {
      final assets = _fullSet();
      final lastPath = _vecPath('lootLoose');
      final icons = MapMarkerIcons(load: assets.load);
      addTearDown(icons.dispose);
      var notifications = 0;
      icons.addListener(() => notifications++);

      await tester.runAsync(() async {
        assets.gates[lastPath] = Completer<void>();
        final opening = icons.open();
        await assets.waitReached(lastPath);
        for (final (key, _) in _icons) {
          expect(icons.icon(key), isNull, reason: key);
        }
        expect(notifications, 0);
        assets.gates[lastPath]!.complete();
        await opening;
      });

      expect(notifications, 1);
      for (final (key, _) in _icons) {
        expect(icons.icon(key)?.glyph, isNotNull, reason: key);
      }
      expect(icons.icon('locks')!.colour, _utility);
      expect(icons.failures, isEmpty);
    });

    testWidgets('a second open() returns the same future and loads once', (
      tester,
    ) async {
      final assets = _fullSet();
      final icons = MapMarkerIcons(load: assets.load);
      addTearDown(icons.dispose);
      await tester.runAsync(() async {
        final first = icons.open();
        final second = icons.open();
        expect(identical(first, second), isTrue);
        await first;
        expect(identical(icons.open(), first), isTrue);
      });
      expect(assets.loaded.length, 1 + _icons.length);
    });

    testWidgets('a corrupt locks .vec leaves locks on the fallback in its role '
        'colour and logs the file once', (tester) async {
      final assets = _fullSet();
      assets.assets[_vecPath('locks')] = _data([1, 2, 3, 4, 5]);
      final icons = MapMarkerIcons(load: assets.load);
      addTearDown(icons.dispose);
      var notifications = 0;
      icons.addListener(() => notifications++);
      await tester.runAsync(icons.open);

      final locks = icons.icon('locks');
      expect(locks, isNotNull);
      expect(locks!.glyph, isNull);
      expect(locks.colour, _utility);
      expect(icons.colourFor('locks'), _utility);
      expect(icons.icon('PmcExtracts')!.glyph, isNotNull);
      expect(icons.icon('lootLoose')!.glyph, isNotNull);
      expect(icons.failures, hasLength(1));
      expect(icons.failures.single, contains('locks.svg'));
      expect(notifications, 1);
    });

    for (final (name, assets) in <(String, _FakeAssets Function())>[
      ('missing', () => _FakeAssets({})),
      (
        'non-JSON',
        () => _FakeAssets({_manifestPath: _data(utf8.encode('not json {'))}),
      ),
      ('wrong-schema', () => _fullSet(schemaVersion: 2)),
    ]) {
      testWidgets('a $name manifest leaves every key on its fallback colour '
          'and logs the manifest', (tester) async {
        final source = assets();
        final icons = MapMarkerIcons(load: source.load);
        addTearDown(icons.dispose);
        var notifications = 0;
        icons.addListener(() => notifications++);
        await tester.runAsync(icons.open);

        for (final (key, _) in _icons) {
          expect(icons.icon(key), isNull, reason: key);
        }
        expect(icons.colourFor('PmcExtracts'), _green);
        expect(icons.colourFor('locks'), _neutral);
        expect(icons.colourFor('CustomPins'), _blue);
        expect(icons.failures, hasLength(1));
        expect(icons.failures.single, contains('manifest.json'));
        expect(source.loaded, [_manifestPath]);
        expect(notifications, 1);
      });
    }

    testWidgets('a throwing load never escapes open()', (tester) async {
      Future<ByteData> thrower(String path) async => throw ArgumentError(path);
      final icons = MapMarkerIcons(load: thrower);
      addTearDown(icons.dispose);
      await tester.runAsync(() async {
        await expectLater(icons.open(), completes);
      });
      expect(icons.failures, hasLength(1));
      expect(icons.icon('locks'), isNull);
    });

    testWidgets('a throwing icon load leaves only that key on the fallback', (
      tester,
    ) async {
      final assets = _fullSet();
      assets.assets.remove(_vecPath('PmcExtracts'));
      final icons = MapMarkerIcons(load: assets.load);
      addTearDown(icons.dispose);
      await tester.runAsync(icons.open);

      expect(icons.icon('PmcExtracts')!.glyph, isNull);
      expect(icons.icon('PmcExtracts')!.colour, _green);
      expect(icons.icon('locks')!.glyph, isNotNull);
      expect(icons.failures.single, contains('pmc_extracts.svg'));
    });

    testWidgets('dispose() during open() disposes made images and never '
        'notifies afterwards', (tester) async {
      final assets = _fullSet();
      final gatedPath = _vecPath('lootLoose');
      final icons = MapMarkerIcons(load: assets.load);
      var notifications = 0;
      icons.addListener(() => notifications++);

      await tester.runAsync(() async {
        assets.gates[gatedPath] = Completer<void>();
        final opening = icons.open();
        await assets.waitReached(gatedPath);
        expect(icons.debugLiveImageCount, 2);
        icons.dispose();
        assets.gates[gatedPath]!.complete();
        await opening;
      });

      expect(icons.debugLiveImageCount, 0);
      expect(notifications, 0);
    });

    testWidgets('dispose() after open() disposes the stored images', (
      tester,
    ) async {
      final icons = MapMarkerIcons(load: _fullSet().load);
      await tester.runAsync(icons.open);
      expect(icons.debugLiveImageCount, _icons.length);
      icons.dispose();
      expect(icons.debugLiveImageCount, 0);
    });

    testWidgets('a rasterized glyph is 64 by 64 px', (tester) async {
      final icons = MapMarkerIcons(load: _fullSet().load);
      addTearDown(icons.dispose);
      await tester.runAsync(icons.open);
      final ui.Image glyph = icons.icon('locks')!.glyph!;
      expect((glyph.width, glyph.height), (64, 64));
    });
  });

  group('MapMarkerIcons.disabled', () {
    testWidgets('never calls load, never notifies and always falls back', (
      tester,
    ) async {
      final icons = MapMarkerIcons.disabled();
      addTearDown(icons.dispose);
      var notifications = 0;
      icons.addListener(() => notifications++);
      await tester.runAsync(icons.open);

      expect(icons.failures, isEmpty);
      expect(notifications, 0);
      expect(icons.icon('locks'), isNull);
      expect(icons.colourFor('Hazards'), _red);
    });
  });
}

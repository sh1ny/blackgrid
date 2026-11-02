import 'dart:math' as math;

import 'package:blackgrid/domain/map_zone_style.dart';
import 'package:blackgrid/domain/marker_categories.dart';
import 'package:flutter_test/flutter_test.dart';

const _exitKeys = {
  'PmcExtracts': LabelFaction.pmc,
  'ScavExtracts': LabelFaction.scav,
  'SharedExtracts': LabelFaction.shared,
  'Transits': LabelFaction.transit,
};

const _background = 0xFF090F0D;

void main() {
  final keys = [
    for (final (key, _) in markerCategoryLabels) key,
    'UnmappedPackCategory',
  ];

  group('labelFactionFor', () {
    test('only the four exit keys have a label faction', () {
      for (final key in keys) {
        expect(labelFactionFor(key), _exitKeys[key], reason: key);
      }
    });
  });

  group('outlineDrawn', () {
    test('outlineDrawn is true for non-exit keys at rest', () {
      for (final key in keys) {
        for (final hovered in [false, true]) {
          for (final selected in [false, true]) {
            final expected = !_exitKeys.containsKey(key) || hovered || selected;
            expect(
              outlineDrawn(key, hovered: hovered, selected: selected),
              expected,
              reason: '$key hovered=$hovered selected=$selected',
            );
          }
        }
      }
    });
  });

  group('labelColourFor', () {
    test('label palette meets contrast, hue band and distinctness rules', () {
      final failures = <String>[];
      final seen = <int, LabelFaction>{};
      for (final faction in LabelFaction.values) {
        final colour = labelColourFor(faction);
        final hex = _hex(colour);
        final contrast = _contrast(colour, _background);
        if (contrast < 3) {
          failures.add(
            '${faction.name} $hex: contrast '
            '${contrast.toStringAsFixed(2)} is below 3:1 against #090F0D',
          );
        }
        final (:hue, :saturation) = _hueSaturation(colour);
        if (hue >= 170 && hue <= 190 && saturation >= 0.10) {
          failures.add(
            '${faction.name} $hex: hue ${hue.toStringAsFixed(0)} at '
            '${(saturation * 100).toStringAsFixed(0)}% saturation is inside '
            'the 170-190 highlight band',
          );
        }
        final other = seen[colour & 0xFFFFFF];
        if (other != null) {
          failures.add(
            '${faction.name} $hex: not distinct, equals ${other.name}',
          );
        }
        seen[colour & 0xFFFFFF] = faction;
        if (colour >> 24 != 0xFF) {
          failures.add('${faction.name} $hex: not opaque');
        }
      }
      expect(failures, isEmpty);
    });
  });
}

String _hex(int argb) =>
    '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

List<double> _channels(int argb) => [
  (argb >> 16) & 0xFF,
  (argb >> 8) & 0xFF,
  argb & 0xFF,
].map((c) => c / 255).toList();

double _luminance(int argb) {
  final [r, g, b] = [
    for (final c in _channels(argb))
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble(),
  ];
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

double _contrast(int a, int b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

({double hue, double saturation}) _hueSaturation(int argb) {
  final [r, g, b] = _channels(argb);
  final maxC = math.max(r, math.max(g, b));
  final minC = math.min(r, math.min(g, b));
  final delta = maxC - minC;
  if (delta == 0) return (hue: 0, saturation: 0);
  final lightness = (maxC + minC) / 2;
  final saturation = delta / (1 - (2 * lightness - 1).abs());
  final double hue;
  if (maxC == r) {
    hue = 60 * (((g - b) / delta) % 6);
  } else if (maxC == g) {
    hue = 60 * ((b - r) / delta + 2);
  } else {
    hue = 60 * ((r - g) / delta + 4);
  }
  return (hue: hue, saturation: saturation);
}

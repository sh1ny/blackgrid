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
      expect(
        _paletteFailures({
          for (final faction in LabelFaction.values)
            faction: labelColourFor(faction),
        }),
        isEmpty,
      );
    });

    test('map-zone-labels: Palette rule rejects a bad label colour', () {
      const good = {
        LabelFaction.pmc: 0xFF7BE495,
        LabelFaction.scav: 0xFFF59AB8,
        LabelFaction.shared: 0xFF8CB4FF,
        LabelFaction.transit: 0xFFD29BF2,
      };
      expect(_paletteFailures(good), isEmpty);

      List<String> swap(LabelFaction faction, int colour) =>
          _paletteFailures({...good, faction: colour});

      final lowContrast = swap(LabelFaction.pmc, 0xFF3A4A44);
      expect(lowContrast, hasLength(1));
      expect(lowContrast.single, contains('pmc'));
      expect(lowContrast.single, contains('#3A4A44'));
      expect(lowContrast.single, contains('3:1'));

      final cyan = swap(LabelFaction.shared, 0xFF18E0E0);
      expect(cyan, hasLength(1));
      expect(cyan.single, contains('shared'));
      expect(cyan.single, contains('#18E0E0'));
      expect(cyan.single, contains('170-190'));

      final amber = swap(LabelFaction.scav, 0xFFF2C14E);
      expect(amber, hasLength(1));
      expect(amber.single, contains('scav'));
      expect(amber.single, contains('#F2C14E'));
      expect(amber.single, contains('25-60'));

      final duplicate = swap(LabelFaction.transit, 0xFF7BE495);
      expect(duplicate, hasLength(1));
      expect(duplicate.single, contains('transit'));
      expect(duplicate.single, contains('#7BE495'));
      expect(duplicate.single, contains('not distinct'));

      // A grey below 10% saturation sits in the amber hue without breaking
      // the rule.
      expect(swap(LabelFaction.pmc, 0xFF9E9B94), isEmpty);
    });
  });

  group('placeLabelColour', () {
    test('place label colour differs from faction colours and meets 3:1 '
        'blended at 85%', () {
      final failures = <String>[];
      final hex = _hex(placeLabelColour);
      for (final faction in LabelFaction.values) {
        if ((labelColourFor(faction) & 0xFFFFFF) ==
            (placeLabelColour & 0xFFFFFF)) {
          failures.add(
            'place label colour $hex equals the ${faction.name} name colour',
          );
        }
      }
      final blended = _blend(placeLabelColour, placeLabelOpacity);
      final contrast = _contrast(blended, _background);
      if (contrast < 3) {
        failures.add(
          'place label colour $hex blended at 85%: contrast '
          '${contrast.toStringAsFixed(2)} is below 3:1 against #090F0D',
        );
      }
      expect(placeLabelOpacity, 0.85);
      expect(failures, isEmpty);
    });
  });
}

/// The failures of the label palette rule for [colours]: contrast, the cyan
/// band, the amber band, distinctness and opacity.
List<String> _paletteFailures(Map<LabelFaction, int> colours) {
  final failures = <String>[];
  final seen = <int, LabelFaction>{};
  for (final MapEntry(key: faction, value: colour) in colours.entries) {
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
    if (hue >= 25 && hue <= 60 && saturation >= 0.10) {
      failures.add(
        '${faction.name} $hex: hue ${hue.toStringAsFixed(0)} at '
        '${(saturation * 100).toStringAsFixed(0)}% saturation is inside '
        'the 25-60 amber band',
      );
    }
    final other = seen[colour & 0xFFFFFF];
    if (other != null) {
      failures.add('${faction.name} $hex: not distinct, equals ${other.name}');
    }
    seen[colour & 0xFFFFFF] = faction;
    if (colour >> 24 != 0xFF) {
      failures.add('${faction.name} $hex: not opaque');
    }
  }
  return failures;
}

/// Blends [argb] at [opacity] over the map background.
int _blend(int argb, double opacity) {
  int channel(int shift) {
    final fg = (argb >> shift) & 0xFF;
    final bg = (_background >> shift) & 0xFF;
    return (fg * opacity + bg * (1 - opacity)).round();
  }

  return 0xFF000000 | channel(16) << 16 | channel(8) << 8 | channel(0);
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

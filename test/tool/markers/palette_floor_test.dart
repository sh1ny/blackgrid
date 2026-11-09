import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:blackgrid/domain/map_zone_style.dart';
import 'package:flutter_test/flutter_test.dart';

/// The smallest OKLab distance two shipped role or label colours may have
/// (ADR-0039).
const _floor = 0.08;

/// The colours ADR-0039 added. Older pairs, such as the exit role and the PMC
/// label, were shipped closer than the floor before it existed, so the floor
/// binds these colours against every other role and label.
const _bound = {'role quest', 'role loot', 'label scav'};

void main() {
  test('map-marker-icons: Shipped roles and labels keep the OKLab floor', () {
    final manifest = jsonDecode(
      File('assets/map_markers/manifest.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final roles = (manifest['roles']! as Map<String, Object?>).map(
      (name, hex) => MapEntry('role $name', _parse(hex! as String)),
    );
    final labels = {
      for (final faction in LabelFaction.values)
        'label ${faction.name}': labelColourFor(faction) & 0xFFFFFF,
    };
    final colours = {...roles, ...labels};

    final failures = <String>[];
    final names = colours.keys.toList();
    for (var i = 0; i < names.length; i++) {
      for (var j = i + 1; j < names.length; j++) {
        if (!_bound.contains(names[i]) && !_bound.contains(names[j])) continue;
        final a = colours[names[i]]!;
        final b = colours[names[j]]!;
        final distance = _distance(a, b);
        if (distance < _floor) {
          failures.add(
            '${names[i]} ${_hex(a)} and ${names[j]} ${_hex(b)}: OKLab '
            'distance ${distance.toStringAsFixed(3)} is below $_floor',
          );
        }
      }
    }
    expect(colours, hasLength(roles.length + labels.length));
    expect(failures, isEmpty);
  });
}

int _parse(String hex) => int.parse(hex.substring(1), radix: 16);

String _hex(int rgb) =>
    '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';

double _distance(int a, int b) {
  final [l1, a1, b1] = _oklab(a);
  final [l2, a2, b2] = _oklab(b);
  return math.sqrt(
    math.pow(l1 - l2, 2) + math.pow(a1 - a2, 2) + math.pow(b1 - b2, 2),
  );
}

List<double> _oklab(int rgb) {
  double linear(int shift) {
    final c = ((rgb >> shift) & 0xFF) / 255;
    return c <= 0.04045
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  final r = linear(16);
  final g = linear(8);
  final b = linear(0);
  final l = math.pow(
    0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b,
    1 / 3,
  );
  final m = math.pow(
    0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b,
    1 / 3,
  );
  final s = math.pow(
    0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b,
    1 / 3,
  );
  return [
    0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
  ];
}

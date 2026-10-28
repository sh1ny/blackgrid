import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../tool/markers/icon_set.dart';

/// A minimal SVG that satisfies the restricted single-tint form.
const validSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
    '<path d="M2 2h20v20H2z" fill="#fff"/>'
    '<circle cx="12" cy="12" r="4" fill="#FFFFFF"/></svg>';

/// The starting D7 palette roles.
const starterRoles = <String, String>{
  'exit': '#48D28B',
  'danger': '#FF5252',
  'boss': '#E57CE5',
  'spawn': '#C9CDBF',
  'quest': '#DCC05A',
  'loot': '#E8A04A',
  'utility': '#B7A6F0',
  'pin': '#40C4FF',
};

const _roleOfKey = <String, String>{
  'QuestItems': 'quest',
  'QuestObjectives': 'quest',
  'PmcExtracts': 'exit',
  'ScavExtracts': 'exit',
  'SharedExtracts': 'exit',
  'Transits': 'exit',
  'Hazards': 'danger',
  'HazardZones': 'danger',
  'Switches': 'utility',
  'PmcSpawns': 'spawn',
  'ScavSpawns': 'spawn',
  'BossSpawns': 'boss',
  'CultistSpawns': 'boss',
  'BtrStops': 'utility',
  'lootContainers': 'loot',
  'lootLoose': 'loot',
  'locks': 'utility',
  'stationaryWeapons': 'danger',
  'CustomPins': 'pin',
};

String sha(List<int> bytes) => sha256.convert(bytes).toString();

/// A throwaway icon set directory with a mutable manifest.
class SetFixture {
  SetFixture._(this.dir, this.manifest);

  /// Creates a valid set for [keys] (all 19 by default) and writes it.
  factory SetFixture.create({
    String scope = 'release',
    Iterable<String>? keys,
  }) {
    final dir = Directory.systemTemp.createTempSync('icon_set_test_');
    final fixture = SetFixture._(dir, <String, Object?>{
      'schemaVersion': 1,
      'scope': scope,
      'background': '#090F0D',
      'badge': {'diameter': 24, 'selectedDiameter': 30, 'glyph': 16, 'ring': 2},
      'roles': Map<String, Object?>.of(starterRoles),
      'icons': <Object?>[],
    });
    for (final key in keys ?? iconKeys) {
      final file = iconFileName(key);
      File('${dir.path}${Platform.pathSeparator}$file')
          .writeAsStringSync(validSvg);
      fixture.icons.add(<String, Object?>{
        'key': key,
        'file': file,
        'role': _roleOfKey[key],
        'sha256': sha(utf8.encode(validSvg)),
        'provenance': <String, Object?>{
          'author': 'Blackgrid project',
          'origin': 'project',
          'method': 'ai-assisted',
          'tools': ['Claude Code (claude-opus-5-5)'],
          'concept': <String, Object?>{'source': 'none'},
          'date': '2026-10-28',
        },
      });
    }
    fixture.write();
    return fixture;
  }

  /// The set directory.
  final Directory dir;

  /// The mutable manifest document; call [write] after editing it.
  final Map<String, Object?> manifest;

  /// The manifest file path.
  String get manifestPath =>
      '${dir.path}${Platform.pathSeparator}manifest.json';

  /// The icon entries of the manifest.
  List<Object?> get icons => manifest['icons']! as List<Object?>;

  /// The manifest entry for [key].
  Map<String, Object?> icon(String key) =>
      icons.cast<Map<String, Object?>>().firstWhere((i) => i['key'] == key);

  /// The provenance record of [key].
  Map<String, Object?> provenance(String key) =>
      icon(key)['provenance']! as Map<String, Object?>;

  /// The SVG file of [key].
  File file(String key) => File(
    '${dir.path}${Platform.pathSeparator}${icon(key)['file']! as String}',
  );

  /// Replaces the SVG of [key] and refreshes its recorded hash.
  void setSvg(String key, String svg) {
    file(key).writeAsStringSync(svg);
    icon(key)['sha256'] = sha(utf8.encode(svg));
  }

  /// Writes the manifest.
  void write() => File(manifestPath).writeAsStringSync(jsonEncode(manifest));

  /// Removes the directory.
  void dispose() => dir.deleteSync(recursive: true);
}

/// The failures of an invalid [result]; fails the test when it is valid.
List<IconSetFailure> failuresOf(IconSetResult result) => switch (result) {
  IconSetInvalid(:final failures) => failures,
  IconSetValid() => throw TestFailure('expected an invalid set'),
};

/// Expects that [result] is invalid with a failure of [rule] about [subject]
/// whose value contains every string in [contains].
void expectFailure(
  IconSetResult result, {
  required String rule,
  required String subject,
  List<String> contains = const [],
}) {
  final failures = failuresOf(result);
  final found = failures.any(
    (f) =>
        f.rule == rule &&
        f.subject == subject &&
        contains.every(f.value.contains),
  );
  expect(
    found,
    isTrue,
    reason:
        'no $rule failure for $subject containing $contains in:\n'
        '${failures.map(formatFailure).join('\n')}',
  );
}

/// Expects [result] to be valid and returns the set.
IconSet expectValid(IconSetResult result) => switch (result) {
  IconSetValid(:final set) => set,
  IconSetInvalid(:final failures) => throw TestFailure(
    'expected a valid set:\n${failures.map(formatFailure).join('\n')}',
  ),
};

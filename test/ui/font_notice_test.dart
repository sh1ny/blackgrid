import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// One font file declared in the `fonts:` block of `pubspec.yaml`.
typedef DeclaredFont = ({String family, String asset});

/// Reads the font files declared under `flutter: fonts:` in [pubspecYaml].
List<DeclaredFont> declaredFonts(String pubspecYaml) {
  final root = loadYaml(pubspecYaml) as YamlMap;
  final fonts = (root['flutter'] as YamlMap)['fonts'] as YamlList?;
  return [
    for (final entry in fonts ?? const [])
      for (final font in (entry as YamlMap)['fonts'] as YamlList)
        (
          family: entry['family'] as String,
          asset: (font as YamlMap)['asset'] as String,
        ),
  ];
}

String _squash(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Checks one font file against `THIRD_PARTY_NOTICES.md`.
///
/// Returns one message per problem, each naming the font file: no notice
/// entry, an entry with a different SHA-256, or a missing OFL text for the
/// [family]. An empty list means the notice matches the bytes.
List<String> fontNoticeFailures({
  required String family,
  required String fileName,
  required List<int> bytes,
  required String notices,
  required String oflText,
}) {
  final failures = <String>[];
  final entry = notices
      .split('\n')
      .where((line) => line.contains(fileName))
      .join('\n');
  final sha = sha256.convert(bytes).toString();
  if (entry.isEmpty) {
    failures.add('$fileName: THIRD_PARTY_NOTICES.md has no entry for it');
  } else if (!entry.contains(sha)) {
    failures.add(
      '$fileName: SHA-256 $sha is not the one in THIRD_PARTY_NOTICES.md',
    );
  }
  if (!_squash(notices).contains(_squash(oflText))) {
    failures.add(
      '$fileName: the full OFL 1.1 text for $family is missing from '
      'THIRD_PARTY_NOTICES.md',
    );
  }
  return failures;
}

String _oflFor(String family) =>
    File('brand/fonts/OFL-${family.toLowerCase()}.txt').readAsStringSync();

void main() {
  final notices = File('THIRD_PARTY_NOTICES.md').readAsStringSync();

  test('every declared font file has a matching notice and OFL text', () {
    final fonts = declaredFonts(File('pubspec.yaml').readAsStringSync());
    expect(fonts.map((f) => f.family).toSet(), {'Geist', 'Literata'});
    for (final font in fonts) {
      final file = File(font.asset);
      expect(file.existsSync(), isTrue, reason: '${font.asset} must exist');
      final failures = fontNoticeFailures(
        family: font.family,
        fileName: file.uri.pathSegments.last,
        bytes: file.readAsBytesSync(),
        notices: notices,
        oflText: _oflFor(font.family),
      );
      expect(failures, isEmpty);
    }
  });

  test('a hash mismatch names the font file', () {
    final font = declaredFonts(File('pubspec.yaml').readAsStringSync())
        .firstWhere((f) => f.family == 'Geist');
    final name = File(font.asset).uri.pathSegments.last;
    final bytes = File(font.asset).readAsBytesSync();
    final dir = Directory.systemTemp.createTempSync('font_notice_');
    try {
      final copy = File('${dir.path}/$name')
        ..writeAsBytesSync([...bytes]..[bytes.length ~/ 2] ^= 0xff);
      final failures = fontNoticeFailures(
        family: font.family,
        fileName: copy.uri.pathSegments.last,
        bytes: copy.readAsBytesSync(),
        notices: notices,
        oflText: _oflFor(font.family),
      );
      expect(failures, hasLength(1));
      expect(failures.single, startsWith(name));
      expect(failures.single, contains('SHA-256'));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}

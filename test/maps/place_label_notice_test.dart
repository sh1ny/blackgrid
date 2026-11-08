import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pack-relative path of the tarkov.dev licence text the place labels credit.
const _licencePath = 'evidence/terms/tarkov-dev-software-LICENSE.txt';

/// Returns the active generation's directory, read from `active.json`.
Directory _activeGeneration() {
  final pointer = jsonDecode(
    File('assets/maps/active.json').readAsStringSync(),
  ) as Map<String, Object?>;
  return Directory('assets/maps/versions/${pointer['version']}');
}

/// Fails naming [_licencePath] when [generation] lacks the licence text.
void _expectLicence(Directory generation) {
  final licence = File('${generation.path}/$_licencePath');
  if (!licence.existsSync() || licence.lengthSync() == 0) {
    fail('The pack lacks $_licencePath (${generation.path})');
  }
}

void main() {
  test('third-party notices credit the place labels', () {
    final notices = File('THIRD_PARTY_NOTICES.md').readAsLinesSync();
    final entry = notices.where((line) => line.contains('Place labels'));

    expect(entry, hasLength(1), reason: 'one place labels entry');
    final text = entry.single;
    expect(text, contains('the-hideout/tarkov-dev'));
    expect(text, contains('src/data/maps.json'));
    expect(text, contains('MIT'));
    expect(text, contains('Copyright (c) 2019 Oskar Risberg'));
    expect(text, contains(_licencePath));
    expect(text, contains('evidence/sources.json'));
    expect(text, contains('no ownership'));
  });

  test('missing tarkov-dev licence in the pack fails naming the path', () {
    _expectLicence(_activeGeneration());

    final empty = Directory.systemTemp.createTempSync('place_label_notice');
    addTearDown(() => empty.deleteSync(recursive: true));
    expect(
      () => _expectLicence(empty),
      throwsA(
        isA<TestFailure>().having(
          (failure) => failure.message,
          'message',
          contains(_licencePath),
        ),
      ),
    );
  });
}

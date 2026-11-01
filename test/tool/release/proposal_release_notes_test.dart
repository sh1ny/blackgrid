import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/release/src/release_notes.dart';

const _valid =
    '# Change\n\n## Release Notes\n\nSummary.\n\n### Added\n\n- A thing.\n';

void main() {
  test('in-flight proposals of this repository have valid release notes', () {
    // flutter test runs from the package root.
    final changes = Directory('openspec/changes');
    expect(changes.existsSync(), isTrue, reason: changes.absolute.path);

    expect(checkInFlightProposals(changes), isEmpty);
  });

  test('a fixture tree with an invalid in-flight proposal fails naming it', () {
    final root = Directory.systemTemp.createTempSync('in_flight_');
    addTearDown(() => root.deleteSync(recursive: true));
    void write(String path, String text) {
      File('${root.path}/$path')
        ..createSync(recursive: true)
        ..writeAsStringSync(text);
    }

    write('good/proposal.md', _valid);
    write('bad/proposal.md', '# Bad\n\n## Release Notes\n\nSummary.\n');
    write('missing/proposal.md', '# Missing\n\n## Why\n\nBecause.\n');
    write('archive/2026-01-01-old/proposal.md', '# Old, no section\n');

    final problems = checkInFlightProposals(root);

    expect(problems, hasLength(2));
    final bad = problems.firstWhere((p) => p.$1.contains('bad'));
    expect(bad.$1, endsWith('bad${Platform.pathSeparator}proposal.md'));
    expect(bad.$2, startsWith('line 3:'));
    expect(bad.$2, contains('no list item'));
    final missing = problems.firstWhere((p) => p.$1.contains('missing'));
    expect(missing.$2, contains('no release notes'));
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/markers/check.dart';
import 'support/icon_set_fixture.dart';

void main() {
  late SetFixture fx;

  setUp(() => fx = SetFixture.create());
  tearDown(() => fx.dispose());

  test('cli: valid fixture exits 0 and prints no failure lines', () {
    final out = StringBuffer();
    final err = StringBuffer();
    expect(runCli([fx.manifestPath], out: out, err: err), 0);
    expect(out.toString(), contains('valid'));
    expect(out.toString(), isNot(contains('form:')));
    expect(err.toString(), isEmpty);
  });

  test('cli: invalid fixture exits 1 with one line per failure', () {
    fx.icon('Transits').remove('provenance');
    fx.file('Switches').writeAsStringSync('$validSvg ');
    fx.icon('BtrStops')['role'] = 'nowhere';
    fx.write();
    final out = StringBuffer();
    expect(runCli([fx.manifestPath], out: out, err: StringBuffer()), 1);
    final lines = out.toString().trim().split('\n');
    expect(
      lines,
      contains('provenance: transits.svg: missing provenance record'),
    );
    expect(
      lines.any(
        (l) =>
            l.startsWith('provenance: switches.svg: stale') &&
            l.contains('expected sha256 ${sha(utf8.encode('$validSvg '))}'),
      ),
      isTrue,
      reason: 'stale records print the expected hash',
    );
    expect(lines.any((l) => l.startsWith('palette: BtrStops:')), isTrue);
  });

  test('cli: usage errors exit 2', () {
    final err = StringBuffer();
    expect(runCli([], out: StringBuffer(), err: err), 2);
    expect(err.toString(), contains('usage'));
    expect(runCli(['a', 'b'], out: StringBuffer(), err: StringBuffer()), 2);
  });
}

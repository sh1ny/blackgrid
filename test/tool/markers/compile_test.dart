import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/markers/compile.dart';
import '../../../tool/markers/icon_set.dart';
import 'support/icon_set_fixture.dart';

void main() {
  late SetFixture fx;

  setUp(
    () => fx = SetFixture.create(
      scope: 'candidate',
      keys: ['PmcExtracts', 'Hazards'],
    ),
  );
  tearDown(() => fx.dispose());

  String compiledPath(String name) =>
      '${fx.dir.path}${Platform.pathSeparator}compiled'
      '${Platform.pathSeparator}$name';

  int compile() =>
      runCli([fx.manifestPath], out: StringBuffer(), err: StringBuffer());

  List<String> failureLines() =>
      compiledSetFailures(expectValid(checkIconSet(fx.manifestPath)))
          .map(formatFailure)
          .toList();

  test('compiledSetFailures passes a set compiled in step', () {
    expect(compile(), 0);
    expect(failureLines(), isEmpty);
  });

  test('compiledSetFailures names a stale compiled file', () {
    expect(compile(), 0);
    fx.setSvg('PmcExtracts', validSvg.replaceFirst('r="4"', 'r="5"'));
    fx.write();
    expect(failureLines(), [contains('compiled: pmc_extracts.vec: stale')]);
  });

  test('compiledSetFailures names a missing compiled file', () {
    expect(compile(), 0);
    File(compiledPath('hazards.vec')).deleteSync();
    expect(failureLines(), [contains('compiled: hazards.vec: missing')]);
  });

  test('compiledSetFailures names labels.vec as unexpected', () {
    expect(compile(), 0);
    File(compiledPath('labels.vec')).writeAsBytesSync([1, 2, 3]);
    expect(failureLines(), [contains('compiled: labels.vec: unexpected')]);
  });

  test('compiledSetFailures names every file when nothing is compiled', () {
    expect(failureLines(), hasLength(2));
  });

  test('cli: an invalid set exits 1 and writes nothing', () {
    fx.icon('Hazards')['role'] = 'nowhere';
    fx.write();
    final out = StringBuffer();
    expect(runCli([fx.manifestPath], out: out, err: StringBuffer()), 1);
    expect(out.toString(), contains('palette: Hazards:'));
    expect(Directory(compiledPath('')).existsSync(), isFalse);
  });

  test('cli: removes other files from compiled and leaves no .tmp', () {
    Directory(compiledPath('')).createSync();
    File(compiledPath('labels.vec')).writeAsBytesSync([1]);
    expect(compile(), 0);
    final names = Directory(
      compiledPath(''),
    ).listSync().map((e) => e.uri.pathSegments.last).toList()..sort();
    expect(names, ['hazards.vec', 'pmc_extracts.vec']);
  });

  test('cli: refuses a linked compiled directory and deletes nothing', () {
    final elsewhere = Directory('${fx.dir.path}${Platform.pathSeparator}src')
      ..createSync();
    final kept = File('${elsewhere.path}${Platform.pathSeparator}keep.svg')
      ..writeAsStringSync('keep');
    // Dart creates a junction or a symbolic link; either is refused.
    Link('${fx.dir.path}${Platform.pathSeparator}compiled')
        .createSync(elsewhere.path);
    final out = StringBuffer();
    expect(runCli([fx.manifestPath], out: out, err: StringBuffer()), 1);
    expect(out.toString(), contains('is a symbolic link or junction'));
    expect(kept.readAsStringSync(), 'keep');
    expect(elsewhere.listSync(), hasLength(1));
  });

  test('cli: usage errors exit 2', () {
    final err = StringBuffer();
    expect(runCli(['a', 'b'], out: StringBuffer(), err: err), 2);
    expect(err.toString(), contains('usage'));
  });

  test('compiling the same SVG twice gives equal bytes', () {
    expect(compile(), 0);
    final first = File(compiledPath('hazards.vec')).readAsBytesSync();
    expect(compile(), 0);
    expect(File(compiledPath('hazards.vec')).readAsBytesSync(), first);
    expect(
      compileIconSvg(validSvg, 'a.svg'),
      compileIconSvg(validSvg, 'a.svg'),
    );
  });

  test("the committed release set's compiled files are in step", () {
    final set = expectValid(checkIconSet('assets/map_markers/manifest.json'));
    expect(compiledSetFailures(set).map(formatFailure), isEmpty);
  });
}

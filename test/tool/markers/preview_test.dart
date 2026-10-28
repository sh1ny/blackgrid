import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/markers/icon_set.dart';
import '../../../tool/markers/preview.dart';
import 'support/icon_set_fixture.dart';

final _cell = RegExp(
  r'<div class="cell" data-set="([^"]*)" data-key="([^"]*)" '
  r'data-state="([^"]*)" data-bg="([^"]*)"',
);

const _states = {'normal', 'selected', 'dimmed', 'highlighted', 'deuteranopia'};
const _backgrounds = {'#070D0B', '#5A6150', '#C9C2A8'};

void main() {
  late Directory work;
  late List<SetFixture> fixtures;

  SetFixture newSet({String scope = 'release'}) {
    final fixture = SetFixture.create(scope: scope);
    fixtures.add(fixture);
    return fixture;
  }

  String outPath([String name = 'index.html']) =>
      '${work.path}${Platform.pathSeparator}sub${Platform.pathSeparator}$name';

  setUp(() {
    work = Directory.systemTemp.createTempSync('preview_test_');
    fixtures = [];
  });

  tearDown(() {
    for (final fixture in fixtures) {
      fixture.dispose();
    }
    work.deleteSync(recursive: true);
  });

  test('sheet has every key x state x background and no external URL', () {
    final set = newSet();
    final out = outPath();
    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();

    final code = runCli(
      [set.manifestPath, '--out', out],
      out: stdoutBuffer,
      err: stderrBuffer,
    );

    expect(code, 0, reason: '$stdoutBuffer$stderrBuffer');
    final html = File(out).readAsStringSync();
    final name = set.dir.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    final cells = _cell
        .allMatches(html)
        .map((m) => m.groups([1, 2, 3, 4]).join('|'));
    expect(cells, hasLength(iconKeys.length * _states.length * 3));
    expect(cells.toSet(), hasLength(cells.length), reason: 'duplicate cells');
    for (final key in iconKeys) {
      for (final state in _states) {
        for (final bg in _backgrounds) {
          expect(
            cells,
            contains('$name|$key|$state|$bg'),
            reason: '$key / $state / $bg',
          );
        }
      }
    }

    // One inline symbol per glyph, tinted by alpha rather than by rewriting.
    expect('<symbol '.allMatches(html), hasLength(iconKeys.length));
    expect(html, contains('<feFlood'));
    expect(html, contains('operator="in"'));
    expect(html, contains('<feColorMatrix'));
    expect(html, contains('#18FFFF'));
    expect(html, contains('opacity="0.22"'));

    // Nothing is fetched from outside the document.
    for (final forbidden in [
      'http:',
      'https:',
      'file:',
      '//',
      '<script',
      '@import',
      '@font-face',
      '<link',
      '<img',
      'src=',
    ]) {
      expect(html, isNot(contains(forbidden)), reason: forbidden);
    }
    for (final m in RegExp(r'url\(([^)]*)\)').allMatches(html)) {
      expect(m.group(1), startsWith('#'), reason: m.group(0));
    }
    for (final m in RegExp(r'href="([^"]*)"').allMatches(html)) {
      expect(m.group(1), startsWith('#'), reason: m.group(0));
    }
    expect(File('$out.tmp').existsSync(), isFalse);
  });

  test('two candidate sets render side by side under their names', () {
    final first = newSet(scope: 'candidate');
    final second = newSet(scope: 'candidate');
    final out = outPath();

    final code = runCli([
      first.manifestPath,
      second.manifestPath,
      '--out',
      out,
    ]);

    expect(code, 0);
    final html = File(out).readAsStringSync();
    final names = [first, second]
        .map((f) => f.dir.uri.pathSegments.lastWhere((s) => s.isNotEmpty))
        .toList();
    expect(names[0], isNot(names[1]));
    final cells = _cell
        .allMatches(html)
        .map((m) => m.groups([1, 2, 3, 4]).join('|'));
    for (final key in iconKeys) {
      for (final name in names) {
        expect(
          cells.where((c) => c.startsWith('$name|$key|')),
          hasLength(_states.length * 3),
          reason: '$name / $key',
        );
      }
    }
    for (final name in names) {
      expect(html, contains('<h2>$name</h2>'));
    }
    expect('<symbol '.allMatches(html), hasLength(iconKeys.length * 2));
  });

  test('keys no set covers get no row', () {
    final set = newSet(scope: 'candidate');
    (set.manifest['icons']! as List<Object?>).removeWhere(
      (e) => (e! as Map<String, Object?>)['key'] != 'Transits',
    );
    set.write();
    final out = outPath();

    expect(runCli([set.manifestPath, '--out', out]), 0);
    final html = File(out).readAsStringSync();
    expect(html, contains('<section class="key" data-key="Transits">'));
    expect('<section class="key"'.allMatches(html), hasLength(1));
    expect(html, isNot(contains('no icon')));
  });

  test('deuteranopia row uses the Machado 2009 full-severity matrix', () {
    final set = newSet();
    final out = outPath();

    expect(runCli([set.manifestPath, '--out', out]), 0);
    expect(
      File(out).readAsStringSync(),
      contains('values="0.367322 0.860646 -0.227968 0 0'),
    );
  });

  test('five sets exit non-zero and write nothing', () {
    final out = outPath();
    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    final manifests = [
      for (var i = 0; i < 5; i++)
        '${work.path}${Platform.pathSeparator}set$i${Platform.pathSeparator}'
            'manifest.json',
    ];

    final code = runCli(
      [...manifests, '--out', out],
      out: stdoutBuffer,
      err: stderrBuffer,
    );

    expect(code, isNot(0));
    expect('$stdoutBuffer$stderrBuffer', contains('4'));
    expect(File(out).existsSync(), isFalse);
    expect(File('$out.tmp').existsSync(), isFalse);
    expect(Directory(File(out).parent.path).existsSync(), isFalse);
  });

  test(
    'invalid set prints failures and leaves the previous sheet untouched',
    () {
      final valid = newSet();
      final broken = newSet();
      broken.icon('Hazards')['sha256'] = '0' * 64;
      broken.write();
      final expected = failuresOf(checkIconSet(broken.manifestPath));
      expect(expected, isNotEmpty);
      final out = outPath();
      File(out).createSync(recursive: true);
      File(out).writeAsBytesSync([1, 2, 3, 4]);
      final stdoutBuffer = StringBuffer();

      final code = runCli(
        [valid.manifestPath, broken.manifestPath, '--out', out],
        out: stdoutBuffer,
        err: StringBuffer(),
      );

      expect(code, 1);
      for (final failure in expected) {
        expect(stdoutBuffer.toString(), contains(formatFailure(failure)));
      }
      expect(File(out).readAsBytesSync(), [1, 2, 3, 4]);
      expect(File('$out.tmp').existsSync(), isFalse);
    },
  );

  test('--out naming an input file, however spelled, writes nothing', () {
    final set = newSet();
    final sep = Platform.pathSeparator;
    final icon = '${set.dir.path}$sep${iconFileName('Hazards')}';
    final inputs = {
      set.manifestPath: File(set.manifestPath).readAsBytesSync(),
      icon: File(icon).readAsBytesSync(),
    };

    for (final out in [
      set.manifestPath,
      icon,
      '${set.dir.path}$sep.${sep}manifest.json',
      '${set.dir.path}${sep}x$sep..$sep${iconFileName('Hazards')}',
    ]) {
      final err = StringBuffer();
      final code = runCli(
        [set.manifestPath, '--out', out],
        out: StringBuffer(),
        err: err,
      );

      expect(code, 1, reason: out);
      expect(err.toString(), contains('input'), reason: out);
      expect(File('$out.tmp').existsSync(), isFalse, reason: out);
    }
    inputs.forEach((path, bytes) {
      expect(File(path).readAsBytesSync(), bytes, reason: path);
    });
  });

  test('--out through a directory link to an input set writes nothing', () {
    final set = newSet();
    final sep = Platform.pathSeparator;
    final alias = Link('${work.path}${sep}alias');
    try {
      alias.createSync(set.dir.path);
    } on FileSystemException catch (e) {
      markTestSkipped('cannot create a link here: ${e.message}');
      return;
    }
    final before = File(set.manifestPath).readAsBytesSync();

    final code = runCli(
      [set.manifestPath, '--out', '${alias.path}${sep}manifest.json'],
      out: StringBuffer(),
      err: StringBuffer(),
    );

    expect(code, 1);
    expect(File(set.manifestPath).readAsBytesSync(), before);
  });

  test(
    '--out through a link then .. reaching an input writes nothing',
    () {
      final set = newSet();
      final sub = Directory('${set.dir.path}/sub')..createSync();
      final alias = Link('${work.path}/alias')..createSync(sub.path);
      final before = File(set.manifestPath).readAsBytesSync();

      final code = runCli(
        [set.manifestPath, '--out', '${alias.path}/../manifest.json'],
        out: StringBuffer(),
        err: StringBuffer(),
      );

      expect(code, 1);
      expect(File(set.manifestPath).readAsBytesSync(), before);
    },
    // Windows collapses `..` before following a link, so the alias there
    // names work/manifest.json, not an input.
    testOn: '!windows',
  );

  test('usage errors exit 2 with a usage line', () {
    final set = newSet();
    for (final args in [
      <String>[],
      ['--out', outPath()],
      [set.manifestPath, '--out'],
      [set.manifestPath, '--bogus'],
    ]) {
      final err = StringBuffer();
      expect(
        runCli(args, out: StringBuffer(), err: err),
        2,
        reason: '$args',
      );
      expect(err.toString(), contains('usage:'));
    }
    expect(
      Directory('${work.path}${Platform.pathSeparator}sub').existsSync(),
      isFalse,
    );
  });
}

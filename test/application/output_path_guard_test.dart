import 'dart:io';

import 'package:blackgrid/application/output_path_guard.dart';
import 'package:flutter_test/flutter_test.dart';

/// Creates [link] as a hard link to [target] with `mklink /H`, which needs no
/// privilege on NTFS.
void _hardLink(String link, String target) {
  final r = Process.runSync('cmd', [
    '/c',
    'mklink',
    '/H',
    link.replaceAll('/', r'\'),
    target.replaceAll('/', r'\'),
  ]);
  if (r.exitCode != 0) fail('mklink /H failed: ${r.stdout}${r.stderr}');
}

void main() {
  group('unsafeOutputReason', () {
    late Directory dir;
    late String input;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('bg_guard');
      input = '${dir.path}${Platform.pathSeparator}x.txt';
      File(input).writeAsStringSync('input');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('a distinct output is safe', () {
      expect(
        unsafeOutputReason('${dir.path}/y.txt', protectedFiles: [input]),
        isNull,
      );
    });

    test('the input itself is refused', () {
      expect(
        unsafeOutputReason(input, protectedFiles: [input]),
        contains('would overwrite input'),
      );
    });

    test('an output whose temp sibling is the input is refused', () {
      final output = '${dir.path}/y.txt';
      expect(
        unsafeOutputReason(output, protectedFiles: ['$output.tmp']),
        contains('would overwrite input'),
      );
    });

    for (final shape in [
      'missing/../x.txt',
      'a/b/../../x.txt',
      'missing/./../X.TXT',
    ]) {
      test(
        '$shape through missing directories still names the input',
        () {
          expect(
            unsafeOutputReason('${dir.path}/$shape', protectedFiles: [input]),
            contains('would overwrite input'),
          );
        },
        // Collapsing `..` past a missing segment and ignoring case are Win32
        // path semantics; the guard's callers are Windows-only.
        skip: Platform.isWindows ? false : 'Windows path semantics',
      );
    }

    test('an output inside a protected directory is refused', () {
      expect(
        unsafeOutputReason(
          '${dir.path}/out/new/z.txt',
          protectedDirectories: ['${dir.path}/OUT'],
        ),
        Platform.isWindows ? contains('must not be modified') : isNull,
      );
      expect(
        unsafeOutputReason(
          '${dir.path}/out/z.txt',
          protectedDirectories: ['${dir.path}/out'],
        ),
        contains('must not be modified'),
      );
    });

    test(
      'writeBytesViaTemp replaces a hard link instead of writing through it',
      () {
        final output = '${dir.path}/y.txt';
        _hardLink(output, input);
        writeBytesViaTemp(output, [1, 2, 3]);
        expect(File(output).readAsBytesSync(), [1, 2, 3]);
        expect(File(input).readAsStringSync(), 'input');
        expect(File('$output.tmp').existsSync(), isFalse);
      },
      skip: Platform.isWindows ? false : 'uses mklink /H',
    );

    test('writeBytesViaTemp refuses a link planted at the temp path', () {
      final output = '${dir.path}/y.txt';
      Link('$output.tmp').createSync(input);
      expect(
        () => writeBytesViaTemp(output, [1, 2, 3]),
        throwsA(isA<FileSystemException>()),
      );
      expect(File(input).readAsStringSync(), 'input');
      expect(File(output).existsSync(), isFalse);
    });

    test('writeBytesViaTemp refuses an output below a link', () {
      final real = Directory('${dir.path}/real')..createSync();
      Link('${dir.path}/via').createSync(real.path);
      expect(
        () => writeBytesViaTemp('${dir.path}/via/z.txt', [1]),
        throwsA(isA<FileSystemException>()),
      );
      expect(real.listSync(), isEmpty);
    });

    test('an output below a link is refused', () {
      final real = Directory('${dir.path}/real')..createSync();
      Link('${dir.path}/via').createSync(real.path);
      expect(
        unsafeOutputReason('${dir.path}/via/z.txt'),
        contains('is a symbolic link or junction'),
      );
    });
  });
}

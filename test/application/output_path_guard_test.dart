import 'dart:io';

import 'package:blackgrid/application/output_path_guard.dart';
import 'package:flutter_test/flutter_test.dart';

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

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/vision/pe.dart';
import '../../support/pe_builder.dart';

typedef _Entry = ({
  int width,
  int height,
  int bitCount,
  int planes,
  int size,
  int id,
});

_Entry _entry(int size, {int bitCount = 32, int id = 1, int bytes = 8}) => (
  width: size,
  height: size,
  bitCount: bitCount,
  planes: 1,
  size: bytes,
  id: id,
);

Uint8List _data(int seed, [int length = 8]) =>
    Uint8List.fromList([for (var i = 0; i < length; i++) (seed + i) & 0xFF]);

void main() {
  test('readIconGroup reads the entries and their image bytes', () {
    final exe = PeBuilder(
      imports: ['KERNEL32.dll'],
      iconGroup: PeBuilder.iconGroupDir([
        _entry(16, id: 1),
        _entry(256, bitCount: 24, id: 7, bytes: 5),
      ]),
      iconImages: {1: _data(10), 7: _data(70, 5)},
    ).build();
    final result = readIconGroup(exe);
    expect(result, isA<IconGroupReadable>());
    final images = (result as IconGroupReadable).images;
    expect(images, hasLength(2));
    expect(
      (images[0].width, images[0].height, images[0].bitCount, images[0].id),
      (16, 16, 32, 1),
    );
    expect(images[0].planes, 1);
    expect(images[0].bytes, _data(10));
    // A stored 0 reads as 256.
    expect(
      (images[1].width, images[1].height, images[1].bitCount, images[1].id),
      (256, 256, 24, 7),
    );
    expect(images[1].bytes, _data(70, 5));
  });

  group('a missing or malformed icon group gives an unreadable result without '
      'throwing', () {
    void expectUnreadable(Uint8List exe, Pattern reason) {
      final result = readIconGroup(exe);
      expect(result, isA<IconGroupUnreadable>());
      expect((result as IconGroupUnreadable).reason, contains(reason));
    }

    test('no .rsrc', () {
      expectUnreadable(PeBuilder().build(), 'no resource');
    });

    test('no RT_GROUP_ICON', () {
      expectUnreadable(
        PeBuilder(version: [1, 0, 0, 0], iconImages: {1: _data(1)}).build(),
        'RT_GROUP_ICON',
      );
    });

    test('a group count above 32', () {
      final entries = [for (var i = 1; i <= 33; i++) _entry(16, id: i)];
      expectUnreadable(
        PeBuilder(
          iconGroup: PeBuilder.iconGroupDir(entries),
          iconImages: {for (var i = 1; i <= 33; i++) i: _data(i)},
        ).build(),
        '33',
      );
    });

    test('a declared count larger than the group data', () {
      expectUnreadable(
        PeBuilder(
          iconGroup: PeBuilder.iconGroupDir([_entry(16)], declaredCount: 5),
          iconImages: {1: _data(1)},
        ).build(),
        'group',
      );
    });

    test('an entry whose nID has no RT_ICON', () {
      expectUnreadable(
        PeBuilder(
          iconGroup: PeBuilder.iconGroupDir([
            _entry(16, id: 1),
            _entry(32, id: 99),
          ]),
          iconImages: {1: _data(1)},
        ).build(),
        '99',
      );
    });

    test('no RT_ICON resources at all', () {
      expectUnreadable(
        PeBuilder(iconGroup: PeBuilder.iconGroupDir([_entry(16)])).build(),
        'RT_ICON',
      );
    });

    test('image data running past the end of the file', () {
      expectUnreadable(
        PeBuilder(
          iconGroup: PeBuilder.iconGroupDir([_entry(16)]),
          iconImages: {1: _data(1)},
          iconSizeOverrides: {1: 0x4000},
        ).build(),
        'outside section data',
      );
    });

    test('an image larger than 1 MiB', () {
      expectUnreadable(
        PeBuilder(
          iconGroup: PeBuilder.iconGroupDir([_entry(16)]),
          iconImages: {1: _data(1)},
          iconSizeOverrides: {1: 0x100001},
        ).build(),
        'too large',
      );
    });

    test('bytes that are not a PE image', () {
      expectUnreadable(Uint8List.fromList([1, 2, 3]), 'MZ');
    });

    test('truncating a valid image at every length never throws', () {
      final exe = PeBuilder(
        imports: ['KERNEL32.dll'],
        iconGroup: PeBuilder.iconGroupDir([_entry(16), _entry(32, id: 2)]),
        iconImages: {1: _data(1), 2: _data(2)},
      ).build();
      expect(readIconGroup(exe), isA<IconGroupReadable>());
      for (var n = 0; n < exe.length; n++) {
        expect(
          () => readIconGroup(Uint8List.sublistView(exe, 0, n)),
          returnsNormally,
          reason: 'truncated to $n bytes',
        );
      }
    });
  });

  test('a malformed icon group leaves the imports and version readable', () {
    final exe = PeBuilder(
      imports: ['KERNEL32.dll', 'USER32.dll'],
      delayImports: ['SHELL32.dll'],
      version: [1, 2, 3, 4],
      iconGroup: PeBuilder.iconGroupDir([_entry(16, id: 42)]),
      iconImages: {1: _data(1)},
    ).build();
    expect(readIconGroup(exe), isA<IconGroupUnreadable>());
    final pe = readPe(exe);
    expect(pe.readable, isTrue, reason: '${pe.error}');
    expect(pe.imports, ['KERNEL32.dll', 'USER32.dll']);
    expect(pe.delayImports, ['SHELL32.dll']);
    expect(pe.versionString, '1.2.3.4');
  });
}

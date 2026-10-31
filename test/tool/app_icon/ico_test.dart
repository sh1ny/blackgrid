import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/app_icon/ico.dart';

/// A square raster of [size] x [size] pixels, every pixel [rgba].
Uint8List solid(int size, List<int> rgba) {
  final out = Uint8List(size * size * 4);
  for (var i = 0; i < out.length; i += 4) {
    out.setRange(i, i + 4, rgba);
  }
  return out;
}

Map<int, Uint8List> fullSet([List<int> rgba = const [10, 20, 30, 255]]) => {
  for (final s in icoRequiredSizes) s: solid(s, rgba),
};

IcoParsed parsed(Uint8List bytes) {
  final r = parseIco(bytes);
  expect(r, isA<IcoParsed>(), reason: '$r');
  return r as IcoParsed;
}

typedef RawEntry = ({int size, Uint8List data, int planes, int bpp});

/// Builds an ICO from hand-picked entries, bypassing [encodeIco].
Uint8List buildIco(List<RawEntry> entries) {
  final headerLen = 6 + 16 * entries.length;
  final total = headerLen + entries.fold<int>(0, (n, e) => n + e.data.length);
  final out = Uint8List(total);
  final d = ByteData.sublistView(out);
  d.setUint16(2, 1, Endian.little);
  d.setUint16(4, entries.length, Endian.little);
  var offset = headerLen;
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    final p = 6 + 16 * i;
    out[p] = e.size >= 256 ? 0 : e.size;
    out[p + 1] = e.size >= 256 ? 0 : e.size;
    d.setUint16(p + 4, e.planes, Endian.little);
    d.setUint16(p + 6, e.bpp, Endian.little);
    d.setUint32(p + 8, e.data.length, Endian.little);
    d.setUint32(p + 12, offset, Endian.little);
    out.setRange(offset, offset + e.data.length, e.data);
    offset += e.data.length;
  }
  return out;
}

/// The entries of a valid encoded set, as editable raw entries.
List<RawEntry> validEntries() => [
  for (final i in parsed(encodeIco(fullSet())).images)
    (size: i.width, data: i.bytes, planes: i.planes, bpp: i.bitCount),
];

void main() {
  group('encodeIco', () {
    test('writes the D4 layout in ascending size order', () {
      final bytes = encodeIco(fullSet());
      final d = ByteData.sublistView(bytes);
      expect(d.getUint16(0, Endian.little), 0);
      expect(d.getUint16(2, Endian.little), 1);
      expect(d.getUint16(4, Endian.little), 10);
      final stored = [for (var i = 0; i < 10; i++) bytes[6 + 16 * i]];
      expect(stored, [16, 20, 24, 32, 40, 48, 64, 96, 128, 0]);
      final images = parsed(bytes).images;
      expect([for (final i in images) i.width], icoRequiredSizes);
      expect(images.last.format, IcoImageFormat.png);
      for (final i in images.take(9)) {
        expect(i.format, IcoImageFormat.dib);
        expect(i.bitCount, 32);
        expect(i.planes, 1);
      }
      expect(checkIco(bytes), isEmpty);
    });

    test('a 16 px DIB is 40-byte header, BGRA rows and a zero AND mask', () {
      final img = parsed(encodeIco(fullSet())).images.first;
      final d = ByteData.sublistView(img.bytes);
      expect(d.getUint32(0, Endian.little), 40);
      expect(d.getInt32(8, Endian.little), 32); // 2 x height
      // 40 + 16*16*4 pixels + 16 rows x 4-byte padded mask.
      expect(img.bytes.length, 40 + 1024 + 16 * 4);
      expect(img.bytes.sublist(40 + 1024).every((b) => b == 0), isTrue);
    });

    test('a half-transparent pixel round-trips with straight alpha', () {
      const px = [200, 100, 50, 128];
      final set = fullSet()
        ..[16] = solid(16, px)
        ..[256] = solid(256, px);
      final images = parsed(encodeIco(set)).images;
      for (final i in [images.first, images.last]) {
        final rgba = i.decodeRgba()!;
        expect(rgba.sublist(0, 4), px, reason: '${i.width} px');
        expect(rgba.length, i.width * i.width * 4);
      }
    });

    test('DIB rows are bottom-up', () {
      final r = solid(16, [0, 0, 0, 255]);
      r.setRange(0, 4, [1, 2, 3, 255]); // top-left pixel
      final rgba = parsed(encodeIco(fullSet()..[16] = r)).images.first
          .decodeRgba()!;
      expect(rgba.sublist(0, 4), [1, 2, 3, 255]);
      expect(rgba.sublist(4, 8), [0, 0, 0, 255]);
    });
  });

  group('parseIco', () {
    test('a stored width or height of 0 reads as 256', () {
      final images = parsed(encodeIco(fullSet())).images;
      expect(images.last.width, 256);
      expect(images.last.height, 256);
    });

    test('exposes exactly the bytes rc.exe copies', () {
      final bytes = encodeIco(fullSet());
      final d = ByteData.sublistView(bytes);
      final images = parsed(bytes).images;
      for (var i = 0; i < images.length; i++) {
        final size = d.getUint32(6 + 16 * i + 8, Endian.little);
        final off = d.getUint32(6 + 16 * i + 12, Endian.little);
        expect(images[i].bytes, bytes.sublist(off, off + size));
      }
    });

    test('malformed input is unreadable and never throws', () {
      final good = encodeIco(fullSet());
      final cases = <Uint8List>[
        Uint8List(0),
        Uint8List(5),
        Uint8List.fromList([0, 0, 2, 0, 1, 0]), // type 2 (cursor)
        Uint8List.fromList([0, 0, 1, 0, 3, 0]), // count beyond data
        Uint8List.sublistView(good, 0, 100), // entries past the end
      ];
      for (final c in cases) {
        expect(parseIco(c), isA<IcoUnreadable>());
        expect(checkIco(c), isNotEmpty);
      }
    });
  });

  group('checkIco', () {
    test('an ico missing 20 px or with a duplicate 32 px fails naming the '
        'size', () {
      final entries = validEntries();
      final without20 = buildIco([
        for (final e in entries)
          if (e.size != 20) e,
      ]);
      final missing = checkIco(without20);
      expect(missing, hasLength(1));
      expect(missing.single, contains('20 px'));
      expect(missing.single, contains('missing'));
      expect(missing.single, contains(icoRequiredSizes.join(', ')));

      final dup = buildIco([
        ...entries,
        entries.firstWhere((e) => e.size == 32),
      ]);
      final dupFailures = checkIco(dup);
      expect(dupFailures, hasLength(1));
      expect(dupFailures.single, contains('32 px'));
      expect(dupFailures.single, contains('duplicate'));
      expect(dupFailures.single, contains(icoRequiredSizes.join(', ')));
    });

    test('an ico with the Flutter default SHA-256 fails as the Flutter '
        'default', () {
      final bytes = File('test/fixtures/app_icon/flutter_default_app_icon.ico')
          .readAsBytesSync();
      expect(
        flutterDefaultIcoSha256,
        'c098d3fc85cacff98b8e69811b48e9f0d852fcee278132d794411d978869cbf8',
      );
      final failures = checkIco(bytes);
      expect(
        failures.where((f) => f.contains('Flutter default')),
        hasLength(1),
      );
    });

    test('directory planes and bit count must equal the DIB header', () {
      final entries = validEntries();
      final bad = buildIco([
        for (final e in entries)
          if (e.size == 48) (size: 48, data: e.data, planes: 2, bpp: 32) else e,
      ]);
      final failures = checkIco(bad);
      expect(failures, hasLength(1));
      expect(failures.single, contains('48 px'));
      expect(failures.single, contains('planes'));

      final badBpp = buildIco([
        for (final e in entries)
          if (e.size == 24) (size: 24, data: e.data, planes: 1, bpp: 24) else e,
      ]);
      expect(checkIco(badBpp).join('\n'), contains('24 px'));
    });

    test('a PNG-encoded 32 px entry fails', () {
      final entries = validEntries();
      final png = entries.last.data; // a valid PNG, wrong size on purpose
      final bad = buildIco([
        for (final e in entries)
          if (e.size == 32) (size: 32, data: png, planes: 1, bpp: 32) else e,
      ]);
      final failures = checkIco(bad);
      expect(failures, isNotEmpty);
      expect(failures.join('\n'), contains('32 px'));
      expect(failures.join('\n'), contains('PNG'));
    });

    test('a 24 bpp entry fails', () {
      final entries = validEntries();
      // A 24-bpp DIB header with matching directory fields.
      final dib = Uint8List.fromList(entries.first.data);
      ByteData.sublistView(dib).setUint16(14, 24, Endian.little);
      final bad = buildIco([
        (size: 16, data: dib, planes: 1, bpp: 24),
        ...entries.skip(1),
      ]);
      final failures = checkIco(bad);
      expect(failures, isNotEmpty);
      expect(failures.join('\n'), contains('16 px'));
      expect(failures.join('\n'), contains('32-bit'));
    });

    test('a fully transparent image fails', () {
      final bytes = encodeIco(fullSet()..[64] = solid(64, [9, 9, 9, 0]));
      final failures = checkIco(bytes);
      expect(failures, hasLength(1));
      expect(failures.single, contains('64 px'));
      expect(failures.single, contains('transparent'));
    });
  });
}

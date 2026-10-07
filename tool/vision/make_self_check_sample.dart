// Generates the vision self-check sample (change add-native-vision-runtime).
//
// Renders a fixed title with the vendored Spleen 32x64 BDF font (BSD-2-Clause,
// see tool/vision/fonts/spleen and THIRD_PARTY_NOTICES.md) and writes
//   assets/vision/self_check/title.gray  raw 8-bit grayscale, row-major, no codec
//   assets/vision/self_check/title.json  format, width, height, stride, text, template rect
//
// Output is deterministic: running it twice yields byte-identical files.
//
// Usage: dart run tool/vision/make_self_check_sample.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const String expectedText = 'SALEWA FIRST AID KIT';
const int padding = 16;
const int background = 235;
const int foreground = 25;

/// Template rect: the word "SALEWA" (six glyph cells) including a margin.
const int templateGlyphs = 6;

class _Glyph {
  _Glyph(this.advance, this.w, this.h, this.xOff, this.yOff, this.rows);
  final int advance;
  final int w;
  final int h;
  final int xOff;
  final int yOff;
  final List<List<int>> rows;
}

Map<int, _Glyph> _parseBdf(List<String> lines, {required Set<int> wanted}) {
  final glyphs = <int, _Glyph>{};
  var i = 0;
  while (i < lines.length) {
    if (!lines[i].startsWith('STARTCHAR')) {
      i++;
      continue;
    }
    var encoding = -1;
    var advance = 0;
    var w = 0, h = 0, xOff = 0, yOff = 0;
    final rows = <List<int>>[];
    i++;
    while (!lines[i].startsWith('ENDCHAR')) {
      final line = lines[i];
      final parts = line.split(' ');
      if (parts[0] == 'ENCODING') {
        encoding = int.parse(parts[1]);
      } else if (parts[0] == 'DWIDTH') {
        advance = int.parse(parts[1]);
      } else if (parts[0] == 'BBX') {
        w = int.parse(parts[1]);
        h = int.parse(parts[2]);
        xOff = int.parse(parts[3]);
        yOff = int.parse(parts[4]);
      } else if (parts[0] == 'BITMAP') {
        for (var r = 0; r < h; r++) {
          i++;
          final hex = lines[i];
          final bits = <int>[];
          for (var c = 0; c < hex.length; c += 2) {
            final byte = int.parse(hex.substring(c, c + 2), radix: 16);
            for (var b = 7; b >= 0; b--) {
              bits.add((byte >> b) & 1);
            }
          }
          rows.add(bits);
        }
      }
      i++;
    }
    if (wanted.contains(encoding)) {
      glyphs[encoding] = _Glyph(advance, w, h, xOff, yOff, rows);
    }
    i++;
  }
  return glyphs;
}

/// Box-filters the bitmap render down by 2 in each axis. It turns the bitmap
/// font's hard pixel edges into anti-aliased edges like rendered UI text.
Uint8List _halve(Uint8List src, int w, int h) {
  final ow = w ~/ 2, oh = h ~/ 2;
  final out = Uint8List(ow * oh);
  for (var y = 0; y < oh; y++) {
    for (var x = 0; x < ow; x++) {
      final sum =
          src[2 * y * w + 2 * x] +
          src[2 * y * w + 2 * x + 1] +
          src[(2 * y + 1) * w + 2 * x] +
          src[(2 * y + 1) * w + 2 * x + 1];
      out[y * ow + x] = (sum + 2) >> 2;
    }
  }
  return out;
}

void main() {
  final root = File.fromUri(Platform.script).parent.parent.parent.uri;
  final bdf = File.fromUri(
    root.resolve('tool/vision/fonts/spleen/spleen-32x64.bdf'),
  );
  final lines = const LineSplitter().convert(bdf.readAsStringSync());
  final glyphs = _parseBdf(lines, wanted: expectedText.codeUnits.toSet());

  var ascent = 0, descent = 0;
  for (final l in lines) {
    if (l.startsWith('FONT_ASCENT ')) ascent = int.parse(l.split(' ')[1]);
    if (l.startsWith('FONT_DESCENT ')) descent = int.parse(l.split(' ')[1]);
  }

  var textWidth = 0;
  for (final c in expectedText.codeUnits) {
    textWidth += glyphs[c]!.advance;
  }
  final width = textWidth + 2 * padding;
  final height = ascent + descent + 2 * padding;
  final stride = width; // full-resolution render, tightly packed
  final pixels = Uint8List(stride * height)
    ..fillRange(0, stride * height, background);

  var penX = padding;
  final baseline = padding + ascent;
  for (final c in expectedText.codeUnits) {
    final g = glyphs[c]!;
    final top = baseline - (g.yOff + g.h);
    for (var r = 0; r < g.h; r++) {
      for (var col = 0; col < g.w; col++) {
        if (g.rows[r][col] == 1) {
          pixels[(top + r) * stride + penX + g.xOff + col] = foreground;
        }
      }
    }
    penX += g.advance;
  }

  final cell = glyphs[expectedText.codeUnits.first]!.advance;
  // Output is half the render size; stride equals width (tightly packed).
  final outW = width ~/ 2, outH = height ~/ 2;
  final meta = <String, Object>{
    'format': 1,
    'width': outW,
    'height': outH,
    'stride': outW,
    'text': expectedText,
    'template': <String, int>{
      'x': padding ~/ 2,
      'y': padding ~/ 2,
      'width': cell * templateGlyphs ~/ 2,
      'height': (ascent + descent) ~/ 2,
    },
  };

  final outDir = Directory.fromUri(root.resolve('assets/vision/self_check/'))
    ..createSync(recursive: true);
  File.fromUri(outDir.uri.resolve('title.gray'))
      .writeAsBytesSync(_halve(pixels, width, height));
  final json = const JsonEncoder.withIndent('  ').convert(meta);
  File.fromUri(outDir.uri.resolve('title.json'))
      .writeAsBytesSync(utf8.encode('$json\n'));
  stdout.writeln('wrote ${outDir.path} ${outW}x$outH');
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A valid one-rectangle SVG that the marker compiler accepts.
const validSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
    '<rect width="10" height="10" fill="#e6a63d"/></svg>';

/// An SVG that the marker compiler rejects (`filter` is unimplemented).
const rejectedSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
    '<filter id="f"/><rect width="10" height="10"/></svg>';

/// A tiny PNG.
Uint8List tinyPng() => Uint8List.fromList(
  img.encodePng(img.Image(width: 4, height: 4, numChannels: 4)),
);

/// A fake rasterizer that records its calls and returns a straight-RGBA
/// buffer whose alpha is 255 and whose red channel encodes the size.
class RecordingRasterizer {
  /// The `(debugName, size)` of each call, in order.
  final List<(String name, int size)> calls = [];

  /// Rasterizes without drawing anything real.
  Future<Uint8List> call(Uint8List compiled, int size, String name) async {
    calls.add((name, size));
    final out = Uint8List(size * size * 4);
    for (var i = 0; i < out.length; i += 4) {
      out[i] = size % 256;
      out[i + 3] = 255;
    }
    return out;
  }
}

/// One recorded candidates-folder entry.
Map<String, Object?> candidateEntry(String file, {String? concept}) => {
  'file': file,
  'author': 'Test Author',
  'method': 'ai-assisted',
  'tools': ['ChatGPT'],
  'date': '2026-10-31',
  'prompt': null,
  'concept': concept,
};

/// Writes a candidates folder under [root] with [concepts] PNGs and [vectors]
/// SVGs (each map value is the SVG text), plus a record naming the files in
/// [recorded] (every file when null). Returns the folder path.
String writeCandidates(
  Directory root, {
  List<String> concepts = const [],
  Map<String, String> vectors = const {},
  List<String>? recorded,
}) {
  final dir = Directory('${root.path}/candidates')..createSync();
  Directory('${dir.path}/concepts').createSync();
  Directory('${dir.path}/vector').createSync();
  for (final name in concepts) {
    File('${dir.path}/concepts/$name').writeAsBytesSync(tinyPng());
  }
  vectors.forEach((name, text) {
    File('${dir.path}/vector/$name').writeAsStringSync(text);
  });
  final files = [
    for (final c in concepts) 'concepts/$c',
    for (final v in vectors.keys) 'vector/$v',
  ];
  final firstConcept = concepts.isEmpty ? null : 'concepts/${concepts.first}';
  final entries = [
    for (final f in recorded ?? files)
      candidateEntry(f, concept: f.startsWith('vector/') ? firstConcept : null),
  ];
  File(
    '${dir.path}/provenance.json',
  ).writeAsStringSync(jsonEncode({'schemaVersion': 1, 'candidates': entries}));
  return dir.path;
}

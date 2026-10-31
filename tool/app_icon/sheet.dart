// The app icon comparison sheet (design D3): one self-contained HTML file with
// a column per recorded candidate, each at every icon size and enlarged, on a
// light and a dark background. Pure Dart (no `dart:ui`): the rasters come from
// an injected [IconRasterizer].
//
// A failed run writes nothing and leaves any earlier sheet in place; the
// sheet itself is written through a `.tmp` file and a rename.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'ico.dart';
import 'provenance.dart';
import 'render.dart';

/// The most candidates one sheet shows (design Resource Bounds).
const int maxSheetCandidates = 12;

/// Where the sheet is written, relative to the repository root.
const String defaultSheetPath = 'build/app-icon-preview/index.html';

/// Where the candidates live, relative to the repository root.
const String defaultCandidatesDir = 'docs/design/app-icon/candidates';

/// The candidates record's file name inside the candidates folder.
const String candidatesRecordName = 'provenance.json';

const _lightBackground = '#F3F4F6';
const _darkBackground = '#11161A';
const _enlarge = 4;

/// Writes the comparison sheet for the candidates in [candidatesDir] to
/// [outputPath].
///
/// Order of work, each step failing the run before the next starts:
/// 1. the candidates record must parse and name every PNG under `concepts/`
///    and SVG under `vector/` (an unrecorded file fails naming it);
/// 2. at most [maxSheetCandidates] candidates;
/// 3. every vector is read (at most [maxSourceBytes]) and compiled;
/// 4. every vector is rasterized at every size in [icoRequiredSizes] through
///    [rasterize].
///
/// Only then is the sheet written. Returns the failure messages, each naming
/// the file, when any step fails.
Future<IconToolResult> writeSheet({
  required String candidatesDir,
  required String outputPath,
  required IconRasterizer rasterize,
}) async {
  final Uint8List recordBytes;
  try {
    recordBytes = File('$candidatesDir/$candidatesRecordName')
        .readAsBytesSync();
  } on FileSystemException catch (e) {
    return IconToolResult.failure([
      '$candidatesRecordName: cannot read the candidates record '
          '($candidatesDir): ${e.message}',
    ]);
  }

  final discovered = _discover(candidatesDir);
  final parsed = parseCandidatesRecord(
    utf8.decode(recordBytes, allowMalformed: true),
    fileExists: (file) => File('$candidatesDir/$file').existsSync(),
  );
  final List<CandidateEntry> entries;
  switch (parsed) {
    case CandidatesInvalid(:final failures):
      return IconToolResult.failure(failures);
    case CandidatesParsed(:final candidates):
      entries = candidates;
  }

  final recorded = {for (final e in entries) e.file};
  final unrecorded = [
    for (final file in discovered)
      if (!recorded.contains(file))
        '$file: has no entry in $candidatesRecordName, so it cannot appear '
            'on the sheet',
  ];
  if (unrecorded.isNotEmpty) return IconToolResult.failure(unrecorded);

  if (entries.length > maxSheetCandidates) {
    return IconToolResult.failure([
      '${entries.length} candidates recorded; a sheet shows at most '
          '$maxSheetCandidates. Split the round.',
    ]);
  }

  final vectors = [
    for (final e in entries)
      if (e.file.startsWith('vector/')) e.file,
  ];
  final compile = compileSources({
    for (final v in vectors) v: '$candidatesDir/$v',
  });
  if (compile.failures.isNotEmpty) {
    return IconToolResult.failure(compile.failures);
  }

  final rasters = <String, Map<int, String>>{};
  for (final source in compile.compiled) {
    final bySize = <int, String>{};
    for (final size in icoRequiredSizes) {
      try {
        final rgba = await rasterizeChecked(rasterize, source, size);
        bySize[size] = _pngDataUri(rgba, size);
      } on Object catch (e) {
        return IconToolResult.failure([
          '${source.name}: rendering at $size px failed ($e)',
        ]);
      }
    }
    rasters[source.name] = bySize;
  }

  final conceptUris = <String, String>{};
  for (final e in entries) {
    if (!e.file.startsWith('concepts/')) continue;
    try {
      final bytes = File('$candidatesDir/${e.file}').readAsBytesSync();
      conceptUris[e.file] = 'data:image/png;base64,${base64Encode(bytes)}';
    } on FileSystemException catch (error) {
      return IconToolResult.failure([
        '${e.file}: cannot read (${error.message})',
      ]);
    }
  }

  final html = _renderSheet(entries, rasters, conceptUris);
  try {
    writeAtomically(outputPath, utf8.encode(html));
  } on FileSystemException catch (e) {
    return IconToolResult.failure([
      '$outputPath: cannot write the sheet (${e.message})',
    ]);
  }
  return IconToolResult.success([
    'wrote $outputPath (${entries.length} candidates)',
  ]);
}

/// Candidate files on disk: `concepts/*.png` and `vector/*.svg`, relative to
/// the candidates folder, sorted.
List<String> _discover(String candidatesDir) {
  List<String> list(String sub, String extension) {
    final dir = Directory('$candidatesDir/$sub');
    if (!dir.existsSync()) return const [];
    return [
      for (final entity in dir.listSync(followLinks: false))
        if (entity is File && entity.path.toLowerCase().endsWith(extension))
          '$sub/${entity.uri.pathSegments.last}',
    ]..sort();
  }

  return [...list('concepts', '.png'), ...list('vector', '.svg')];
}

String _pngDataUri(Uint8List rgba, int size) {
  final image = img.Image.fromBytes(
    width: size,
    height: size,
    bytes: rgba.buffer,
    bytesOffset: rgba.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return 'data:image/png;base64,${base64Encode(img.encodePng(image))}';
}

String _esc(String text) =>
    const HtmlEscape(HtmlEscapeMode.attribute).convert(text);

String _renderSheet(
  List<CandidateEntry> entries,
  Map<String, Map<int, String>> rasters,
  Map<String, String> conceptUris,
) {
  final css = StringBuffer();
  final columns = StringBuffer();
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final isVector = entry.file.startsWith('vector/');
    final label = isVector
        ? 'vector raster (exact pixels of the .ico)'
        : 'browser-scaled concept (not the shipped raster)';
    final imageClass = <int, String>{};
    if (isVector) {
      for (final size in icoRequiredSizes) {
        imageClass[size] = 'c$i-s$size';
        css.writeln(
          '.c$i-s$size { background-image: '
          'url("${rasters[entry.file]![size]}"); }',
        );
      }
    } else {
      css.writeln(
        '.c$i { background-image: url("${conceptUris[entry.file]}"); }',
      );
    }

    columns
      ..writeln('<section class="candidate" data-file="${_esc(entry.file)}">')
      ..writeln('<h2>${_esc(entry.file)}</h2>')
      ..writeln('<p class="kind">$label</p>')
      ..writeln('<dl>')
      ..writeln('<dt>Author</dt><dd>${_esc(entry.author)}</dd>')
      ..writeln('<dt>Method</dt><dd>${_esc(entry.method.wire)}</dd>')
      ..writeln('<dt>Tools</dt><dd>${_esc(entry.tools.join(', '))}</dd>')
      ..writeln('<dt>Date</dt><dd>${_esc(entry.date)}</dd>');
    if (entry.concept case final concept?) {
      columns.writeln('<dt>Concept</dt><dd>${_esc(concept)}</dd>');
    }
    columns.writeln('</dl>');
    for (final (name, _) in const [
      ('light', _lightBackground),
      ('dark', _darkBackground),
    ]) {
      columns.writeln('<div class="panel $name">');
      for (final size in icoRequiredSizes) {
        final cls = isVector ? imageClass[size]! : 'c$i';
        final pixelated = isVector ? ' pixelated' : '';
        final alt = _esc('${entry.file} at $size px');
        columns
          ..writeln(
            '<div class="cell" data-file="${_esc(entry.file)}" '
            'data-size="$size" data-background="$name">',
          )
          ..writeln('<span class="size">$size px</span>')
          ..writeln(
            '<div class="img$pixelated $cls" role="img" aria-label="$alt" '
            'style="width:${size}px;height:${size}px"></div>',
          )
          ..writeln(
            '<div class="img$pixelated $cls" role="img" '
            'aria-label="$alt, enlarged ${_enlarge}x" '
            'style="width:${size * _enlarge}px;height:'
            '${size * _enlarge}px"></div>',
          )
          ..writeln('</div>');
      }
      columns.writeln('</div>');
    }
    columns.writeln('</section>');
  }

  return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Blackgrid app icon candidates</title>
<style>
body { margin: 0; padding: 16px; font-family: sans-serif; background: #fff; color: #111; }
h1 { font-size: 20px; }
.sheet { display: flex; gap: 16px; align-items: flex-start; overflow-x: auto; }
.candidate { flex: none; padding: 8px; border: 1px solid #999; }
.candidate h2 { font-size: 14px; margin: 0 0 4px; }
.kind { font-size: 12px; margin: 0 0 8px; }
dl { font-size: 12px; margin: 0 0 8px; }
dt { font-weight: bold; }
dd { margin: 0 0 2px; }
.panel { padding: 8px; margin-bottom: 8px; }
.panel.light { background: $_lightBackground; color: #111; }
.panel.dark { background: $_darkBackground; color: #eee; }
.cell { display: flex; align-items: center; gap: 8px; margin-bottom: 8px; }
.size { width: 44px; font-size: 11px; flex: none; }
.img { background-repeat: no-repeat; background-size: 100% 100%; flex: none; }
.img.pixelated { image-rendering: pixelated; }
$css</style>
</head>
<body>
<h1>Blackgrid app icon candidates</h1>
<p>Vector columns show the exact rasters the .ico would hold, at 1x and enlarged ${_enlarge}x with image-rendering: pixelated. Concept columns are browser-scaled concept images.</p>
<div class="sheet">
$columns</div>
</body>
</html>
''';
}

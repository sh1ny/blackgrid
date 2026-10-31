// Rebuilds the committed Windows icon from its source SVG (design D1, D2, D4).
// Pure Dart (no `dart:ui`): the rasters come from an injected
// [IconRasterizer].
//
// Every source is validated and compiled before anything is rendered, and the
// `.ico` and the record are written only after every size rendered: the `.ico`
// first, then the record, each through a `.tmp` file and a rename. A failed
// run therefore leaves both unchanged.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'ico.dart';
import 'provenance.dart';
import 'render.dart';
import 'sheet.dart' show candidatesRecordName;

/// Where the icon sources and their record live, relative to the repository
/// root.
const String defaultIconSourceDir = 'windows/runner/resources/app_icon';

/// Where the generated icon is written, relative to the repository root.
const String defaultIcoPath = 'windows/runner/resources/app_icon.ico';

/// The source record's file name inside the icon source folder.
const String sourceRecordName = 'provenance.json';

/// The sizes drawn from the small-size SVG when it exists.
const Set<int> smallSizes = {16, 20, 24};

/// Rebuilds [icoPath] and the record in [iconDir] from the SVG sources there.
///
/// [iconDir] holds `app_icon.svg`, the optional `app_icon_small.svg` and
/// `provenance.json`. The record's hash binding is ignored (it is about to be
/// rewritten), but its picked candidate and concept are checked against the
/// candidates record in [candidatesDir]. Sizes 16, 20 and 24 come from the
/// small SVG when present.
///
/// Returns failure messages naming the file at fault, and writes nothing,
/// when any record is invalid, a source is over [maxSourceBytes], a source
/// does not compile, or a size fails to render.
Future<IconToolResult> buildIcon({
  required String iconDir,
  required String icoPath,
  required String candidatesDir,
  required IconRasterizer rasterize,
}) async {
  final recordPath = '$iconDir/$sourceRecordName';
  final String recordText;
  try {
    recordText = File(recordPath).readAsStringSync();
  } on FileSystemException catch (e) {
    return IconToolResult.failure([
      '$sourceRecordName: cannot read the source record ($recordPath): '
          '${e.message}',
    ]);
  }
  final SourceRecord record;
  switch (parseSourceRecord(recordText)) {
    case SourceInvalid(:final failures):
      return IconToolResult.failure([
        for (final f in failures) '$sourceRecordName: $f',
      ]);
    case SourceParsed(record: final parsed):
      record = parsed;
  }

  final candidatesPath = '$candidatesDir/$candidatesRecordName';
  final String candidatesText;
  try {
    candidatesText = File(candidatesPath).readAsStringSync();
  } on FileSystemException catch (e) {
    return IconToolResult.failure([
      '$candidatesRecordName: cannot read the candidates record '
          '($candidatesPath): ${e.message}',
    ]);
  }
  switch (parseCandidatesRecord(
    candidatesText,
    fileExists: (file) => File('$candidatesDir/$file').existsSync(),
  )) {
    case CandidatesInvalid(:final failures):
      return IconToolResult.failure([
        for (final f in failures) '$candidatesRecordName: $f',
      ]);
    case final CandidatesParsed candidates:
      final mismatches = checkSourceAgainstCandidates(record, candidates);
      if (mismatches.isNotEmpty) return IconToolResult.failure(mismatches);
  }

  final smallPath = '$iconDir/$smallSvgName';
  final hasSmall = File(smallPath).existsSync();
  final compile = compileSources({
    sourceSvgName: '$iconDir/$sourceSvgName',
    if (hasSmall) smallSvgName: smallPath,
  });
  if (compile.failures.isNotEmpty) {
    return IconToolResult.failure(compile.failures);
  }
  final main = compile.compiled.firstWhere((s) => s.name == sourceSvgName);
  final small = hasSmall
      ? compile.compiled.firstWhere((s) => s.name == smallSvgName)
      : null;

  final rasters = <int, Uint8List>{};
  for (final size in icoRequiredSizes) {
    final source = (small != null && smallSizes.contains(size)) ? small : main;
    try {
      rasters[size] = await rasterizeChecked(rasterize, source, size);
    } on Object catch (e) {
      return IconToolResult.failure([
        '${source.name}: rendering at $size px failed ($e)',
      ]);
    }
  }

  final Uint8List ico;
  final String newRecord;
  try {
    ico = encodeIco(rasters);
    newRecord = renderSourceRecord(
      record,
      svg: main.svg,
      smallSvg: small?.svg,
      ico: ico,
    );
  } on Object catch (e) {
    return IconToolResult.failure(['$icoName: cannot encode ($e)']);
  }

  try {
    writeAtomically(icoPath, ico);
    writeAtomically(recordPath, utf8.encode(newRecord));
  } on FileSystemException catch (e) {
    return IconToolResult.failure([
      '${e.path ?? 'output'}: cannot write (${e.message}); rerun $iconBuildCommand',
    ]);
  }
  return IconToolResult.success(['wrote $icoPath and $recordPath']);
}

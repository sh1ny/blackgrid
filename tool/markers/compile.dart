/// Compiles a marker icon set's SVG files into the bundled vector files.
///
/// ```sh
/// mise exec -- dart run tool/markers/compile.dart [<manifest>]
/// ```
///
/// The manifest defaults to `assets/map_markers/manifest.json`. The command
/// first runs the set check and, on any failure, prints the failures, exits 1
/// and writes nothing. Otherwise it writes `compiled/<stem>.vec` beside the
/// manifest for each icon, compiled with the set check's settings, and deletes
/// every other file in `compiled/`. It also exits 1 and writes nothing when
/// `compiled/`, an ancestor or an output is a symbolic link or junction, so a
/// linked directory can never redirect the writes or the deletions. Exits 0 on
/// success and 2 on a usage error.
///
/// [compiledSetFailures] is the offline check that the compiled files are in
/// step with the SVG sources.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:blackgrid/application/output_path_guard.dart';

import 'icon_set.dart';

const _defaultManifest = 'assets/map_markers/manifest.json';
const _usage = 'usage: dart run tool/markers/compile.dart [<manifest>]';
const _compiledDirectory = 'compiled';

/// The compiled file name for [svgFile], such as `pmc_extracts.vec`.
String _compiledName(String svgFile) =>
    '${svgFile.substring(0, svgFile.length - '.svg'.length)}.vec';

Directory _compiledDir(IconSet set) => Directory(
  '${set.directory.path}${Platform.pathSeparator}$_compiledDirectory',
);

String _fileName(FileSystemEntity entity) =>
    entity.path.split(RegExp(r'[\\/]')).last;

/// Compares the compiled files beside [set] with a fresh compile of its SVGs.
///
/// Returns one `compiled` failure for each file that is stale (its bytes
/// differ from compiling the SVG), missing (an icon has no compiled file) or
/// unexpected (no icon owns it). The subject is the compiled file name. An
/// in-step set returns an empty list.
List<IconSetFailure> compiledSetFailures(
  IconSet set, {
  IconCompiler compile = compileIconSvg,
}) {
  final failures = <IconSetFailure>[];
  final directory = _compiledDir(set);
  final present = <String, File>{
    if (directory.existsSync())
      for (final file in directory.listSync().whereType<File>())
        _fileName(file): file,
  };
  final expected = <String>{};
  for (final icon in set.icons) {
    final name = _compiledName(icon.file);
    expected.add(name);
    final file = present[name];
    if (file == null) {
      failures.add(
        IconSetFailure(
          rule: 'compiled',
          subject: name,
          value: 'missing; ${icon.file} has no compiled file',
        ),
      );
    } else if (!_sameBytes(
      file.readAsBytesSync(),
      compile(icon.svg, icon.file),
    )) {
      failures.add(
        IconSetFailure(
          rule: 'compiled',
          subject: name,
          value: 'stale; it differs from compiling ${icon.file}',
        ),
      );
    }
  }
  for (final name in present.keys.where((n) => !expected.contains(n))) {
    failures.add(
      IconSetFailure(
        rule: 'compiled',
        subject: name,
        value: 'unexpected; no manifest icon compiles to it',
      ),
    );
  }
  return failures;
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Runs the compile for [args] and returns the process exit code.
///
/// Writes failures to [out] (default stdout) and usage errors to [err]
/// (default stderr).
int runCli(List<String> args, {StringSink? out, StringSink? err}) {
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;
  final manifest = switch (args) {
    [] => _defaultManifest,
    [final path] when !path.startsWith('-') => path,
    _ => null,
  };
  if (manifest == null) {
    stderrSink.writeln(_usage);
    return 2;
  }
  switch (checkIconSet(manifest)) {
    case IconSetInvalid(:final failures):
      failures.map(formatFailure).forEach(stdoutSink.writeln);
      stdoutSink.writeln('invalid: ${failures.length} failure(s)');
      return 1;
    case IconSetValid(:final set):
      final directory = _compiledDir(set);
      final targets = {
        for (final icon in set.icons)
          '${directory.path}${Platform.pathSeparator}${_compiledName(icon.file)}':
              icon,
      };
      final unsafe = targets.keys.map(unsafeOutputReason).nonNulls;
      if (unsafe.isNotEmpty) {
        stdoutSink.writeln('unsafe: ${unsafe.first}');
        return 1;
      }
      directory.createSync(recursive: true);
      for (final MapEntry(key: target, value: icon) in targets.entries) {
        writeBytesViaTemp(target, compileIconSvg(icon.svg, icon.file));
      }
      final names = targets.keys.map((t) => _fileName(File(t))).toSet();
      // Deleting a link removes only the link, never what it points at.
      for (final entity in directory.listSync(followLinks: false)) {
        if (names.contains(_fileName(entity))) continue;
        if (entity is File || entity is Link) entity.deleteSync();
      }
      stdoutSink.writeln('compiled: ${set.name} (${set.icons.length} icons)');
      return 0;
  }
}

void main(List<String> args) {
  exit(runCli(args));
}

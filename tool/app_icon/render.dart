// Shared pieces of the app icon tools: the raster provider interface, the
// result type, and the compile-before-render step both commands use (design
// D1, D3). Pure Dart (no `dart:ui`) so plain tests can drive it with a fake
// rasterizer; only `render_host_test.dart` supplies the real one.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:blackgrid/application/output_path_guard.dart';

import '../markers/icon_set.dart';

/// The largest source or candidate SVG, in bytes (design Resource Bounds).
const int maxSourceBytes = 64 * 1024;

/// Draws the compiled vector graphics [compiled] scaled to a square of [size]
/// pixels and returns `size * size * 4` bytes of straight (not premultiplied)
/// RGBA. [debugName] names the source for error messages.
typedef IconRasterizer = Future<Uint8List> Function(
  Uint8List compiled,
  int size,
  String debugName,
);

/// The outcome of an icon command: success, or failure with messages naming
/// the files at fault.
final class IconToolResult {
  /// A successful run with optional informational [messages].
  const IconToolResult.success([this.messages = const []]) : ok = true;

  /// A failed run; [messages] must name the file or field at fault.
  const IconToolResult.failure(this.messages) : ok = false;

  /// Whether the command completed and wrote its outputs.
  final bool ok;

  /// Lines for the developer, one problem or note per entry.
  final List<String> messages;

  /// The process exit code: 0 on success, 1 on failure.
  int get exitCode => ok ? 0 : 1;
}

/// An SVG source read from disk and compiled.
final class CompiledSource {
  /// Creates a compiled source.
  const CompiledSource(this.name, this.svg, this.compiled);

  /// Name used in messages: a file name or a candidates-relative path.
  final String name;

  /// The SVG file bytes as read (what the record hashes).
  final Uint8List svg;

  /// The vector graphics bytes the rasterizer draws.
  final Uint8List compiled;
}

/// Reads and compiles every file in [sources] (name to path) before anything
/// is rendered.
///
/// Returns the compiled sources in iteration order, or every failure found:
/// an unreadable file, a file over [maxSourceBytes], or a compile error. Each
/// failure names the file.
({List<CompiledSource> compiled, List<String> failures}) compileSources(
  Map<String, String> sources, {
  IconCompiler compile = compileIconSvg,
}) {
  final compiled = <CompiledSource>[];
  final failures = <String>[];
  for (final MapEntry(key: name, value: path) in sources.entries) {
    final Uint8List bytes;
    try {
      bytes = File(path).readAsBytesSync();
    } on FileSystemException catch (e) {
      failures.add('$name: cannot read ($path): ${e.message}');
      continue;
    }
    if (bytes.length > maxSourceBytes) {
      failures.add(
        '$name: ${bytes.length} bytes exceeds the $maxSourceBytes byte limit',
      );
      continue;
    }
    try {
      final xml = utf8.decode(bytes);
      compiled.add(CompiledSource(name, bytes, compile(xml, name)));
    } on FormatException catch (e) {
      failures.add('$name: not valid UTF-8 text (${e.message})');
    } on Object catch (e) {
      failures.add('$name: the SVG compiler rejected it ($e)');
    }
  }
  return (compiled: compiled, failures: failures);
}

/// Rasterizes [source] at [size] through [rasterize], checking the result is
/// exactly `size * size * 4` bytes.
///
/// Throws a [StateError] naming the source and size on a bad length. Errors
/// from [rasterize] itself pass through.
Future<Uint8List> rasterizeChecked(
  IconRasterizer rasterize,
  CompiledSource source,
  int size,
) async {
  final rgba = await rasterize(source.compiled, size, source.name);
  if (rgba.length != size * size * 4) {
    throw StateError(
      '${source.name}: the $size px raster is ${rgba.length} bytes, '
      'expected ${size * size * 4}',
    );
  }
  return rgba;
}

/// Writes [bytes] to [path] through a `.tmp` sibling and a rename, creating
/// the parent folder first.
void writeAtomically(String path, List<int> bytes) {
  Directory(File(path).parent.path).createSync(recursive: true);
  writeBytesViaTemp(path, bytes);
}

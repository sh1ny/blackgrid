/// Builds an M2 corpus from a scan-frame recording and the user's labels.
///
/// Usage: `build_corpus.dart RECORDING_DIR LABELS_FILE OUTPUT_DIR`. It maps
/// `frames.jsonl` to `corpus.json` as `docs/qualification/m2/CORPUS.md`
/// describes and copies the full-frame PNGs beside it. It reads and copies
/// files only; it never touches the app or a game.
library;

import 'dart:convert';
import 'dart:io';

const _usage = 'Usage: build_corpus.dart RECORDING_DIR LABELS_FILE OUTPUT_DIR';

/// A refusal: the build stops before its first write.
class _Refusal implements Exception {
  const _Refusal(this.message);
  final String message;
}

/// Builds the corpus and returns the process exit code: 0 on success, 2 for a
/// usage error and 1 for a refusal. Messages go to [out] and [err]. Every
/// check runs before the first write, so a refusal leaves [OUTPUT_DIR] as it
/// was.
int runBuildCorpus(
  List<String> arguments, {
  required StringSink out,
  required StringSink err,
}) {
  if (arguments.length != 3 || arguments.any((a) => a.startsWith('--'))) {
    err
      ..writeln(
        'Expected a recording folder, a labels file and an output '
        'folder.',
      )
      ..writeln(_usage);
    return 2;
  }
  final [recordingPath, labelsPath, outputPath] = arguments;
  try {
    final labels = _readLabels(labelsPath);
    final cases = _readCases(recordingPath);
    _checkLabelCoverage(cases, labels);
    _checkOutput(outputPath);

    final built = <Map<String, Object?>>[];
    final copies = <(File, String)>[];
    for (final line in cases) {
      final id = line['id'] as String;
      final image = line['image'];
      if (image == null) {
        throw _Refusal('$id has no whole-client image and cannot be a case');
      }
      if (line['clipped'] == true) {
        throw _Refusal('$id is a clipped frame and cannot be a case');
      }
      if (image is! String ||
          image.isEmpty ||
          image.contains('/') ||
          image.contains(r'\')) {
        throw _Refusal('$id has an invalid image name: $image');
      }
      final source = File('$recordingPath${Platform.pathSeparator}$image');
      if (!source.existsSync()) {
        throw _Refusal('$id image is missing: ${source.path}');
      }
      copies.add((source, image));
      built.add({
        'id': id,
        'image': image,
        'client': line['client'],
        'kind': line['kind'],
        if (line.containsKey('cursor') && line['cursor'] != null)
          'cursor': line['cursor'],
        'expected': labels[id],
      });
    }

    final directory = Directory(outputPath)..createSync(recursive: true);
    for (final (source, name) in copies) {
      source.copySync('${directory.path}${Platform.pathSeparator}$name');
    }
    File('${directory.path}${Platform.pathSeparator}corpus.json')
        .writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert({'cases': built})}\n',
        );
    out.writeln('Corpus written: $outputPath (${built.length} cases)');
    return 0;
  } on _Refusal catch (error) {
    err.writeln('Refused: ${error.message}');
    return 1;
  } on FileSystemException catch (error) {
    err.writeln('File error: ${error.message} ${error.path ?? ''}'.trimRight());
    return 1;
  }
}

/// Reads the labels file into an id to expected map, refusing anything but
/// confirmed labels with exactly one label per id.
Map<String, String> _readLabels(String path) {
  final file = File(path);
  if (!file.existsSync()) throw _Refusal('Cannot read labels file: $path');
  final Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException catch (error) {
    throw _Refusal('Labels file is not valid JSON: ${error.message}');
  }
  if (decoded is! Map<String, Object?>) {
    throw const _Refusal('Labels file must hold a JSON object');
  }
  final status = decoded['status'];
  if (status != 'confirmed') {
    throw _Refusal(
      'Labels are not confirmed: status is "$status", not '
      '"confirmed"',
    );
  }
  final cases = decoded['cases'];
  if (cases is! List) throw const _Refusal('Labels file has no "cases" list');
  final labels = <String, String>{};
  final duplicates = <String>{};
  for (final entry in cases) {
    final (id, expected) = switch (entry) {
      {'id': final String id, 'expected': final String expected}
          when id.isNotEmpty && expected.isNotEmpty =>
        (id, expected),
      _ => throw _Refusal('Malformed label entry: ${jsonEncode(entry)}'),
    };
    if (labels.containsKey(id)) duplicates.add(id);
    labels[id] = expected;
  }
  if (duplicates.isNotEmpty) {
    throw _Refusal('Duplicate label ids: ${duplicates.join(', ')}');
  }
  return labels;
}

/// Reads `frames.jsonl`, skipping an unparseable final line and refusing any
/// other unparseable line.
List<Map<String, Object?>> _readCases(String recordingPath) {
  final file = File('$recordingPath${Platform.pathSeparator}frames.jsonl');
  if (!file.existsSync()) {
    throw _Refusal('Cannot read recording: ${file.path}');
  }
  final lines = const LineSplitter()
      .convert(file.readAsStringSync())
      .where((line) => line.trim().isNotEmpty)
      .toList();
  final result = <Map<String, Object?>>[];
  final ids = <String>{};
  for (var i = 0; i < lines.length; i++) {
    final Object? decoded;
    try {
      decoded = jsonDecode(lines[i]);
    } on FormatException {
      if (i == lines.length - 1) continue;
      throw _Refusal('frames.jsonl line ${i + 1} is not valid JSON');
    }
    if (decoded is! Map<String, Object?> || decoded['id'] is! String) {
      throw _Refusal('frames.jsonl line ${i + 1} has no string id');
    }
    final id = decoded['id'] as String;
    if (!ids.add(id)) throw _Refusal('frames.jsonl repeats the id $id');
    result.add(decoded);
  }
  return result;
}

void _checkLabelCoverage(
  List<Map<String, Object?>> cases,
  Map<String, String> labels,
) {
  final recorded = {for (final line in cases) line['id'] as String};
  final unlabelled = recorded.difference(labels.keys.toSet());
  final unknown = labels.keys.toSet().difference(recorded);
  if (unlabelled.isNotEmpty) {
    throw _Refusal('Recorded lines without a label: ${unlabelled.join(', ')}');
  }
  if (unknown.isNotEmpty) {
    throw _Refusal(
      'Labels for ids not in the recording: ${unknown.join(', ')}',
    );
  }
}

void _checkOutput(String path) {
  final type = FileSystemEntity.typeSync(path);
  if (type == FileSystemEntityType.notFound) return;
  if (type != FileSystemEntityType.directory) {
    throw _Refusal('Output path is not a folder: $path');
  }
  if (Directory(path).listSync().isNotEmpty) {
    throw _Refusal('Output folder is not empty: $path');
  }
}

void main(List<String> arguments) {
  exitCode = runBuildCorpus(arguments, out: stdout, err: stderr);
}

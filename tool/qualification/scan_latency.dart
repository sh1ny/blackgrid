/// Offline scan latency report over the app's timing log files.
///
/// Usage: `scan_latency.dart [--since UTC] [--until UTC] [--out FILE]
/// [--force] LOG...`. It reads files only; it never touches the app or a game.
library;

import 'dart:convert';
import 'dart:io';

import 'scan_latency_report.dart';

const _usage =
    'Usage: scan_latency.dart [--since UTC] [--until UTC] [--out FILE] '
    '[--force] LOG_FILE...';

class _UsageError implements Exception {
  const _UsageError(this.message);
  final String message;
}

/// Runs the report and returns the process exit code: 0 on success, 2 for a
/// usage error and 1 for a file error. Messages go to [out] and [err].
Future<int> runScanLatency(
  List<String> arguments, {
  required StringSink out,
  required StringSink err,
}) async {
  try {
    DateTime? since;
    DateTime? until;
    String? outputPath;
    var force = false;
    final files = <String>[];
    DateTime bound(String option, String? value) {
      final parsed = value == null ? null : DateTime.tryParse(value);
      // Without Z or an offset, DateTime.parse reads local time.
      if (parsed == null || !parsed.isUtc) {
        throw _UsageError(
          '$option needs a UTC timestamp with Z or an offset, got "$value"',
        );
      }
      return parsed;
    }

    for (var i = 0; i < arguments.length; i++) {
      final argument = arguments[i];
      String? next() => i + 1 < arguments.length ? arguments[++i] : null;
      switch (argument) {
        case '--since':
          since = bound(argument, next());
        case '--until':
          until = bound(argument, next());
        case '--out':
          outputPath =
              next() ?? (throw const _UsageError('--out needs a file path'));
        case '--force':
          force = true;
        case _ when argument.startsWith('--'):
          throw _UsageError('Unknown option: $argument');
        default:
          files.add(argument);
      }
    }
    if (files.isEmpty) throw const _UsageError('No log files given');

    if (outputPath != null &&
        !force &&
        FileSystemEntity.typeSync(outputPath) !=
            FileSystemEntityType.notFound) {
      err.writeln('Output exists, use --force to overwrite: $outputPath');
      return 1;
    }
    for (final path in files) {
      if (!File(path).existsSync()) {
        err.writeln('Cannot read log file: $path');
        return 1;
      }
    }
    // --force must never replace a log the report reads. Only an existing
    // output can be one of them.
    if (outputPath != null && File(outputPath).existsSync()) {
      final target = File(outputPath).resolveSymbolicLinksSync();
      for (final path in files) {
        if (File(path).resolveSymbolicLinksSync() == target) {
          err.writeln('Output would overwrite a log file: $outputPath');
          return 1;
        }
      }
    }

    final accumulator = LatencyAccumulator(
      since: since,
      until: until,
      files: files,
    );
    for (final path in files) {
      try {
        final lines = File(path)
            .openRead()
            .transform(const Utf8Decoder(allowMalformed: true))
            .transform(const LineSplitter());
        await for (final line in lines) {
          accumulator.addLine(line);
        }
      } on FileSystemException catch (error) {
        err.writeln('Cannot read log file: $path (${error.message})');
        return 1;
      }
    }
    final report = accumulator.build();
    if (outputPath != null) {
      try {
        await File(outputPath).writeAsString(
          '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
        );
      } on FileSystemException catch (error) {
        err.writeln('Cannot write report: $outputPath (${error.message})');
        return 1;
      }
    }
    out.write(report.toTable());
    if (outputPath != null) out.writeln('Report written: $outputPath');
    return 0;
  } on _UsageError catch (error) {
    err
      ..writeln(error.message)
      ..writeln(_usage);
    return 2;
  }
}

Future<void> main(List<String> arguments) async {
  exitCode = await runScanLatency(arguments, out: stdout, err: stderr);
}

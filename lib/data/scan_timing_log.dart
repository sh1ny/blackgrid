import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Whether the timing log can currently be written.
sealed class ScanTimingStatus {
  const ScanTimingStatus();
}

/// The last write succeeded, or none has been tried yet.
final class ScanTimingAvailable extends ScanTimingStatus {
  /// Creates the available status.
  const ScanTimingAvailable();
}

/// The last write failed with [error]. Later appends keep trying.
final class ScanTimingUnavailable extends ScanTimingStatus {
  /// Creates an unavailable status carrying the failure.
  const ScanTimingUnavailable(this.error);

  /// The error from the failed open, write or rotation.
  final Object error;
}

/// The file operations [ScanTimingLog] needs, so tests can hold or fail them.
abstract interface class ScanTimingFileSink {
  /// Current size in bytes of the live log file, or 0 when it does not exist.
  Future<int> length();

  /// Opens the live log file for append, writes [bytes] and closes it.
  Future<void> append(List<int> bytes);

  /// Renames the live log file to the previous-log name, replacing any
  /// earlier previous log.
  Future<void> rotate();
}

/// [ScanTimingFileSink] over `scan-timings.jsonl` in a directory.
final class DirectoryScanTimingSink implements ScanTimingFileSink {
  /// Creates a sink writing into [directory].
  DirectoryScanTimingSink(Directory directory)
    : _directory = directory,
      _current = File('${directory.path}/${ScanTimingLog.fileName}'),
      _previous = File('${directory.path}/${ScanTimingLog.previousFileName}');

  final Directory _directory;
  final File _current;
  final File _previous;

  @override
  Future<int> length() async =>
      await _current.exists() ? await _current.length() : 0;

  @override
  Future<void> append(List<int> bytes) async {
    await _directory.create(recursive: true);
    final handle = await _current.open(mode: FileMode.append);
    try {
      await handle.writeFrom(bytes);
    } finally {
      await handle.close();
    }
  }

  @override
  Future<void> rotate() async {
    if (await _previous.exists()) await _previous.delete();
    await _current.rename(_previous.path);
  }
}

/// Bounded, non-blocking JSON Lines log of scan timings.
///
/// [append] never waits for the disk. One async loop writes lines one at a
/// time in append order. At most [maxQueued] lines wait; further lines are
/// dropped and counted, and the next written line carries `droppedLines`.
/// Before a write would grow the file past [maxBytes], the file is renamed to
/// `scan-timings.1.jsonl`, replacing any earlier one.
class ScanTimingLog {
  /// Creates a log in [logs]. [sink] replaces the real file for tests.
  ScanTimingLog(
    Directory logs, {
    this.maxBytes = defaultMaxBytes,
    this.maxQueued = defaultMaxQueued,
    this.closeTimeout = const Duration(seconds: 1),
    ScanTimingFileSink? sink,
  }) : _sink = sink ?? DirectoryScanTimingSink(logs);

  /// Name of the live log file.
  static const String fileName = 'scan-timings.jsonl';

  /// Name of the previous log file.
  static const String previousFileName = 'scan-timings.1.jsonl';

  /// Default size bound of the live file: 1 MiB.
  static const int defaultMaxBytes = 1024 * 1024;

  /// Default number of lines allowed to wait.
  static const int defaultMaxQueued = 32;

  /// Size the live file may not grow past.
  final int maxBytes;

  /// Number of lines that may wait behind the one being written.
  final int maxQueued;

  /// How long [close] waits for queued lines.
  final Duration closeTimeout;

  final ScanTimingFileSink _sink;
  final Queue<Map<String, Object?>> _queue = Queue<Map<String, Object?>>();
  final ValueNotifier<ScanTimingStatus> _status =
      ValueNotifier<ScanTimingStatus>(const ScanTimingAvailable());

  int _dropped = 0;
  bool _closed = false;
  bool _discard = false;
  Future<void>? _loop;

  /// Whether the last write worked. Notifies when it changes.
  ValueListenable<ScanTimingStatus> get status => _status;

  /// Completes when the write loop has nothing left to do.
  @visibleForTesting
  Future<void> get idle => _loop ?? Future<void>.value();

  /// Queues [entry] as one line. Drops and counts it when the queue is full;
  /// ignores it after [close].
  void append(Map<String, Object?> entry) {
    if (_closed) return;
    if (_queue.length >= maxQueued) {
      _dropped++;
      return;
    }
    _queue.add(Map<String, Object?>.of(entry));
    _loop ??= _run();
  }

  /// Writes what is queued within [closeTimeout], drops the rest, and ignores
  /// later appends.
  Future<void> close() async {
    _closed = true;
    final loop = _loop;
    if (loop != null) {
      try {
        await loop.timeout(closeTimeout);
      } on TimeoutException {
        // Fall through and drop what is left.
      }
    }
    _discard = true;
    _queue.clear();
  }

  Future<void> _run() async {
    try {
      while (_queue.isNotEmpty && !_discard) {
        final entry = _queue.removeFirst();
        final carried = _dropped;
        final line = carried == 0 ? entry : {...entry, 'droppedLines': carried};
        try {
          await _write(utf8.encode('${jsonEncode(line)}\n'));
          _dropped -= carried;
          _setStatus(const ScanTimingAvailable());
        } on Object catch (error) {
          _setStatus(ScanTimingUnavailable(error));
        }
      }
    } finally {
      _loop = null;
    }
  }

  Future<void> _write(List<int> bytes) async {
    final length = await _sink.length();
    if (length > 0 && length + bytes.length > maxBytes) {
      await _sink.rotate();
    }
    await _sink.append(bytes);
  }

  // The const available status is canonical, so ValueNotifier skips repeats.
  void _setStatus(ScanTimingStatus next) => _status.value = next;
}

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../domain/map_session.dart';

class SavedScreenshot {
  const SavedScreenshot({
    required this.path,
    required this.modifiedAt,
    required this.bytes,
    required this.contentId,
  });
  final String path;
  final DateTime modifiedAt;
  final Uint8List bytes;
  final String contentId;
}

/// Watch and explicit reads share the same stable-file reader and ordering.
/// Initial files form a baseline, not evidence of a current raid.
class ScreenshotDirectoryWatcher {
  ScreenshotDirectoryWatcher({
    this.stabilityDelay = const Duration(milliseconds: 80),
    this.pollInterval = const Duration(seconds: 1),
    this.maxBytes = 64 * 1024 * 1024,
  });
  final Duration stabilityDelay;
  final Duration pollInterval;
  final int maxBytes;
  final _screenshots = StreamController<SavedScreenshot>.broadcast(sync: true);
  final _statuses = StreamController<(MapInputStatus, String?)>.broadcast(
    sync: true,
  );
  Stream<SavedScreenshot> get screenshots => _screenshots.stream;
  Stream<(MapInputStatus, String?)> get statuses => _statuses.stream;
  String _directory = '';
  int _generation = 0;
  bool _closed = false;
  MapInputStatus _lastStatus = MapInputStatus.disabled;
  String? _lastMessage;
  Timer? _timer;
  StreamSubscription<FileSystemEvent>? _watch;
  Future<void>? _active;
  Future<void>? _closing;
  bool _pending = false;
  final Map<String, String> _seen = {};
  final Set<String> _knownContentIds = {};
  final Map<String, (int, DateTime, DateTime)> _fileStamps = {};
  final Set<String> _dirty = {};
  (DateTime, String)? _watermark;
  final Set<Future<SavedScreenshot?>> _reads = {};
  final Set<Future<void>> _bindings = {};

  Future<void> bind(String directory) {
    late Future<void> operation;
    operation = _bind(directory)
        .whenComplete(() => _bindings.remove(operation));
    _bindings.add(operation);
    return operation;
  }

  Future<void> _bind(String directory) async {
    final generation = ++_generation;
    _timer?.cancel();
    await _watch?.cancel();
    if (_closed || generation != _generation) return;
    _watch = null;
    _directory = directory;
    _seen.clear();
    _knownContentIds.clear();
    _fileStamps.clear();
    _dirty.clear();
    _watermark = null;
    if (_closed) return;
    if (directory.isEmpty) {
      _status(MapInputStatus.disabled, 'No screenshot directory configured.');
      return;
    }
    // Replay is intentionally excluded from watched raid evidence. Existing
    // files are only stamped: reading and hashing a full screenshot folder
    // would delay watching by minutes.
    final files = await _list(generation);
    for (final file in files) {
      try {
        final stat = await file.stat();
        if (generation != _generation || _closed) return;
        _fileStamps[file.path] = (stat.size, stat.modified, stat.changed);
        _watermark = (stat.modified, file.path);
      } on FileSystemException {
        // A file removed during the baseline is simply not part of it.
      }
    }
    if (generation != _generation || _closed) return;
    try {
      _watch = Directory(directory).watch().listen(
        (event) {
          _dirty.add(event.path);
          if (event is FileSystemMoveEvent && event.destination != null) {
            _dirty.add(event.destination!);
          }
          _schedule();
        },
        onError: (Object error) {
          _status(MapInputStatus.error, 'Screenshot watcher failed: $error');
          _schedule();
        },
      );
    } on FileSystemException {
      // Polling keeps configured missing directories recoverable.
    }
    _timer = Timer.periodic(pollInterval, (_) => _schedule());
  }

  void _status(MapInputStatus status, String? message) {
    // Polls repeat their status; re-emitting it would erase the session's
    // reading/assumed-association messages every interval.
    if (status == _lastStatus && message == _lastMessage) return;
    _lastStatus = status;
    _lastMessage = message;
    if (!_closed) _statuses.add((status, message));
  }

  Future<List<File>> _list(int generation) async {
    if (_directory.isEmpty) return [];
    try {
      final directory = Directory(_directory);
      if (!await directory.exists()) {
        if (generation == _generation) {
          _status(MapInputStatus.missing, 'Screenshot directory is missing.');
        }
        return [];
      }
      final entries = await directory
          .list(followLinks: false)
          .where(
            (e) =>
                e is File &&
                RegExp(
                  r'\.(png|jpe?g)$',
                  caseSensitive: false,
                ).hasMatch(e.path),
          )
          .cast<File>()
          .toList();
      final stamps = <String, DateTime>{};
      for (final file in entries) {
        stamps[file.path] = (await file.stat()).modified;
      }
      entries.sort((a, b) {
        final order = stamps[a.path]!.compareTo(stamps[b.path]!);
        return order == 0 ? a.path.compareTo(b.path) : order;
      });
      if (generation == _generation) {
        _status(
          entries.isEmpty ? MapInputStatus.empty : MapInputStatus.watching,
          entries.isEmpty ? 'No saved screenshots found.' : null,
        );
      }
      return entries;
    } on FileSystemException catch (error) {
      if (generation == _generation) {
        _status(
          MapInputStatus.error,
          'Screenshot input is inaccessible: $error',
        );
      }
      return [];
    }
  }

  Future<SavedScreenshot?> _stableRead(File file, int generation) async {
    try {
      final before = await file.stat();
      if (before.type != FileSystemEntityType.file || before.size == 0) {
        return null;
      }
      if (before.size > maxBytes) {
        _status(
          MapInputStatus.error,
          'Saved screenshot exceeds the supported input size.',
        );
        return null;
      }
      await Future<void>.delayed(stabilityDelay);
      if (_closed || generation != _generation) return null;
      final middle = await file.stat();
      if (before.size != middle.size || before.modified != middle.modified) {
        return null;
      }
      final bytes = await file.readAsBytes();
      final after = await file.stat();
      if (_closed ||
          generation != _generation ||
          bytes.length != after.size ||
          middle.size != after.size ||
          middle.modified != after.modified) {
        return null;
      }
      _fileStamps[file.path] = (after.size, after.modified, after.changed);
      return SavedScreenshot(
        path: file.path,
        modifiedAt: after.modified,
        bytes: bytes,
        contentId: sha256.convert(bytes).toString(),
      );
    } on FileSystemException catch (error) {
      if (generation == _generation) {
        _status(
          MapInputStatus.error,
          'Saved screenshot could not be read: $error',
        );
      }
      return null;
    }
  }

  void _schedule() {
    if (_closed || _directory.isEmpty) return;
    if (_active != null) {
      _pending = true;
      return;
    }
    _active = _scan().whenComplete(() {
      _active = null;
      if (_pending && !_closed) {
        _pending = false;
        _schedule();
      }
    });
  }

  /// Explicit deterministic rescan also makes filesystem race tests timer-free.
  Future<void> rescan() async {
    _schedule();
    while (_active != null) {
      await _active;
    }
  }

  Future<void> _scan() async {
    final generation = _generation;
    try {
      final files = await _list(generation);
      // Only the newest stable changed file enters the bounded processing queue.
      SavedScreenshot? newest;
      for (final file in files) {
        final stat = await file.stat();
        final dirty = _dirty.remove(file.path);
        if (!dirty &&
            _fileStamps[file.path] ==
                (stat.size, stat.modified, stat.changed)) {
          continue;
        }
        final saved = await _stableRead(file, generation);
        if (_closed || generation != _generation) return;
        if (saved == null || _seen[file.path] == saved.contentId) continue;
        final duplicate = !_knownContentIds.add(saved.contentId);
        _seen[file.path] = saved.contentId;
        if (!duplicate && _eligibleOrder(saved)) newest = saved;
      }
      final paths = files.map((file) => file.path).toSet();
      _seen.removeWhere((path, _) => !paths.contains(path));
      _fileStamps.removeWhere((path, _) => !paths.contains(path));
      if (newest != null && !_closed && generation == _generation) {
        _watermark = (newest.modifiedAt, newest.path);
        _screenshots.add(newest);
      }
    } on FileSystemException catch (error) {
      if (!_closed && generation == _generation) {
        _status(
          MapInputStatus.error,
          'Screenshot input changed while scanning: $error',
        );
      }
    }
  }

  bool _eligibleOrder(SavedScreenshot saved) {
    final watermark = _watermark;
    if (watermark == null) return true;
    final time = saved.modifiedAt.compareTo(watermark.$1);
    return time > 0 || (time == 0 && saved.path.compareTo(watermark.$2) >= 0);
  }

  Future<SavedScreenshot?> readLatest() {
    if (_closed) return Future.value(null);
    late Future<SavedScreenshot?> operation;
    operation = _readLatest().whenComplete(() => _reads.remove(operation));
    _reads.add(operation);
    return operation;
  }

  Future<SavedScreenshot?> _readLatest() async {
    final generation = _generation;
    final files = await _list(generation);
    if (files.isEmpty) return null;
    final saved = await _stableRead(files.last, generation);
    if (saved != null && generation == _generation && !_closed) {
      _seen[saved.path] = saved.contentId;
      _knownContentIds.add(saved.contentId);
      if (_eligibleOrder(saved)) _watermark = (saved.modifiedAt, saved.path);
    }
    if (saved == null &&
        generation == _generation &&
        !_closed &&
        _lastStatus != MapInputStatus.error) {
      _status(
        MapInputStatus.unavailable,
        'Latest screenshot is still being written or unavailable.',
      );
    }
    return saved;
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    ++_generation;
    _timer?.cancel();
    await _watch?.cancel();
    await _active;
    await Future.wait(_reads.toList());
    await Future.wait(_bindings.toList());
    await _screenshots.close();
    await _statuses.close();
  }
}

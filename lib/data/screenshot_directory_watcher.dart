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

/// What an explicit read of the newest saved screenshot found.
sealed class ScreenshotRead {
  const ScreenshotRead();
}

/// The newest screenshot was read stably.
final class ScreenshotFound extends ScreenshotRead {
  const ScreenshotFound(this.screenshot);

  /// The stable bytes and metadata of the newest screenshot.
  final SavedScreenshot screenshot;
}

/// The folder exists and holds no png or jpeg.
final class ScreenshotEmpty extends ScreenshotRead {
  const ScreenshotEmpty();
}

/// No screenshot could be read: no folder is bound, the folder is missing or
/// inaccessible, or the newest file is unreadable, oversized or still changing.
final class ScreenshotUnavailable extends ScreenshotRead {
  const ScreenshotUnavailable();
}

/// The watcher closed or moved to another folder before the read finished.
final class ScreenshotDiscarded extends ScreenshotRead {
  const ScreenshotDiscarded();
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
  final Set<Future<ScreenshotRead>> _reads = {};
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
    final (files, _) = await _list(generation);
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

  /// Lists the folder's screenshots, oldest first, and how listing went.
  Future<(List<File>, _Listing)> _list(int generation) async {
    if (_directory.isEmpty) return (const <File>[], _Listing.unbound);
    try {
      final directory = Directory(_directory);
      if (!await directory.exists()) {
        if (generation == _generation) {
          _status(MapInputStatus.missing, 'Screenshot directory is missing.');
        }
        return (const <File>[], _Listing.missing);
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
      return (entries, _Listing.listed);
    } on FileSystemException catch (error) {
      if (generation == _generation) {
        _status(
          MapInputStatus.error,
          'Screenshot input is inaccessible: $error',
        );
      }
      return (const <File>[], _Listing.inaccessible);
    }
  }

  Future<ScreenshotRead> _stableRead(File file, int generation) async {
    try {
      final before = await file.stat();
      if (before.type != FileSystemEntityType.file || before.size == 0) {
        return const ScreenshotUnavailable();
      }
      if (before.size > maxBytes) {
        _status(
          MapInputStatus.error,
          'Saved screenshot exceeds the supported input size.',
        );
        return const ScreenshotUnavailable();
      }
      await Future<void>.delayed(stabilityDelay);
      if (_closed || generation != _generation) {
        return const ScreenshotDiscarded();
      }
      final middle = await file.stat();
      if (before.size != middle.size || before.modified != middle.modified) {
        return const ScreenshotUnavailable();
      }
      final bytes = await file.readAsBytes();
      final after = await file.stat();
      // Closed or moved comes first: a mismatch of a discarded read is not
      // evidence that the file was still changing.
      if (_closed || generation != _generation) {
        return const ScreenshotDiscarded();
      }
      if (bytes.length != after.size ||
          middle.size != after.size ||
          middle.modified != after.modified) {
        return const ScreenshotUnavailable();
      }
      _fileStamps[file.path] = (after.size, after.modified, after.changed);
      return ScreenshotFound(
        SavedScreenshot(
          path: file.path,
          modifiedAt: after.modified,
          bytes: bytes,
          contentId: sha256.convert(bytes).toString(),
        ),
      );
    } on FileSystemException catch (error) {
      if (generation == _generation) {
        _status(
          MapInputStatus.error,
          'Saved screenshot could not be read: $error',
        );
      }
      return const ScreenshotUnavailable();
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
      final (files, _) = await _list(generation);
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
        final read = await _stableRead(file, generation);
        if (_closed || generation != _generation) return;
        final saved = read is ScreenshotFound ? read.screenshot : null;
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

  /// Reads the newest saved screenshot and reports why none was read.
  Future<ScreenshotRead> readLatest() {
    if (_closed) return Future.value(const ScreenshotDiscarded());
    late Future<ScreenshotRead> operation;
    operation = _readLatest().whenComplete(() => _reads.remove(operation));
    _reads.add(operation);
    return operation;
  }

  Future<ScreenshotRead> _readLatest() async {
    final generation = _generation;
    final (files, listing) = await _list(generation);
    // Closed and moved come first: a discarded read says nothing about the folder.
    if (_closed || generation != _generation) {
      return const ScreenshotDiscarded();
    }
    switch (listing) {
      case _Listing.unbound || _Listing.missing || _Listing.inaccessible:
        return const ScreenshotUnavailable();
      case _Listing.listed:
        if (files.isEmpty) return const ScreenshotEmpty();
    }
    final read = await _stableRead(files.last, generation);
    switch (read) {
      case ScreenshotFound(:final screenshot):
        if (generation == _generation && !_closed) {
          _seen[screenshot.path] = screenshot.contentId;
          _knownContentIds.add(screenshot.contentId);
          if (_eligibleOrder(screenshot)) {
            _watermark = (screenshot.modifiedAt, screenshot.path);
          }
        }
      case ScreenshotUnavailable():
        if (generation == _generation &&
            !_closed &&
            _lastStatus != MapInputStatus.error) {
          _status(
            MapInputStatus.unavailable,
            'Latest screenshot is still being written or unavailable.',
          );
        }
      case ScreenshotEmpty() || ScreenshotDiscarded():
        break;
    }
    return read;
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

/// How listing the screenshot folder went.
enum _Listing { listed, unbound, missing, inaccessible }

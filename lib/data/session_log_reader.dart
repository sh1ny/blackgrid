import 'dart:async';
import 'dart:io';

import '../domain/catalog.dart';
import '../domain/map_session.dart';
import '../domain/raid_lifecycle.dart';
import 'game_log/game_locations.dart';
import 'game_log/game_log_parsers.dart';
import 'game_log/log_file_tail.dart';
import 'game_log/session_folders.dart';

/// An ordered event batch and the application/backend records proven live.
typedef SessionLogBatch = ({
  List<GameLogEvent> events,
  Set<LogRecordId> liveIds,
});

/// Configured-root-only replay and tail of the three raid-lifecycle logs.
///
/// Each scan snapshots push first and application last, reads to those sizes,
/// and emits events sorted by log time, file (application, backend, push), then
/// byte offset. Push consumption waits for complete application consumption;
/// recovered push records may arrive in a later scan than their mode evidence.
///
/// [states] describes the application log alone: status, incarnation, map and
/// mode never depend on the backend or push files. Problems with those two go
/// to [SessionLogState.raidLogsMessage]. Record identity is folder name, file
/// and byte offset, not timestamps. UTF-8 is decoded only after a full line
/// arrives.
class SessionLogReader {
  /// Creates a reader; call [bind] to start it.
  ///
  /// [pollInterval] is how often the folder is rescanned, [chunkBytes] the
  /// largest single file read, and [maxLineBytes] the longest accepted line.
  SessionLogReader({
    this.pollInterval = const Duration(milliseconds: 250),
    this.chunkBytes = 8192,
    this.maxLineBytes = 65536,
    this.snapshotStat,
  });

  /// How often the session folder is rescanned.
  final Duration pollInterval;

  /// Largest single read from a log file, in bytes.
  final int chunkBytes;

  /// Longest accepted log line, in bytes.
  final int maxLineBytes;

  /// Optional size-snapshot filesystem seam for deterministic offline tests.
  final Future<FileStat> Function(File file)? snapshotStat;
  final _states = StreamController<SessionLogState>.broadcast(sync: true);
  final _events = StreamController<SessionLogBatch>.broadcast(sync: true);
  late final _plainEvents = _events.stream.map((batch) => batch.events);

  /// The application-log state; see the class comment for what it excludes.
  Stream<SessionLogState> get states => _states.stream;

  /// One batch per scan that produced events, in lifecycle order.
  ///
  /// Control events ([LogInputReset], [SessionFolderChanged]) come first in
  /// their batch, followed by the sorted record events. A scan with nothing to
  /// report emits no batch.
  Stream<List<GameLogEvent>> get events => _plainEvents;

  /// The same ordered batches as [events], with byte provenance.
  Stream<SessionLogBatch> get eventBatches => _events.stream;
  SessionLogState _state = const SessionLogState();

  /// The latest published state.
  SessionLogState get state => _state;
  String _root = '';

  /// The log directory currently bound to this reader.
  String get root => _root;
  String? _path;
  String? _session;
  int _generation = 0;
  int _incarnation = 0;
  late final Map<LogFile, LogFileTail> _tails = {
    // The application tail also frames headerless lines: the map and mode
    // detection below accepts them. Only header records become events.
    LogFile.application: LogFileTail(
      kind: LogFile.application,
      headersOnly: false,
      chunkBytes: chunkBytes,
      maxLineBytes: maxLineBytes,
    ),
    LogFile.backend: LogFileTail(
      kind: LogFile.backend,
      chunkBytes: chunkBytes,
      maxLineBytes: maxLineBytes,
    ),
    LogFile.pushNotifications: LogFileTail(
      kind: LogFile.pushNotifications,
      chunkBytes: chunkBytes,
      maxLineBytes: maxLineBytes,
    ),
  };
  LogFileTail get _tail => _tails[LogFile.application]!;
  final _problems = <LogFile, String>{};

  /// Raid logs whose last read failed; cleared by the next read that opens
  /// the file, so a transient failure never outlives a clean retry and never
  /// replaces a rejection still in [_problems].
  final _unreadable = <LogFile>{};
  final _pendingControl = <GameLogEvent>[];
  bool _needReset = false;
  String? _newestObservedSession;
  bool _rootListed = false;
  String? _provenanceSession;
  bool _sessionStartsLive = false;
  bool _applicationNeedsBaseline = false;
  final _boundaries = <LogFile, _LiveBoundary>{};
  String? _backendReadPath;

  /// Whether a different newest session folder has no application log yet.
  bool _folderAwaitsApplicationLog = false;
  bool _batch = false;
  bool _recordRejected = false;
  SessionLogState? _lastPublished;
  bool _closed = false;
  bool _pending = false;
  Timer? _timer;
  StreamSubscription<FileSystemEvent>? _watch;
  Future<void>? _active;
  Future<void>? _closing;

  /// Starts reading the session folders under [root].
  ///
  /// The first batch starts with [LogInputReset], because the input position
  /// is discarded. An empty [root] disables the reader.
  Future<void> bind(String root) async {
    final generation = ++_generation;
    _timer?.cancel();
    await _watch?.cancel();
    if (_closed || generation != _generation) return;
    _watch = null;
    _root = root;
    _reset(null, null);
    _newestObservedSession = null;
    _rootListed = false;
    _forgetSelection();
    _pendingControl.clear();
    _needReset = true;
    if (_closed) return;
    if (root.isEmpty) {
      _publish(
        MapInputStatus.disabled,
        message: 'No game log directory configured.',
      );
      _needReset = false;
      _events.add((events: const [LogInputReset()], liveIds: const {}));
      return;
    }
    await rescan();
    if (_closed || generation != _generation) return;
    try {
      _watch = Directory(root)
          .watch(recursive: true)
          .listen(
            (_) => _schedule(),
            onError: (Object error) {
              _publish(
                MapInputStatus.error,
                message: 'Log watcher failed: $error',
              );
              _schedule();
            },
          );
    } on FileSystemException {
      // The timer rebinds a configured folder that appears later.
    }
    _timer = Timer.periodic(pollInterval, (_) => _schedule());
  }

  void _reset(String? path, String? session) {
    _path = path;
    _session = session;
    ++_incarnation;
    for (final tail in _tails.values) {
      tail.reset();
    }
    _backendReadPath = null;
    _problems.clear();
    _unreadable.clear();
    _recordRejected = false;
    _state = SessionLogState(sessionId: session, incarnation: _incarnation);
  }

  void _publish(
    MapInputStatus status, {
    String? map,
    GameMode? mode,
    String? message,
    bool clearMap = false,
  }) {
    if (_closed) return;
    final next = SessionLogState(
      status: status,
      sessionId: _session,
      incarnation: _incarnation,
      detectedMapId: clearMap ? null : map ?? _state.detectedMapId,
      detectedMode: mode ?? _state.detectedMode,
      message: message,
      raidLogsMessage: _state.raidLogsMessage,
    );
    if (_same(next, _state)) return;
    _state = next;
    if (!_batch) _emit();
  }

  /// Updates the raid-log message without publishing; the scan's final
  /// [_emit] carries it.
  void _setRaidLogsMessage(String? message) {
    if (_closed || _state.raidLogsMessage == message) return;
    _state = SessionLogState(
      status: _state.status,
      sessionId: _state.sessionId,
      incarnation: _state.incarnation,
      detectedMapId: _state.detectedMapId,
      detectedMode: _state.detectedMode,
      message: _state.message,
      raidLogsMessage: message,
    );
  }

  static bool _same(SessionLogState a, SessionLogState b) =>
      a.status == b.status &&
      a.sessionId == b.sessionId &&
      a.incarnation == b.incarnation &&
      a.detectedMapId == b.detectedMapId &&
      a.detectedMode == b.detectedMode &&
      a.message == b.message &&
      a.raidLogsMessage == b.raidLogsMessage;

  void _emit() {
    final old = _lastPublished;
    final next = _state;
    if (_closed || (old != null && _same(old, next))) return;
    _lastPublished = next;
    _states.add(next);
  }

  void _schedule() {
    if (_closed || _root.isEmpty) return;
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

  /// Runs scans until none is active or queued, then returns.
  Future<void> rescan() async {
    _schedule();
    while (_active != null) {
      await _active;
    }
  }

  void _forgetSelection() {
    _provenanceSession = null;
    _sessionStartsLive = false;
    _applicationNeedsBaseline = false;
    _boundaries.clear();
  }

  // This tracks file selection independently of the reduction's input reset:
  // a rewrite may schedule a second scan to replay the same selected files.
  void _observeRole(LogFile kind, File? file) {
    if (kind == LogFile.application && _applicationNeedsBaseline) {
      if (file == null) return;
      _applicationNeedsBaseline = false;
      _boundaries[kind] = (path: file.path, offset: null);
      return;
    }
    final previous = _boundaries[kind];
    final path = file?.path;
    if (previous != null && previous.path == path) return;
    final startsLive = previous == null
        ? _sessionStartsLive
        : previous.path == null;
    _boundaries[kind] = (path: path, offset: startsLive ? 0 : null);
  }

  void _setBoundary(LogFile kind, int? size) {
    final path = _boundaries[kind]?.path;
    if (path != null) _boundaries[kind] = (path: path, offset: size);
  }

  void _baselineSnapshot(Map<LogFile, FileStat> snapshots) {
    _setBoundary(LogFile.application, snapshots[LogFile.application]?.size);
    _setBoundary(LogFile.backend, snapshots[LogFile.backend]?.size);
  }

  Future<FileStat> _snapshot(
    File file,
    LogFile kind,
    bool Function() cancelled,
  ) async {
    final stat = await (snapshotStat?.call(file) ?? file.stat());
    // Retain each known size even if a later stat or read fails.
    if (!cancelled() &&
        stat.type == FileSystemEntityType.file &&
        _boundaries[kind]?.offset == null) {
      _setBoundary(kind, stat.size);
    }
    return stat;
  }

  Future<_Selection?> _select(bool Function() cancelled) async {
    _folderAwaitsApplicationLog = false;
    var listed = false;
    final sessions = await listSessionFolders(
      _root,
      onListed: () => listed = true,
    );
    if (cancelled()) return null;
    if (sessions.isEmpty) {
      _forgetSelection();
      if (listed) _rootListed = true;
      return null;
    }
    final session = sessions.last;
    final newest = _newestObservedSession;
    final newer =
        newest == null || compareSessionFolderNames(session.name, newest) > 0;
    if (session.path != _provenanceSession) {
      _forgetSelection();
      _provenanceSession = session.path;
      _sessionStartsLive = _rootListed && newer;
    }
    if (newer) _newestObservedSession = session.name;
    _rootListed = true;
    final files = await selectSessionLogFiles(
      Directory(session.path),
      LogFile.values,
    );
    if (cancelled()) return null;
    final application = files[LogFile.application];
    final backend = files[LogFile.backend];
    if (application == null && _path != null && session.path == _session) {
      // Losing the bound application role resets the input. Its return is a
      // replay, not the first appearance of a previously absent file.
      _applicationNeedsBaseline = true;
      _sessionStartsLive = false;
      _boundaries.clear();
    }
    _observeRole(LogFile.application, application);
    _observeRole(LogFile.backend, backend);
    if (application == null) {
      _folderAwaitsApplicationLog = session.path != _session;
      // An existing backend may already contain bytes even though the
      // application role cannot publish records yet.
      if (backend != null && _boundaries[LogFile.backend]?.offset == null) {
        try {
          await _snapshot(backend, LogFile.backend, cancelled);
        } on FileSystemException {
          // Leave the size unknown until a snapshot succeeds.
        }
      }
      return null;
    }
    return _Selection(
      session.path,
      session.name,
      session.time,
      application,
      backend,
      files[LogFile.pushNotifications],
    );
  }

  Future<void> _scan() async {
    final generation = _generation;
    final found = <RecordedGameLogEvent>[];
    var keep = false;
    try {
      keep = await _scanOnce(generation, found);
    } on FileSystemException catch (error) {
      _batch = false;
      keep = true;
      if (!_closed && generation == _generation) {
        // Keep the detected map/mode: a transient sharing violation is not a
        // session change, and a vanished log reaches the missing branch above.
        _publish(
          MapInputStatus.error,
          message: 'Configured log input is inaccessible: $error',
        );
      }
    }
    if (keep && !_closed && generation == _generation) _flush(found);
  }

  /// Emits the pending control events and the sorted [found] records as one
  /// batch, when there is anything to emit.
  void _flush(List<RecordedGameLogEvent> found) {
    found.sort((a, b) {
      var comparison = a.time.compareTo(b.time);
      if (comparison == 0) {
        comparison = a.id.file.index.compareTo(b.id.file.index);
      }
      return comparison == 0 ? a.id.offset.compareTo(b.id.offset) : comparison;
    });
    final batch = [..._pendingControl, ...found];
    _pendingControl.clear();
    if (batch.isEmpty) return;
    Set<LogRecordId>? liveIds;
    for (final event in found) {
      final boundary = _boundaries[event.id.file]?.offset;
      if (boundary != null && event.id.offset >= boundary) {
        (liveIds ??= {}).add(event.id);
      }
    }
    _events.add((events: batch, liveIds: liveIds ?? const {}));
  }

  /// Runs one scan, adding record events to [found]. Returns false when the
  /// scan was cancelled or the application log must be replayed, so [found]
  /// must be dropped.
  Future<bool> _scanOnce(
    int generation,
    List<RecordedGameLogEvent> found,
  ) async {
    bool cancelled() => _closed || generation != _generation;
    final selected = await _select(cancelled);
    if (cancelled()) return false;
    if (selected == null) {
      if (_path != null || _session != null) {
        _reset(null, null);
        // A different folder whose application log is not there yet is not
        // a restart of the input: the folder change that follows interrupts
        // the raid instead of discarding it. Losing the current folder's log
        // does reset the input, even if the folder is removed afterward.
        if (!_folderAwaitsApplicationLog) _needReset = true;
      }
      _publish(
        MapInputStatus.missing,
        message: 'No current application log found in the configured root.',
        clearMap: true,
        mode: GameMode.unknown,
      );
      if (_needReset) {
        _needReset = false;
        _pendingControl.add(const LogInputReset());
      }
      return true;
    }
    final files = {
      LogFile.application: selected.application,
      LogFile.backend: selected.backend,
      LogFile.pushNotifications: selected.push,
    };
    final snapshots = await statSessionLogSnapshot(
      files,
      stat: (file) => _snapshot(
        file,
        identical(file, selected.application)
            ? LogFile.application
            : identical(file, selected.backend)
            ? LogFile.backend
            : LogFile.pushNotifications,
        cancelled,
      ),
    );
    final missing = <LogFile, String>{};
    for (final kind in files.keys) {
      final stat = snapshots[kind];
      if (stat == null || stat.type == FileSystemEntityType.notFound) {
        missing[kind] = _missingText[kind]!;
        _problems.remove(kind);
        _unreadable.remove(kind);
        snapshots.remove(kind);
      }
    }
    if (cancelled()) return false;
    final application = selected.application;
    final replaced =
        application.path != _path ||
        selected.session != _session ||
        (snapshots[LogFile.application]?.size ?? 0) < _tail.offset;
    if (replaced) {
      // A new folder only announces itself; a replaced or truncated
      // application log in the same folder also restarts the replay.
      if (selected.session == _session) {
        _needReset = true;
        _baselineSnapshot(snapshots);
      }
      _reset(application.path, selected.session);
      _publish(MapInputStatus.reading);
      if (_needReset) _pendingControl.add(const LogInputReset());
      _needReset = false;
      _pendingControl.add(SessionFolderChanged(selected.name, selected.time));
    }
    // The tail revalidates the consumed prefix through its own read handle,
    // so an in-place rewrite restarts the file instead of adopting bytes.
    final batch = await _tail.read(
      application,
      snapshots[LogFile.application]?.size ?? 0,
      isCancelled: cancelled,
    );
    if (batch.cancelled || cancelled()) return false;
    if (batch.restarted) {
      _baselineSnapshot(snapshots);
      _reset(null, null);
      _publish(MapInputStatus.reading);
      _pendingControl.clear();
      _needReset = true;
      _pending = true;
      return false;
    }
    if (batch.bytesRead > 0) _recordRejected = false;
    _batch = true;
    try {
      for (final item in batch.items) {
        switch (item) {
          case TailRecord(:final text):
            _record(text);
            if (parseGameLogRecord(selected.name, LogFile.application, item)
                case ParsedEvent(:final event)) {
              found.add(event);
            }
          case TailRejection(:final reason):
            _recordRejected = true;
            _publish(
              MapInputStatus.error,
              message: switch (reason) {
                TailRejectionReason.malformedUtf8 =>
                  'Malformed UTF-8 log record rejected.',
                TailRejectionReason.lineTooLong ||
                TailRejectionReason.recordTooLarge =>
                  'Over-limit malformed log record rejected.',
              },
            );
        }
      }
    } finally {
      _batch = false;
    }
    final applicationComplete =
        _tail.offset == snapshots[LogFile.application]?.size &&
        !_tail.hasPendingLine;
    for (final kind in _raidLogs) {
      if (kind == LogFile.pushNotifications && !applicationComplete) continue;
      final file = files[kind];
      if (file == null || !snapshots.containsKey(kind)) {
        if (kind == LogFile.backend) {
          if (file?.path == _backendReadPath && _tails[kind]!.offset > 0) {
            // Discarding this cursor will replay its consumed bytes.
            _setBoundary(kind, null);
          }
          _backendReadPath = null;
        }
        _tails[kind]!.reset();
        continue;
      }
      if (!await _readRaidLog(
        kind,
        file,
        snapshots[kind]!.size,
        selected.name,
        found,
        cancelled,
      )) {
        return false;
      }
    }
    final problems = [
      for (final kind in _raidLogs)
        ?(_unreadable.contains(kind)
            ? '${_fileNames[kind]} log could not be read'
            : _problems[kind] ?? missing[kind]),
    ];
    _setRaidLogsMessage(problems.isEmpty ? null : problems.join('; '));
    // A rejected record stays visible until newer bytes read cleanly.
    if (_state.status != MapInputStatus.unavailable && !_recordRejected) {
      _publish(
        applicationComplete ? MapInputStatus.watching : MapInputStatus.reading,
        message: applicationComplete
            ? null
            : 'Waiting for the application log to finish writing.',
      );
    }
    _emit();
    return true;
  }

  /// Reads the backend or push [file] to [size], adding its events to [found]
  /// and updating its entry in [_problems]. Returns false when cancelled.
  Future<bool> _readRaidLog(
    LogFile kind,
    File file,
    int size,
    String folder,
    List<RecordedGameLogEvent> found,
    bool Function() cancelled,
  ) async {
    final tail = _tails[kind]!;
    final backend = kind == LogFile.backend;
    final sameBackendPath = backend && file.path == _backendReadPath;
    if (backend) _backendReadPath = file.path;
    if (sameBackendPath && size < tail.offset) _setBoundary(kind, size);
    try {
      var batch = await tail.read(file, size, isCancelled: cancelled);
      if (batch.cancelled || cancelled()) return false;
      final rewritten = batch.restarted;
      // A path change already has the new path's first snapshot, which may
      // precede this read. Only a restart within a path changes its boundary.
      if (rewritten && sameBackendPath) _setBoundary(kind, size);
      var bytesRead = batch.bytesRead;
      if (batch.restarted && batch.items.isEmpty) {
        // Same-length rewrite: the tail reset itself; read again from the top.
        batch = await tail.read(file, size, isCancelled: cancelled);
        if (batch.cancelled || cancelled()) return false;
        bytesRead += batch.bytesRead;
      }
      var rejected = false;
      for (final item in batch.items) {
        switch (item) {
          case TailRecord():
            switch (parseGameLogRecord(folder, kind, item)) {
              case ParsedEvent(:final event):
                found.add(event);
              case ParseRejected():
                rejected = true;
              case ParsedNothing():
                break;
            }
          case TailRejection():
            rejected = true;
        }
      }
      _unreadable.remove(kind);
      final name = _fileNames[kind]!;
      if (rejected) {
        _problems[kind] = '$name log: a record was rejected';
      } else if (rewritten) {
        _problems[kind] = '$name log was rewritten and read again';
      } else if (bytesRead > 0) {
        _problems.remove(kind);
      }
    } on FileSystemException {
      _unreadable.add(kind);
    }
    return true;
  }

  void _record(String text) {
    final mode = _mode.firstMatch(text);
    if (mode != null) {
      final detected = gameModeFromLog(mode[1]!);
      _publish(
        _state.detectedMapId == null &&
                _state.status == MapInputStatus.unavailable
            ? MapInputStatus.unavailable
            : MapInputStatus.watching,
        mode: detected,
      );
    }
    // Scene metadata must belong to the application logger, not arbitrary text.
    if (!text.toLowerCase().contains('application|scene preset path:')) return;
    final scene = _scene.firstMatch(text);
    final map = scene == null ? null : sceneMapId(scene[1]!);
    if (map == null) {
      _publish(
        MapInputStatus.unavailable,
        clearMap: true,
        message: 'Current log scene is unsupported.',
      );
    } else {
      _publish(MapInputStatus.watching, map: map);
    }
  }

  /// Stops reading and closes [states] and [events].
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    ++_generation;
    _timer?.cancel();
    await _watch?.cancel();
    await _active;
    await _states.close();
    await _events.close();
  }
}

// A null path means the role was absent; a selected path with no offset
// awaits its first successful size snapshot.
typedef _LiveBoundary = ({String? path, int? offset});

/// The newest session folder and the newest file of each kind inside it.
final class _Selection {
  const _Selection(
    this.session,
    this.name,
    this.time,
    this.application,
    this.backend,
    this.push,
  );

  final String session;
  final String name;
  final DateTime time;
  final File application;
  final File? backend;
  final File? push;
}

const _raidLogs = [LogFile.backend, LogFile.pushNotifications];

const _fileNames = {
  LogFile.application: 'application',
  LogFile.backend: 'backend',
  LogFile.pushNotifications: 'notifications',
};

const _missingText = {
  LogFile.application: 'application log not found',
  LogFile.backend: 'backend log not found',
  LogFile.pushNotifications: 'notifications log not written yet',
};

final _mode = RegExp(r'Session mode\s*:\s*([^\s|]+)', caseSensitive: false);
final _scene = RegExp(
  r'scene preset path:\s*maps/([a-zA-Z0-9_]+)\.bundle',
  caseSensitive: false,
);

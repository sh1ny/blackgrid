import 'dart:async';
import 'dart:io';

import '../domain/catalog.dart';
import '../domain/map_session.dart';
import '../domain/raid_lifecycle.dart';
import 'game_log/game_locations.dart';
import 'game_log/game_log_parsers.dart';
import 'game_log/log_file_tail.dart';

/// Configured-root-only replay and tail of the three raid-lifecycle logs.
///
/// Each scan picks the newest session folder once, stats the application,
/// backend and push-notifications files, reads each to its stat size, and
/// emits the scan's events as one batch on [events], sorted by log time, then
/// file (application, backend, push), then byte offset. The bind-time replay is
/// one such scan, so a replay and a live read yield the same events in the same
/// order.
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
  });

  /// How often the session folder is rescanned.
  final Duration pollInterval;

  /// Largest single read from a log file, in bytes.
  final int chunkBytes;

  /// Longest accepted log line, in bytes.
  final int maxLineBytes;
  final _states = StreamController<SessionLogState>.broadcast(sync: true);
  final _events = StreamController<List<GameLogEvent>>.broadcast(sync: true);

  /// The application-log state; see the class comment for what it excludes.
  Stream<SessionLogState> get states => _states.stream;

  /// One batch per scan that produced events, in lifecycle order.
  ///
  /// Control events ([LogInputReset], [SessionFolderChanged]) come first in
  /// their batch, followed by the sorted record events. A scan with nothing to
  /// report emits no batch.
  Stream<List<GameLogEvent>> get events => _events.stream;
  SessionLogState _state = const SessionLogState();

  /// The latest published state.
  SessionLogState get state => _state;
  String _root = '';
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
  final _pendingControl = <GameLogEvent>[];
  bool _needReset = false;

  /// Whether the last selection found a newest session folder that has no
  /// application log yet, as when the game has just created it.
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
    _pendingControl.clear();
    _needReset = true;
    if (_closed) return;
    if (root.isEmpty) {
      _publish(
        MapInputStatus.disabled,
        message: 'No game log directory configured.',
      );
      _needReset = false;
      _events.add(const [LogInputReset()]);
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
    _problems.clear();
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

  Future<_Selection?> _select() async {
    _folderAwaitsApplicationLog = false;
    final root = Directory(_root);
    if (!await root.exists()) return null;
    final sessions = <(DateTime, Directory)>[];
    await for (final entry in root.list(followLinks: false)) {
      if (entry is! Directory) continue;
      final match = _folder.firstMatch(_basename(entry.path));
      if (match == null) continue;
      final time = DateTime.tryParse(
        '${match[1]}-${match[2]}-${match[3]}T${match[4]!.padLeft(2, '0')}:${match[5]}:${match[6]}',
      );
      if (time != null &&
          time.year == int.parse(match[1]!) &&
          time.month == int.parse(match[2]!) &&
          time.day == int.parse(match[3]!) &&
          time.hour == int.parse(match[4]!) &&
          time.minute == int.parse(match[5]!) &&
          time.second == int.parse(match[6]!)) {
        sessions.add((time, entry));
      }
    }
    sessions.sort((a, b) {
      final comparison = a.$1.compareTo(b.$1);
      return comparison == 0 ? a.$2.path.compareTo(b.$2.path) : comparison;
    });
    if (sessions.isEmpty) return null;
    final (time, session) = sessions.last;
    final candidates = <LogFile, List<(DateTime, File)>>{
      for (final kind in LogFile.values) kind: [],
    };
    await for (final entry in session.list(followLinks: false)) {
      if (entry is! File) continue;
      for (final kind in LogFile.values) {
        if (_patterns[kind]!.hasMatch(entry.path)) {
          candidates[kind]!.add(((await entry.stat()).modified, entry));
        }
      }
    }
    File? newest(LogFile kind) {
      final files = candidates[kind]!;
      files.sort((a, b) {
        final comparison = a.$1.compareTo(b.$1);
        return comparison == 0 ? a.$2.path.compareTo(b.$2.path) : comparison;
      });
      return files.isEmpty ? null : files.last.$2;
    }

    final application = newest(LogFile.application);
    if (application == null) {
      _folderAwaitsApplicationLog = true;
      return null;
    }
    return _Selection(
      session.path,
      _basename(session.path),
      time,
      application,
      newest(LogFile.backend),
      newest(LogFile.pushNotifications),
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
    if (batch.isNotEmpty) _events.add(batch);
  }

  /// Runs one scan, adding record events to [found]. Returns false when the
  /// scan was cancelled or the application log must be replayed, so [found]
  /// must be dropped.
  Future<bool> _scanOnce(
    int generation,
    List<RecordedGameLogEvent> found,
  ) async {
    bool cancelled() => _closed || generation != _generation;
    final selected = await _select();
    if (cancelled()) return false;
    if (selected == null) {
      if (_path != null || _session != null) {
        _reset(null, null);
        // A new folder whose application log is not there yet is not a
        // restart of the input: the folder change that follows interrupts
        // the raid instead of discarding it.
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
    // Stat every file before reading any, so each read stops at a size seen
    // together.
    final sizes = <LogFile, int>{};
    final missing = <LogFile, String>{};
    for (final MapEntry(key: kind, value: file) in files.entries) {
      final stat = file == null ? null : await file.stat();
      if (stat == null || stat.type == FileSystemEntityType.notFound) {
        missing[kind] = _missingText[kind]!;
        _problems.remove(kind);
      } else {
        sizes[kind] = stat.size;
      }
    }
    if (cancelled()) return false;
    final application = selected.application;
    final replaced =
        application.path != _path ||
        selected.session != _session ||
        (sizes[LogFile.application] ?? 0) < _tail.offset;
    if (replaced) {
      // A new folder only announces itself; a replaced or truncated
      // application log in the same folder also restarts the replay.
      if (selected.session == _session) _needReset = true;
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
      sizes[LogFile.application] ?? 0,
      isCancelled: cancelled,
    );
    if (batch.cancelled || cancelled()) return false;
    if (batch.restarted) {
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
    for (final kind in _raidLogs) {
      final file = files[kind];
      if (file == null || !sizes.containsKey(kind)) {
        _tails[kind]!.reset();
        continue;
      }
      if (!await _readRaidLog(
        kind,
        file,
        sizes[kind]!,
        selected.name,
        found,
        cancelled,
      )) {
        return false;
      }
    }
    final problems = [
      for (final kind in _raidLogs) ?_problems[kind] ?? missing[kind],
    ];
    _setRaidLogsMessage(problems.isEmpty ? null : problems.join('; '));
    // A rejected record stays visible until newer bytes read cleanly.
    if (_state.status != MapInputStatus.unavailable && !_recordRejected) {
      _publish(MapInputStatus.watching);
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
    try {
      var batch = await tail.read(file, size, isCancelled: cancelled);
      if (batch.cancelled || cancelled()) return false;
      final rewritten = batch.restarted;
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
      final name = _fileNames[kind]!;
      if (rejected) {
        _problems[kind] = '$name log: a record was rejected';
      } else if (rewritten) {
        _problems[kind] = '$name log was rewritten and read again';
      } else if (bytesRead > 0) {
        _problems.remove(kind);
      }
    } on FileSystemException {
      _problems[kind] = '${_fileNames[kind]} log could not be read';
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

String _basename(String path) => path.replaceAll('\\', '/').split('/').last;

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

// Real folders carry a game-version suffix: `log_2026.10.07_10-25-14_1.2.0.0.47888`.
final _folder = RegExp(
  r'^log_(\d{4})\.(\d{2})\.(\d{2})_(\d{1,2})-(\d{2})-(\d{2})(?:_[^\\/]*)?$',
  caseSensitive: false,
);
final _patterns = {
  LogFile.application: RegExp(
    r'application(?:_000)?\.log$',
    caseSensitive: false,
  ),
  LogFile.backend: RegExp(r'backend(?:_000)?\.log$', caseSensitive: false),
  LogFile.pushNotifications: RegExp(
    r'push-notifications(?:_000)?\.log$',
    caseSensitive: false,
  ),
};
final _mode = RegExp(r'Session mode\s*:\s*([^\s|]+)', caseSensitive: false);
final _scene = RegExp(
  r'scene preset path:\s*maps/([a-zA-Z0-9_]+)\.bundle',
  caseSensitive: false,
);

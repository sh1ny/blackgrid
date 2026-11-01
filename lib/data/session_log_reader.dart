import 'dart:async';
import 'dart:io';

import '../domain/catalog.dart';
import '../domain/map_session.dart';
import '../domain/raid_lifecycle.dart';
import 'game_log/game_locations.dart';
import 'game_log/log_file_tail.dart';

/// Configured-root-only replay and tail. Record identity is incarnation plus
/// byte offset, not timestamps. UTF-8 is decoded only after a full line arrives.
class SessionLogReader {
  SessionLogReader({
    this.pollInterval = const Duration(milliseconds: 250),
    this.chunkBytes = 8192,
    this.maxLineBytes = 65536,
  });
  final Duration pollInterval;
  final int chunkBytes;
  final int maxLineBytes;
  final _states = StreamController<SessionLogState>.broadcast(sync: true);
  Stream<SessionLogState> get states => _states.stream;
  SessionLogState _state = const SessionLogState();
  SessionLogState get state => _state;
  String _root = '';
  String? _path;
  String? _session;
  int _generation = 0;
  int _incarnation = 0;
  late final _tail = LogFileTail(
    kind: LogFile.application,
    headersOnly: false,
    chunkBytes: chunkBytes,
    maxLineBytes: maxLineBytes,
  );
  bool _batch = false;
  bool _recordRejected = false;
  SessionLogState? _lastPublished;
  bool _closed = false;
  bool _pending = false;
  Timer? _timer;
  StreamSubscription<FileSystemEvent>? _watch;
  Future<void>? _active;
  Future<void>? _closing;

  Future<void> bind(String root) async {
    final generation = ++_generation;
    _timer?.cancel();
    await _watch?.cancel();
    if (_closed || generation != _generation) return;
    _watch = null;
    _root = root;
    _reset(null, null);
    if (_closed) return;
    if (root.isEmpty) {
      _publish(
        MapInputStatus.disabled,
        message: 'No game log directory configured.',
      );
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
    _tail.reset();
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
    );
    if (next.status == _state.status &&
        next.sessionId == _state.sessionId &&
        next.incarnation == _state.incarnation &&
        next.detectedMapId == _state.detectedMapId &&
        next.detectedMode == _state.detectedMode &&
        next.message == _state.message) {
      return;
    }
    _state = next;
    if (!_batch) _emit();
  }

  void _emit() {
    final old = _lastPublished;
    final next = _state;
    if (_closed ||
        (old != null &&
            old.status == next.status &&
            old.sessionId == next.sessionId &&
            old.incarnation == next.incarnation &&
            old.detectedMapId == next.detectedMapId &&
            old.detectedMode == next.detectedMode &&
            old.message == next.message)) {
      return;
    }
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

  Future<void> rescan() async {
    _schedule();
    while (_active != null) {
      await _active;
    }
  }

  Future<(String, File)?> _select() async {
    final root = Directory(_root);
    if (!await root.exists()) return null;
    final sessions = <(DateTime, Directory)>[];
    await for (final entry in root.list(followLinks: false)) {
      if (entry is! Directory) continue;
      final name = entry.path.replaceAll('\\', '/').split('/').last;
      final match = _folder.firstMatch(name);
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
    final session = sessions.last.$2;
    final files = <(DateTime, File)>[];
    await for (final entry in session.list(followLinks: false)) {
      if (entry is! File || !_application.hasMatch(entry.path)) continue;
      files.add(((await entry.stat()).modified, entry));
    }
    files.sort((a, b) {
      final comparison = a.$1.compareTo(b.$1);
      return comparison == 0 ? a.$2.path.compareTo(b.$2.path) : comparison;
    });
    return files.isEmpty ? null : (session.path, files.last.$2);
  }

  Future<void> _scan() async {
    final generation = _generation;
    try {
      final selected = await _select();
      if (_closed || generation != _generation) return;
      if (selected == null) {
        if (_path != null || _session != null) _reset(null, null);
        _publish(
          MapInputStatus.missing,
          message: 'No current application log found in the configured root.',
          clearMap: true,
          mode: GameMode.unknown,
        );
        return;
      }
      final file = selected.$2;
      final stat = await file.stat();
      final replaced =
          file.path != _path ||
          selected.$1 != _session ||
          stat.size < _tail.offset;
      if (replaced) {
        _reset(file.path, selected.$1);
        _publish(MapInputStatus.reading);
      }
      // The tail revalidates the consumed prefix through its own read handle,
      // so an in-place rewrite restarts the file instead of adopting bytes.
      final batch = await _tail.read(
        file,
        stat.size,
        isCancelled: () => _closed || generation != _generation,
      );
      if (batch.cancelled || _closed || generation != _generation) return;
      final rewritten = batch.restarted;
      if (!rewritten) {
        if (batch.bytesRead > 0) _recordRejected = false;
        _batch = true;
        try {
          for (final item in batch.items) {
            switch (item) {
              case TailRecord(:final text):
                _record(text);
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
      }
      if (rewritten) {
        _reset(null, null);
        _publish(MapInputStatus.reading);
        _pending = true;
        return;
      }
      // A rejected record stays visible until newer bytes read cleanly.
      if (_state.status != MapInputStatus.unavailable && !_recordRejected) {
        _publish(MapInputStatus.watching);
      }
      _emit();
    } on FileSystemException catch (error) {
      _batch = false;
      if (!_closed && generation == _generation) {
        // Keep the detected map/mode: a transient sharing violation is not a
        // session change, and a vanished log reaches the missing branch above.
        _publish(
          MapInputStatus.error,
          message: 'Configured log input is inaccessible: $error',
        );
      }
    }
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

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    ++_generation;
    _timer?.cancel();
    await _watch?.cancel();
    await _active;
    await _states.close();
  }
}

// Real folders carry a game-version suffix: `log_2026.10.07_10-25-14_1.2.0.0.47888`.
final _folder = RegExp(
  r'^log_(\d{4})\.(\d{2})\.(\d{2})_(\d{1,2})-(\d{2})-(\d{2})(?:_[^\\/]*)?$',
  caseSensitive: false,
);
final _application = RegExp(
  r'application(?:_000)?\.log$',
  caseSensitive: false,
);
final _mode = RegExp(r'Session mode\s*:\s*([^\s|]+)', caseSensitive: false);
final _scene = RegExp(
  r'scene preset path:\s*maps/([a-zA-Z0-9_]+)\.bundle',
  caseSensitive: false,
);

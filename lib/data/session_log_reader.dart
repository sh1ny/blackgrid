import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../domain/catalog.dart';
import '../domain/map_session.dart';

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
  int _offset = 0;

  /// Last consumed bytes, revalidated before each tail read.
  Uint8List _window = Uint8List(0);
  final List<int> _line = [];
  bool _discardLine = false;
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

  void _remember(Uint8List bytes) {
    if (bytes.length >= _windowBytes) {
      _window = Uint8List.fromList(bytes.sublist(bytes.length - _windowBytes));
      return;
    }
    final keep = (_windowBytes - bytes.length).clamp(0, _window.length);
    _window = Uint8List.fromList([
      ..._window.sublist(_window.length - keep),
      ...bytes,
    ]);
  }

  void _reset(String? path, String? session) {
    _path = path;
    _session = session;
    ++_incarnation;
    _offset = 0;
    _window = Uint8List(0);
    _line.clear();
    _discardLine = false;
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
          file.path != _path || selected.$1 != _session || stat.size < _offset;
      if (replaced) {
        _reset(file.path, selected.$1);
        _publish(MapInputStatus.reading);
      }
      final handle = await file.open();
      var rewritten = false;
      _batch = true;
      try {
        // Validate the tail of the consumed prefix through this same handle. A
        // separate path precheck can precede an in-place rewrite and wrongly
        // adopt unparsed replacement bytes. Rehashing the whole prefix on every
        // poll would reread a growing game log continuously while it is played.
        if (_window.isNotEmpty) {
          await handle.setPosition(_offset - _window.length);
          final consumed = await _readExactly(handle, _window.length);
          if (_closed || generation != _generation) return;
          rewritten = !_sameBytes(consumed, _window);
        }
        final end = stat.size;
        if (!rewritten && _offset < end) _recordRejected = false;
        while (!rewritten && _offset < end) {
          final bytes = await handle.read((end - _offset).clamp(0, chunkBytes));
          if (_closed || generation != _generation) return;
          if (bytes.isEmpty) break;
          _remember(bytes);
          for (final byte in bytes) {
            ++_offset;
            if (byte == 10) {
              if (!_discardLine) _record(_line);
              _line.clear();
              _discardLine = false;
            } else if (!_discardLine) {
              if (_line.length >= maxLineBytes) {
                _line.clear();
                _discardLine = true;
                _recordRejected = true;
                _publish(
                  MapInputStatus.error,
                  message: 'Over-limit malformed log record rejected.',
                );
              } else {
                _line.add(byte);
              }
            }
          }
        }
      } finally {
        _batch = false;
        await handle.close();
      }
      if (_closed || generation != _generation) return;
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

  void _record(List<int> bytes) {
    String text;
    try {
      final length = bytes.isNotEmpty && bytes.last == 13
          ? bytes.length - 1
          : bytes.length;
      text = utf8.decoder.convert(bytes, 0, length);
    } on FormatException {
      _recordRejected = true;
      _publish(
        MapInputStatus.error,
        message: 'Malformed UTF-8 log record rejected.',
      );
      return;
    }
    final mode = _mode.firstMatch(text);
    if (mode != null) {
      final detected = switch (mode[1]!.toLowerCase()) {
        'pve' => GameMode.pve,
        'pvp' || 'regular' => GameMode.pvp,
        'pvpseason' || 'seasonal' || 'szn' => GameMode.seasonal,
        _ => GameMode.unknown,
      };
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
    final map = scene == null ? null : _sceneMap(scene[1]!.toLowerCase());
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

const _windowBytes = 4096;

Future<Uint8List> _readExactly(RandomAccessFile handle, int length) async {
  final result = BytesBuilder(copy: false);
  while (result.length < length) {
    final bytes = await handle.read(length - result.length);
    if (bytes.isEmpty) break;
    result.add(bytes);
  }
  return result.takeBytes();
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; ++i) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// Independently reconciled scene vocabulary; persisted IDs remain settings IDs.
String? _sceneMap(String scene) => switch (scene) {
  'factory4_day' ||
  'factory4_night' ||
  'factory_day_preset' ||
  'factory_night_preset' => 'factory',
  'bigmap' || 'customs_preset' => 'customs',
  'woods' || 'woods_preset' => 'woods',
  'shoreline' || 'shoreline_preset' => 'shoreline',
  'interchange' || 'shopping_mall' => 'interchange',
  'laboratory' || 'laboratory_preset' => 'thelab',
  'rezervbase' || 'rezerv_base_preset' => 'reserve',
  'lighthouse' || 'lighthouse_preset' => 'lighthouse',
  'tarkovstreets' || 'city_preset' => 'streetsoftarkov',
  'sandbox' ||
  'sandbox_preset' ||
  'sandbox_high' ||
  'sandbox_high_preset' ||
  'sandbox_start_preset' => 'groundzero',
  'terminal' || 'icebreaker' || 'labyrinth' => scene,
  _ => null,
};

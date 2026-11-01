import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../domain/raid_lifecycle.dart';

/// Why a line or record was rejected by [LogFileTail].
enum TailRejectionReason {
  /// The line is not valid UTF-8.
  malformedUtf8,

  /// A single line is longer than the line limit.
  lineTooLong,

  /// A push record is larger than the byte or line limit.
  recordTooLarge,
}

/// One framed item produced by [LogFileTail], in file order.
sealed class TailItem {
  const TailItem(this.offset);

  /// Absolute byte offset of the first byte of the item's header line.
  final int offset;
}

/// A complete record: one header line, plus body lines for push records.
final class TailRecord extends TailItem {
  const TailRecord(super.offset, this.text);

  /// Header line, then (push only) body lines joined with `\n`. No CR, no
  /// trailing newline.
  final String text;
}

/// A line or record that was dropped. It produces no event.
final class TailRejection extends TailItem {
  const TailRejection(super.offset, this.reason);

  /// Why the bytes at [offset] were dropped.
  final TailRejectionReason reason;
}

/// The result of one [LogFileTail.read].
final class TailBatch {
  const TailBatch({
    this.items = const [],
    this.restarted = false,
    this.cancelled = false,
    this.bytesRead = 0,
  });

  /// Records and rejections in file order.
  final List<TailItem> items;

  /// True when the file was replaced, truncated or rewritten and the tail
  /// restarted from the first byte. After a same-length rewrite the batch is
  /// empty and the caller should read again.
  final bool restarted;

  /// True when the caller's cancellation callback fired; nothing was consumed
  /// after that point and [items] is empty.
  final bool cancelled;

  /// Number of new bytes consumed by this read.
  final int bytesRead;

  /// The complete records of [items].
  List<TailRecord> get records => items.whereType<TailRecord>().toList();

  /// The rejections of [items].
  List<TailRejection> get rejections =>
      items.whereType<TailRejection>().toList();
}

/// Incremental, read-only byte tail of one game log file.
///
/// Keeps an absolute byte offset, decodes UTF-8 only after a full line has
/// arrived, and frames lines into records for the file's [kind]. Application
/// and backend files yield header lines only. Push files yield a record per
/// `Got notification |` header, closed by a lone `}` line or by the next
/// header. The last 4 KiB consumed is revalidated through the handle used for
/// every read, so an in-place rewrite restarts the file instead of adopting
/// replacement bytes.
class LogFileTail {
  /// Creates a tail for one [kind] of log file.
  LogFileTail({
    required this.kind,
    this.chunkBytes = 8192,
    this.maxLineBytes = 65536,
    this.maxRecordBytes = 1 << 20,
    this.maxRecordLines = 8192,
    this.headersOnly = true,
  });

  /// Which file this tail frames.
  final LogFile kind;

  /// Largest single read from the file handle.
  final int chunkBytes;

  /// Longest accepted line, in bytes, excluding the newline.
  final int maxLineBytes;

  /// Largest accepted push record, in bytes.
  final int maxRecordBytes;

  /// Largest accepted push record, in lines.
  final int maxRecordLines;

  /// When false, application and backend files yield every line as a record
  /// instead of only timestamped header lines. Only the legacy session reader,
  /// whose fixtures carry headerless lines, turns this off.
  final bool headersOnly;

  String? _path;
  int _offset = 0;
  Uint8List _window = Uint8List(0);
  final List<int> _line = [];
  int _lineStart = 0;
  bool _discardLine = false;

  // Push record state.
  int? _recordStart;
  final List<String> _recordLines = [];
  int _recordBytes = 0;

  // Items framed but not yet handed out; survives a failed read.
  final List<TailItem> _items = [];

  /// Absolute offset of the next unread byte.
  int get offset => _offset;

  /// Current size of [file], or -1 when it does not exist.
  Future<int> stat(File file) async => (await file.stat()).size;

  /// Forgets all state; the next read starts at the first byte of whatever
  /// file it is given, without a restart signal.
  void reset() {
    _path = null;
    _offset = 0;
    _window = Uint8List(0);
    _line.clear();
    _lineStart = 0;
    _discardLine = false;
    _recordStart = null;
    _recordLines.clear();
    _recordBytes = 0;
    _items.clear();
  }

  /// Reads new bytes of [file] up to [size] (the size seen at stat) and
  /// returns the records and rejections they complete.
  ///
  /// [isCancelled] is checked after every await; when it returns true the
  /// read stops without consuming more and the result has `cancelled` set.
  /// File system errors propagate; framed items are kept for the next read.
  Future<TailBatch> read(
    File file,
    int size, {
    bool Function()? isCancelled,
  }) async {
    bool cancelled() => isCancelled?.call() ?? false;
    var restarted = false;
    if (_path != null && (_path != file.path || size < _offset)) {
      reset();
      restarted = true;
    }
    _path = file.path;
    final start = _offset;
    final handle = await file.open();
    try {
      if (cancelled()) return const TailBatch(cancelled: true);
      if (_window.isNotEmpty) {
        await handle.setPosition(_offset - _window.length);
        final consumed = await _readExactly(handle, _window.length);
        if (cancelled()) return const TailBatch(cancelled: true);
        if (!_sameBytes(consumed, _window)) {
          reset();
          return const TailBatch(restarted: true);
        }
      }
      await handle.setPosition(_offset);
      if (cancelled()) return const TailBatch(cancelled: true);
      while (_offset < size) {
        final bytes = await handle.read((size - _offset).clamp(0, chunkBytes));
        if (cancelled()) return const TailBatch(cancelled: true);
        if (bytes.isEmpty) break;
        _remember(bytes);
        for (final byte in bytes) {
          _consume(byte);
        }
      }
    } finally {
      await handle.close();
    }
    final items = List<TailItem>.of(_items);
    _items.clear();
    return TailBatch(
      items: items,
      restarted: restarted,
      bytesRead: _offset - start,
    );
  }

  static const _windowBytes = 4096;

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

  void _consume(int byte) {
    ++_offset;
    if (byte == 10) {
      if (!_discardLine) _lineDone();
      _line.clear();
      _discardLine = false;
      _lineStart = _offset;
    } else if (!_discardLine) {
      if (_line.length >= maxLineBytes) {
        _line.clear();
        _discardLine = true;
        _items.add(TailRejection(_lineStart, TailRejectionReason.lineTooLong));
        _abandonRecord();
      } else {
        _line.add(byte);
      }
    }
  }

  void _lineDone() {
    final String text;
    try {
      final length = _line.isNotEmpty && _line.last == 13
          ? _line.length - 1
          : _line.length;
      text = utf8.decoder.convert(_line, 0, length);
    } on FormatException {
      _items.add(TailRejection(_lineStart, TailRejectionReason.malformedUtf8));
      _abandonRecord();
      return;
    }
    final isHeader = _header.hasMatch(text);
    switch (kind) {
      case LogFile.application || LogFile.backend:
        if (isHeader || !headersOnly) _items.add(TailRecord(_lineStart, text));
      case LogFile.pushNotifications:
        _pushLine(text, isHeader);
    }
  }

  void _pushLine(String text, bool isHeader) {
    if (isHeader) {
      _closeRecord();
      if (text.contains(_pushMarker)) {
        _recordStart = _lineStart;
        _recordLines.add(text);
        _recordBytes = _line.length + 1;
      }
      return;
    }
    if (_recordStart == null) return;
    _recordLines.add(text);
    _recordBytes += _line.length + 1;
    if (_recordBytes > maxRecordBytes || _recordLines.length > maxRecordLines) {
      _items.add(
        TailRejection(_recordStart!, TailRejectionReason.recordTooLarge),
      );
      _abandonRecord();
      return;
    }
    if (text == '}') _closeRecord();
  }

  void _closeRecord() {
    final start = _recordStart;
    if (start == null) return;
    _items.add(TailRecord(start, _recordLines.join('\n')));
    _recordStart = null;
    _recordLines.clear();
    _recordBytes = 0;
  }

  /// Drops the open push record; later lines are ignored until the next header.
  void _abandonRecord() {
    if (kind != LogFile.pushNotifications) return;
    _recordStart = null;
    _recordLines.clear();
    _recordBytes = 0;
  }
}

final _header = RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}\|');
const _pushMarker = 'Got notification |';

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

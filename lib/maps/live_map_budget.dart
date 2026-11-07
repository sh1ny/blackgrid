import 'dart:convert';
import 'dart:typed_data';

/// Reports that a live-map operation exceeded a configured resource limit.
class LiveMapResourceLimitException implements Exception {
  /// Creates a resource-limit failure with a useful explanation.
  const LiveMapResourceLimitException(this.message);

  /// The resource limit that was exceeded.
  final String message;

  @override
  String toString() => 'LiveMapResourceLimitException: $message';
}

/// Accounts for expanded live-map data and bounded UTF-8 JSON output.
class LiveMapBudget {
  /// Creates a budget using the normative runtime resource limits.
  LiveMapBudget({
    this.maxMaterializedBytes = 256 * 1024 * 1024,
    this.maxSerializedBytes = 64 * 1024 * 1024,
  }) {
    if (maxMaterializedBytes < 0 || maxSerializedBytes < 0) {
      throw ArgumentError('Live-map limits must not be negative.');
    }
  }

  /// The maximum conservatively materialized data size.
  final int maxMaterializedBytes;

  /// The maximum encoded JSON size.
  final int maxSerializedBytes;

  /// The currently reserved materialized size.
  int materializedBytes = 0;

  /// The currently reserved serialized size.
  int serializedBytes = 0;

  /// Reserves [bytes] before an allocation represented by those bytes.
  void reserveMaterialized(int bytes) {
    if (bytes < 0) throw ArgumentError.value(bytes, 'bytes');
    final next = materializedBytes + bytes;
    if (next > maxMaterializedBytes) {
      throw const LiveMapResourceLimitException(
        'Materialized live-map data exceeds its configured limit.',
      );
    }
    materializedBytes = next;
  }

  /// Releases [bytes] once the corresponding materialized data is unreachable.
  void releaseMaterialized(int bytes) {
    if (bytes < 0 || bytes > materializedBytes) {
      throw ArgumentError.value(bytes, 'bytes');
    }
    materializedBytes -= bytes;
  }

  /// Reserves a recursive conservative charge for every occurrence in [value].
  void reserveValue(Object? value, {int copies = 1}) {
    if (copies < 1) throw ArgumentError.value(copies, 'copies');
    final charge = _valueSize(value);
    if (charge != 0 && copies > maxMaterializedBytes ~/ charge) {
      throw const LiveMapResourceLimitException(
        'Materialized live-map data exceeds its configured limit.',
      );
    }
    reserveMaterialized(charge * copies);
  }

  /// Reserves [bytes] of serialized output produced by a worker.
  void reserveSerialized(int bytes) {
    if (bytes < 0) throw ArgumentError.value(bytes, 'bytes');
    final next = serializedBytes + bytes;
    if (next > maxSerializedBytes) {
      throw const LiveMapResourceLimitException(
        'Serialized live-map data exceeds its configured limit.',
      );
    }
    serializedBytes = next;
  }

  /// Decodes bounded JSON after reserving its text and recursive tree storage.
  ///
  /// The scanner accounts for JSON structure and UTF-16 string units without
  /// constructing a decoded string or container. The SDK decoder remains the
  /// authority for JSON syntax validation.
  Object? decodeJson(Uint8List bytes, {int? maxBytes}) {
    final limit = maxBytes ?? maxSerializedBytes;
    if (bytes.length > limit) {
      throw const LiveMapResourceLimitException(
        'Serialized live-map data exceeds its configured limit.',
      );
    }
    final textCharge = 32 + _encodedUtf16Length(bytes) * 2;
    reserveMaterialized(textCharge);
    try {
      _reserveJsonTree(bytes, reserveMaterialized);
      return jsonDecode(utf8.decode(bytes));
    } finally {
      releaseMaterialized(textCharge);
    }
  }

  /// Encodes JSON with the SDK encoder and bounds each output-buffer chunk.
  Uint8List encodeJson(Object? value) {
    final sink = _BudgetedJsonSink(this);
    try {
      final encoder = JsonUtf8Encoder(
        null,
        null,
        _BudgetedJsonSink._chunkLimit,
      );
      final converter = encoder.startChunkedConversion(sink);
      converter.add(value);
      converter.close();
      return sink.finish();
    } catch (_) {
      final failure = sink.failure;
      sink.abort();
      if (failure != null) throw failure;
      rethrow;
    }
  }
}

class _BudgetedJsonSink implements Sink<List<int>> {
  _BudgetedJsonSink(this._budget);

  static const _chunkLimit = 4096;

  final LiveMapBudget _budget;
  final BytesBuilder _output = BytesBuilder(copy: false);
  int _size = 0;
  int _reservedBytes = 0;
  bool _closed = false;
  Object? failure;

  @override
  void add(List<int> chunk) {
    if (_closed) throw StateError('JSON byte sink is closed.');
    var offset = 0;
    while (offset < chunk.length) {
      final length = chunk.length - offset < _chunkLimit
          ? chunk.length - offset
          : _chunkLimit;
      if (_budget.serializedBytes + _size + length >
          _budget.maxSerializedBytes) {
        failure = const LiveMapResourceLimitException(
          'Serialized live-map data exceeds its configured limit.',
        );
        throw failure!;
      }
      try {
        _budget.reserveMaterialized(length);
      } on LiveMapResourceLimitException catch (error) {
        failure = error;
        rethrow;
      }
      _reservedBytes += length;
      _output.add(chunk.sublist(offset, offset + length));
      _size += length;
      offset += length;
    }
  }

  @override
  void close() {
    _closed = true;
  }

  Uint8List finish() {
    _budget.reserveMaterialized(_size);
    _reservedBytes += _size;
    final result = _output.takeBytes();
    _budget.releaseMaterialized(_size);
    _reservedBytes -= _size;
    _budget.serializedBytes += _size;
    _closed = true;
    return result;
  }

  void abort() {
    if (_reservedBytes > 0) {
      _budget.releaseMaterialized(_reservedBytes);
      _reservedBytes = 0;
    }
    _closed = true;
  }
}

class _JsonFrame {
  _JsonFrame(this.isObject);

  final bool isObject;
  int state = 0;
}

void _reserveJsonTree(Uint8List bytes, void Function(int bytes) reserve) {
  final frames = <_JsonFrame>[];
  var index = 0;

  void finishParentValue() {
    if (frames.isEmpty) return;
    final parent = frames.last;
    if (parent.isObject) {
      if (parent.state == 2) parent.state = 3;
    } else {
      reserve(24);
      parent.state = 1;
    }
  }

  while (index < bytes.length) {
    final byte = bytes[index];
    if (byte == 32 || byte == 9 || byte == 10 || byte == 13) {
      index++;
      continue;
    }
    if (byte == 44) {
      if (frames.isNotEmpty) frames.last.state = 0;
      index++;
      continue;
    }
    if (byte == 58) {
      if (frames.isNotEmpty && frames.last.isObject) {
        frames.last.state = 2;
      }
      index++;
      continue;
    }
    if (byte == 125 || byte == 93) {
      if (frames.isNotEmpty) frames.removeLast();
      index++;
      continue;
    }
    if (byte == 34) {
      final (end, units) = _scanJsonString(bytes, index);
      final isKey =
          frames.isNotEmpty && frames.last.isObject && frames.last.state == 0;
      reserve(32 + units * 2 + (isKey ? 48 : 0));
      index = end;
      if (isKey) {
        frames.last.state = 1;
      } else {
        finishParentValue();
      }
      continue;
    }
    if (byte == 123 || byte == 91) {
      finishParentValue();
      final isObject = byte == 123;
      reserve(isObject ? 96 : 48);
      frames.add(_JsonFrame(isObject));
      index++;
      continue;
    }

    finishParentValue();
    reserve(32);
    final start = index;
    final number = byte == 45 || (byte >= 48 && byte <= 57);
    while (index < bytes.length) {
      final next = bytes[index];
      if (next == 32 ||
          next == 9 ||
          next == 10 ||
          next == 13 ||
          next == 44 ||
          next == 58 ||
          next == 93 ||
          next == 125) {
        break;
      }
      index++;
    }
    if (number) reserve((index - start) * 2);
    if (index == bytes.length) break;
  }
}

(int, int) _scanJsonString(Uint8List bytes, int start) {
  var index = start + 1;
  var units = 0;
  while (index < bytes.length) {
    final byte = bytes[index];
    if (byte == 34) return (index + 1, units);
    if (byte == 92) {
      index++;
      if (index >= bytes.length) break;
      if (bytes[index] == 117) {
        index += 5;
      } else {
        index++;
      }
      units++;
    } else if (byte < 0x80) {
      index++;
      units++;
    } else {
      final width = byte >= 0xF0
          ? 4
          : byte >= 0xE0
          ? 3
          : 2;
      index += width;
      units += width == 4 ? 2 : 1;
    }
  }
  return (bytes.length, units);
}

int _encodedUtf16Length(Uint8List bytes) {
  var units = 0;
  for (var index = 0; index < bytes.length; index++) {
    final byte = bytes[index];
    if (byte < 0x80 || byte >= 0xC0) {
      units += byte >= 0xF0 ? 2 : 1;
    }
  }
  return units;
}

int _valueSize(Object? value) {
  var total = 0;
  void visit(Object? current) {
    if (current == null || current is bool || current is num) {
      total += 32;
    } else if (current is String) {
      total += 32 + current.length * 2;
    } else if (current is List) {
      total += 48 + current.length * 24;
      for (final item in current) {
        visit(item);
      }
    } else if (current is Map) {
      total += 96 + current.length * 48;
      for (final entry in current.entries) {
        visit(entry.key);
        visit(entry.value);
      }
    } else {
      throw ArgumentError.value(
        current,
        'value',
        'Unsupported live-map value.',
      );
    }
  }

  visit(value);
  return total;
}

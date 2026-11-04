import 'package:blackgrid/maps/prepared_map.dart';

/// A bounded UTF-8 diagnostic prefix for one prepared marker.
class BoundedMarkerPreview {
  const BoundedMarkerPreview({required this.text, required this.shortened});

  /// The serialized diagnostic prefix, at most 16 KiB when UTF-8 encoded.
  final String text;

  /// Whether a byte, depth, node, or collection limit shortened the preview.
  final bool shortened;
}

/// Builds a bounded diagnostic preview of the marker's current raw data.
///
/// Traversal stops at 16 KiB of UTF-8 output, depth 16, 1,024 visited values,
/// or 128 entries per collection. Strings are escaped and appended one Unicode
/// scalar at a time, so a large source string is never fully encoded first.
/// The result's [BoundedMarkerPreview.shortened] flag reports any limit.
BoundedMarkerPreview previewMarkerDetails(PreparedMarker marker) {
  final source = <String, dynamic>{
    'id': marker.id,
    'category': marker.category,
    'filterKey': marker.filterKey,
    'name': marker.name,
    'position': {
      'x': marker.position.x,
      'z': marker.position.z,
      if (marker.position.height != null) 'height': marker.position.height,
    },
    'details': marker.details,
    'source': marker.source,
  };
  final writer = _BoundedJsonWriter();
  writer.write(source);
  return BoundedMarkerPreview(
    text: writer.buffer.toString(),
    shortened: writer.shortened,
  );
}

class _BoundedJsonWriter {
  static const _maxBytes = 16 * 1024;
  static const _maxDepth = 16;
  static const _maxNodes = 1024;
  static const _maxCollectionEntries = 128;

  final StringBuffer buffer = StringBuffer();
  var _bytes = 0;
  var _nodes = 0;
  bool shortened = false;
  bool _stopped = false;

  void write(Object? value) => _writeValue(value, 0);

  void _writeValue(Object? value, int depth) {
    if (_stopped) return;
    if (_nodes >= _maxNodes) {
      _stop();
      return;
    }
    _nodes++;
    if (depth > _maxDepth) {
      _stop();
      return;
    }

    if (value == null) {
      _appendAscii('null');
    } else if (value is bool) {
      _appendAscii(value ? 'true' : 'false');
    } else if (value is String) {
      _writeString(value);
    } else if (value is num) {
      _appendAscii(value.toString());
    } else if (value is Map) {
      _writeMap(value, depth);
    } else if (value is List) {
      _writeList(value, depth);
    } else {
      _writeString(value.toString());
    }
  }

  void _writeMap(Map value, int depth) {
    _appendAscii('{');
    if (_stopped) return;
    final limit = value.length < _maxCollectionEntries
        ? value.length
        : _maxCollectionEntries;
    final iterator = value.entries.iterator;
    var emitted = 0;
    while (emitted < limit && !_stopped) {
      if (_nodes >= _maxNodes) {
        _stop();
        return;
      }
      if (!iterator.moveNext()) break;
      if (emitted != 0) _appendAscii(',');
      final entry = iterator.current;
      _writeString(entry.key is String ? entry.key as String : '${entry.key}');
      _appendAscii(':');
      _writeValue(entry.value, depth + 1);
      emitted++;
    }
    if (!_stopped && value.length > _maxCollectionEntries) _stop();
    if (!_stopped) _appendAscii('}');
  }

  void _writeList(List value, int depth) {
    _appendAscii('[');
    if (_stopped) return;
    final limit = value.length < _maxCollectionEntries
        ? value.length
        : _maxCollectionEntries;
    for (var i = 0; i < limit && !_stopped; i++) {
      if (_nodes >= _maxNodes) {
        _stop();
        return;
      }
      if (i != 0) _appendAscii(',');
      _writeValue(value[i], depth + 1);
    }
    if (!_stopped && value.length > _maxCollectionEntries) _stop();
    if (!_stopped) _appendAscii(']');
  }

  void _writeString(String value) {
    _appendAscii('"');
    if (_stopped) return;
    for (final rune in value.runes) {
      if (_stopped) break;
      switch (rune) {
        case 0x22:
          _appendAscii(r'\"');
        case 0x5c:
          _appendAscii(r'\\');
        case 0x08:
          _appendAscii(r'\b');
        case 0x0c:
          _appendAscii(r'\f');
        case 0x0a:
          _appendAscii(r'\n');
        case 0x0d:
          _appendAscii(r'\r');
        case 0x09:
          _appendAscii(r'\t');
        default:
          if (rune < 0x20) {
            final hex = rune.toRadixString(16).padLeft(4, '0');
            _appendAscii('\\u$hex');
          } else {
            _appendRune(rune);
          }
      }
    }
    if (!_stopped) _appendAscii('"');
  }

  void _appendRune(int rune) {
    final byteLength = switch (rune) {
      <= 0x7f => 1,
      <= 0x7ff => 2,
      <= 0xffff => 3,
      _ => 4,
    };
    if (_bytes + byteLength > _maxBytes) {
      _stop();
      return;
    }
    buffer.writeCharCode(rune);
    _bytes += byteLength;
  }

  void _appendAscii(String value) {
    assert(value.codeUnits.every((unit) => unit < 0x80));
    if (_bytes + value.length > _maxBytes) {
      _stop();
      return;
    }
    buffer.write(value);
    _bytes += value.length;
  }

  void _stop() {
    shortened = true;
    _stopped = true;
  }
}

import 'dart:collection';
import 'dart:typed_data';

import 'live_map_budget.dart';
import 'live_map_normalizer.dart';
import 'prepared_map.dart';

/// The compact live-map inventory wire version.
const int liveMapInventoryFormatVersion = 2;

/// Holds immutable prepared markers backed by a shared source-fact graph.
class LiveMapInventory {
  LiveMapInventory._(this._maps, this._retainedMaterializedBytes);

  final Map<String, List<PreparedMarker>> _maps;
  final int _retainedMaterializedBytes;

  /// Builds the compact inventory while the shared normalizer visits markers.
  factory LiveMapInventory.fromSources({
    required LiveMapSourceBodies sources,
    required Iterable<LiveMapBinding> bindings,
    required String mode,
    required LiveMapBudget budget,
  }) {
    final pool = _FactPool(budget);
    try {
      budget.reserveMaterialized(64);
      final maps = <String, List<PreparedMarker>>{};
      normalizeLiveMapData(
        sources: sources,
        bindings: bindings,
        mode: mode,
        reserveMaterialization: budget.reserveMaterialized,
        releaseMaterialization: budget.releaseMaterialized,
        onMarker: (mapId, raw) {
          final marker = _markerFromJson(raw, pool);
          final rows = maps[mapId];
          if (rows == null) {
            budget.reserveMaterialized(_stringBytes(mapId) + 64);
            maps[mapId] = [marker];
          } else {
            budget.reserveMaterialized(24);
            rows.add(marker);
          }
        },
      ).keys.forEach((mapId) {
        if (!maps.containsKey(mapId)) {
          budget.reserveMaterialized(_stringBytes(mapId) + 64);
          maps[mapId] = <PreparedMarker>[];
        }
      });
      return _owned(maps, pool.retainedBytes, 0);
    } finally {
      pool.dispose();
    }
  }

  /// Builds an inventory by reusing prepared markers' immutable fact graphs.
  ///
  /// The caller's [budget] must already account for those borrowed graphs;
  /// this inventory reserves only its own containers and occurrence headers.
  factory LiveMapInventory.fromMarkers({
    required Map<String, List<PreparedMarker>> maps,
    required LiveMapBudget budget,
  }) {
    budget.reserveMaterialized(64);
    final frozen = <String, List<PreparedMarker>>{};
    var retainedReferences = 0;
    for (final entry in maps.entries) {
      budget.reserveMaterialized(
        _stringBytes(entry.key) + 64 + entry.value.length * 24,
      );
      budget.reserveMaterialized(entry.value.length * 32);
      final identities = <String>{};
      final rows = <PreparedMarker>[];
      for (final marker in entry.value) {
        if (!identities.add(marker.id)) {
          throw const FormatException('Duplicate marker identity.');
        }
        final headerBytes = _preparedHeaderBytes(marker);
        budget.reserveMaterialized(headerBytes);
        retainedReferences += headerBytes;
        rows.add(
          PreparedMarker.fromSharedFacts(
            id: marker.id,
            category: marker.category,
            filterKey: marker.filterKey,
            name: marker.name,
            position: marker.position,
            details: marker.details,
            source: marker.source,
            outline: marker.outline,
            floorId: marker.floorId,
            heightBand: marker.heightBand,
          ),
        );
      }
      budget.releaseMaterialized(entry.value.length * 32);
      frozen[entry.key] = rows;
    }
    return _owned(frozen, 0, retainedReferences);
  }

  /// Decodes and validates a compact inventory payload without retaining a
  /// whole-payload JSON tree.
  factory LiveMapInventory.decode(
    Uint8List payload, {
    required LiveMapBudget budget,
  }) {
    if (payload.length > budget.maxSerializedBytes) {
      throw const LiveMapResourceLimitException(
        'Serialized live-map data exceeds its configured limit.',
      );
    }
    final before = budget.materializedBytes;
    budget.reserveMaterialized(128);
    final scanner = _JsonSpanScanner(payload, budget);
    var retainedBytes = 0;
    var success = false;
    final facts = <Object?>[];
    final maps = <String, List<PreparedMarker>>{};
    try {
      final root = scanner.readRoot();
      if (root.version != liveMapInventoryFormatVersion) {
        throw const FormatException(
          'Invalid compact live-map inventory version.',
        );
      }
      for (final span in root.facts) {
        final decoded = _decodeSpan(budget, payload, span);
        try {
          final fact = _materializeFact(decoded.value, facts, budget);
          facts.add(fact.value);
          retainedBytes += fact.bytes;
        } finally {
          budget.releaseMaterialized(decoded.treeBytes);
        }
      }
      for (final mapSpan in root.maps) {
        final decodedKey = _decodeSpan(budget, payload, mapSpan.key);
        late final String mapId;
        try {
          if (decodedKey.value is! String) {
            throw const FormatException('Invalid compact map identifier.');
          }
          mapId = decodedKey.value as String;
          budget.reserveMaterialized(_stringBytes(mapId));
        } finally {
          budget.releaseMaterialized(decodedKey.treeBytes);
        }
        final identityBytes = mapSpan.rows.length * 32;
        final mapAllocation = 64 + mapSpan.rows.length * 24;
        budget.reserveMaterialized(mapAllocation + identityBytes);
        final rows = <PreparedMarker>[];
        final identities = <String>{};
        try {
          for (final rowSpan in mapSpan.rows) {
            final decoded = _decodeSpan(budget, payload, rowSpan);
            try {
              final raw = decoded.value;
              if (raw is! Map<String, dynamic>) {
                throw const FormatException('Invalid compact marker row.');
              }
              if (!raw.containsKey('id') ||
                  !raw.containsKey('category') ||
                  !raw.containsKey('filterKey') ||
                  !raw.containsKey('name') ||
                  !raw.containsKey('position') ||
                  !raw.containsKey('floorId') ||
                  !raw.containsKey('outline') ||
                  !raw.containsKey('heightBand') ||
                  !raw.containsKey('detailsRef') ||
                  !raw.containsKey('sourceRef') ||
                  raw['id'] is! String ||
                  raw['category'] is! String ||
                  raw['filterKey'] is! String ||
                  raw['name'] is! String ||
                  raw['position'] is! Map<String, dynamic> ||
                  (raw['floorId'] != null && raw['floorId'] is! String) ||
                  raw['outline'] is! List ||
                  (raw['heightBand'] != null && raw['heightBand'] is! List)) {
                throw const FormatException(
                  'Missing or invalid marker header.',
                );
              }
              final details = _rootRef(raw['detailsRef'], facts);
              final source = _rootRef(raw['sourceRef'], facts);
              if (details is! Map<String, dynamic> ||
                  source is! Map<String, dynamic>) {
                throw const FormatException(
                  'Invalid compact marker fact references.',
                );
              }
              final headerBytes = _wireHeaderBytes(raw);
              budget.reserveMaterialized(headerBytes);
              retainedBytes += headerBytes;
              final marker = PreparedMarker.fromJsonWithSharedFacts(
                raw,
                details: details,
                source: source,
              );
              if (!identities.add(marker.id)) {
                throw const FormatException(
                  'Duplicate compact marker identity.',
                );
              }
              rows.add(marker);
            } finally {
              budget.releaseMaterialized(decoded.treeBytes);
            }
          }
          maps[mapId] = rows;
          budget.releaseMaterialized(identityBytes);
        } catch (_) {
          budget.releaseMaterialized(mapAllocation + identityBytes);
          rethrow;
        }
      }
      final copyBytes =
          64 +
          maps.entries.fold<int>(
            0,
            (total, entry) => total + 64 + entry.value.length * 24,
          );
      budget.reserveMaterialized(copyBytes);
      final result = _owned(maps, retainedBytes, 0);
      budget.releaseMaterialized(
        64 +
            maps.entries.fold<int>(
              0,
              (total, entry) => total + 64 + entry.value.length * 24,
            ),
      );
      success = true;
      return result;
    } finally {
      if (!success) {
        final outstanding = budget.materializedBytes - before;
        if (outstanding > 0) {
          budget.releaseMaterialized(outstanding - scanner.scratchBytes);
        }
      }
      budget.releaseMaterialized(scanner.scratchBytes);
    }
  }

  /// The immutable prepared marker maps.
  Map<String, List<PreparedMarker>> get maps => _maps;

  /// The conservatively charged owned facts, containers, and occurrence references.
  ///
  /// Borrowed fact graphs are excluded and remain accounted for by their owner.
  int get retainedMaterializedBytes => _retainedMaterializedBytes;

  /// Reserves this inventory's owned facts, containers, and occurrence references.
  void reserveRetained(LiveMapBudget budget) {
    budget.reserveMaterialized(_retainedMaterializedBytes);
  }

  /// Encodes the inventory using the compact versioned wire representation.
  Uint8List encode({required LiveMapBudget budget}) {
    final wireBytes = _wireMaterializationBytes(budget);
    budget.reserveMaterialized(wireBytes);
    try {
      final facts = <Object?>[];
      final indexes = HashMap<Object, int>.identity();
      final completed = HashSet<Object>.identity();
      int collect(Object? value) {
        if (value is! Map && value is! List) {
          throw const FormatException('Fact roots must be maps or lists.');
        }
        final root = value as Object;
        if (indexes.containsKey(root)) return indexes[root]!;
        final active = HashSet<Object>.identity();
        final stack = <_EncodeFrame>[];
        active.add(root);
        stack.add(_EncodeFrame(root));
        while (stack.isNotEmpty) {
          final frame = stack.last;
          if (!frame.iterator.moveNext()) {
            stack.removeLast();
            active.remove(frame.value);
            if (completed.add(frame.value)) {
              final index = facts.length;
              indexes[frame.value] = index;
              facts.add(_encodeFactNode(frame.value, indexes));
            }
            continue;
          }
          final item = frame.iterator.current;
          final child = frame.value is Map ? (item as MapEntry).value : item;
          if (frame.value is Map && (item as MapEntry).key is! String) {
            throw const FormatException('Live-map fact keys must be strings.');
          }
          if (child is Map || child is List) {
            final node = child as Object;
            if (active.contains(node)) {
              throw const FormatException('Cyclic live-map facts are invalid.');
            }
            if (!completed.contains(node)) {
              active.add(node);
              stack.add(_EncodeFrame(node));
            }
          } else {
            _validateScalar(child);
          }
        }
        return indexes[root]!;
      }

      final maps = <String, Object?>{};
      for (final entry in _maps.entries) {
        maps[entry.key] = [
          for (final marker in entry.value)
            {
              'id': marker.id,
              'category': marker.category,
              'filterKey': marker.filterKey,
              'name': marker.name,
              'position': {
                'x': marker.position.x,
                'z': marker.position.z,
                if (marker.position.height != null)
                  'height': marker.position.height,
              },
              'floorId': marker.floorId,
              'outline': [
                for (final point in marker.outline)
                  {
                    'x': point.x,
                    'z': point.z,
                    if (point.height != null) 'height': point.height,
                  },
              ],
              'heightBand': marker.heightBand == null
                  ? null
                  : [marker.heightBand!.min, marker.heightBand!.max],
              'detailsRef': collect(marker.details),
              'sourceRef': collect(marker.source),
            },
        ];
      }
      return budget.encodeJson({
        'version': liveMapInventoryFormatVersion,
        'facts': facts,
        'maps': maps,
      });
    } finally {
      budget.releaseMaterialized(wireBytes);
    }
  }

  int _wireMaterializationBytes(LiveMapBudget budget) {
    var scratchBytes = 128;
    budget.reserveMaterialized(scratchBytes);
    final seen = HashSet<Object>.identity();
    var bytes = 256;
    try {
      for (final entry in _maps.entries) {
        bytes += 64 + entry.value.length * 384;
        for (final marker in entry.value) {
          bytes += marker.outline.length * 96;
        }
      }

      final pending = <Object>[];
      void visit(Object? value) {
        if (value is Map || value is List) {
          final node = value as Object;
          if (seen.contains(node)) return;
          budget.reserveMaterialized(32);
          scratchBytes += 32;
          seen.add(node);
          pending.add(node);
          bytes += value is Map
              ? 160 + value.length * 128
              : 128 + (value as List).length * 32;
        } else if (value is String) {
          // The existing fact graph owns this immutable string.
        } else {
          bytes += 16;
        }
      }

      for (final entry in _maps.values) {
        for (final marker in entry) {
          visit(marker.details);
          visit(marker.source);
        }
      }
      while (pending.isNotEmpty) {
        final value = pending.removeLast();
        if (value is Map) {
          for (final entry in value.entries) {
            visit(entry.value);
          }
        } else {
          for (final item in value as List) {
            visit(item);
          }
        }
      }
      return bytes;
    } finally {
      budget.releaseMaterialized(scratchBytes);
    }
  }

  static LiveMapInventory _owned(
    Map<String, List<PreparedMarker>> maps,
    int retainedFacts,
    int references,
  ) {
    final frozen = Map<String, List<PreparedMarker>>.unmodifiable({
      for (final entry in maps.entries)
        entry.key: List<PreparedMarker>.unmodifiable(entry.value),
    });
    final retained =
        retainedFacts +
        references +
        64 +
        maps.entries.fold<int>(
          0,
          (bytes, entry) =>
              bytes + _stringBytes(entry.key) + 64 + entry.value.length * 24,
        );
    return LiveMapInventory._(frozen, retained);
  }
}

class _EncodeFrame {
  _EncodeFrame(this.value)
    : iterator = value is Map
          ? value.entries.iterator
          : (value as List).iterator;

  final Object value;
  final Iterator<dynamic> iterator;
}

Object _encodeFactNode(Object value, Map<Object, int> indexes) {
  Object? encode(Object? child) {
    if (child is Map || child is List) {
      final index = indexes[child as Object];
      if (index == null) {
        throw const FormatException('Fact references must point backward.');
      }
      return [1, index];
    }
    _validateScalar(child);
    return child;
  }

  if (value is Map) {
    final entries = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw const FormatException('Live-map fact keys must be strings.');
      }
      entries[entry.key as String] = encode(entry.value);
    }
    return {'kind': 'map', 'entries': entries};
  }
  return {
    'kind': 'list',
    'items': [for (final child in value as List) encode(child)],
  };
}

Object? _rootRef(Object? reference, List<Object?> facts) {
  if (reference is! int || reference < 0 || reference >= facts.length) {
    throw const FormatException('Compact fact reference is out of range.');
  }
  return facts[reference];
}

_DecodedSpan _decodeSpan(
  LiveMapBudget budget,
  Uint8List payload,
  _JsonSpan span,
) {
  final view = Uint8List.sublistView(payload, span.start, span.end);
  final before = budget.materializedBytes;
  try {
    final value = budget.decodeJson(view, maxBytes: view.length);
    return _DecodedSpan(value, budget.materializedBytes - before);
  } catch (_) {
    final outstanding = budget.materializedBytes - before;
    if (outstanding > 0) budget.releaseMaterialized(outstanding);
    rethrow;
  }
}

_FactResult _materializeFact(
  Object? raw,
  List<Object?> facts,
  LiveMapBudget budget,
) {
  if (raw is! Map<String, dynamic>) {
    throw const FormatException('Invalid compact fact.');
  }
  final kind = raw['kind'];
  final mapKind = kind == 'map' && raw['entries'] is Map<String, dynamic>;
  final listKind = kind == 'list' && raw['items'] is List;
  if (raw.length != 2 || (!mapKind && !listKind)) {
    throw const FormatException('Invalid compact fact kind or body.');
  }
  var bytes =
      64 +
      (mapKind
          ? 48 + (raw['entries']! as Map<String, dynamic>).length * 32
          : 32 + (raw['items']! as List).length * 16);
  Object? resolve(Object? encoded, {bool account = false}) {
    if (encoded is List) {
      if (encoded.length != 2 ||
          encoded[0] != 1 ||
          encoded[0] is! int ||
          encoded[1] is! int ||
          (encoded[1] as int) < 0 ||
          (encoded[1] as int) >= facts.length) {
        throw const FormatException(
          'Compact facts must reference completed earlier facts.',
        );
      }
      return facts[encoded[1] as int];
    }
    if (!(encoded == null ||
        encoded is String ||
        encoded is bool ||
        encoded is num && encoded.isFinite)) {
      throw const FormatException('Invalid compact fact scalar.');
    }
    if (account) bytes += encoded is String ? _stringBytes(encoded) : 8;
    return encoded;
  }

  if (mapKind) {
    final rawEntries = raw['entries']! as Map<String, dynamic>;
    for (final entry in rawEntries.entries) {
      bytes += _stringBytes(entry.key);
      // Validate and account every value before creating the owned map.
      resolve(entry.value, account: true);
    }
    budget.reserveMaterialized(bytes);
    final scratch = 48 + rawEntries.length * 32;
    budget.reserveMaterialized(scratch);
    try {
      final owned = <String, Object?>{
        for (final entry in rawEntries.entries) entry.key: resolve(entry.value),
      };
      return _FactResult(Map<String, dynamic>.unmodifiable(owned), bytes);
    } finally {
      budget.releaseMaterialized(scratch);
    }
  }
  final rawItems = raw['items']! as List;
  for (final encoded in rawItems) {
    resolve(encoded, account: true);
  }
  budget.reserveMaterialized(bytes);
  final scratch = 32 + rawItems.length * 16;
  budget.reserveMaterialized(scratch);
  try {
    final owned = <Object?>[for (final encoded in rawItems) resolve(encoded)];
    return _FactResult(List<Object?>.unmodifiable(owned), bytes);
  } finally {
    budget.releaseMaterialized(scratch);
  }
}

class _DecodedSpan {
  const _DecodedSpan(this.value, this.treeBytes);

  final Object? value;
  final int treeBytes;
}

class _FactResult {
  const _FactResult(this.value, this.bytes);

  final Object value;
  final int bytes;
}

class _JsonSpan {
  const _JsonSpan(this.start, this.end);

  final int start;
  final int end;
}

class _MapRowsSpan {
  const _MapRowsSpan(this.key, this.rows);

  final _JsonSpan key;
  final List<_JsonSpan> rows;
}

class _JsonRootSpans {
  const _JsonRootSpans(this.version, this.facts, this.maps);

  final int version;
  final List<_JsonSpan> facts;
  final List<_MapRowsSpan> maps;
}

class _JsonSpanScanner {
  _JsonSpanScanner(this.bytes, this.budget);

  final Uint8List bytes;
  final LiveMapBudget budget;
  int offset = 0;
  int scratchBytes = 64;

  _JsonSpan _span(int start, int end) {
    budget.reserveMaterialized(32);
    scratchBytes += 32;
    return _JsonSpan(start, end);
  }

  _JsonRootSpans readRoot() {
    budget.reserveMaterialized(128);
    scratchBytes += 128;
    _space();
    _expect(123);
    _space();
    final seen = <String>{};
    int? version;
    List<_JsonSpan>? facts;
    List<_MapRowsSpan>? maps;
    if (_take(125)) throw const FormatException('Empty compact inventory.');
    while (true) {
      final keySpan = _stringSpan();
      final decodedKey = _decodeSpan(budget, bytes, keySpan);
      late final String key;
      try {
        if (decodedKey.value is! String) {
          throw const FormatException('Invalid compact inventory root key.');
        }
        key = decodedKey.value as String;
        budget.reserveMaterialized(_stringBytes(key));
        scratchBytes += _stringBytes(key);
      } finally {
        budget.releaseMaterialized(decodedKey.treeBytes);
      }
      if (!seen.add(key)) {
        throw const FormatException('Invalid compact inventory root key.');
      }
      _space();
      _expect(58);
      _space();
      switch (key) {
        case 'version':
          final value = _valueSpan();
          final decoded = _decodeSpan(budget, bytes, value);
          try {
            if (decoded.value is! int) {
              throw const FormatException('Invalid compact inventory version.');
            }
            version = decoded.value as int;
          } finally {
            budget.releaseMaterialized(decoded.treeBytes);
          }
        case 'facts':
          facts = _arraySpans();
        case 'maps':
          maps = _mapRowsSpans();
        default:
          throw const FormatException('Unknown compact inventory root field.');
      }
      _space();
      if (_take(125)) break;
      _expect(44);
      _space();
    }
    _space();
    if (offset != bytes.length ||
        version == null ||
        facts == null ||
        maps == null) {
      throw const FormatException('Invalid compact inventory root structure.');
    }
    return _JsonRootSpans(version, facts, maps);
  }

  List<_JsonSpan> _arraySpans() {
    _expect(91);
    _space();
    budget.reserveMaterialized(64);
    scratchBytes += 64;
    final values = <_JsonSpan>[];
    if (_take(93)) return values;
    while (true) {
      budget.reserveMaterialized(16);
      scratchBytes += 16;
      values.add(_valueSpan());
      _space();
      if (_take(93)) return values;
      _expect(44);
      _space();
    }
  }

  List<_MapRowsSpan> _mapRowsSpans() {
    _expect(123);
    _space();
    budget.reserveMaterialized(128);
    scratchBytes += 128;
    final values = <_MapRowsSpan>[];
    final keys = <String>{};
    if (_take(125)) return values;
    while (true) {
      final key = _stringSpan();
      final decodedKey = _decodeSpan(budget, bytes, key);
      late final String decoded;
      try {
        if (decodedKey.value is! String) {
          throw const FormatException('Invalid compact map key.');
        }
        decoded = decodedKey.value as String;
        budget.reserveMaterialized(_stringBytes(decoded));
        scratchBytes += _stringBytes(decoded);
      } finally {
        budget.releaseMaterialized(decodedKey.treeBytes);
      }
      if (!keys.add(decoded)) {
        throw const FormatException('Duplicate compact map key.');
      }
      _space();
      _expect(58);
      _space();
      budget.reserveMaterialized(32);
      scratchBytes += 32;
      values.add(_MapRowsSpan(key, _arraySpans()));
      _space();
      if (_take(125)) return values;
      _expect(44);
      _space();
    }
  }

  _JsonSpan _valueSpan() {
    _space();
    final start = offset;
    if (offset >= bytes.length) {
      throw const FormatException('Missing JSON value.');
    }
    final first = bytes[offset];
    if (first == 34) {
      _stringSpan();
      return _span(start, offset);
    }
    if (first != 123 && first != 91) {
      while (offset < bytes.length &&
          bytes[offset] != 44 &&
          bytes[offset] != 93 &&
          bytes[offset] != 125 &&
          bytes[offset] != 32 &&
          bytes[offset] != 9 &&
          bytes[offset] != 10 &&
          bytes[offset] != 13) {
        offset++;
      }
      if (offset == start) throw const FormatException('Invalid JSON value.');
      return _span(start, offset);
    }
    budget.reserveMaterialized(64);
    scratchBytes += 64;
    var stackBytes = 64;
    final stack = <int>[];
    try {
      while (offset < bytes.length) {
        final byte = bytes[offset];
        if (byte == 34) {
          _stringSpan();
          continue;
        }
        if (byte == 123 || byte == 91) {
          budget.reserveMaterialized(8);
          scratchBytes += 8;
          stackBytes += 8;
          stack.add(byte);
        } else if (byte == 125 || byte == 93) {
          if (stack.isEmpty ||
              (byte == 125 && stack.removeLast() != 123) ||
              (byte == 93 && stack.removeLast() != 91)) {
            throw const FormatException('Mismatched JSON container.');
          }
          budget.releaseMaterialized(8);
          scratchBytes -= 8;
          stackBytes -= 8;
          if (stack.isEmpty) {
            offset++;
            budget.releaseMaterialized(stackBytes);
            scratchBytes -= stackBytes;
            stackBytes = 0;
            return _span(start, offset);
          }
        }
        offset++;
      }
      throw const FormatException('Unclosed JSON container.');
    } finally {
      if (stackBytes > 0) {
        budget.releaseMaterialized(stackBytes);
        scratchBytes -= stackBytes;
      }
    }
  }

  _JsonSpan _stringSpan() {
    _space();
    final start = offset;
    _expect(34);
    var escaped = false;
    while (offset < bytes.length) {
      final byte = bytes[offset++];
      if (escaped) {
        escaped = false;
      } else if (byte == 92) {
        escaped = true;
      } else if (byte == 34) {
        return _span(start, offset);
      } else if (byte < 32) {
        throw const FormatException('Invalid JSON string control byte.');
      }
    }
    throw const FormatException('Unclosed JSON string.');
  }

  void _space() {
    while (offset < bytes.length &&
        (bytes[offset] == 32 ||
            bytes[offset] == 9 ||
            bytes[offset] == 10 ||
            bytes[offset] == 13)) {
      offset++;
    }
  }

  bool _take(int byte) {
    if (offset < bytes.length && bytes[offset] == byte) {
      offset++;
      return true;
    }
    return false;
  }

  void _expect(int byte) {
    if (!_take(byte)) throw const FormatException('Invalid JSON punctuation.');
  }
}

PreparedMarker _markerFromJson(Map<String, Object?> raw, _FactPool pool) {
  final headerBytes = _wireHeaderBytes(raw);
  pool.retainHeader(headerBytes);
  final details = pool.freezeMap(raw['details']! as Map<String, dynamic>);
  final source = pool.freezeMap(raw['source']! as Map<String, dynamic>);
  return PreparedMarker.fromJsonWithSharedFacts(
    raw,
    details: details,
    source: source,
  );
}

int _wireHeaderBytes(Map<String, dynamic> raw) =>
    320 +
    ['id', 'category', 'filterKey', 'name', 'floorId'].fold<int>(
      0,
      (bytes, key) =>
          bytes + (raw[key] is String ? _stringBytes(raw[key] as String) : 0),
    ) +
    (raw['outline'] is List ? (raw['outline']! as List).length * 48 : 0);

int _preparedHeaderBytes(PreparedMarker marker) =>
    320 +
    _stringBytes(marker.id) +
    _stringBytes(marker.category) +
    _stringBytes(marker.filterKey) +
    _stringBytes(marker.name) +
    (marker.floorId == null ? 0 : _stringBytes(marker.floorId!)) +
    marker.outline.length * 48;

class _FactFrame {
  _FactFrame(this.value)
    : iterator = value is Map
          ? value.values.iterator
          : (value as List).iterator;

  final Object value;
  final Iterator<dynamic> iterator;
}

class _FactPool {
  _FactPool(this._budget) {
    _budget.reserveMaterialized(64);
    _poolScratchBytes = 64;
    _frozen = HashMap<Object, Object>.identity();
  }

  final LiveMapBudget _budget;
  late final HashMap<Object, Object> _frozen;
  int _poolScratchBytes = 0;
  int retainedBytes = 0;

  void retainHeader(int bytes) {
    _budget.reserveMaterialized(bytes);
    retainedBytes += bytes;
  }

  Map<String, dynamic> freezeMap(Map<String, dynamic> value) =>
      freeze(value) as Map<String, dynamic>;

  void dispose() {
    if (_poolScratchBytes == 0) return;
    _budget.releaseMaterialized(_poolScratchBytes);
    _poolScratchBytes = 0;
  }

  Object freeze(Object value) {
    if (value is! Map && value is! List) {
      _validateScalar(value);
      return value;
    }
    final existing = _frozen[value];
    if (existing != null) return existing;

    var scratchBytes = 128;
    var factBytes = 0;
    var poolBytes = 0;
    var poolReservationMade = false;
    _budget.reserveMaterialized(scratchBytes);
    final toCharge = HashSet<Object>.identity();
    final visiting = HashSet<Object>.identity();
    final order = <Object>[];

    void reserveFact(int bytes) {
      _budget.reserveMaterialized(bytes);
      factBytes += bytes;
    }

    void measure(Object? current) {
      final stack = <_FactFrame>[];

      void push(Object node) {
        if (_frozen.containsKey(node)) return;
        if (visiting.contains(node)) {
          throw const FormatException('Cyclic live-map facts are invalid.');
        }
        if (toCharge.contains(node)) return;
        _budget.reserveMaterialized(64);
        scratchBytes += 64;
        toCharge.add(node);
        visiting.add(node);
        reserveFact(_factNodeRetainedBytes(node));
        stack.add(_FactFrame(node));
      }

      if (current is Map || current is List) {
        push(current as Object);
      } else {
        _validateScalar(current);
      }
      while (stack.isNotEmpty) {
        final frame = stack.last;
        if (!frame.iterator.moveNext()) {
          visiting.remove(frame.value);
          order.add(frame.value);
          stack.removeLast();
          continue;
        }
        final child = frame.iterator.current;
        if (child is Map || child is List) {
          final node = child as Object;
          if (visiting.contains(node)) {
            throw const FormatException('Cyclic live-map facts are invalid.');
          }
          push(node);
        } else {
          _validateScalar(child);
        }
      }
    }

    try {
      measure(value);
      // Identity keys keep the original input graphs alive until disposal.
      poolBytes = toCharge.length * 32 + factBytes;
      _budget.reserveMaterialized(poolBytes);
      poolReservationMade = true;
      final copied = <Object>[];
      try {
        for (final node in order) {
          final source = node;
          Object frozen;
          if (source is Map) {
            _budget.reserveMaterialized(48 + source.length * 32);
            try {
              final result = <String, dynamic>{};
              for (final entry in source.entries) {
                result[entry.key as String] = _frozenValue(entry.value);
              }
              frozen = Map<String, dynamic>.unmodifiable(result);
            } finally {
              _budget.releaseMaterialized(48 + source.length * 32);
            }
          } else {
            final sourceList = source as List;
            _budget.reserveMaterialized(32 + sourceList.length * 16);
            try {
              frozen = List<Object?>.unmodifiable([
                for (final item in sourceList) _frozenValue(item),
              ]);
            } finally {
              _budget.releaseMaterialized(32 + sourceList.length * 16);
            }
          }
          _frozen[source] = frozen;
          copied.add(source);
        }
      } catch (_) {
        for (final node in copied) {
          _frozen.remove(node);
        }
        rethrow;
      }
      _poolScratchBytes += poolBytes;
      retainedBytes += factBytes;
      return _frozen[value]!;
    } catch (_) {
      if (poolReservationMade) _budget.releaseMaterialized(poolBytes);
      if (factBytes > 0) _budget.releaseMaterialized(factBytes);
      rethrow;
    } finally {
      _budget.releaseMaterialized(scratchBytes);
    }
  }

  Object? _frozenValue(Object? value) {
    if (value is Map || value is List) return _frozen[value];
    _validateScalar(value);
    return value;
  }
}

int _factNodeRetainedBytes(Object value) {
  if (value is Map) {
    var bytes = 48 + value.length * 32;
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw const FormatException('Live-map fact keys must be strings.');
      }
      bytes += _stringBytes(entry.key as String);
      if (entry.value is! Map && entry.value is! List) {
        bytes += _scalarBytes(entry.value);
      }
    }
    return bytes;
  }
  final values = value as List;
  var bytes = 32 + values.length * 16;
  for (final item in values) {
    if (item is! Map && item is! List) bytes += _scalarBytes(item);
  }
  return bytes;
}

void _validateScalar(Object? value) {
  if (!(value == null ||
      value is String ||
      value is bool ||
      value is num && value.isFinite)) {
    throw const FormatException('Unsupported live-map fact value.');
  }
}

int _scalarBytes(Object? value) => value is String ? _stringBytes(value) : 8;

int _stringBytes(String value) => 16 + value.length * 2;

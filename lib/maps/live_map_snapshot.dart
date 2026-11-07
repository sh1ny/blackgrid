import 'dart:convert';
import 'dart:typed_data';

import '../domain/catalog.dart';
import 'live_map_normalizer.dart';
import 'prepared_map.dart';

/// Identifies one of the six source bodies that make up a live-map snapshot.
enum LiveMapSourceDataset {
  maps('maps'),
  mapTranslations('maps_en'),
  tasks('tasks'),
  taskTranslations('tasks_en'),
  traders('traders'),
  traderTranslations('traders_en');

  const LiveMapSourceDataset(this.path);

  /// The endpoint name under a json.tarkov.dev mode route.
  final String path;
}

/// One exact source response and its optional revalidation headers.
class LiveMapSourceBody {
  /// Creates a source body.
  const LiveMapSourceBody({
    required this.dataset,
    required this.bytes,
    this.etag,
    this.lastModified,
  });

  /// The source this body belongs to.
  final LiveMapSourceDataset dataset;

  /// The exact response bytes.
  final Uint8List bytes;

  /// The ETag header, when the server supplied one.
  final String? etag;

  /// The Last-Modified header, when the server supplied one.
  final String? lastModified;
}

/// A complete set of six source bodies for one game mode.
///
/// Only the sources are stored. Markers are derived from them with the
/// current normalizer and prepared pack each time the snapshot is used, so a
/// snapshot never goes stale against a new normalizer or calibration.
class LiveMapSnapshot {
  /// Creates a snapshot; [sources] must hold every dataset exactly once.
  LiveMapSnapshot({
    required this.mode,
    required this.checkedAt,
    required Iterable<LiveMapSourceBody> sources,
  }) : sources = Map.unmodifiable({
         for (final source in sources) source.dataset: source,
       }) {
    if (this.sources.length != LiveMapSourceDataset.values.length) {
      throw ArgumentError.value(
        sources,
        'sources',
        'A live-map snapshot needs all six sources exactly once.',
      );
    }
  }

  /// The game mode these sources were downloaded for.
  final GameMode mode;

  /// When the sources were last confirmed against the server.
  final DateTime checkedAt;

  /// The source bodies by dataset.
  final Map<LiveMapSourceDataset, LiveMapSourceBody> sources;

  /// Whether [other] holds byte-identical source bodies.
  bool sameContent(LiveMapSnapshot? other) {
    if (other == null) return false;
    for (final dataset in LiveMapSourceDataset.values) {
      final left = sources[dataset]!.bytes;
      final right = other.sources[dataset]!.bytes;
      if (identical(left, right)) continue;
      if (left.length != right.length) return false;
      for (var i = 0; i < left.length; i++) {
        if (left[i] != right[i]) return false;
      }
    }
    return true;
  }
}

/// Durable per-mode storage for the last good snapshot.
abstract interface class LiveMapStore {
  /// Reads the stored snapshot for [mode], or `null` when there is none.
  Future<LiveMapSnapshot?> read(GameMode mode);

  /// Replaces the stored snapshot for its mode atomically.
  Future<void> commit(LiveMapSnapshot snapshot);
}

/// The json.tarkov.dev route for a supported game mode.
String liveMapRoute(GameMode mode) => switch (mode) {
  GameMode.pvp => 'regular',
  GameMode.pve => 'pve',
  GameMode.seasonal => 'pvp-season',
  GameMode.unknown => throw ArgumentError.value(mode, 'mode'),
};

/// Derives the marker inventory for every bound prepared map from [sources].
///
/// This decodes and normalizes the complete set, so it is meant to run off the
/// UI isolate. Facts shared between markers, such as a quest's task record,
/// stay shared in the result instead of being copied per marker. Throws a
/// [FormatException] when a source is malformed.
Map<String, List<PreparedMarker>> buildLiveMarkers({
  required Map<LiveMapSourceDataset, Uint8List> sources,
  required List<LiveMapBinding> bindings,
  required GameMode mode,
}) {
  Map<String, dynamic> decode(LiveMapSourceDataset dataset) {
    final bytes = sources[dataset];
    if (bytes == null) {
      throw FormatException('${dataset.path}: source is missing');
    }
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, dynamic>) {
      throw FormatException('${dataset.path}: root must be an object');
    }
    return value;
  }

  final normalized = normalizeLiveMapData(
    sources: LiveMapSourceBodies(
      maps: decode(LiveMapSourceDataset.maps),
      mapTranslations: decode(LiveMapSourceDataset.mapTranslations),
      tasks: decode(LiveMapSourceDataset.tasks),
      taskTranslations: decode(LiveMapSourceDataset.taskTranslations),
      traders: decode(LiveMapSourceDataset.traders),
      traderTranslations: decode(LiveMapSourceDataset.traderTranslations),
    ),
    bindings: bindings,
    mode: liveMapRoute(mode),
  );
  final shared = Map<Object, Object>.identity();
  return {
    for (final MapEntry(key: mapId, value: raw) in normalized.entries)
      mapId: _markers(mapId, raw, shared),
  };
}

List<PreparedMarker> _markers(
  String mapId,
  List<Map<String, Object?>> raw,
  Map<Object, Object> shared,
) {
  final ids = <String>{};
  final markers = <PreparedMarker>[];
  for (final json in raw) {
    final marker = PreparedMarker.fromJson(json, shared: shared);
    if (!ids.add(marker.id)) {
      throw FormatException('$mapId: duplicate marker ${marker.id}');
    }
    markers.add(marker);
  }
  return List.unmodifiable(markers);
}

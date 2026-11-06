import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../domain/catalog.dart';
import '../maps/live_map_budget.dart';
import '../maps/live_map_normalizer.dart';
import '../maps/live_map_snapshot.dart';
import 'database.dart';

const int _maxSourceBodyBytes = 16 * 1024 * 1024;
const int _maxAggregateSourceBytes = 64 * 1024 * 1024;
const int _maxNormalizedPayloadBytes = 64 * 1024 * 1024;

/// Stores complete, independently replaceable live-map snapshots by mode.
class LiveMapCacheStore implements LiveMapStore {
  /// Creates a cache backed by [database].
  LiveMapCacheStore({required BlackgridDatabase database})
    : _database = database;

  final BlackgridDatabase _database;

  @override
  Future<LiveMapSnapshot?> read(
    GameMode mode, {
    required LiveMapCompatibility compatibility,
    void Function(Object failure)? onRejected,
  }) async {
    LiveMapSnapshot? reject(String message) {
      onRejected?.call(FormatException(message));
      return null;
    }

    if (!_supportedMode(mode)) return null;
    final rows = await _database
        .customSelect(
          'SELECT mode, checked_at, format_version, normalizer_version, '
          'compatibility_fingerprint, normalized_sha256, '
          'length(normalized_payload) AS payload_length '
          'FROM live_map_snapshots WHERE mode = ?',
          variables: [Variable<int>(mode.index)],
        )
        .get();
    if (rows.isEmpty) return null;
    if (rows.length != 1) return reject('Duplicate live-map snapshot rows.');
    final row = rows.single.data;
    final payloadLength = row['payload_length'];
    if (payloadLength is! int ||
        payloadLength < 0 ||
        payloadLength > _maxNormalizedPayloadBytes ||
        row['compatibility_fingerprint'] != compatibility.fingerprint ||
        row['format_version'] != liveMapSnapshotFormatVersion ||
        row['normalizer_version'] != liveMapNormalizerVersion) {
      return reject('Live-map snapshot is incompatible or oversized.');
    }

    final budget = LiveMapBudget();
    budget.reserveMaterialized(payloadLength);
    final payloadRows = await _database
        .customSelect(
          'SELECT normalized_payload FROM live_map_snapshots WHERE mode = ?',
          variables: [Variable<int>(mode.index)],
        )
        .get();
    if (payloadRows.length != 1) {
      return reject('Live-map normalized payload is missing.');
    }
    final payload = payloadRows.single.read<Uint8List>('normalized_payload');
    if (payload.length != payloadLength ||
        _digest(payload) != row['normalized_sha256']) {
      return reject('Live-map normalized payload integrity check failed.');
    }

    final sourceRows = await _database
        .customSelect(
          'SELECT dataset, body_sha256, etag, last_modified, length(body) '
          'AS body_length FROM live_map_sources WHERE mode = ? ORDER BY dataset',
          variables: [Variable<int>(mode.index)],
        )
        .get();
    if (sourceRows.length != LiveMapSourceDataset.values.length) {
      return reject('Live-map source inventory is incomplete.');
    }
    final seen = <LiveMapSourceDataset>{};
    var aggregateBytes = 0;
    for (final sourceRow in sourceRows) {
      final data = sourceRow.data;
      final dataset = _dataset(data['dataset']);
      final length = data['body_length'];
      if (dataset == null ||
          !seen.add(dataset) ||
          length is! int ||
          length < 0 ||
          length > _maxSourceBodyBytes) {
        return reject('Live-map source inventory is invalid or oversized.');
      }
      aggregateBytes += length;
      if (aggregateBytes > _maxAggregateSourceBytes) {
        return reject('Live-map source inventory exceeds aggregate limit.');
      }
    }
    if (seen.length != LiveMapSourceDataset.values.length) {
      return reject('Live-map source inventory is incomplete.');
    }
    budget.reserveMaterialized(aggregateBytes);
    final sources = <LiveMapSourceBody>[];
    for (final metadata in sourceRows) {
      final data = metadata.data;
      final bodyRows = await _database
          .customSelect(
            'SELECT body FROM live_map_sources WHERE mode = ? AND dataset = ?',
            variables: [
              Variable<int>(mode.index),
              Variable<String>(data['dataset']! as String),
            ],
          )
          .get();
      if (bodyRows.length != 1) {
        return reject('Live-map source body is missing.');
      }
      final bytes = bodyRows.single.read<Uint8List>('body');
      final length = data['body_length']! as int;
      if (bytes.length != length || _digest(bytes) != data['body_sha256']) {
        return reject('Live-map source body integrity check failed.');
      }
      sources.add(
        LiveMapSourceBody(
          dataset: _dataset(data['dataset'])!,
          bytes: bytes,
          etag: data['etag'] as String?,
          lastModified: data['last_modified'] as String?,
          budget: budget,
        ),
      );
    }

    if (!_hasValidInventory(payload, compatibility.preparedMapIds, budget)) {
      return reject('Normalized live-map inventory is invalid.');
    }
    final checkedAtMicros = row['checked_at'];
    if (checkedAtMicros is! int) {
      return reject('Live-map check time is invalid.');
    }
    return LiveMapSnapshot(
      mode: mode,
      checkedAt: DateTime.fromMicrosecondsSinceEpoch(
        checkedAtMicros,
        isUtc: true,
      ),
      normalizedPayload: payload,
      sources: sources,
      formatVersion: row['format_version']! as int,
      normalizerVersion: row['normalizer_version']! as int,
      compatibility: compatibility,
      budget: budget,
    );
  }

  @override
  Future<void> commit(LiveMapSnapshot snapshot) async {
    if (!_supportedMode(snapshot.mode)) {
      throw ArgumentError.value(snapshot.mode, 'snapshot.mode');
    }
    _validateCandidate(snapshot);
    final mode = snapshot.mode.index;
    await _database.transaction(() async {
      await _database
          .into(_database.liveMapSnapshots)
          .insertOnConflictUpdate(
            LiveMapSnapshotsCompanion.insert(
              mode: Value(mode),
              checkedAt: snapshot.checkedAt.toUtc().microsecondsSinceEpoch,
              formatVersion: snapshot.formatVersion,
              normalizerVersion: snapshot.normalizerVersion,
              compatibilityFingerprint: snapshot.compatibility.fingerprint,
              normalizedPayload: snapshot.normalizedPayload,
              normalizedSha256: snapshot.normalizedSha256,
            ),
          );
      await (_database.delete(
        _database.liveMapSources,
      )..where((row) => row.mode.equals(mode))).go();
      for (final source in snapshot.sources) {
        await _database
            .into(_database.liveMapSources)
            .insert(
              LiveMapSourcesCompanion.insert(
                mode: mode,
                dataset: source.dataset.name,
                body: source.bytes,
                bodySha256: source.sha256,
                etag: Value(source.etag),
                lastModified: Value(source.lastModified),
              ),
            );
      }
    });
  }

  void _validateCandidate(LiveMapSnapshot snapshot) {
    if (snapshot.formatVersion != liveMapSnapshotFormatVersion ||
        snapshot.normalizerVersion != liveMapNormalizerVersion) {
      throw ArgumentError('Unsupported live-map snapshot version.');
    }
    if (snapshot.sources.length != LiveMapSourceDataset.values.length ||
        snapshot.sources.map((source) => source.dataset).toSet().length !=
            LiveMapSourceDataset.values.length) {
      throw ArgumentError('A live-map snapshot requires six unique sources.');
    }
    var sourceBytes = 0;
    for (final source in snapshot.sources) {
      if (source.bytes.length > _maxSourceBodyBytes) {
        throw ArgumentError('A live-map source exceeds the body size limit.');
      }
      sourceBytes += source.bytes.length;
    }
    if (sourceBytes > _maxAggregateSourceBytes ||
        snapshot.normalizedPayload.length > _maxNormalizedPayloadBytes) {
      throw ArgumentError('A live-map snapshot exceeds its size limit.');
    }
    if (_digest(snapshot.normalizedPayload) != snapshot.normalizedSha256 ||
        !_hasValidInventory(
          snapshot.normalizedPayload,
          snapshot.compatibility.preparedMapIds,
          snapshot.budget,
        )) {
      throw ArgumentError('Invalid normalized live-map inventory.');
    }
    for (final source in snapshot.sources) {
      if (_digest(source.bytes) != source.sha256) {
        throw ArgumentError('Invalid live-map source digest.');
      }
    }
  }
}

bool _supportedMode(GameMode mode) =>
    mode == GameMode.pvp || mode == GameMode.pve || mode == GameMode.seasonal;

LiveMapSourceDataset? _dataset(Object? name) {
  for (final dataset in LiveMapSourceDataset.values) {
    if (dataset.name == name) return dataset;
  }
  return null;
}

bool _hasValidInventory(
  Uint8List payload,
  Set<String> preparedMapIds,
  LiveMapBudget budget,
) {
  try {
    final value = budget.decodeJson(payload);
    if (value is! Map<String, dynamic> ||
        value.length != preparedMapIds.length ||
        !value.keys.toSet().containsAll(preparedMapIds)) {
      return false;
    }
    for (final entry in value.entries) {
      if (entry.value is! List) return false;
      for (final marker in entry.value) {
        if (marker is! Map<String, dynamic> ||
            marker['id'] is! String ||
            marker['category'] is! String ||
            marker['name'] is! String ||
            marker['position'] is! Map<String, dynamic> ||
            marker['source'] is! Map<String, dynamic> ||
            marker['details'] is! Map<String, dynamic>) {
          return false;
        }
        final position = marker['position']! as Map<String, dynamic>;
        if (position['x'] is! num ||
            position['z'] is! num ||
            (position['height'] != null && position['height'] is! num)) {
          return false;
        }
      }
    }
    return true;
  } on FormatException {
    return false;
  } on LiveMapResourceLimitException {
    return false;
  }
}

String _digest(List<int> bytes) => sha256.convert(bytes).toString();

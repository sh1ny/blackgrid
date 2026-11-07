import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'live_map_budget.dart';

import '../domain/map_coordinates.dart';
import '../domain/catalog.dart';
import 'live_map_inventory.dart';
import 'live_map_normalizer.dart';
import 'prepared_map.dart';

/// Identifies one of the six exact source bodies in a live-map snapshot.
enum LiveMapSourceDataset {
  maps,
  mapTranslations,
  tasks,
  taskTranslations,
  traders,
  traderTranslations,
}

/// Stores one exact source response and its optional revalidation metadata.
class LiveMapSourceBody {
  /// Creates a source body, retaining a private copy of [bytes].
  LiveMapSourceBody({
    required this.dataset,
    required Uint8List bytes,
    this.etag,
    this.lastModified,
    LiveMapBudget? budget,
  }) {
    if (bytes.length > 16 * 1024 * 1024) {
      throw const LiveMapResourceLimitException(
        'A live-map source exceeds the 16 MiB body limit.',
      );
    }
    final reservation = budget ?? LiveMapBudget();
    reservation.reserveMaterialized(bytes.length + _metadataCharge);
    _bytes = Uint8List.fromList(bytes).asUnmodifiableView();
    _digest = _LiveMapSourceDigest(_bytes);
  }

  LiveMapSourceBody._sharingBytes({
    required this.dataset,
    required this._bytes,
    required this.etag,
    required this.lastModified,
    required LiveMapBudget? budget,
    required this._digest,
  }) {
    (budget ?? LiveMapBudget()).reserveMaterialized(_metadataCharge);
  }

  /// The source represented by this body.
  final LiveMapSourceDataset dataset;

  /// The exact response bytes.
  late final Uint8List _bytes;
  late final _LiveMapSourceDigest _digest;

  /// The exact response bytes, exposed through a read-only view.
  Uint8List get bytes => _bytes;

  /// The source's ETag validator, when supplied.
  final String? etag;

  /// The source's Last-Modified validator, when supplied.
  final String? lastModified;

  /// The SHA-256 digest of [bytes].
  String get sha256 => _digest.value;

  /// Returns this body or a validator-updated body sharing the exact bytes.
  ///
  /// A changed validator creates only a small metadata object. The immutable
  /// response bytes and their cached digest remain shared.
  LiveMapSourceBody withValidators({
    required String? etag,
    required String? lastModified,
    LiveMapBudget? budget,
  }) {
    if (this.etag == etag && this.lastModified == lastModified) return this;
    return LiveMapSourceBody._sharingBytes(
      dataset: dataset,
      bytes: _bytes,
      etag: etag,
      lastModified: lastModified,
      budget: budget,
      digest: _digest,
    );
  }
}

/// The current serialized live-map snapshot format.
const int liveMapSnapshotFormatVersion = liveMapInventoryFormatVersion;

/// Describes the mapping and projection inputs that make cached markers usable.
class LiveMapCompatibility {
  LiveMapCompatibility._({
    required this.fingerprint,
    required Iterable<String> preparedMapIds,
  }) : preparedMapIds = Set.unmodifiable(preparedMapIds);

  /// Creates compatibility evidence from the active prepared pack and bindings.
  factory LiveMapCompatibility.fromPreparedPack(
    PreparedMapPack pack,
    Iterable<LiveMapBinding> bindings, {
    int formatVersion = liveMapSnapshotFormatVersion,
    int normalizerVersion = liveMapNormalizerVersion,
  }) {
    final mapIds = pack.maps.map((map) => map.id).toList()..sort();
    final bindingRows =
        [
          for (final binding in bindings)
            {
              'sourceKey': binding.sourceKey,
              'mapId': binding.mapId,
              'calibration': _compatibilityCalibration(binding.calibration),
            },
        ]..sort((left, right) {
          final sourceOrder = (left['sourceKey']! as String).compareTo(
            right['sourceKey']! as String,
          );
          if (sourceOrder != 0) return sourceOrder;
          return (left['mapId']! as String).compareTo(
            right['mapId']! as String,
          );
        });
    final material = <String, Object?>{
      'formatVersion': formatVersion,
      'normalizerVersion': normalizerVersion,
      'preparedMaps': [
        for (final map in pack.maps)
          {
            'id': map.id,
            'projection': [
              for (final point in [
                GamePoint(0, 0),
                GamePoint(1, 0),
                GamePoint(0, 1),
              ])
                [
                  map.geometry.gameToArtwork(point).x,
                  map.geometry.gameToArtwork(point).y,
                ],
            ],
            'floorPolicy': {
              'exclusive': map.floorPolicy.exclusive,
              'supportsAutomaticHeight':
                  map.floorPolicy.supportsAutomaticHeight,
              'floors': [
                for (final floor in map.floorPolicy.floors)
                  {
                    'id': floor.id,
                    'attachedLayerIds': floor.attachedLayerIds,
                    if (floor.heightBand case final band?)
                      'heightBand': [band.min, band.max],
                  },
              ],
            },
          },
      ],
      'preparedMapIds': mapIds,
      'bindings': bindingRows,
    };
    return LiveMapCompatibility._(
      fingerprint: _sha256Of(utf8.encode(canonicalJson(material))),
      preparedMapIds: mapIds,
    );
  }

  /// The stable digest of relevant format, normalizer and map inputs.
  final String fingerprint;

  /// The complete prepared-map identity closure required in normalized data.
  final Set<String> preparedMapIds;
}

/// Holds one complete durable snapshot for a single game mode.
class LiveMapSnapshot {
  /// Creates a candidate snapshot and retains a private payload copy.
  LiveMapSnapshot({
    required this.mode,
    required this.checkedAt,
    required Uint8List normalizedPayload,
    required Iterable<LiveMapSourceBody> sources,
    required this.formatVersion,
    required this.normalizerVersion,
    required this.compatibility,
    LiveMapBudget? budget,
  }) : budget = budget ?? LiveMapBudget() {
    final reservation = this.budget;
    const sourceReferenceCharge = 48;
    reservation.reserveMaterialized(sourceReferenceCharge);
    final collectedSources = <LiveMapSourceBody>[];
    final seenDatasets = <LiveMapSourceDataset>{};
    var sourceBytes = 0;
    for (final source in sources) {
      if (collectedSources.length == LiveMapSourceDataset.values.length) {
        throw FormatException('A live-map snapshot requires six sources.');
      }
      if (!seenDatasets.add(source.dataset)) {
        throw FormatException('Duplicate live-map source dataset.');
      }
      sourceBytes += source.bytes.length;
      if (sourceBytes > 64 * 1024 * 1024) {
        throw const LiveMapResourceLimitException(
          'A live-map snapshot exceeds the 64 MiB source aggregate limit.',
        );
      }
      collectedSources.add(source);
    }
    if (collectedSources.length != LiveMapSourceDataset.values.length) {
      throw FormatException('A live-map snapshot requires six sources.');
    }
    reservation.reserveMaterialized(sourceReferenceCharge);
    this.sources = List.unmodifiable(collectedSources);
    if (normalizedPayload.length > reservation.maxSerializedBytes) {
      throw const LiveMapResourceLimitException(
        'A live-map snapshot exceeds the serialized payload limit.',
      );
    }
    reservation.reserveMaterialized(normalizedPayload.length);
    this.normalizedPayload = Uint8List.fromList(normalizedPayload)
        .asUnmodifiableView();
  }

  /// The mode whose endpoint route produced this snapshot.
  final GameMode mode;

  /// The time this complete snapshot was checked.
  final DateTime checkedAt;

  /// The canonical UTF-8 normalized payload.
  late final Uint8List normalizedPayload;

  /// The six exact upstream source bodies and validators.
  late final List<LiveMapSourceBody> sources;

  /// The stored normalized payload format version.
  final int formatVersion;

  /// The version of the normalizer that produced this payload.
  final int normalizerVersion;

  /// The prepared-map compatibility evidence for this payload.
  final LiveMapCompatibility compatibility;

  /// The resource budget shared across materialization and storage.
  final LiveMapBudget budget;

  LiveMapInventoryValidation? _inventoryValidation;

  /// The opaque validation proof for these immutable bytes, when available.
  LiveMapInventoryValidation? get inventoryValidation => _inventoryValidation;

  /// Reuses a completed proof only for identical payload and compatibility.
  ///
  /// Source validators and check times may change without changing marker
  /// facts. This avoids decoding an unchanged inventory a second time.
  bool reuseInventoryValidation(LiveMapInventoryValidation? proof) {
    if (proof == null ||
        proof._sha256 != normalizedSha256 ||
        proof._compatibility != compatibility.fingerprint ||
        proof._formatVersion != formatVersion ||
        proof._normalizerVersion != normalizerVersion) {
      return false;
    }
    _inventoryValidation = proof;
    return true;
  }

  /// Decodes the private immutable payload and validates its complete map set.
  ///
  /// A successful decode certifies this snapshot's payload for later storage
  /// validation without retaining a second decoded inventory.
  LiveMapInventory decodeInventory({required LiveMapBudget budget}) {
    final before = budget.materializedBytes;
    try {
      final inventory = LiveMapInventory.decode(
        normalizedPayload,
        budget: budget,
      );
      final maps = inventory.maps;
      if (maps.length != compatibility.preparedMapIds.length ||
          !compatibility.preparedMapIds.every(maps.containsKey)) {
        throw const FormatException(
          'Live-map inventory has an incomplete map set.',
        );
      }
      _inventoryValidation ??= LiveMapInventoryValidation._(
        normalizedSha256,
        compatibility.fingerprint,
        formatVersion,
        normalizerVersion,
      );
      return inventory;
    } catch (_) {
      budget.releaseMaterialized(budget.materializedBytes - before);
      rethrow;
    }
  }

  /// Validates the immutable payload once without retaining decoded facts.
  ///
  /// The certificate applies only to this snapshot's privately copied bytes
  /// and immutable compatibility identity. Digests remain independently checked
  /// by storage on every write.
  void validateInventory({required LiveMapBudget budget}) {
    if (_inventoryValidation != null) return;
    final before = budget.materializedBytes;
    try {
      decodeInventory(budget: budget);
    } finally {
      budget.releaseMaterialized(budget.materializedBytes - before);
    }
  }

  /// The SHA-256 digest of [normalizedPayload].
  late final String normalizedSha256 = _sha256Of(normalizedPayload);
}

/// Proves that one immutable payload and compatibility identity were decoded.
///
/// Only a successful [LiveMapSnapshot.decodeInventory] can create this proof.
/// It retains no source bodies, payload bytes or decoded facts.
final class LiveMapInventoryValidation {
  const LiveMapInventoryValidation._(
    this._sha256,
    this._compatibility,
    this._formatVersion,
    this._normalizerVersion,
  );

  final String _sha256;
  final String _compatibility;
  final int _formatVersion;
  final int _normalizerVersion;
}

/// Persists complete mode snapshots independently from other user records.
abstract interface class LiveMapStore {
  /// Loads a compatible complete snapshot, or returns `null` without authority.
  ///
  /// Calls [onRejected] once when stored authority is corrupt or incompatible;
  /// an absent cache does not count as rejection.
  Future<LiveMapSnapshot?> read(
    GameMode mode, {
    required LiveMapCompatibility compatibility,
    void Function(Object failure)? onRejected,
  });

  /// Replaces one mode's complete snapshot atomically using [budget].
  ///
  /// When [budget] is omitted, the store creates a fresh resource budget.
  Future<void> commit(LiveMapSnapshot snapshot, {LiveMapBudget? budget});
}

const int _metadataCharge = 64;

class _LiveMapSourceDigest {
  _LiveMapSourceDigest(this.bytes);

  final Uint8List bytes;
  late final String value = _sha256Of(bytes);
}

String _sha256Of(List<int> bytes) => sha256.convert(bytes).toString();

Object? _compatibilityCalibration(Map<String, Object?> calibration) {
  final geometry = calibration['geometry'];
  final floors = calibration['floors'];
  final assignments = calibration['markerFloorAssignments'];
  if (geometry is! Map<String, Object?> || floors is! List) {
    throw FormatException('Invalid live-map compatibility calibration.');
  }
  return {
    'geometry': geometry,
    'floors': [
      for (final value in floors)
        if (value is Map<String, Object?>)
          {
            for (final key in [
              'id',
              'heightBand',
              'base',
              'exclusive',
              'attachedIds',
            ])
              if (value.containsKey(key)) key: value[key],
          }
        else
          throw FormatException('Invalid live-map calibration floor.'),
    ],
    'markerFloorAssignments': ?assignments,
  };
}

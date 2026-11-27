import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:blackgrid/domain/map_coordinates.dart';
import 'package:blackgrid/maps/prepared_map.dart';
import 'package:blackgrid/maps/prepared_map_loader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/maps/calibration.dart' show interactiveMetadata;
import '../../tool/maps/place_labels.dart' show extractPlaceLabels;

/// Loads the committed active generation through the real loader, as the app
/// does from its asset bundle.
void main() {
  Future<PreparedMapPack> loadPack() => PreparedMapPackLoader(
    loadBytes: (path) async =>
        ByteData.sublistView(await File(path).readAsBytes()),
  ).load();

  test('all bundled multi-floor maps carry the frozen extents', () async {
    final pack = await loadPack();
    for (final map in pack.maps) {
      expect(
        map.floorPolicy.supportsAutomaticHeight,
        map.floorPolicy.floors.length > 1,
        reason: map.id,
      );
    }
    for (final (id, first, base) in const [
      ('factory', 'Basement', 'Ground_Floor'),
      ('customs', 'Underground_Level', 'Ground_Level'),
      ('shoreline', 'Underground_Level', 'Ground_Level'),
      ('thelab', 'Technical_Level', 'First_Level'),
      ('reserve', 'Bunkers', 'Ground_Level'),
      ('streetsoftarkov', 'Underground_Level', 'Ground_Level'),
      ('groundzero', 'Underground_Level', 'Ground_Level'),
    ]) {
      final policy = pack.byId[id]!.floorPolicy;
      expect(policy.floors.first.id, first, reason: id);
      expect(policy.floors[1].id, base, reason: id);
      expect(policy.reset().visibleLayerIds.first, base, reason: id);
    }
    final reserve = pack.byId['reserve']!.floorPolicy;
    expect(
      reserve.floorForPosition(GamePoint(-100, 0, height: -9))?.id,
      'Bunkers',
    );
    expect(
      reserve.floorForPosition(GamePoint(1000, 1000, height: -9))?.id,
      reserve.base.id,
    );
    final streets = pack.byId['streetsoftarkov']!.floorPolicy;
    expect(
      streets.floorForPosition(GamePoint(200, -250, height: -9))?.id,
      'Underground_Level',
    );
    expect(
      streets.floorForPosition(GamePoint(-100, 200, height: 16))?.id,
      'Third_Floor',
    );
    final icebreaker = pack.byId['icebreaker']!.floorPolicy;
    expect(icebreaker.floors[6].id, 'Infirmary');
    expect(icebreaker.reset().visibleLayerIds, ['Infirmary']);
    expect(
      icebreaker.floorForPosition(GamePoint(0, 0, height: 18.919))?.id,
      'Storage_Security',
    );
    expect(
      icebreaker.floorForPosition(GamePoint(0, 0, height: 18.925))?.id,
      'Infirmary',
    );
  });

  final fixture = _read('test/fixtures/map_floor_marker_delta.json');
  final active = _read('assets/maps/active.json');
  final manifest = _read('assets/maps/${active['manifest']}');
  final hashes = {
    for (final output in manifest['outputs'] as List)
      output['path']: output['sha256'],
  };
  final sameInputs = (fixture['inputHashes'] as Map).entries.every(
    (entry) => hashes[entry.key] == entry.value,
  );

  test(
    'bundled before/after marker floor transitions and owners match',
    () async {
      final pack = await loadPack();
      final oldBands = fixture['v4HeightBands'] as Map;
      final expected = <(String, String?, String?), Set<String>>{
        for (final row in fixture['changes'] as List)
          (
            row['mapId'] as String,
            row['before'] as String?,
            row['after'] as String?,
          ): (row['markerIds'] as List)
              .cast<String>()
              .toSet(),
      };
      final actual = <(String, String?, String?), Set<String>>{};
      for (final inventory in fixture['markerInventories'] as List) {
        final map = pack.byId[inventory['mapId']]!;
        expect(
          map.markers,
          hasLength(inventory['count'] as int),
          reason: map.id,
        );
        expect(
          {
            for (final marker in map.markers)
              if (marker.floorId case final String id) marker.id: id,
          },
          inventory['explicitOwners'],
          reason: '${map.id} explicit ownership',
        );
        for (final marker in map.markers) {
          if (marker.floorId != null) continue;
          final before = _v4Floor(map, marker, oldBands[map.id] as Map?);
          final after = map.floorPolicy.floorForPosition(marker.position)?.id;
          if (before != after) {
            (actual[(map.id, before, after)] ??= {}).add(marker.id);
          }
        }
      }
      expect(actual, expected);
    },
    skip: sameInputs
        ? false
        : 'Active pack uses different frozen marker inputs.',
  );

  test('the real loader loads the committed active pack', () async {
    final pack = await loadPack();
    expect(pack.maps, hasLength(13));

    // Every map carries the labels its own frozen metadata gives: 303 on the
    // ten maps that have any, none on Terminal, Icebreaker and Labyrinth.
    final pointer = jsonDecode(
      File('assets/maps/active.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final manifest = jsonDecode(
      File('assets/maps/${pointer['manifest']}').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(manifest['preparationVersion'], 5);
    final metadata = jsonDecode(
      File(
        'assets/maps/versions/${pointer['version']}/evidence/metadata/maps.json',
      ).readAsStringSync(),
    ) as List;
    var total = 0;
    var withLabels = 0;
    for (final map in pack.maps) {
      final expected = extractPlaceLabels(
        interactiveMetadata(metadata, map.sourceKey!),
        mapId: map.id,
      ).length;
      expect(map.placeLabels, hasLength(expected), reason: map.id);
      total += map.placeLabels.length;
      if (map.placeLabels.isNotEmpty) withLabels++;
    }
    expect(total, 303);
    expect(withLabels, 10);
    for (final id in ['terminal', 'icebreaker', 'labyrinth']) {
      expect(pack.byId[id]!.placeLabels, isEmpty, reason: id);
    }
    expect(pack.byId['interchange']!.placeLabels, hasLength(77));
    expect(pack.byId['customs']!.placeLabels, hasLength(24));
    expect(pack.byId['thelab']!.placeLabels, hasLength(31));
  });
}

Map<String, dynamic> _read(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

String? _v4Floor(PreparedMap map, PreparedMarker marker, Map? bands) {
  final height = marker.position.height;
  if (bands == null || height == null) return null;
  var winner = map.floorPolicy.base.id;
  var min = double.negativeInfinity;
  var max = double.infinity;
  for (final entry in bands.entries) {
    final range = entry.value as List;
    final low = (range[0] as num).toDouble();
    final high = (range[1] as num).toDouble();
    if (low <= height &&
        height < high &&
        (low > min || (low == min && high < max))) {
      min = low;
      max = high;
      winner = entry.key as String;
    }
  }
  return winner;
}

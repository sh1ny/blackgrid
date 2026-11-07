import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/maps/live_map_snapshot.dart';
import 'package:blackgrid/maps/prepared_map.dart';

import '../support/prepared_pack_manifest.dart' show minimalPreparedMap;

Map<String, Object?> _body(LiveMapSourceDataset dataset) => switch (dataset) {
  LiveMapSourceDataset.maps => {
    'data': {'maps': <String, Object?>{}, 'mobs': <String, Object?>{}},
  },
  LiveMapSourceDataset.tasks => {
    'data': {'tasks': <String, Object?>{}, 'questItems': <String, Object?>{}},
  },
  _ => {'data': <String, Object?>{}},
};

void main() {
  test('a bound map absent upstream gets no markers, not bundled ones', () {
    final manifestMap = minimalPreparedMap('customs-map')
      ..['sourceKey'] = 'customs'
      ..['markers'] = [
        {
          'id': 'bundled-marker',
          'category': 'lootLoose',
          'name': 'Bundled marker',
          'position': {'x': 1, 'z': 2},
          'details': <String, Object?>{},
          'source': {'kind': 'prepared'},
        },
      ];
    final pack = PreparedMapPack(
      version: 'binding-test',
      assetRoot: 'test',
      maps: [PreparedMap.fromJson(manifestMap, assetRoot: 'test')],
    );

    final markers = buildLiveMarkers(
      sources: {
        for (final dataset in LiveMapSourceDataset.values)
          dataset: Uint8List.fromList(utf8.encode(jsonEncode(_body(dataset)))),
      },
      bindings: pack.liveMapBindings,
      mode: GameMode.pve,
    );

    expect(markers.keys, ['customs-map']);
    expect(
      markers['customs-map'],
      isEmpty,
      reason: 'Absent upstream metadata must not resurrect bundled markers.',
    );
  });
}

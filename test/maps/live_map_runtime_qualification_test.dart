@Tags(['qualification'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/maps/live_map_snapshot.dart';
import 'package:blackgrid/maps/prepared_map.dart';
import 'package:blackgrid/maps/prepared_map_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('frozen regular sources rebuild the bundled pack markers', () async {
    final pointer = jsonDecode(
      await File('assets/maps/active.json').readAsString(),
    ) as Map<String, dynamic>;
    final evidenceRoot = 'assets/maps/versions/${pointer['version']}/evidence';
    final index = jsonDecode(
      await File('$evidenceRoot/sources.json').readAsString(),
    ) as Map<String, dynamic>;
    final sources = <LiveMapSourceDataset, Uint8List>{};
    for (final value in index['sources'] as List<dynamic>) {
      final source = value as Map<String, dynamic>;
      final uri = Uri.parse(source['url'] as String);
      if (uri.host != 'json.tarkov.dev') continue;
      for (final dataset in LiveMapSourceDataset.values) {
        if (uri.path == '/regular/${dataset.path}') {
          sources[dataset] = await File('$evidenceRoot/${source['path']}')
              .readAsBytes();
        }
      }
    }
    expect(sources.keys, unorderedEquals(LiveMapSourceDataset.values));

    final pack = await PreparedMapPackLoader(
      loadBytes: (path) async =>
          ByteData.sublistView(await File(path).readAsBytes()),
    ).load();
    final live = buildLiveMarkers(
      sources: sources,
      bindings: pack.liveMapBindings,
      mode: GameMode.pvp,
    );

    expect(pack.maps.expand((map) => map.markers), isNotEmpty);
    expect(live.keys, unorderedEquals(pack.maps.map((map) => map.id)));
    for (final map in pack.maps) {
      expect(
        live[map.id]!.map(_facts).toList(),
        map.markers.map(_facts).toList(),
        reason: map.id,
      );
    }
  });
}

Map<String, Object?> _facts(PreparedMarker marker) => {
  'id': marker.id,
  'category': marker.category,
  'name': marker.name,
  'position': [marker.position.x, marker.position.z, marker.position.height],
  'details': marker.details,
  'source': marker.source,
};

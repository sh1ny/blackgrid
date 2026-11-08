import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:blackgrid/maps/prepared_map_loader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/maps/calibration.dart' show interactiveMetadata;
import '../../tool/maps/place_labels.dart' show extractPlaceLabels;

/// Loads the committed active generation through the real loader, as the app
/// does from its asset bundle.
void main() {
  test('the real loader loads the committed active pack', () async {
    final pack = await PreparedMapPackLoader(
      loadBytes: (path) async =>
          ByteData.sublistView(await File(path).readAsBytes()),
    ).load();
    expect(pack.maps, hasLength(13));

    // Every map carries the labels its own frozen metadata gives: 303 on the
    // ten maps that have any, none on Terminal, Icebreaker and Labyrinth.
    final pointer = jsonDecode(
      File('assets/maps/active.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final manifest = jsonDecode(
      File('assets/maps/${pointer['manifest']}').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(manifest['preparationVersion'], 4);
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

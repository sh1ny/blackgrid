import 'dart:convert';
import 'dart:io';

import 'package:blackgrid/maps/prepared_map_loader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/maps/pack.dart' show validateCandidate;
import '../support/prepared_pack_manifest.dart';

void main() {
  test('loader and validator reject malformed floor extents', () async {
    final candidate = await Directory.systemTemp.createTemp('floor-extents-');
    addTearDown(() => candidate.delete(recursive: true));
    final cases = <Map<String, Object?>>[
      {},
      {'extents': null},
      {
        'extents': [null],
      },
      {
        'extents': [
          {
            'height': [1, 2],
          },
        ],
      },
      {
        'extents': [
          {
            'height': [3, 3],
            'bounds': [],
          },
        ],
      },
      {
        'extents': [
          {
            'height': [-1e308, 1e308],
            'bounds': [],
          },
        ],
      },
      {
        'extents': [
          {
            'height': [1, 2],
            'bounds': [
              [4, 5, 3, 9],
            ],
          },
        ],
      },
      {
        'extents': [
          {
            'height': [1, 2],
            'bounds': [
              [2, 2, 4, 2],
            ],
          },
        ],
      },
    ];
    for (final fields in cases) {
      final manifest = preparedPackManifest();
      final map = (manifest['maps'] as List).singleWhere(
        (map) => map['id'] == 'factory',
      );
      final floor = Map<String, dynamic>.of(
        (map['floors'] as List).single as Map<String, dynamic>,
      );
      map['floors'] = [floor];
      floor.remove('extents');
      floor.addAll(fields);
      final loader = PreparedMapPackLoader(
        loadBytes: preparedPackBytes(manifest),
      );
      final error = throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          allOf(contains('factory'), contains(floor['id'] as String)),
        ),
      );
      await expectLater(loader.load(), error, reason: '$fields');
      await File('${candidate.path}/manifest.json')
          .writeAsString(jsonEncode(manifest));
      await expectLater(validateCandidate(candidate), error, reason: '$fields');
    }
  });
}
